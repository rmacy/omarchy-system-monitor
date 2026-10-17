import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "bitr0t.system-monitor"
  ipcTarget: "bitr0t.system-monitor"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  SystemMonitorTheme {
    id: theme
    bar: root.bar
    useSystemTheme: root.hostWidget ? root.hostWidget.useSystemTheme === true : false
  }

  readonly property int performanceTab: 0
  readonly property int processesTab: 1
  readonly property int systemInfoTab: 2
  readonly property int settingsPage: 3
  readonly property int tabCount: 3
  readonly property int dataPageHeight: Style.space(380)
  property int selectedTab: performanceTab
  property int lastDataTab: performanceTab
  readonly property bool settingsSelected: selectedTab === settingsPage
  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  onOpenedChanged: {
    if (!opened && settingsSelected) selectedTab = lastDataTab
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function selectTab(index) {
    if (index < root.performanceTab || index > root.systemInfoTab) return
    root.selectedTab = index
    root.lastDataTab = index
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  function toggleSettings() {
    if (root.settingsSelected) {
      root.selectTab(root.lastDataTab)
      return
    }
    if (root.selectedTab >= root.performanceTab && root.selectedTab <= root.systemInfoTab)
      root.lastDataTab = root.selectedTab
    root.selectedTab = root.settingsPage
    Qt.callLater(function() {
      if (root.opened && root.settingsSelected && typeof settingsView.focusFirst === "function")
        settingsView.focusFirst()
    })
  }

  function selectRelativeTab(direction) {
    var current = root.settingsSelected ? root.lastDataTab : root.selectedTab
    var next = (current + direction + root.tabCount) % root.tabCount
    root.selectTab(next)
  }

  function openBtop() {
    if (root.bar && typeof root.bar.run === "function")
      root.bar.run("omarchy-launch-or-focus-tui btop")
    root.close()
  }

  Shortcut {
    sequence: "Ctrl+Tab"
    context: Qt.WindowShortcut
    enabled: root.opened
    onActivated: root.selectRelativeTab(1)
  }

  Shortcut {
    sequence: "Ctrl+Shift+Tab"
    context: Qt.WindowShortcut
    enabled: root.opened
    onActivated: root.selectRelativeTab(-1)
  }

  Component {
    id: monitorIcon

    Text {
      text: "󰍛"
      color: theme.foreground
      font.family: theme.fontFamily
      font.pixelSize: Style.font.display
    }
  }

  KeyboardPanel {
    id: panel

    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(600))
    contentHeight: panel.fittedContentHeight(monitorColumn.implicitHeight)

    // Raw-key funnel for the processes tab. PanelKeyCatcher is blocked
    // while the settings page is up or while the selected processes view
    // owns its keys (search field focused, kill dialog open); blocked, it
    // leaves the raw key event to bubble, and this wrapper offers it to
    // processView.handleKey() — the confirm dialog answers first, so
    // Escape/Enter/arrows/Tab never close the panel or switch tabs
    // mid-confirmation. Plain search typing still reaches the field.
    Item {
      id: processKeySink

      anchors.fill: parent

      Keys.onPressed: function(event) {
        if (root.selectedTab === root.processesTab
            && processView.inputOwnsKeys
            && processView.handleKey(event)) {
          event.accepted = true
        }
      }

      PanelKeyCatcher {
        id: keyCatcher

        blocked: root.settingsSelected
          || (root.selectedTab === root.processesTab && processView.inputOwnsKeys)
        anchors.fill: parent
        onMoveRequested: function(dx, dy) {
          if (dx !== 0) root.selectRelativeTab(dx)
        }
        onCloseRequested: root.close()
        onTabRequested: function(direction) { root.switchPanel(direction) }

        Flickable {
          id: monitorScroll

          anchors.fill: parent
          contentWidth: monitorColumn.width
          contentHeight: monitorColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          Column {
            id: monitorColumn

            width: monitorScroll.width
            spacing: theme.monitorGap

            PanelHero {
              width: parent.width
              iconComponent: monitorIcon
              title: "System Monitor"
              meta: "LIVE SYSTEM RESOURCES"
              foreground: theme.foreground
              fontFamily: theme.fontFamily
              trailingControl: Component {
                PanelActionButton {
                  iconText: "󰒓"
                  tooltipText: "Settings"
                  foreground: theme.muted
                  hoverColor: theme.accentColor
                  fontFamily: theme.fontFamily
                  bordered: true
                  hasCursor: root.settingsSelected
                  onClicked: root.toggleSettings()

                  Accessible.role: Accessible.Button
                  Accessible.name: "System monitor settings"
                  Accessible.checkable: true
                  Accessible.checked: root.settingsSelected
                }
              }
            }

            Row {
              id: tabs

              width: parent.width
              spacing: theme.monitorGap
              readonly property real tabWidth:
                (width - spacing * (root.tabCount - 1)) / root.tabCount

              Button {
                width: tabs.tabWidth
                text: "Performance"
                selected: root.selectedTab === root.performanceTab
                bordered: true
                foreground: theme.foreground
                fontFamily: theme.fontFamily
                onClicked: root.selectTab(root.performanceTab)

                Accessible.role: Accessible.PageTab
                Accessible.name: text
                Accessible.selected: selected
              }

              Button {
                width: tabs.tabWidth
                text: "Processes"
                selected: root.selectedTab === root.processesTab
                bordered: true
                foreground: theme.foreground
                fontFamily: theme.fontFamily
                onClicked: root.selectTab(root.processesTab)

                Accessible.role: Accessible.PageTab
                Accessible.name: text
                Accessible.selected: selected
              }

              Button {
                width: tabs.tabWidth
                text: "System Info"
                selected: root.selectedTab === root.systemInfoTab
                bordered: true
                foreground: theme.foreground
                fontFamily: theme.fontFamily
                onClicked: root.selectTab(root.systemInfoTab)

                Accessible.role: Accessible.PageTab
                Accessible.name: text
                Accessible.selected: selected
              }
            }

            Item {
              id: viewStack

              width: parent.width
              implicitHeight: root.settingsSelected
                ? settingsView.implicitHeight
                : root.dataPageHeight
              height: root.settingsSelected
                ? settingsView.implicitHeight
                : root.dataPageHeight

              SystemPerformanceView {
                id: performanceView

                anchors.fill: parent
                hostWidget: root.hostWidget
                bar: root.bar
                active: root.opened && root.selectedTab === root.performanceTab
                visible: root.selectedTab === root.performanceTab
                onOpenBtopRequested: root.openBtop()
              }

              SystemProcessView {
                id: processView

                anchors.fill: parent
                bar: root.bar
                active: root.opened && root.selectedTab === root.processesTab
                visible: root.selectedTab === root.processesTab
                fullViewAvailable: true
                onOpenBtopRequested: root.openBtop()
                onOpenTaskManagerRequested: {
                  if (root.hostWidget && typeof root.hostWidget.openTaskManager === "function")
                    root.hostWidget.openTaskManager()
                  root.close()
                }
              }

              SystemInfoView {
                id: systemInfoView

                anchors.fill: parent
                bar: root.bar
                active: root.opened && root.selectedTab === root.systemInfoTab
                visible: root.selectedTab === root.systemInfoTab
              }

              SystemMonitorSettingsView {
                id: settingsView

                anchors.fill: parent
                hostWidget: root.hostWidget
                bar: root.bar
                active: root.opened && root.settingsSelected
                visible: root.settingsSelected
                onCloseRequested: root.selectTab(root.lastDataTab)
              }
            }
          }
        }
      }
    }
  }
}
