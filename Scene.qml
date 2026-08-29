import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// 顶部栏场景标签 + 切换弹窗。配置界面在 ConfigPanel.qml（懒加载居中弹层，
// 由下方 Loader 按需创建，关闭即销毁，平时不占内存）。
// 依赖 omarchy-scene CLI：切换用 `set`，配置开关用 `toggle-plugin`（= omarchy plugin enable/disable）。

BarWidget {
    id: root
    moduleName: "max.scene"

    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string scenesPath: root.homeDir + "/.config/omarchy/scenes/scenes.json"
    readonly property string bin: root.homeDir + "/.local/bin/omarchy-scene"

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

    // ---------------- 数据 ----------------

    function parseScenes() {
        var raw = scenesFile.text() || ""
        if (!raw.trim()) return
        var o
        try { o = JSON.parse(raw) } catch (e) { return }
        if (!o || typeof o !== "object") return
        var c = String(o.current || "default")

        root.currentScene = c
        root.currentLabel = c === "default"
            ? "Default"
            : (o.scenes && o.scenes[c] && o.scenes[c].label) || c
        root.currentIcon = c === "default"
            ? (o.defaultIcon || "")
            : (o.scenes && o.scenes[c] && o.scenes[c].icon) || ""

        var rows = []
        rows.push({ name: "default", label: "Default", icon: o.defaultIcon || "", active: c === "default" })
        var names = o.scenes ? Object.keys(o.scenes) : []
        for (var i = 0; i < names.length; i++) {
            var n = names[i]
            var sc = o.scenes[n]
            rows.push({ name: n, label: (sc && sc.label) || n, icon: (sc && sc.icon) || "", active: c === n })
        }
        root.sceneRows = rows
    }

    // ---------------- 动作 ----------------

    function switchScene(name) {
        if (root.bar) root.bar.run(root.bin + " set " + name)
        root.close()
    }

    function openConfig() {
        root.close()
        configLoader.active = true
    }

    function refreshCache() {
        if (root.bar) root.bar.run(root.bin + " refresh")
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

    FileView {
        id: scenesFile
        path: root.scenesPath
        watchChanges: true
        atomicWrites: true
        onLoaded: root.parseScenes()
        onFileChanged: reload()
    }

    // omarchy-scene refresh 会触发 shell 重建插件部件（本部件被销毁重建，配置面板随之关闭）。
    // cmd_refresh 已先写入 .reopen-config 标记；此处检测到标记即自动重新打开配置面板并清除标记。
    FileView {
        id: reopenMarker
        path: root.homeDir + "/.config/omarchy/scenes/.reopen-config"
        watchChanges: true
        onLoaded: {
            if (!root.homeDir) return
            if ((reopenMarker.text() || "").trim() !== "1") return
            // 清除标记，避免下次部件重建时再次误开面板
            if (root.bar) root.bar.run("printf 0 > " + root.homeDir + "/.config/omarchy/scenes/.reopen-config")
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
