import QtQuick
import Quickshell.Io
import qs.Ui
import "SystemMonitorModel.js" as MonitorModel

BarWidget {
  id: root
  moduleName: "bitr0t.system-monitor"

  SystemMonitorTheme {
    id: monitorTheme
    bar: root.bar
    useSystemTheme: root.useSystemTheme
  }

  property int cpuUsage: 0
  property int memoryUsage: 0
  property int gpuUsage: 0
  property real gpuMemoryUsedMiB: 0
  property real gpuMemoryTotalMiB: 0
  property int gpuTemperature: -1
  property bool gpuCommandAvailable: false
  property bool gpuReadingAvailable: false
  property var gpuHistory: []
  property real receiveRate: 0
  property real transmitRate: 0
  property real loadOne: 0
  property real loadFive: 0
  property real loadFifteen: 0
  property real uptimeSeconds: 0
  property bool ready: false
  property var previousStats: null
  property real previousSampleTime: 0
  property var cpuHistory: []
  property var memoryHistory: []
  property var receiveHistory: []
  property var transmitHistory: []
  property var loadHistory: []
  property var availableSensors: []
  property var temperatureSensors: []
  property var fanSensors: []
  property var sensorReadingsById: ({})
  property var sensorHistories: ({})
  property var knownSensorReadingsById: ({})
  property bool sensorsStale: false
  property string pendingSensorsOutput: ""
  property bool sensorStreamFinished: false
  property bool sensorProcessExited: false
  property int sensorExitCode: -1
  readonly property bool sensorTransactionPending:
    sensorStreamFinished || sensorProcessExited
  property bool chipSettingsDirty: false
  property bool stagedUseSystemTheme: false
  property bool stagedShowChipBackground: true
  readonly property bool useSystemTheme: chipSettingsDirty
    ? stagedUseSystemTheme : setting("useSystemTheme", false) === true
  readonly property bool showChipBackground: chipSettingsDirty
    ? stagedShowChipBackground : setting("showChipBackground", true) !== false
  property string stagedChipMode: "instrument"
  property var stagedChipMonitors: []

  readonly property string boundedCommandPath: MonitorModel.localFilePath(Qt.resolvedUrl("bin/bounded-command"))
  readonly property string chipMode: chipSettingsDirty
    ? stagedChipMode
    : MonitorModel.normalizeChipMode(settings ? settings.chipMode : undefined)
  readonly property var chipMonitors: chipSettingsDirty
    ? stagedChipMonitors
    : MonitorModel.normalizeChipMonitors(settings ? settings.monitors : undefined)
  readonly property var selectedSensorMonitorIds: {
    var selected = []
    for (var index = 0; index < chipMonitors.length; index++) {
      var monitorId = chipMonitors[index]
      if (MonitorModel.isSensorMonitorId(monitorId)) selected.push(monitorId)
    }
    return selected
  }
  readonly property var selectedSensorReadings: {
    var selected = []
    for (var index = 0; index < selectedSensorMonitorIds.length; index++) {
      var reading = sensorReadingsById[selectedSensorMonitorIds[index]]
      if (reading) selected.push(reading)
    }
    return selected
  }
  readonly property var unavailableSelectedSensors: {
    var unavailable = []
    for (var index = 0; index < selectedSensorMonitorIds.length; index++) {
      var monitorId = selectedSensorMonitorIds[index]
      if (!sensorReadingsById[monitorId]) unavailable.push(monitorId)
    }
    return unavailable
  }
  readonly property bool sensorPollingActive: opened || selectedSensorMonitorIds.length > 0
  readonly property bool gpuPollingActive: monitorEnabled("gpu") && gpuCommandAvailable
  readonly property string tooltip: ready
    ? "CPU " + cpuUsage + "%  •  Memory " + memoryUsage + "%"
      + (gpuReadingAvailable
        ? "  •  GPU " + gpuUsage + "%  ·  VRAM "
          + (gpuMemoryUsedMiB / 1024).toFixed(1) + "/"
          + (gpuMemoryTotalMiB / 1024).toFixed(1) + " GiB"
          + (gpuTemperature >= 0 ? "  ·  " + gpuTemperature + "°C" : "")
        : "")
      + "\nDownload " + MonitorModel.formatRate(receiveRate) + "  •  Upload " + MonitorModel.formatRate(transmitRate)
      + "\nClick for System Monitor  •  Middle-click for btop  •  Right-click for Task Manager"
    : "Collecting system statistics…"
  readonly property int chevronGap: root.chipMode === "minimal"
    ? Math.round(monitorTheme.monitorGap * 0.5)
    : Math.round(monitorTheme.monitorGap * 1.5)
  readonly property int systemIconGap: root.chipMode === "minimal"
    ? Math.round(monitorTheme.monitorGap * 0.5)
    : Math.round(monitorTheme.monitorGap * 1.25)
  implicitWidth: chevronGap + button.implicitWidth + systemIconGap
  implicitHeight: button.implicitHeight

  function dim(color, opacity) {
    return Qt.rgba(color.r, color.g, color.b, opacity)
  }

  function cpuLevelColor(value) {
    var level = MonitorModel.utilizationLevel(value)
    if (level === "critical") return monitorTheme.criticalColor
    if (level === "warning") return monitorTheme.warningColor
    return monitorTheme.cpuColor
  }

  function memoryLevelColor(value) {
    var level = MonitorModel.utilizationLevel(value)
    if (level === "critical") return monitorTheme.criticalColor
    if (level === "warning") return monitorTheme.warningColor
    return monitorTheme.memoryColor
  }

  function gpuLevelColor(value) {
    var level = MonitorModel.utilizationLevel(value)
    if (level === "critical") return monitorTheme.criticalColor
    if (level === "warning") return monitorTheme.warningColor
    return monitorTheme.gpuColor
  }

  function monitorEnabled(id) {
    return MonitorModel.chipMonitorEnabled(chipMonitors, id)
  }

  function monitorPosition(id) {
    return chipMonitors.indexOf(id)
  }
  function sensorReading(id) {
    return sensorReadingsById && sensorReadingsById[id] ? sensorReadingsById[id] : null
  }

  function sensorHistory(id) {
    return sensorHistories && sensorHistories[id] ? sensorHistories[id] : []
  }

  function sensorDisplayLabel(id) {
    var reading = sensorReading(id)
    if (!reading && knownSensorReadingsById) reading = knownSensorReadingsById[id]
    if (reading) return reading.shortLabel || reading.label || reading.feature

    var parts = String(id || "").split(":")
    if (parts.length === 5) {
      try {
        var feature = decodeURIComponent(parts[3])
        if (feature) return feature
      } catch (error) {
      }
    }
    return MonitorModel.sensorMonitorType(id) === "fan" ? "FAN" : "TEMP"
  }

  function sensorValueText(reading) {
    if (!reading || !isFinite(Number(reading.value))) return "—"
    if (reading.type === "temperature")
      return (Math.round(Number(reading.value) * 10) / 10) + "°"
    if (reading.type === "fan")
      return Math.round(Number(reading.value)) + " RPM"
    return "—"
  }

  function sensorValueReserve(id) {
    return MonitorModel.sensorMonitorType(id) === "fan" ? "99999 RPM" : "999.9°"
  }

  function sensorLevelColor(reading) {
    if (!reading) return monitorTheme.muted
    if (reading.type !== "temperature") return monitorTheme.fanColor

    var value = Number(reading.value)
    if (reading.critical !== null && reading.critical !== undefined
        && isFinite(Number(reading.critical)) && value >= Number(reading.critical))
      return monitorTheme.criticalColor
    if (reading.max !== null && reading.max !== undefined
        && isFinite(Number(reading.max)) && value >= Number(reading.max))
      return monitorTheme.warningColor
    return monitorTheme.temperatureColor
  }

  function stageChipSettings(mode, monitors) {
    if (!chipSettingsDirty) {
      stagedUseSystemTheme = useSystemTheme
      stagedShowChipBackground = showChipBackground
    }
    stagedChipMode = MonitorModel.normalizeChipMode(mode)
    stagedChipMonitors = MonitorModel.normalizeChipMonitors(monitors)
    chipSettingsDirty = true
  }

  function commitChipSettings() {
    if (!chipSettingsDirty) return

    var entry = ({})
    var current = settings || ({})
    for (var key in current) if (key !== "id") entry[key] = current[key]
    entry.id = moduleName || "bitr0t.system-monitor"
    entry.useSystemTheme = stagedUseSystemTheme
    entry.showChipBackground = stagedShowChipBackground
    entry.chipMode = stagedChipMode
    entry.monitors = stagedChipMonitors.slice()

    var localSettings = ({})
    for (var localKey in entry) if (localKey !== "id") localSettings[localKey] = entry[localKey]
    settings = localSettings
    chipSettingsDirty = false

    var shell = bar && bar.shell ? bar.shell : null
    if (shell && typeof shell.updateEntryInline === "function")
      shell.updateEntryInline(entry.id, entry)
  }

  function setChipMode(mode) {
    stageChipSettings(mode, chipMonitors)
  }

  function setMonitorEnabled(id, enabled) {
    stageChipSettings(chipMode, MonitorModel.toggleChipMonitor(chipMonitors, id, enabled))
  }

  function setUseSystemTheme(enabled) {
    stageChipSettings(chipMode, chipMonitors)
    stagedUseSystemTheme = enabled
  }

  function setShowChipBackground(enabled) {
    stageChipSettings(chipMode, chipMonitors)
    stagedShowChipBackground = enabled
  }

  function resetChipSettings() {
    stageChipSettings("instrument", MonitorModel.defaultChipMonitors())
    stagedUseSystemTheme = false
    stagedShowChipBackground = true
  }

  function minimalMonitorText(id) {
    if (id === "cpu") return "CPU " + cpuUsage + "%"
    if (id === "memory") return "MEM " + memoryUsage + "%"
    if (id === "gpu") return "GPU " + (gpuReadingAvailable ? gpuUsage + "%" : "…")
    if (id === "network")
      return "NET ↓" + MonitorModel.formatCompactRate(receiveRate) + " ↑" + MonitorModel.formatCompactRate(transmitRate)
    if (id === "load") return "LOAD " + MonitorModel.formatLoad(loadOne)
    if (id === "uptime") return "UP " + MonitorModel.formatCompactUptime(uptimeSeconds)
    if (MonitorModel.isSensorMonitorId(id))
      return sensorDisplayLabel(id) + " " + sensorValueText(sensorReading(id))
    return ""
  }

  function minimalMonitorReserve(id) {
    if (id === "cpu") return "CPU 99%"
    if (id === "memory") return "MEM 99%"
    if (id === "gpu") return "GPU 99%"
    if (id === "load") return "LOAD 9.99"
    if (id === "uptime") return "UP 99d 23h"
    if (MonitorModel.isSensorMonitorId(id))
      return sensorDisplayLabel(id) + " " + sensorValueReserve(id)
    return ""
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property real openPanelIndicatorWidth: button.implicitWidth
  readonly property real openPanelIndicatorHeight: Math.max(10, Math.round(root.barSize * 0.55))
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  onOpenedChanged: {
    if (!opened) commitChipSettings()
  }

  Component.onDestruction: commitChipSettings()

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function openTaskManager() {
    var items = bar && typeof bar.moduleWidgets === "function"
      ? bar.moduleWidgets(moduleName)
      : []
    for (var index = 0; index < items.length; index++) {
      var widget = items[index]
      if (widget && widget !== root && typeof widget.closeTaskManager === "function")
        widget.closeTaskManager()
    }
    if (taskWindow.opened) taskWindow.focusWindow()
    else taskWindow.open()
  }

  function closeTaskManager() {
    if (taskWindow.opened) taskWindow.close()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  function updateStats(output) {
    var stats = MonitorModel.parseStatsOutput(output)
    if (!stats) return

    var now = Date.now()
    var metrics = MonitorModel.calculateSystemMetrics(stats, previousStats, previousSampleTime, now)

    if (metrics.cpuValue != null) {
      cpuUsage = Math.round(metrics.cpuValue)
      cpuHistory = MonitorModel.appendHistory(cpuHistory, metrics.cpuValue)
    }

    memoryUsage = Math.round(metrics.memoryValue)
    memoryHistory = MonitorModel.appendHistory(memoryHistory, metrics.memoryValue)

    if (previousSampleTime > 0 && now > previousSampleTime) {
      receiveRate = metrics.receiveRate
      transmitRate = metrics.transmitRate
      receiveHistory = MonitorModel.appendHistory(receiveHistory, metrics.receiveRate)
      transmitHistory = MonitorModel.appendHistory(transmitHistory, metrics.transmitRate)
    }

    loadOne = stats.loadOne
    loadFive = stats.loadFive
    loadFifteen = stats.loadFifteen
    loadHistory = MonitorModel.appendHistory(loadHistory, stats.loadOne)
    uptimeSeconds = stats.uptime
    previousStats = stats
    previousSampleTime = now
    ready = true
  }

  function updateGpu(output) {
    var reading = MonitorModel.parseGpuOutput(output)
    if (!reading) {
      gpuReadingAvailable = false
      return
    }

    gpuUsage = Math.round(reading.usage)
    gpuMemoryUsedMiB = reading.memoryUsedMiB
    gpuMemoryTotalMiB = reading.memoryTotalMiB
    gpuTemperature = reading.temperature
    gpuHistory = MonitorModel.appendHistory(gpuHistory, gpuUsage)
    gpuReadingAvailable = true
  }

  function markSensorsStale() {
    availableSensors = []
    temperatureSensors = []
    fanSensors = []
    sensorReadingsById = ({})
    sensorsStale = true
  }

  function applySensorsSample(exitCode, output) {
    if (exitCode !== 0) {
      markSensorsStale()
      return
    }
    updateSensors(output)
  }

  function finishSensorsIfReady() {
    if (!sensorStreamFinished || !sensorProcessExited) return
    var output = pendingSensorsOutput
    var exitCode = sensorExitCode
    pendingSensorsOutput = ""
    sensorStreamFinished = false
    sensorProcessExited = false
    sensorExitCode = -1
    applySensorsSample(exitCode, output)
  }

  function startSensorsProbe() {
    if (!sensorPollingActive || sensorsProcess.running || sensorTransactionPending)
      return
    pendingSensorsOutput = ""
    sensorStreamFinished = false
    sensorProcessExited = false
    sensorExitCode = -1
    sensorsProcess.running = true
  }

  function updateSensors(output) {
    var readings = MonitorModel.parseSensorsJson(output)
    if (readings === null) {
      markSensorsStale()
      return
    }

    var byId = ({})
    var temperatures = []
    var fans = []
    var nextHistories = ({})
    var nextKnownReadings = ({})

    for (var index = 0; index < readings.length; index++) {
      var reading = readings[index]
      byId[reading.id] = reading
      nextKnownReadings[reading.id] = reading
      nextHistories[reading.id] = MonitorModel.appendHistory(
        sensorHistories[reading.id] || [], reading.value)
      if (reading.type === "temperature") temperatures.push(reading)
      else if (reading.type === "fan") fans.push(reading)
    }

    // Prune to the current sensor set plus the persisted selection so hotplug
    // churn cannot grow the maps without bound, while selected sensors keep
    // their labels and histories across temporary absence.
    var selectedIds = selectedSensorMonitorIds
    for (var selectionIndex = 0; selectionIndex < selectedIds.length; selectionIndex++) {
      var selectedId = selectedIds[selectionIndex]
      if (!nextHistories[selectedId] && sensorHistories[selectedId])
        nextHistories[selectedId] = sensorHistories[selectedId]
      if (!nextKnownReadings[selectedId] && knownSensorReadingsById[selectedId])
        nextKnownReadings[selectedId] = knownSensorReadingsById[selectedId]
    }

    availableSensors = readings.slice()
    temperatureSensors = temperatures
    fanSensors = fans
    sensorReadingsById = byId
    sensorHistories = nextHistories
    knownSensorReadingsById = nextKnownReadings
    sensorsStale = false
  }

  component Sparkline: Canvas {
    required property var history
    required property color lineColor
    property real minimumSpan: 10
    readonly property int sampleCapacity: 24
    property bool percentBounded: true

    Behavior on lineColor {
      ColorAnimation { duration: monitorTheme.animationDuration; easing.type: Easing.OutCubic }
    }

    onHistoryChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      var context = getContext("2d")
      context.clearRect(0, 0, width, height)
      if (!history || history.length === 0) return

      var samples = history.slice(Math.max(0, history.length - sampleCapacity))
      var minimum = Number(samples[0])
      var maximum = minimum
      for (var index = 1; index < samples.length; index++) {
        var value = Number(samples[index])
        minimum = Math.min(minimum, value)
        maximum = Math.max(maximum, value)
      }

      var span = Math.max(minimumSpan, maximum - minimum)
      var center = (minimum + maximum) / 2
      var lowerBound = percentBounded
        ? Math.max(0, Math.min(100 - span, center - span / 2))
        : Math.max(0, center - span / 2)
      var xStep = (width - 1) / (sampleCapacity - 1)
      var startX = width - 1 - xStep * (samples.length - 1)

      function sampleX(sampleIndex) {
        return startX + sampleIndex * xStep
      }

      function sampleY(sampleIndex) {
        var normalized = (Number(samples[sampleIndex]) - lowerBound) / span
        normalized = Math.max(0, Math.min(1, normalized))
        return height - 1 - normalized * (height - 2)
      }

      context.beginPath()
      context.moveTo(startX, height - 1)
      for (var fillIndex = 0; fillIndex < samples.length; fillIndex++)
        context.lineTo(sampleX(fillIndex), sampleY(fillIndex))
      context.lineTo(sampleX(samples.length - 1), height - 1)
      context.closePath()
      context.globalAlpha = 0.18
      context.fillStyle = lineColor
      context.fill()

      context.globalAlpha = 1
      context.strokeStyle = lineColor
      context.lineWidth = 1.35
      context.lineCap = "round"
      context.lineJoin = "round"
      context.beginPath()
      context.moveTo(sampleX(0), sampleY(0))
      for (var lineIndex = 1; lineIndex < samples.length; lineIndex++)
        context.lineTo(sampleX(lineIndex), sampleY(lineIndex))
      context.stroke()
    }
  }

  component TrafficGraph: Canvas {
    required property var receiveHistory
    required property var transmitHistory
    required property color receiveColor
    required property color transmitColor
    required property color gridColor
    readonly property int sampleCapacity: 24

    onReceiveHistoryChanged: requestPaint()
    onTransmitHistoryChanged: requestPaint()
    onReceiveColorChanged: requestPaint()
    onTransmitColorChanged: requestPaint()
    onGridColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      var context = getContext("2d")
      context.clearRect(0, 0, width, height)

      var receiveSamples = (receiveHistory || []).slice(Math.max(0, receiveHistory.length - sampleCapacity))
      var transmitSamples = (transmitHistory || []).slice(Math.max(0, transmitHistory.length - sampleCapacity))
      var historyLength = Math.max(receiveSamples.length, transmitSamples.length)
      if (historyLength === 0) return

      var maximumRate = MonitorModel.networkScaleFor(receiveSamples, transmitSamples)

      var middle = height / 2
      var amplitude = middle - 1.5
      var xStep = (width - 1) / (sampleCapacity - 1)
      var startX = width - 1 - xStep * (historyLength - 1)

      context.globalAlpha = 0.34
      context.strokeStyle = gridColor
      context.lineWidth = 1
      context.beginPath()
      context.moveTo(startX, middle)
      context.lineTo(width - 1, middle)
      context.stroke()
      context.globalAlpha = 1

      function drawSeries(history, color, direction) {
        if (!history || history.length === 0) return

        var offset = historyLength - history.length
        var firstX = startX + offset * xStep

        function sampleX(sampleIndex) {
          return firstX + sampleIndex * xStep
        }

        function sampleY(sampleIndex) {
          var value = Math.max(0, Number(history[sampleIndex]))
          var normalized = Math.sqrt(value / maximumRate)
          return middle - direction * Math.min(1, normalized) * amplitude
        }

        context.beginPath()
        context.moveTo(firstX, middle)
        for (var fillIndex = 0; fillIndex < history.length; fillIndex++)
          context.lineTo(sampleX(fillIndex), sampleY(fillIndex))
        context.lineTo(sampleX(history.length - 1), middle)
        context.closePath()
        context.globalAlpha = 0.16
        context.fillStyle = color
        context.fill()

        context.globalAlpha = 1
        context.strokeStyle = color
        context.lineWidth = 1.2
        context.lineCap = "round"
        context.lineJoin = "round"
        context.beginPath()
        context.moveTo(sampleX(0), sampleY(0))
        for (var lineIndex = 1; lineIndex < history.length; lineIndex++)
          context.lineTo(sampleX(lineIndex), sampleY(lineIndex))
        context.stroke()

        context.beginPath()
        context.arc(sampleX(history.length - 1), sampleY(history.length - 1), 1.25, 0, Math.PI * 2)
        context.fillStyle = color
        context.fill()
      }

      drawSeries(receiveSamples, receiveColor, 1)
      drawSeries(transmitSamples, transmitColor, -1)
    }
  }

  component ChipText: Text {
    color: monitorTheme.foreground
    font.family: monitorTheme.fontFamily
    font.pixelSize: Math.max(9, Math.round(root.barSize * 0.38))
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.PlainText
    renderType: Text.NativeRendering

    Behavior on color {
      ColorAnimation { duration: monitorTheme.animationDuration; easing.type: Easing.OutCubic }
    }
    Behavior on opacity {
      NumberAnimation { duration: monitorTheme.animationDuration; easing.type: Easing.OutCubic }
    }
  }

  component ChipDivider: Rectangle {
    width: 1
    height: monitorTheme.graphHeight
    color: monitorTheme.separatorColor
    anchors.verticalCenter: parent.verticalCenter

    Behavior on color {
      ColorAnimation { duration: monitorTheme.animationDuration; easing.type: Easing.OutCubic }
    }
  }

  component CpuInstrument: Row {
    spacing: Math.max(1, Math.round(monitorTheme.monitorGap / 2))
    height: Math.max(monitorTheme.graphHeight, cpuLabel.implicitHeight)

    ChipText {
      id: cpuLabel
      anchors.verticalCenter: parent.verticalCenter
      text: "CPU"
      color: root.useSystemTheme ? root.dim(monitorTheme.foreground, 0.7) : root.dim(monitorTheme.cpuColor, 0.82)
      font.weight: Font.DemiBold
    }

    Sparkline {
      width: monitorTheme.graphWidth
      height: monitorTheme.graphHeight
      anchors.verticalCenter: parent.verticalCenter
      history: root.cpuHistory
      lineColor: monitorTheme.cpuColor
      minimumSpan: 20
    }

    ChipText {
      anchors.verticalCenter: parent.verticalCenter
      text: root.ready ? root.cpuUsage + "%" : "…"
      color: root.cpuLevelColor(root.cpuUsage)
      width: Math.round(monitorTheme.graphWidth * 0.62)
      horizontalAlignment: Text.AlignRight
    }
  }

  component MemoryInstrument: Row {
    spacing: Math.max(1, Math.round(monitorTheme.monitorGap / 2))
    height: Math.max(monitorTheme.graphHeight, memoryLabel.implicitHeight)

    ChipText {
      id: memoryLabel
      anchors.verticalCenter: parent.verticalCenter
      text: "MEM"
      color: root.useSystemTheme ? root.dim(monitorTheme.foreground, 0.7) : root.dim(monitorTheme.memoryColor, 0.82)
      font.weight: Font.DemiBold
    }

    Sparkline {
      width: monitorTheme.graphWidth
      height: monitorTheme.graphHeight
      anchors.verticalCenter: parent.verticalCenter
      history: root.memoryHistory
      lineColor: monitorTheme.memoryColor
      minimumSpan: 1
    }

    ChipText {
      anchors.verticalCenter: parent.verticalCenter
      text: root.ready ? root.memoryUsage + "%" : "…"
      color: root.memoryLevelColor(root.memoryUsage)
      width: Math.round(monitorTheme.graphWidth * 0.62)
      horizontalAlignment: Text.AlignRight
    }
  }

  component GpuInstrument: Row {
    spacing: Math.max(1, Math.round(monitorTheme.monitorGap / 2))
    height: Math.max(monitorTheme.graphHeight, gpuLabel.implicitHeight)

    ChipText {
      id: gpuLabel
      anchors.verticalCenter: parent.verticalCenter
      text: "GPU"
      color: root.useSystemTheme ? root.dim(monitorTheme.foreground, 0.7) : root.dim(monitorTheme.gpuColor, 0.82)
      font.weight: Font.DemiBold
    }

    Sparkline {
      width: monitorTheme.graphWidth
      height: monitorTheme.graphHeight
      anchors.verticalCenter: parent.verticalCenter
      history: root.gpuHistory
      lineColor: monitorTheme.gpuColor
      minimumSpan: 20
    }

    ChipText {
      anchors.verticalCenter: parent.verticalCenter
      text: root.gpuReadingAvailable ? root.gpuUsage + "%" : "…"
      color: root.gpuReadingAvailable ? root.gpuLevelColor(root.gpuUsage) : monitorTheme.muted
      width: Math.round(monitorTheme.graphWidth * 0.62)
      horizontalAlignment: Text.AlignRight
    }
  }

  component NetworkInstrument: Row {
    spacing: Math.max(1, Math.round(monitorTheme.monitorGap / 2))
    height: Math.max(monitorTheme.graphHeight, networkLabel.implicitHeight)

    ChipText {
      id: networkLabel
      anchors.verticalCenter: parent.verticalCenter
      text: "NET"
      color: root.useSystemTheme ? root.dim(monitorTheme.foreground, 0.7) : root.dim(monitorTheme.downloadColor, 0.82)
      font.weight: Font.DemiBold
    }

    TrafficGraph {
      width: monitorTheme.graphWidth
      height: monitorTheme.graphHeight
      anchors.verticalCenter: parent.verticalCenter
      receiveHistory: root.receiveHistory
      transmitHistory: root.transmitHistory
      receiveColor: monitorTheme.downloadColor
      transmitColor: monitorTheme.uploadColor
      gridColor: monitorTheme.graphGrid
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: -Math.max(1, Math.round(monitorTheme.monitorGap / 4))

      ChipText {
        text: "↓" + MonitorModel.formatCompactRate(root.receiveRate)
        color: monitorTheme.downloadColor
        font.pixelSize: Math.max(8, Math.round(root.barSize * 0.34))
        width: monitorTheme.graphWidth
        horizontalAlignment: Text.AlignRight
      }

      ChipText {
        text: "↑" + MonitorModel.formatCompactRate(root.transmitRate)
        color: monitorTheme.uploadColor
        font.pixelSize: Math.max(8, Math.round(root.barSize * 0.34))
        width: monitorTheme.graphWidth
        horizontalAlignment: Text.AlignRight
      }
    }
  }

  component LoadInstrument: Row {
    spacing: Math.max(1, Math.round(monitorTheme.monitorGap / 2))
    height: Math.max(monitorTheme.graphHeight, loadLabel.implicitHeight)

    ChipText {
      id: loadLabel
      anchors.verticalCenter: parent.verticalCenter
      text: "LOAD"
      color: root.useSystemTheme ? root.dim(monitorTheme.foreground, 0.7) : root.dim(monitorTheme.loadColor, 0.82)
      font.weight: Font.DemiBold
    }

    Sparkline {
      width: monitorTheme.graphWidth
      height: monitorTheme.graphHeight
      anchors.verticalCenter: parent.verticalCenter
      history: root.loadHistory
      lineColor: monitorTheme.loadColor
      minimumSpan: 1
      percentBounded: false
    }

    ChipText {
      anchors.verticalCenter: parent.verticalCenter
      text: root.ready ? MonitorModel.formatLoad(root.loadOne) : "…"
      color: monitorTheme.loadColor
      width: monitorTheme.graphWidth
      horizontalAlignment: Text.AlignRight
    }
  }

  component UptimeInstrument: Row {
    spacing: Math.max(1, Math.round(monitorTheme.monitorGap / 2))
    height: Math.max(monitorTheme.graphHeight, uptimeLabel.implicitHeight)

    ChipText {
      id: uptimeLabel
      anchors.verticalCenter: parent.verticalCenter
      text: "UP"
      color: root.useSystemTheme ? root.dim(monitorTheme.foreground, 0.7) : root.dim(monitorTheme.uptimeColor, 0.82)
      font.weight: Font.DemiBold
    }

    ChipText {
      anchors.verticalCenter: parent.verticalCenter
      text: root.ready ? MonitorModel.formatCompactUptime(root.uptimeSeconds) : "…"
      color: monitorTheme.uptimeColor
      horizontalAlignment: Text.AlignRight
    }
  }

  component SensorInstrument: Row {
    id: sensorInstrument
    required property string monitorId
    readonly property var reading: root.sensorReading(monitorId)
    readonly property string sensorType: MonitorModel.sensorMonitorType(monitorId)
    readonly property color instrumentColor: sensorType === "fan"
      ? monitorTheme.fanColor
      : monitorTheme.temperatureColor
    spacing: Math.max(1, Math.round(monitorTheme.monitorGap / 2))
    height: Math.max(monitorTheme.graphHeight, sensorLabel.implicitHeight)
    opacity: reading ? 1 : 0.64

    Behavior on opacity {
      NumberAnimation { duration: monitorTheme.animationDuration; easing.type: Easing.OutCubic }
    }

    ChipText {
      id: sensorLabel
      anchors.verticalCenter: parent.verticalCenter
      text: root.sensorDisplayLabel(sensorInstrument.monitorId)
      color: root.useSystemTheme ? root.dim(monitorTheme.foreground, 0.7) : root.dim(sensorInstrument.instrumentColor, 0.82)
      font.weight: Font.DemiBold
    }

    Sparkline {
      width: monitorTheme.graphWidth
      height: monitorTheme.graphHeight
      anchors.verticalCenter: parent.verticalCenter
      history: sensorInstrument.reading
        ? root.sensorHistory(sensorInstrument.monitorId)
        : []
      lineColor: sensorInstrument.instrumentColor
      minimumSpan: sensorInstrument.sensorType === "fan" ? 500 : 10
      percentBounded: false
    }

    TextMetrics {
      id: sensorValueMetrics
      font.family: monitorTheme.fontFamily
      font.pixelSize: Math.max(9, Math.round(root.barSize * 0.38))
      text: root.sensorValueReserve(sensorInstrument.monitorId)
    }

    ChipText {
      anchors.verticalCenter: parent.verticalCenter
      text: root.sensorValueText(sensorInstrument.reading)
      color: root.sensorLevelColor(sensorInstrument.reading)
      width: sensorValueMetrics.advanceWidth
      horizontalAlignment: Text.AlignRight
    }
  }

  component InstrumentChip: Item {
    implicitWidth: root.chipMonitors.length > 0 ? instrumentMetrics.implicitWidth : emptyInstrument.implicitWidth
    implicitHeight: Math.max(instrumentMetrics.implicitHeight, emptyInstrument.implicitHeight)
    opacity: root.ready ? 1 : 0.64

    Behavior on opacity {
      NumberAnimation { duration: monitorTheme.animationDuration; easing.type: Easing.OutCubic }
    }

    Row {
      id: instrumentMetrics
      anchors.centerIn: parent
      visible: root.chipMonitors.length > 0
      spacing: 0

      Row {
        visible: root.monitorEnabled("cpu")
        spacing: monitorTheme.monitorGap
        ChipDivider { visible: root.monitorPosition("cpu") > 0 }
        CpuInstrument {}
      }

      Row {
        visible: root.monitorEnabled("memory")
        spacing: monitorTheme.monitorGap
        ChipDivider { visible: root.monitorPosition("memory") > 0 }
        MemoryInstrument {}
      }

      Row {
        visible: root.monitorEnabled("gpu")
        spacing: monitorTheme.monitorGap
        ChipDivider { visible: root.monitorPosition("gpu") > 0 }
        GpuInstrument {}
      }

      Row {
        visible: root.monitorEnabled("network")
        spacing: monitorTheme.monitorGap
        ChipDivider { visible: root.monitorPosition("network") > 0 }
        NetworkInstrument {}
      }

      Row {
        visible: root.monitorEnabled("load")
        spacing: monitorTheme.monitorGap
        ChipDivider { visible: root.monitorPosition("load") > 0 }
        LoadInstrument {}
      }

      Row {
        visible: root.monitorEnabled("uptime")
        spacing: monitorTheme.monitorGap
        ChipDivider { visible: root.monitorPosition("uptime") > 0 }
        UptimeInstrument {}
      }

      Repeater {
        model: root.selectedSensorMonitorIds
        delegate: Row {
          required property string modelData
          spacing: monitorTheme.monitorGap
          ChipDivider { visible: root.monitorPosition(modelData) > 0 }
          SensorInstrument { monitorId: modelData }
        }
      }
    }

    ChipText {
      id: emptyInstrument
      anchors.centerIn: parent
      visible: root.chipMonitors.length === 0
      text: "SYS"
      color: monitorTheme.foreground
      font.weight: Font.DemiBold
    }
  }

  component MinimalValue: Item {
    id: minimalValue
    required property string monitorId
    implicitWidth: reserve.advanceWidth
    implicitHeight: value.implicitHeight

    TextMetrics {
      id: reserve
      font.family: monitorTheme.fontFamily
      font.pixelSize: Math.max(9, Math.round(root.barSize * 0.38))
      font.weight: Font.Medium
      text: root.minimalMonitorReserve(minimalValue.monitorId)
    }

    ChipText {
      id: value
      anchors.fill: parent
      text: root.minimalMonitorText(minimalValue.monitorId)
      color: monitorTheme.foreground
      font.weight: Font.Medium
      horizontalAlignment: Text.AlignLeft
    }
  }

  component MinimalRate: Item {
    id: minimalRate
    required property string direction
    required property real rate
    implicitWidth: reserve.advanceWidth
    implicitHeight: value.implicitHeight

    TextMetrics {
      id: reserve
      font.family: monitorTheme.fontFamily
      font.pixelSize: Math.max(9, Math.round(root.barSize * 0.38))
      font.weight: Font.Medium
      text: minimalRate.direction + "999M"
    }

    ChipText {
      id: value
      anchors.fill: parent
      text: minimalRate.direction + MonitorModel.formatCompactRate(minimalRate.rate)
      color: monitorTheme.foreground
      font.weight: Font.Medium
      horizontalAlignment: Text.AlignRight
    }
  }

  component MinimalNetwork: Row {
    spacing: 0

    ChipText {
      text: "NET "
      color: monitorTheme.foreground
      font.weight: Font.Medium
    }
    MinimalRate { direction: "↓"; rate: root.receiveRate }
    ChipText {
      text: " "
      color: monitorTheme.foreground
      font.weight: Font.Medium
    }
    MinimalRate { direction: "↑"; rate: root.transmitRate }
  }

  component MinimalSegment: Row {
    id: segment
    required property string monitorId
    required property int position
    spacing: 0

    ChipText {
      visible: segment.position > 0
      text: monitorTheme.minimalSeparator
      color: monitorTheme.foreground
      font.weight: Font.Medium
    }
    MinimalValue {
      visible: segment.monitorId !== "network"
      monitorId: segment.monitorId
    }
    MinimalNetwork {
      visible: segment.monitorId === "network"
    }
  }

  component MinimalChip: Item {
    implicitWidth: root.chipMonitors.length > 0 ? values.implicitWidth : empty.implicitWidth
    implicitHeight: Math.max(values.implicitHeight, empty.implicitHeight)
    opacity: root.ready || root.chipMonitors.length === 0 ? 1 : 0.64

    Row {
      id: values
      anchors.centerIn: parent
      visible: root.chipMonitors.length > 0
      spacing: 0

      Repeater {
        model: root.chipMonitors
        delegate: MinimalSegment {
          required property string modelData
          required property int index
          monitorId: modelData
          position: index
        }
      }
    }

    ChipText {
      id: empty
      anchors.centerIn: parent
      visible: root.chipMonitors.length === 0
      text: "SYS"
      color: monitorTheme.foreground
      font.weight: Font.Medium
    }
  }

  Component {
    id: instrumentChipComponent
    InstrumentChip {}
  }

  Component {
    id: minimalChipComponent
    MinimalChip {}
  }

  WidgetButton {
    id: button
    anchors.left: parent.left
    anchors.leftMargin: root.chevronGap
    anchors.verticalCenter: parent.verticalCenter
    width: implicitWidth
    height: implicitHeight
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: chipLoader.implicitWidth
      + (root.chipMode === "minimal" ? 0 : monitorTheme.chipPadding * 2)
    fixedHeight: root.barSize
    tooltipText: root.tooltip


    onPressed: function(button) {
      if (button === Qt.MiddleButton && root.bar)
        root.bar.run("omarchy-launch-or-focus-tui btop")
      else if (button === Qt.LeftButton)
        root.togglePanel()
      else if (button === Qt.RightButton)
        root.openTaskManager()
    }

    Rectangle {
      anchors.fill: parent
      anchors.topMargin: Math.max(1, Math.round(monitorTheme.monitorGap / 4))
      anchors.bottomMargin: anchors.topMargin
      visible: root.chipMode === "instrument" && root.showChipBackground
      color: monitorTheme.chipBackground
      border.width: 1
      border.color: monitorTheme.chipBorder
      radius: height / 2

      Behavior on color {
        ColorAnimation { duration: monitorTheme.animationDuration; easing.type: Easing.OutCubic }
      }
      Behavior on opacity {
        NumberAnimation { duration: monitorTheme.animationDuration; easing.type: Easing.OutCubic }
      }
    }

    Loader {
      id: chipLoader
      anchors.centerIn: parent
      sourceComponent: root.chipMode === "minimal" ? minimalChipComponent : instrumentChipComponent
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("SystemMonitorPanel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  SystemTaskManagerWindow {
    id: taskWindow
    bar: root.bar
  }

  IpcHandler {
    target: "bitr0t.system-monitor"

    function taskManager(): void { root.openTaskManager() }
  }

  Process {
    id: sensorsProcess
    running: false
    command: MonitorModel.buildBoundedCommand(
      boundedCommandPath,
      MonitorModel.commandOutputLimit("sensors"),
      ["timeout", "--kill-after=1", "3", "sensors", "-j"]
    )
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.pendingSensorsOutput = String(text || "")
        root.sensorStreamFinished = true
        root.finishSensorsIfReady()
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
    }
    onExited: function (exitCode, exitStatus) {
      root.sensorExitCode = exitCode
      root.sensorProcessExited = true
      root.finishSensorsIfReady()
    }
  }

  Timer {
    interval: 2000
    running: root.sensorPollingActive
    repeat: true
    triggeredOnStart: true
    onTriggered: root.startSensorsProbe()
  }

  FileView {
    path: "/usr/bin/nvidia-smi"
    watchChanges: false
    printErrors: false
    onLoaded: root.gpuCommandAvailable = true
    onLoadFailed: {
      root.gpuCommandAvailable = false
      root.gpuReadingAvailable = false
    }
  }

  Timer {
    interval: 2000
    running: root.gpuPollingActive
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!gpuProcess.running) gpuProcess.running = true
  }

  Process {
    id: gpuProcess
    command: MonitorModel.buildBoundedCommand(
      boundedCommandPath,
      MonitorModel.commandOutputLimit("gpu"),
      ["timeout", "--kill-after=1", "5", "/usr/bin/nvidia-smi",
       "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu",
       "--format=csv,noheader,nounits", "-i", "0"]
    )
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateGpu(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) root.gpuReadingAvailable = false
    }
  }

  Process {
    id: statsProcess
    running: false
    command: MonitorModel.buildBoundedCommand(
      boundedCommandPath,
      MonitorModel.commandOutputLimit("stats"),
      [
        "timeout",
        "--kill-after=1",
        "3",
        "awk",
        "FILENAME == \"/proc/stat\" && FNR == 1 { total = $2 + $3 + $4 + $5 + $6 + $7 + $8 + $9; idle = $5 + $6 } FILENAME == \"/proc/meminfo\" { if ($1 == \"MemTotal:\") memoryTotal = $2; if ($1 == \"MemAvailable:\") memoryAvailable = $2 } FILENAME == \"/proc/net/dev\" && $1 ~ /:$/ && $1 != \"lo:\" { received += $2; transmitted += $10 } FILENAME == \"/proc/loadavg\" { loadOne = $1; loadFive = $2; loadFifteen = $3 } FILENAME == \"/proc/uptime\" { uptime = $1 } END { print total, idle, memoryTotal, memoryAvailable, received, transmitted, loadOne, loadFive, loadFifteen, uptime }",
        "/proc/stat",
        "/proc/meminfo",
        "/proc/net/dev",
        "/proc/loadavg",
        "/proc/uptime"
      ]
    )
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateStats(text)
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!statsProcess.running) statsProcess.running = true
  }
}
