import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  required property var hostWidget
  required property QtObject bar
  property bool active: false

  signal closeRequested()

  enabled: active
  implicitHeight: content.implicitHeight

  readonly property string chipMode: hostWidget && hostWidget.chipMode !== undefined
    ? String(hostWidget.chipMode)
    : "instrument"
  readonly property var temperatureRows: root.sensorRows("temperature", "temperatureSensors")
  readonly property var fanRows: root.sensorRows("fan", "fanSensors")


  function focusFirst() {
    if (root.active) instrumentButton.forceActiveFocus()
  }

  function chooseChipMode(mode) {
    if (root.hostWidget && typeof root.hostWidget.setChipMode === "function")
      root.hostWidget.setChipMode(mode)
  }

  function setMonitorEnabled(id, enabled) {
    if (root.hostWidget && typeof root.hostWidget.setMonitorEnabled === "function")
      root.hostWidget.setMonitorEnabled(id, enabled)
  }
  function monitorEnabled(id) {
    return root.hostWidget && typeof root.hostWidget.monitorEnabled === "function"
      ? root.hostWidget.monitorEnabled(id)
      : false
  }

  function hostArray(name) {
    var value = root.hostWidget ? root.hostWidget[name] : null
    return Array.isArray(value) ? value : []
  }

  function decodeSensorPart(value) {
    try {
      return decodeURIComponent(String(value || ""))
    } catch (error) {
      return String(value || "")
    }
  }

  function sensorIdDetails(id) {
    var parts = String(id || "").split(":")
    if (parts.length !== 5 || parts[0] !== "sensor"
        || (parts[1] !== "temperature" && parts[1] !== "fan"))
      return null
    return {
      id: String(id),
      type: parts[1],
      device: root.decodeSensorPart(parts[2]),
      feature: root.decodeSensorPart(parts[3]),
      inputKey: root.decodeSensorPart(parts[4])
    }
  }

  function readableSensorName(value, fallback) {
    var text = String(value || "").replace(/[_-]+/g, " ").replace(/\s+/g, " ")
    text = text.replace(/^\s+|\s+$/g, "")
    if (text.length === 0) return fallback
    return text.charAt(0).toUpperCase() + text.slice(1)
  }

  function sensorRows(type, hostProperty) {
    var rows = []
    var seen = ({})
    var readings = root.hostArray(hostProperty)
    for (var i = 0; i < readings.length; ++i) {
      var reading = readings[i]
      if (!reading || typeof reading.id !== "string" || seen[reading.id]) continue
      seen[reading.id] = true
      rows.push(reading)
    }

    var unavailable = root.hostArray("unavailableSelectedSensors")
    for (var j = 0; j < unavailable.length; ++j) {
      var details = root.sensorIdDetails(unavailable[j])
      if (!details || details.type !== type || seen[details.id]) continue
      seen[details.id] = true
      rows.push({
        id: details.id,
        type: details.type,
        deviceLabel: details.device,
        label: root.readableSensorName(
          details.feature,
          type === "temperature" ? "Temperature" : "Fan"),
        value: null,
        unit: "",
        available: false
      })
    }
    return rows
  }

  function sensorDescription(sensor) {
    var device = String(sensor && sensor.deviceLabel || "Unknown device")
    if (!sensor || sensor.available === false)
      return device + " · Unavailable — turn off to remove."
    var unit = String(sensor.unit || "")
    var separator = unit.length > 0 ? " " : ""
    return device + " · " + String(sensor.value) + separator + unit
  }

  function sensorStateText(type) {
    var noun = type === "temperature" ? "temperature" : "fan"
    if (!root.hostWidget || root.hostWidget.availableSensors === undefined
        || root.hostWidget.availableSensors === null
        || root.hostWidget.sensorsLoading === true
        || root.hostWidget.sensorLoading === true)
      return "Loading " + noun + " readings…"
    return "No " + noun + " readings detected."
  }

  function firstSensorToggle() {
    if (temperatureRepeater.count > 0) return temperatureRepeater.itemAt(0)
    if (fanRepeater.count > 0) return fanRepeater.itemAt(0)
    return resetButton
  }

  function lastSensorToggle() {
    if (fanRepeater.count > 0) return fanRepeater.itemAt(fanRepeater.count - 1)
    if (temperatureRepeater.count > 0)
      return temperatureRepeater.itemAt(temperatureRepeater.count - 1)
    return gpuToggle
  }

  function nextTemperatureToggle(index) {
    if (index + 1 < temperatureRepeater.count)
      return temperatureRepeater.itemAt(index + 1)
    if (fanRepeater.count > 0) return fanRepeater.itemAt(0)
    return resetButton
  }

  function previousTemperatureToggle(index) {
    return index > 0 ? temperatureRepeater.itemAt(index - 1) : gpuToggle
  }

  function nextFanToggle(index) {
    return index + 1 < fanRepeater.count
      ? fanRepeater.itemAt(index + 1)
      : resetButton
  }

  function previousFanToggle(index) {
    if (index > 0) return fanRepeater.itemAt(index - 1)
    if (temperatureRepeater.count > 0)
      return temperatureRepeater.itemAt(temperatureRepeater.count - 1)
    return gpuToggle
  }


  function resetChipSettings() {
    if (root.hostWidget && typeof root.hostWidget.resetChipSettings === "function")
      root.hostWidget.resetChipSettings()
  }
  component SensorToggleRow: Toggle {
    required property var sensor
    property Item nextFocusItem: null
    property Item previousFocusItem: null
    property color sensorAccent: monitorTheme.accentColor

    label: String(sensor.label || "")
    description: root.sensorDescription(sensor)
    checked: root.monitorEnabled(sensor.id)
    foreground: monitorTheme.foreground
    accent: sensorAccent
    fontFamily: monitorTheme.fontFamily
    onClicked: root.setMonitorEnabled(sensor.id, !checked)

    KeyNavigation.tab: nextFocusItem
    KeyNavigation.backtab: previousFocusItem
    Accessible.role: Accessible.CheckBox
    Accessible.name: label
    Accessible.description: description
    Accessible.checked: checked
  }


  onActiveChanged: {
    if (active) Qt.callLater(root.focusFirst)
  }

  Keys.onEscapePressed: function(event) {
    root.closeRequested()
    event.accepted = true
  }

  SystemMonitorTheme {
    id: monitorTheme
    bar: root.bar
    useSystemTheme: root.hostWidget ? root.hostWidget.useSystemTheme === true : false
  }

  Column {
    id: content

    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.spacing.xl

    Item {
      width: parent.width
      implicitHeight: Math.max(headerCopy.implicitHeight, doneButton.implicitHeight)

      Column {
        id: headerCopy

        anchors.left: parent.left
        anchors.right: doneButton.left
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs

        Text {
          width: parent.width
          text: "Chip settings"
          textFormat: Text.PlainText
          color: monitorTheme.foreground
          font.family: monitorTheme.fontFamily
          font.pixelSize: Style.font.title
          font.weight: Font.Medium
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: "Choose the values shown in the bar."
          textFormat: Text.PlainText
          color: monitorTheme.muted
          font.family: monitorTheme.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }

      Button {
        id: doneButton

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Done"
        bordered: true
        focusable: root.active
        foreground: monitorTheme.foreground
        accent: monitorTheme.accentColor
        fontFamily: monitorTheme.fontFamily
        onClicked: root.closeRequested()

        KeyNavigation.tab: instrumentButton
        KeyNavigation.backtab: resetButton
        Accessible.role: Accessible.Button
        Accessible.name: "Close chip settings"
      }
    }

    PanelSeparator {
      width: parent.width
    }

    Column {
      width: parent.width
      spacing: Style.spacing.md

      PanelSectionHeader {
        text: "CHIP STYLE"
        foreground: monitorTheme.foreground
        fontFamily: monitorTheme.fontFamily
      }

      Text {
        width: parent.width
        text: "Instrument uses color and motion; Minimal is compact monochrome text."
        textFormat: Text.PlainText
        color: monitorTheme.muted
        font.family: monitorTheme.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Row {
        id: modeButtons

        width: parent.width
        spacing: monitorTheme.monitorGap

        Button {
          id: instrumentButton

          width: Math.floor((modeButtons.width - modeButtons.spacing) / 2)
          text: "Instrument"
          selected: root.chipMode === "instrument"
          bordered: true
          focusable: root.active
          foreground: monitorTheme.foreground
          accent: monitorTheme.accentColor
          fontFamily: monitorTheme.fontFamily
          onClicked: root.chooseChipMode("instrument")

          KeyNavigation.tab: minimalButton
          KeyNavigation.backtab: doneButton
          Accessible.role: Accessible.RadioButton
          Accessible.name: "Instrument chip style"
          Accessible.description: "Show colored values with motion"
          Accessible.checked: selected
        }

        Button {
          id: minimalButton

          width: Math.floor((modeButtons.width - modeButtons.spacing) / 2)
          text: "Minimal"
          selected: root.chipMode === "minimal"
          bordered: true
          focusable: root.active
          foreground: monitorTheme.foreground
          accent: monitorTheme.accentColor
          fontFamily: monitorTheme.fontFamily
          onClicked: root.chooseChipMode("minimal")

          KeyNavigation.tab: systemThemeToggle
          KeyNavigation.backtab: instrumentButton
          Accessible.role: Accessible.RadioButton
          Accessible.name: "Minimal chip style"
          Accessible.description: "Show compact monochrome text"
          Accessible.checked: selected
        }
      }
    }

    Column {
      width: parent.width
      spacing: monitorTheme.monitorGap

      Toggle {
        id: systemThemeToggle
        width: parent.width
        label: "Use system theme"
        description: "Use the theme accent and text tones for signals, and its alert color for high usage."
        checked: root.hostWidget ? root.hostWidget.useSystemTheme === true : false
        foreground: monitorTheme.foreground
        accent: monitorTheme.accentColor
        fontFamily: monitorTheme.fontFamily
        onClicked: root.hostWidget.setUseSystemTheme(!checked)
        KeyNavigation.tab: chipBackgroundToggle
        KeyNavigation.backtab: minimalButton
        Accessible.role: Accessible.CheckBox
        Accessible.name: label
        Accessible.description: description
        Accessible.checked: checked
      }

      Toggle {
        id: chipBackgroundToggle
        width: parent.width
        label: "Show chip background"
        description: "Draw a rounded background and outline around the instrument gauges."
        checked: root.hostWidget ? root.hostWidget.showChipBackground !== false : true
        foreground: monitorTheme.foreground
        accent: monitorTheme.accentColor
        fontFamily: monitorTheme.fontFamily
        onClicked: root.hostWidget.setShowChipBackground(!checked)
        KeyNavigation.tab: cpuToggle
        KeyNavigation.backtab: systemThemeToggle
        Accessible.role: Accessible.CheckBox
        Accessible.name: label
        Accessible.description: description
        Accessible.checked: checked
      }
    }

    Column {
      width: parent.width
      spacing: monitorTheme.monitorGap

      PanelSectionHeader {
        text: "CHIP MONITORS"
        foreground: monitorTheme.foreground
        fontFamily: monitorTheme.fontFamily
      }

      Toggle {
        id: cpuToggle

        width: parent.width
        label: "CPU"
        description: "Processor use and recent trend."
        checked: root.monitorEnabled("cpu")
        foreground: monitorTheme.foreground
        accent: monitorTheme.accentColor
        fontFamily: monitorTheme.fontFamily
        onClicked: root.setMonitorEnabled("cpu", !checked)

        KeyNavigation.tab: memoryToggle
        KeyNavigation.backtab: chipBackgroundToggle
        Accessible.role: Accessible.CheckBox
        Accessible.name: label
        Accessible.description: description
        Accessible.checked: checked
      }

      Toggle {
        id: memoryToggle

        width: parent.width
        label: "Memory"
        description: "Used memory and recent trend."
        checked: root.monitorEnabled("memory")
        foreground: monitorTheme.foreground
        accent: monitorTheme.accentColor
        fontFamily: monitorTheme.fontFamily
        onClicked: root.setMonitorEnabled("memory", !checked)

        KeyNavigation.tab: gpuToggle
        KeyNavigation.backtab: cpuToggle
        Accessible.role: Accessible.CheckBox
        Accessible.name: label
        Accessible.description: description
        Accessible.checked: checked
      }

      Toggle {
        id: gpuToggle

        width: parent.width
        label: "GPU"
        description: "NVIDIA GPU utilization; requires nvidia-smi."
        checked: root.monitorEnabled("gpu")
        enabled: root.hostWidget && root.hostWidget.gpuCommandAvailable === true
        foreground: monitorTheme.foreground
        accent: monitorTheme.gpuColor
        fontFamily: monitorTheme.fontFamily
        onClicked: root.setMonitorEnabled("gpu", !checked)

        KeyNavigation.tab: networkToggle
        KeyNavigation.backtab: memoryToggle
        Accessible.role: Accessible.CheckBox
        Accessible.name: label
        Accessible.description: description
        Accessible.checked: checked
      }

      Toggle {
        id: networkToggle

        width: parent.width
        label: "Network"
        description: "Download and upload rates."
        checked: root.monitorEnabled("network")
        foreground: monitorTheme.foreground
        accent: monitorTheme.accentColor
        fontFamily: monitorTheme.fontFamily
        onClicked: root.setMonitorEnabled("network", !checked)

        KeyNavigation.tab: loadToggle
        KeyNavigation.backtab: gpuToggle
        Accessible.role: Accessible.CheckBox
        Accessible.name: label
        Accessible.description: description
        Accessible.checked: checked
      }

      Toggle {
        id: loadToggle

        width: parent.width
        label: "Load"
        description: "One-minute system load average."
        checked: root.monitorEnabled("load")
        foreground: monitorTheme.foreground
        accent: monitorTheme.accentColor
        fontFamily: monitorTheme.fontFamily
        onClicked: root.setMonitorEnabled("load", !checked)

        KeyNavigation.tab: uptimeToggle
        KeyNavigation.backtab: networkToggle
        Accessible.role: Accessible.CheckBox
        Accessible.name: label
        Accessible.description: description
        Accessible.checked: checked
      }

      Toggle {
        id: uptimeToggle

        width: parent.width
        label: "Uptime"
        description: "Time since this system started."
        checked: root.monitorEnabled("uptime")
        foreground: monitorTheme.foreground
        accent: monitorTheme.accentColor
        fontFamily: monitorTheme.fontFamily
        onClicked: root.setMonitorEnabled("uptime", !checked)

        KeyNavigation.tab: gpuToggle
        KeyNavigation.backtab: loadToggle
        Accessible.role: Accessible.CheckBox
        Accessible.name: label
        Accessible.description: description
        Accessible.checked: checked
      }

      Text {
        width: parent.width
        text: "Turn off every monitor to show only SYS; the gear remains available."
        textFormat: Text.PlainText
        color: monitorTheme.muted
        font.family: monitorTheme.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }
    Column {
      id: temperatureGroup

      width: parent.width
      spacing: monitorTheme.monitorGap

      PanelSectionHeader {
        text: "TEMPERATURES"
        foreground: monitorTheme.foreground
        fontFamily: monitorTheme.fontFamily
      }

      Repeater {
        id: temperatureRepeater
        model: root.temperatureRows

        delegate: SensorToggleRow {
          required property var modelData
          required property int index

          width: temperatureGroup.width
          sensor: modelData
          sensorAccent: monitorTheme.temperatureColor
          previousFocusItem: root.previousTemperatureToggle(index)
          nextFocusItem: root.nextTemperatureToggle(index)
        }
      }

      Text {
        width: parent.width
        visible: temperatureRepeater.count === 0
        text: root.sensorStateText("temperature")
        textFormat: Text.PlainText
        color: monitorTheme.muted
        font.family: monitorTheme.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }

    Column {
      id: fanGroup

      width: parent.width
      spacing: monitorTheme.monitorGap

      PanelSectionHeader {
        text: "FANS"
        foreground: monitorTheme.foreground
        fontFamily: monitorTheme.fontFamily
      }

      Repeater {
        id: fanRepeater
        model: root.fanRows

        delegate: SensorToggleRow {
          required property var modelData
          required property int index

          width: fanGroup.width
          sensor: modelData
          sensorAccent: monitorTheme.fanColor
          previousFocusItem: root.previousFanToggle(index)
          nextFocusItem: root.nextFanToggle(index)
        }
      }

      Text {
        width: parent.width
        visible: fanRepeater.count === 0
        text: root.sensorStateText("fan")
        textFormat: Text.PlainText
        color: monitorTheme.muted
        font.family: monitorTheme.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }


    Button {
      id: resetButton

      text: "Reset to defaults"
      bordered: true
      focusable: root.active
      foreground: monitorTheme.foreground
      accent: monitorTheme.accentColor
      fontFamily: monitorTheme.fontFamily
      onClicked: root.resetChipSettings()

      KeyNavigation.tab: doneButton
      KeyNavigation.backtab: root.lastSensorToggle()
      Accessible.role: Accessible.Button
      Accessible.name: "Reset chip settings to defaults"
    }

    Text {
      width: parent.width
      text: "Choices save when the monitor panel closes. Colors, spacing, and motion follow [system-monitor] theme tokens."
      textFormat: Text.PlainText
      color: monitorTheme.muted
      font.family: monitorTheme.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
