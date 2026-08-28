import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// 场景配置面板：全屏居中弹层（遮罩 + 居中卡片）。
// 由 max.scene 的 Loader 懒加载——只在打开时构造，关闭即销毁，平时不占内存。
// 插件开关 = omarchy plugin enable/disable（经 omarchy-scene toggle-plugin）。
// 列表 = 用户安装的插件在前 + omarchy 内置在后；内置默认锁定（遵循系统默认状态），解锁后可开关。

Item {
    id: root

    property var bar: null
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string bin: root.homeDir + "/.local/bin/omarchy-scene"
    readonly property string uiStatePath: root.homeDir + "/.config/omarchy/scenes/ui-state.json"

    property var cfgScenes: []
    property var cfgPlugins: []        // 全部插件：用户安装在前 + omarchy 内置在后（payload 已排序）
    property var visiblePlugins: []    // 列表实际显示的插件（其它场景视图隐藏锁定的）
    property string selectedScene: "default"
    property string newSceneName: ""
    property string sceneIconText: ""          // 当前选中场景的图标（用于高亮）
    property bool sceneIconsExpanded: false    // 图标选择是否展开
    property var sceneIcons: [                 // 预设图标库（Font Awesome 5 solid，字体 f000-f385 全部覆盖）
        { cp: "\uF015", label: "Home" },
        { cp: "\uF0F4", label: "Coffee" },
        { cp: "\uF121", label: "Code" },
        { cp: "\uF120", label: "Terminal" },
        { cp: "\uF140", label: "Focus" },
        { cp: "\uF02D", label: "Book" },
        { cp: "\uF0B1", label: "Work" },
        { cp: "\uF135", label: "Rocket" },
        { cp: "\uF185", label: "Sun" },
        { cp: "\uF186", label: "Moon" },
        { cp: "\uF001", label: "Music" },
        { cp: "\uF005", label: "Star" },
        { cp: "\uF0E7", label: "Bolt" },
        { cp: "\uF06C", label: "Leaf" },
        { cp: "\uF1EB", label: "Wifi" },
        { cp: "\uF06D", label: "Fire" },
        { cp: "\uF004", label: "Heart" },
        { cp: "\uF118", label: "Smile" },
        { cp: "\uF19D", label: "Graduation" },
        { cp: "\uF072", label: "Plane" },
        { cp: "\uF236", label: "Bed" },
        { cp: "\uF108", label: "Desktop" },
        { cp: "\uF26C", label: "TV" },
        { cp: "\uF11C", label: "Keyboard" },
        { cp: "\uF017", label: "Clock" },
        { cp: "\uF007", label: "User" },
        { cp: "\uF013", label: "Settings" },
        { cp: "\uF0EB", label: "Lamp" },
        { cp: "\uF0AC", label: "Globe" },
        { cp: "\uF030", label: "Camera" }
    ]
    property bool renameMode: false    // true=改名模式（TextField 用作改名）
    property int listRev: 0            // 列表版本号，防止迟到的滚动恢复覆盖新列表

    onSelectedSceneChanged: {
        root.renameMode = false
        root.newSceneName = ""
        root.sceneIconText = root.sceneIcon(root.selectedScene)
        root.rebuildList(false)
    }

    signal closeRequested()

    readonly property color fg: Color.foreground
    readonly property color dim: Qt.darker(Color.foreground, 1.55)
    readonly property color urgent: Color.urgent
    readonly property string barFont: Style.font.family
    readonly property real rowHeight: Style.space(30)

    // ---------------- 数据 ----------------

    // 根据当前编辑场景，计算要显示的插件列表：
    //  - 默认场景：全部显示（含锁定，可加/解锁）
    //  - 其它场景：隐藏锁定的插件（它们被所有场景继承、始终启用，无需在此显示）
    // preserveScroll=true 时保留列表滚动位置（切换插件开关后不跳回顶部）
    function rebuildList(preserveScroll) {
        root.listRev = root.listRev + 1
        var rev = root.listRev
        var savedY = (preserveScroll && pluginList) ? pluginList.contentY : 0
        var isDefault = root.selectedScene === "default"
        var out = []
        for (var i = 0; i < root.cfgPlugins.length; i++) {
            var p = root.cfgPlugins[i]
            if (!isDefault && p.locked) continue
            out.push(p)
        }
        root.visiblePlugins = out
        if (savedY > 0 && pluginList) {
            pluginList.contentY = savedY
            Qt.callLater(function () { if (root.listRev === rev) pluginList.contentY = savedY })
        }
    }

    function parseUiState() {
        var raw = uiFile.text() || ""
        if (!raw.trim()) return
        var o
        try { o = JSON.parse(raw) } catch (e) { return }
        if (!o || typeof o !== "object") return

        root.cfgScenes = o.scenes || []
        root.cfgPlugins = o.plugins || []
        root.sceneIconText = root.sceneIcon(root.selectedScene)

        var stillThere = false
        for (var i = 0; i < root.cfgScenes.length; i++) {
            if (root.cfgScenes[i].name === root.selectedScene) { stillThere = true; break }
        }
        if (!stillThere) root.selectedScene = "default"
        root.rebuildList(true)
    }

    function sceneLabel(name) {
        for (var i = 0; i < root.cfgScenes.length; i++) {
            if (root.cfgScenes[i].name === name) return root.cfgScenes[i].label
        }
        return name
    }

    // 插件的有效开关态：锁定=系统状态；已在场景=开；未入任何场景=回显系统默认状态（新装插件正确回显）
    function pluginEffectiveOn(p) {
        if (p.locked) return !!p.enabled
        if (root.pluginInScene(p.id)) return true
        return !!p.enabled
    }

    function pluginInScene(id) {
        for (var i = 0; i < root.cfgPlugins.length; i++) {
            var p = root.cfgPlugins[i]
            if (p.id !== id) continue
            if (root.selectedScene === "default") return !!p.inDefault
            return (p.inScenes || []).indexOf(root.selectedScene) !== -1
        }
        return false
    }

    // ---------------- 动作 ----------------

    function close() { root.closeRequested() }

    function refreshList() {
        // 重扫插件目录 + 重生成 ui-state.json（FileView 自动刷新列表）
        if (root.bar) root.bar.run(root.bin + " refresh")
    }

    function sceneIcon(name) {
        for (var i = 0; i < root.cfgScenes.length; i++) {
            if (root.cfgScenes[i].name === name) return root.cfgScenes[i].icon || ""
        }
        return ""
    }

    function setIcon(glyph) {
        var g = String(glyph || "").trim()
        if (root.bar) root.bar.run(root.bin + " icon " + root.selectedScene + " '" + g.replace(/'/g, "") + "'")
    }

    function togglePlugin(id, currentlyIn) {
        if (root.bar) root.bar.run(root.bin + " toggle-plugin " + root.selectedScene + " " + id + " " + (currentlyIn ? "off" : "on"))
        // CLI 内部 = omarchy plugin enable/disable + 更新场景清单 + 重生成 ui-state.json → FileView 刷新
    }

    function toggleLock(id, currentlyLocked) {
        // 锁只对 default 场景的插件有意义：锁定后所有场景继承（始终启用）
        if (root.bar) root.bar.run(root.bin + " " + (currentlyLocked ? "unlock" : "lock") + " " + id)
    }

    // 改名模式：把 TextField 变成“重命名选中场景”
    function toggleRename() {
        if (root.renameMode) {
            root.renameMode = false
            root.newSceneName = ""
            return
        }
        root.renameMode = true
        root.newSceneName = root.sceneLabel(root.selectedScene)
        if (newName) Qt.callLater(function () { newName.forceActiveFocus() })
    }

    function confirmRename() {
        var n = String(root.newSceneName || "").trim()
        root.renameMode = false
        root.newSceneName = ""
        if (!n) return
        // 显示名允许字母/数字/空格/-/_，最多 10 字符
        if (!/^[a-zA-Z0-9 _-]+$/.test(n)) return
        if (n.length > 10) return
        if (root.bar) root.bar.run(root.bin + " label " + root.selectedScene + " '" + n.replace(/'/g, "") + "'")
    }

    function applyAndSwitch() {
        if (root.bar) root.bar.run(root.bin + " set " + root.selectedScene)
        root.close()
    }

    function createScene() {
        var n = String(root.newSceneName || "").trim()
        if (!n || !/^[a-zA-Z0-9_-]+$/.test(n)) return
        if (n.length > 10) return   // 最多 10 字符
        if (root.cfgScenes.length > 5) return   // 最多 5 个自定义场景（含 default 共 6）
        if (root.bar) root.bar.run(root.bin + " add " + n + " --label " + n)
        root.newSceneName = ""
        root.selectedScene = n
    }

    function deleteSelected() {
        if (root.selectedScene === "default") return
        for (var i = 0; i < root.cfgScenes.length; i++) {
            if (root.cfgScenes[i].name === root.selectedScene && root.cfgScenes[i].active) return
        }
        if (root.bar) root.bar.run(root.bin + " rm " + root.selectedScene)
        root.selectedScene = "default"
    }

    // ---------------- 文件监听 ----------------
    FileView {
        id: uiFile
        path: root.uiStatePath
        watchChanges: true
        atomicWrites: true
        onLoaded: root.parseUiState()
        onFileChanged: reload()
    }

    // ---------------- 全屏弹层 ----------------

    PanelWindow {
        id: panel
        visible: true
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        WlrLayershell.namespace: "omarchy-scene-config"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore

        // 遮罩：点击外部关闭
        Rectangle {
            anchors.fill: parent
            color: Util.alpha(Color.background, 0.62)
            MouseArea { anchors.fill: parent; onClicked: root.close() }
        }

        BorderSurface {
            id: card
            width: Math.min(parent.width - Style.space(48), Style.space(500))
            height: Style.space(700)
            anchors.centerIn: parent
            color: Color.background
            borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
            radius: Style.cornerRadius
            padding: Style.space(18)

            MouseArea { anchors.fill: parent; onClicked: {} }

            Item {
                anchors.fill: parent
                anchors.topMargin: card.contentTopInset
                anchors.rightMargin: card.contentRightInset
                anchors.bottomMargin: card.contentBottomInset
                anchors.leftMargin: card.contentLeftInset

                Column {
                    id: topSection
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: Style.space(8)

                    // ---- 标题行 ----
                    Row {
                        width: parent.width
                        spacing: Style.space(6)

                        Text {
                            width: parent.width - Style.space(40)
                            text: "Scene Configuration"
                            color: root.fg
                            font.family: root.barFont
                            font.pixelSize: Style.font.subtitle
                            font.bold: true
                            elide: Text.ElideRight
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
                        text: "Plugins are toggled with omarchy plugin enable/disable. omarchy built-ins follow the system default and are locked — unlock to manage them."
                        color: root.dim
                        font.family: root.barFont
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                    }

                    PanelSeparator {
                        foreground: root.fg
                    }

                    // ---- 场景标签（Flow 自动换行，避免超宽裁剪）+ 新建/删除 ----
                    Flow {
                        id: sceneTabs
                        width: parent.width
                        spacing: Style.space(4)

                        Repeater {
                            model: root.cfgScenes

                            delegate: Item {
                                required property string name
                                required property string label
                                required property bool active
                                property bool hovered: false

                                width: tabText.implicitWidth + Style.space(10)
                                height: Style.space(24)

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Style.cornerRadius
                                    color: (name === root.selectedScene)
                                        ? Style.hoverFillFor(root.fg, Color.accent)
                                        : (hovered ? Style.hoverFillFor(root.dim, Color.accent) : "transparent")
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: hovered = true
                                    onExited: hovered = false
                                    onClicked: root.selectedScene = name
                                }
                                Text {
                                    id: tabText
                                    anchors.centerIn: parent
                                    text: label + (active ? " ✓" : "")
                                    color: (name === root.selectedScene) ? root.fg : root.dim
                                    font.family: root.barFont
                                    font.pixelSize: Style.font.caption
                                    font.bold: (name === root.selectedScene)
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Style.space(6)

                        TextField {
                            id: newName
                            width: parent.width - Style.space(112)
                            height: Style.space(32)
                            verticalPadding: 2
                            maximumLength: 10
                            placeholderText: root.renameMode ? "Rename scene (max 10)" : "New scene (max 10, letters/digits/-/_)"
                            text: root.newSceneName
                            onTextChanged: root.newSceneName = text
                            onAccepted: root.renameMode ? root.confirmRename() : root.createScene()
                            color: root.fg
                            accent: root.fg
                        }
                        PanelActionButton {
                            width: Style.space(30)
                            height: Style.space(30)
                            size: Style.space(30)
                            iconText: root.renameMode ? "\uF00C" : "＋"
                            tooltipText: root.renameMode ? "Confirm rename" : "Create scene (max 5)"
                            enabled: root.renameMode || root.cfgScenes.length <= 5
                            foreground: root.fg
                            hoverColor: root.fg
                            onClicked: root.renameMode ? root.confirmRename() : root.createScene()
                        }
                        PanelActionButton {
                            width: Style.space(30)
                            height: Style.space(30)
                            size: Style.space(30)
                            iconText: root.renameMode ? "\uF00D" : "\uF040"
                            tooltipText: root.renameMode ? "Cancel rename" : "Rename scene"
                            enabled: root.selectedScene !== "default"
                            foreground: root.fg
                            hoverColor: root.fg
                            onClicked: root.toggleRename()
                        }
                        PanelActionButton {
                            width: Style.space(30)
                            height: Style.space(30)
                            size: Style.space(30)
                            iconText: "🗑"
                            tooltipText: "Delete selected scene"
                            enabled: root.selectedScene !== "default" && !root.isCurrentScene
                            foreground: root.fg
                            hoverColor: root.urgent
                            onClicked: root.deleteSelected()
                        }
                    }

                    // ---- 场景图标选择（一排常显 + 展开更多；已选高亮） ----
                    Component {
                        id: sceneIconButton
                        Item {
                            required property string cp
                            required property string label
                            id: ico
                            property bool hovered: false
                            width: Style.space(24)
                            height: Style.space(24)

                            // 选中高亮：填充圆角底 + 亮边框（与插件行 hover 风格一致）
                            Rectangle {
                                anchors.fill: parent
                                radius: Style.cornerRadius
                                color: (ico.cp === root.sceneIconText)
                                    ? Style.hoverFillFor(root.fg, Color.accent)
                                    : (ico.hovered ? Style.hoverFillFor(root.dim, Color.accent) : "transparent")
                                border.color: (ico.cp === root.sceneIconText) ? root.fg : "transparent"
                                border.width: (ico.cp === root.sceneIconText) ? Math.max(1, Style.space(2)) : 0
                            }
                            Text {
                                anchors.centerIn: parent
                                text: ico.cp
                                color: (ico.cp === root.sceneIconText) ? root.fg : (ico.hovered ? root.fg : root.dim)
                                font.family: root.barFont
                                font.pixelSize: Style.font.body
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: ico.hovered = true
                                onExited: ico.hovered = false
                                onClicked: root.setIcon(ico.cp)
                            }
                            PanelToolTip {
                                visible: ico.hovered
                                text: ico.label + (ico.cp === root.sceneIconText ? " (current)" : "")
                                fontFamily: root.barFont
                            }
                        }
                    }

                    Column {
                        visible: !root.renameMode
                        width: parent.width
                        spacing: Style.space(4)

                        Row {
                            width: parent.width
                            spacing: Style.space(6)

                            Text {
                                width: Style.space(48)
                                height: Style.space(24)
                                text: "Icon:"
                                color: root.dim
                                font.family: root.barFont
                                font.pixelSize: Style.font.caption
                                verticalAlignment: Text.AlignVCenter
                            }
                            Flow {
                                width: parent.width - Style.space(48) - Style.space(66)
                                spacing: Style.space(4)
                                Repeater {
                                    model: root.sceneIcons.slice(0, 12)
                                    delegate: sceneIconButton
                                }
                            }
                            PanelActionButton {
                                width: Style.space(24)
                                height: Style.space(24)
                                size: Style.space(18)
                                iconText: root.sceneIconsExpanded ? "\uF106" : "\uF107"
                                tooltipText: root.sceneIconsExpanded ? "Show fewer icons" : "More icons"
                                foreground: root.dim
                                hoverColor: root.fg
                                onClicked: root.sceneIconsExpanded = !root.sceneIconsExpanded
                            }
                            PanelActionButton {
                                width: Style.space(24)
                                height: Style.space(24)
                                size: Style.space(18)
                                iconText: "\uF00D"
                                tooltipText: "Clear icon"
                                foreground: root.dim
                                hoverColor: root.urgent
                                onClicked: root.setIcon("")
                            }
                        }

                        Flow {
                            visible: root.sceneIconsExpanded
                            width: parent.width - Style.space(54)
                            anchors.left: parent.left
                            anchors.leftMargin: Style.space(54)
                            spacing: Style.space(4)
                            Repeater {
                                model: root.sceneIcons.slice(12)
                                delegate: sceneIconButton
                            }
                        }
                    }

                                        // ---- 插件勾选列表（所有非内置 + 内置） ----
                    Text {
                        width: parent.width
                        text: "Configure: " + root.sceneLabel(root.selectedScene)
                        color: root.fg
                        font.family: root.barFont
                        font.pixelSize: Style.font.caption
                        font.bold: true
                    }

                    Text {
                        visible: root.selectedScene === "default"
                        width: parent.width
                        text: "🔒 Locked plugins are inherited by every scene."
                        color: root.dim
                        font.family: root.barFont
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                    }

                    }
                // ---- 插件列表（弹性填充顶部与 footer 之间的空间） ----
                ListView {
                    id: pluginList
                    anchors.top: topSection.bottom
                    anchors.topMargin: Style.space(8)
                    anchors.bottom: footerSection.top
                    anchors.bottomMargin: Style.space(8)
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: Style.space(2)
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.visiblePlugins
                    clip: true

                    // 小节：用户安装插件 / omarchy 内置（payload 已把内置排后，天然分组）
                    section.property: "firstParty"
                    section.criteria: ViewSection.FullString
                    section.delegate: Item {
                        required property string section
                        width: pluginList.width
                        height: Style.space(24)

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Style.space(8)
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: (section === "true") ? "omarchy built-ins" : "User plugins"
                            color: root.dim
                            font.family: root.barFont
                            font.pixelSize: Style.font.caption
                            font.bold: true
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: Style.space(8)
                            anchors.right: parent.right
                            anchors.rightMargin: Style.space(8)
                            anchors.bottom: parent.bottom
                            height: 1
                            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
                        }
                    }
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        width: Style.space(4)
                        background: Rectangle {
                            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.1)
                        }
                        contentItem: Rectangle {
                            radius: Style.space(2)
                            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.35)
                        }
                    }

                        delegate: Item {
                            required property var modelData
                            id: prow
                            width: pluginList.width
                            height: Math.max(Style.space(48), Style.font.body + Style.spacing.md * 3)
                            property bool hovered: false

                            Rectangle {
                                anchors.fill: parent
                                radius: Style.cornerRadius
                                color: prow.hovered ? Style.hoverFillFor(root.fg, Color.accent) : "transparent"
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: modelData.locked ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onEntered: prow.hovered = true
                                onExited: prow.hovered = false
                                onClicked: {
                                    if (!modelData.locked) root.togglePlugin(modelData.id, root.pluginEffectiveOn(modelData))
                                }
                            }

                            // 左侧文字列：垂直居中（锚点布局保证居中）
                            Column {
                                id: labelCol
                                anchors.left: parent.left
                                anchors.leftMargin: Style.space(8)
                                anchors.right: rightArea.left
                                anchors.rightMargin: Style.space(6)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text {
                                    text: modelData.name
                                    color: root.fg
                                    font.family: root.barFont
                                    font.pixelSize: Style.font.body
                                    font.bold: true
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                                Text {
                                    text: modelData.id
                                        + (root.pluginEffectiveOn(modelData) ? " · on" : " · off")
                                        + (modelData.locked ? " · locked" : "")
                                    color: root.dim
                                    font.family: root.barFont
                                    font.pixelSize: Style.font.caption
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }

                            // 右侧：开关 + 锁（锁在开关右边），垂直居中
                            Row {
                                id: rightArea
                                anchors.right: parent.right
                                anchors.rightMargin: Style.space(8)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Style.space(4)

                                // 开关：锁定的插件不显示（始终启用、不可开关）
                                ToggleSwitch {
                                    width: Style.space(38)
                                    height: Style.space(22)
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !modelData.locked
                                    checked: root.pluginEffectiveOn(modelData)
                                    interactive: false
                                    foreground: root.fg
                                    accent: root.fg
                                }

                                // 锁槽（在开关右边，固定宽度保证对齐）
                                Item {
                                    width: Style.space(24)
                                    height: Style.space(24)
                                    anchors.verticalCenter: parent.verticalCenter
                                    // 默认场景视图：可点击的锁按钮（锁住=亮+边框，未锁=暗）
                                    PanelActionButton {
                                        anchors.fill: parent
                                        size: Style.space(24)
                                        iconText: modelData.locked ? "" : ""
                                        tooltipText: modelData.locked
                                            ? (modelData.firstParty
                                                ? "Unlock \"" + modelData.name + "\" (allow manual on/off)"
                                                : "Unlock \"" + modelData.name + "\" (stop inheriting to all scenes)")
                                            : (modelData.firstParty
                                                ? "Lock \"" + modelData.name + "\" (follow system default)"
                                                : "Lock \"" + modelData.name + "\" (inherit to all scenes)")
                                        visible: root.selectedScene === "default"
                                        foreground: modelData.locked ? root.fg : root.dim
                                        hoverColor: root.fg
                                        bordered: modelData.locked
                                        onClicked: root.toggleLock(modelData.id, modelData.locked)
                                    }
                                    // 其它场景视图：锁定插件只显示锁（不可点击、无开关）
                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        color: modelData.locked ? root.fg : "transparent"
                                        font.family: root.barFont
                                        font.pixelSize: Style.font.body
                                        visible: root.selectedScene !== "default"
                                    }
                                }
                            }
                        }
                    }

                // ---- 刷新按钮：列表右上角（User plugins 标题右侧浮层） ----
                PanelActionButton {
                    id: refreshBtn
                    width: Style.space(22)
                    height: Style.space(22)
                    size: Style.space(18)
                    iconText: "\uF0453"
                    tooltipText: "Refresh plugin list (pick up newly installed plugins)"
                    foreground: root.dim
                    hoverColor: root.fg
                    onClicked: root.refreshList()

                    anchors.top: pluginList.top
                    anchors.topMargin: Style.space(2)
                    anchors.right: pluginList.right
                    anchors.rightMargin: Style.space(6)
                }

                // ---- 底部固定 footer ----
                Column {
                    id: footerSection
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: Style.space(8)

                    PanelSeparator {
                        foreground: root.fg
                    }

                    // ---- 底部动作 ----
                    Row {
                        width: parent.width
                        spacing: Style.space(6)

                        PanelActionButton {
                            width: Style.space(30)
                            height: Style.space(30)
                            size: Style.space(30)
                            iconText: "󰁔"
                            tooltipText: "Apply & switch to \"" + root.sceneLabel(root.selectedScene) + "\""
                            onClicked: root.applyAndSwitch()
                            foreground: root.fg
                            hoverColor: root.fg
                        }
                        Text {
                            width: parent.width - Style.space(36)
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Apply to \"" + root.sceneLabel(root.selectedScene) + "\""
                            color: root.dim
                            font.family: root.barFont
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    readonly property bool isCurrentScene: {
        for (var i = 0; i < root.cfgScenes.length; i++) {
            if (root.cfgScenes[i].name === root.selectedScene) return root.cfgScenes[i].active
        }
        return false
    }
}
