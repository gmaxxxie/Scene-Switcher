import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// 顶部栏场景标签 + 切换弹窗。配置界面在 ConfigPanel.qml（懒加载居中弹层，
// 由下方 Loader 按需创建，关闭即销毁，平时不占内存）。
// 依赖 omarchy-scene CLI：切换用 `set`，配置开关用 `toggle-plugin`（= omarchy plugin enable/disable）。
// 数据来源是 CLI 生成的 ui-state.json（config_payload 已按 secure_io 上限校验并截断后原子发布），
// 而不是可被任意进程改写的 scenes.json——脚本端读 scenes.json 的原状在审查里是命令执行入口。
// 本文件仍对 ui-state.json 做防御性二次校验（体积上限 + 场景键/标签/图标限长 + 剥富文本标记），
// 因为该文件也躺在用户目录里，不能假设它始终由 CLI 亲手写成。

BarWidget {
    id: root
    moduleName: "max.scene"

    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string statePath: root.homeDir + "/.config/omarchy/scenes/ui-state.json"
    readonly property string bin: root.homeDir + "/.local/bin/omarchy-scene"

    // 与 CLI secure_io 同款上限（防御性；正常时 payload 已被 CLI 截断）
    readonly property int maxBytes: 8 * 1024 * 1024
    readonly property int maxScenes: 12
    readonly property int maxLabelLen: 64
    readonly property int maxIconLen: 4

    property string currentScene: "default"
    property string currentLabel: "Default"
    property string currentIcon: ""
    property var sceneRows: []
    property bool popupOpen: false

    readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
    readonly property color dim: Qt.darker(root.fg, 1.55)
    readonly property string barFont: root.bar ? root.bar.fontFamily : Style.font.family
    readonly property real rowHeight: Math.max(Style.space(30), Style.font.body + Style.spacing.md * 2)

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    // 剥掉富文本标记字符：WidgetButton/tooltip 等无法逐处设 Text.PlainText 的显示面
    // 也靠这里保证文件来源的字符串永远不会被当作 Qt 富文本（AutoText）渲染。
    function scrub(s) { return String(s == null ? "" : s).replace(/[<>]/g, "") }

    // ---------------- 数据 ----------------

    function parseScenes() {
        var raw = stateFile.text() || ""
        if (!raw.trim()) return
        if (raw.length > root.maxBytes) return   // 字节上限，拒绝超大文件
        var o
        try { o = JSON.parse(raw) } catch (e) { return }
        if (!o || typeof o !== "object" || Array.isArray(o)) return

        // current 必须过键正则（后续只用于高亮，不透出到 shell）
        var c = "default"
        if (typeof o.current === "string" && /^[a-zA-Z0-9_-]{1,10}$/.test(o.current)) c = o.current

        var scenes = Array.isArray(o.scenes) ? o.scenes.slice(0, root.maxScenes) : []
        var defaultIcon = ""
        var rows = []

        // 关键校验：场景名只收 CLI 同款受控键（字母/数字/-/_，<=10 字符）。
        // 非法键直接丢弃，绝不进入列表——点击行是 switchScene -> bash -lc 的入口。
        var i
        for (i = 0; i < scenes.length; i++) {
            var e = scenes[i] || {}
            var n = String(e.name == null ? "" : e.name)
            if (!/^[a-zA-Z0-9_-]{1,10}$/.test(n)) continue
            if (n === "default") { defaultIcon = root.scrub(e.icon); continue }
            var label = root.scrub(String(e.label == null ? "" : e.label)).slice(0, root.maxLabelLen) || n
            var icon = root.scrub(String(e.icon == null ? "" : e.icon)).slice(0, root.maxIconLen)
            rows.push({ name: n, label: label, icon: icon, active: c === n })
        }
        rows.unshift({ name: "default", label: "Default", icon: defaultIcon, active: c === "default" })

        // 当前场景显示名/图标：只从通过校验的行里取，取不到就回退为键名本身（已受控）
        var cur = rows.length ? rows[0] : { name: "default", label: "Default", icon: "" }
        for (i = 0; i < rows.length; i++) {
            if (rows[i].name === c) { cur = rows[i]; break }
        }
        root.sceneRows = rows
        root.currentScene = c
        root.currentLabel = cur.label || c
        root.currentIcon = cur.icon || ""
    }

    // ---------------- 动作 ----------------

    function switchScene(name) {
        var n = String(name || "")
        // 二次校验 + 引号：即使数据层被绕过，命令仍是字面参数（Util.shellQuote 正确处理内嵌引号）
        if (!/^[a-zA-Z0-9_-]{1,10}$/.test(n)) return
        if (root.bar) root.bar.run(root.bin + " set " + Util.shellQuote(n))
        root.close()
    }

    function openConfig() {
        root.close()
        configLoader.active = true
    }

    function refreshCache() {
        // 只刷新缓存：加 --no-reopen，避免刷新后 shell 重建部件时经 .reopen-config 标记
        // 自动弹出配置面板——那是配置面板“refresh plugins”按钮（保留弹窗）的行为，
        // 切换弹层的这个按钮只应刷缓存、不弹配置页。
        if (root.bar) root.bar.run(root.bin + " refresh --no-reopen")
        root.close()
    }

    function close() {
        root.popupOpen = false
    }

    // ---- bar-widget 面板契约（Bar.findPanelWidget 路由揭起/关闭用） ----
    readonly property bool opened: root.popupOpen
    function open() {
        root.parseScenes()
        root.popupOpen = true
    }
    function closeForPopoutSwitch() {
        root.popupOpen = false
    }
    readonly property bool popoutSwitchClosing: false

    // ---------------- 文件监听 ----------------

    // 监听 CLI 原子发布的验证后 payload（ui-state.json），而非原始 scenes.json。
    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        atomicWrites: true
        onLoaded: root.parseScenes()
        onFileChanged: reload()
    }

    // omarchy-scene refresh 会触发 shell 重建插件部件（本部件被销毁重建，配置面板随之关闭）。
    // cmd_refresh 已先经 secure_io 写入 .reopen-config 标记；此处检测到标记即自动重新打开
    // 配置面板，清除动作改由 CLI 的 reopen-done 完成（unlink 链接本身，绝无 shell 重定向截断）。
    FileView {
        id: reopenMarker
        path: root.homeDir + "/.config/omarchy/scenes/.reopen-config"
        watchChanges: true
        onLoaded: {
            if (!root.homeDir) return
            var txt = reopenMarker.text() || ""
            if (txt.length > 16) return           // 标记内容只会是 "1"，超长/巨大文件一律忽略
            if (txt.trim() !== "1") return
            // 清除标记，避免下次部件重建时再次误开面板（由 CLI 原子删除，不经过 shell 重定向）
            if (root.bar) root.bar.run(root.bin + " reopen-done")
            Qt.callLater(root.openConfig)
        }
    }

    // ---------------- 懒加载配置面板 ----------------

    Loader {
        id: configLoader
        source: Qt.resolvedUrl("ConfigPanel.qml")
        active: false
        onLoaded: {
            configLoader.item.bar = root.bar
            configLoader.item.closeRequested.connect(function () { configLoader.active = false })
        }
    }

    // ---------------- IPC 唤起 ----------------

    IpcHandler {
        target: "max.scene"

        function toggle() { root.popupOpen = !root.popupOpen }
        function open() {
            root.parseScenes()
            root.popupOpen = true
        }
        function config() { root.openConfig() }
    }

    // ---------------- 顶部栏按钮 ----------------

    WidgetButton {
        id: button
        anchors.verticalCenter: parent.verticalCenter
        bar: root.bar
        text: (root.currentIcon || "󰕮") + " " + root.currentLabel
        tooltipText: "Scene: " + root.currentLabel + " (left click)"
        horizontalMargin: 7.5
        onPressed: function (b) {
            if (b !== Qt.LeftButton) return
            root.parseScenes()
            root.popupOpen = !root.popupOpen
        }
    }

    // ---------------- 切换弹窗 ----------------

    PopupCard {
        id: popup
        anchorItem: button
        bar: root.bar
        owner: root
        open: root.popupOpen
        triggerMode: "click"
        contentWidth: popup.fittedContentWidth(Style.space(280))
        contentHeight: popup.fittedContentHeight(
            Math.min(switchList.contentHeight, Style.space(220)) + Style.space(110),
            Style.space(560))

        Column {
            anchors.fill: parent
            spacing: Style.space(6)

            Row {
                width: parent.width
                Text {
                    width: parent.width - Style.space(40)
                    text: "Scenes"
                    color: root.fg
                    font.family: root.barFont
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    verticalAlignment: Text.AlignVCenter
                }
                PanelActionButton {
                    width: Style.space(30)
                    height: Style.space(30)
                    size: Style.space(30)
                    iconText: "×"
                    tooltipText: "Close"
                    foreground: root.fg
                    hoverColor: root.fg
                    onClicked: root.close()
                }
            }

            Text {
                width: parent.width
                text: "Current: " + root.currentLabel
                color: root.dim
                font.family: root.barFont
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
            }

            PanelSeparator {
                foreground: root.fg
            }

            ListView {
                id: switchList
                width: parent.width
                height: Math.min(contentHeight, Style.space(220))
                interactive: contentHeight > height
                spacing: Style.space(2)
                clip: true
                model: root.sceneRows

                delegate: Item {
                    required property string name
                    required property string label
                    required property string icon
                    required property bool active
                    property bool hovered: false

                    width: switchList.width
                    height: root.rowHeight

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.cornerRadius
                        color: hovered ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: hovered = true
                        onExited: hovered = false
                        onClicked: root.switchScene(name)
                    }
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Style.space(8)
                        anchors.rightMargin: Style.space(8)
                        spacing: Style.space(6)
                        Text {
                            width: Style.space(18)
                            height: parent.height
                            text: active ? "✓" : ""
                            color: active ? root.fg : root.dim
                            font.family: root.barFont
                            font.pixelSize: Style.font.body
                            verticalAlignment: Text.AlignVCenter
                            textFormat: Text.PlainText
                        }
                        Text {
                            width: Style.space(20)
                            height: parent.height
                            text: icon
                            color: root.dim
                            font.family: root.barFont
                            font.pixelSize: Style.font.body
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            textFormat: Text.PlainText
                        }
                        Text {
                            width: parent.width - Style.space(18) - Style.space(20) - Style.space(12)
                            height: parent.height
                            text: label
                            color: active ? root.fg : root.dim
                            font.family: root.barFont
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                            textFormat: Text.PlainText
                        }
                    }
                }
            }

            PanelSeparator {
                foreground: root.fg
            }

            Row {
                spacing: Style.space(6)
                PanelActionButton {
                    width: Style.space(30)
                    height: Style.space(30)
                    size: Style.space(30)
                    iconText: "󰒓"
                    tooltipText: "Open scene configuration"
                    foreground: root.fg
                    hoverColor: root.fg
                    onClicked: root.openConfig()
                }
                PanelActionButton {
                    width: Style.space(30)
                    height: Style.space(30)
                    size: Style.space(30)
                    iconText: "󰑓"
                    tooltipText: "Refresh plugin cache"
                    foreground: root.fg
                    hoverColor: root.fg
                    onClicked: root.refreshCache()
                }
            }
        }
    }
}
