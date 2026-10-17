import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "SystemMonitorModel.js" as MonitorModel

Item {
  id: root

  required property var hostWidget
  required property QtObject bar
  property bool active: false

  signal openBtopRequested()

  SystemMonitorTheme {
    id: theme
    bar: root.bar
    useSystemTheme: root.hostWidget ? root.hostWidget.useSystemTheme === true : false
  }

  readonly property real cpuUsage: MonitorModel.finiteNumber(hostWidget ? hostWidget.cpuUsage : 0, 0)
  readonly property real memoryUsage: MonitorModel.finiteNumber(hostWidget ? hostWidget.memoryUsage : 0, 0)
  readonly property real receiveRate: MonitorModel.finiteNumber(hostWidget ? hostWidget.receiveRate : 0, 0)
  readonly property real transmitRate: MonitorModel.finiteNumber(hostWidget ? hostWidget.transmitRate : 0, 0)
  readonly property real loadOne: MonitorModel.finiteNumber(hostWidget && hostWidget.loadOne !== undefined ? hostWidget.loadOne : 0, 0)
  readonly property real loadFive: MonitorModel.finiteNumber(hostWidget && hostWidget.loadFive !== undefined ? hostWidget.loadFive : 0, 0)
  readonly property real loadFifteen: MonitorModel.finiteNumber(hostWidget && hostWidget.loadFifteen !== undefined ? hostWidget.loadFifteen : 0, 0)
  readonly property real uptimeSeconds: MonitorModel.finiteNumber(hostWidget && hostWidget.uptimeSeconds !== undefined ? hostWidget.uptimeSeconds : 0, 0)
  readonly property var cpuHistory: MonitorModel.recentHistory(hostWidget ? hostWidget.cpuHistory : [])
  readonly property var memoryHistory: MonitorModel.recentHistory(hostWidget ? hostWidget.memoryHistory : [])
  readonly property var receiveHistory: MonitorModel.recentHistory(hostWidget ? hostWidget.receiveHistory : [])
  readonly property var transmitHistory: MonitorModel.recentHistory(hostWidget ? hostWidget.transmitHistory : [])
  readonly property real networkScale: MonitorModel.networkScaleFor(receiveHistory, transmitHistory)

  readonly property int dashboardHeight: Style.space(380)
  readonly property int headerHeight: Style.space(32)
  readonly property int percentGraphHeight: Style.space(142)
  readonly property real networkGraphHeight: Math.max(
    Style.space(104),
    dashboardHeight - headerHeight - percentGraphHeight - readoutHeight - Style.spacing.lg * 3)
  readonly property int readoutHeight: Style.space(72)
  readonly property int sensorCardHeight: Style.space(132)
  readonly property var selectedSensorCards: buildSelectedSensorCards()
  readonly property bool hasSelectedSensors: selectedSensorCards.length > 0
  implicitHeight: dashboardHeight

  property bool diskProbeComplete: false
  property bool diskAvailable: false
  property real diskUsedBytes: 0
  property real diskTotalBytes: 0
  property int diskUsedPercent: 0

  property bool gpuCommandAvailable: false
  property bool gpuProbeFailed: false
  property bool gpuReadingAvailable: false
  property int gpuUsage: 0
  property real gpuMemoryUsedMiB: 0
  property real gpuMemoryTotalMiB: 0
  property int gpuTemperature: -1

  property string probeKind: ""
  property string probeOutput: ""
  property bool probeStreamFinished: false
  property bool probeProcessExited: false
  property bool probeCancelled: false
  property int probeExitCode: -1
  readonly property string boundedCommandPath: MonitorModel.localFilePath(
    Qt.resolvedUrl("bin/bounded-command"))

  readonly property int visibleReadoutCount: gpuCommandAvailable && !gpuProbeFailed ? 4 : 3

  function isDynamicSensorId(id) {
    if (typeof MonitorModel.isSensorMonitorId === "function")
      return MonitorModel.isSensorMonitorId(id)
    return /^sensor:(temperature|fan):/.test(String(id || ""))
  }

  function decodedSensorPart(value) {
    try {
      return decodeURIComponent(String(value || ""))
    } catch (error) {
      return String(value || "")
    }
  }

  function missingSensorReading(id, source) {
    var parts = String(id || "").split(":")
    var type = source && source.type
      ? String(source.type)
      : (parts.length > 1 ? String(parts[1]) : "temperature")
    var device = source && source.device
      ? String(source.device)
      : decodedSensorPart(parts.length > 2 ? parts[2] : "")
    var feature = source && source.feature
      ? String(source.feature)
      : decodedSensorPart(parts.length > 3 ? parts[3] : "")
    return {
      id: String(id || ""),
      type: type,
      device: device,
      deviceLabel: source && source.deviceLabel
        ? String(source.deviceLabel) : (device || "Sensor device"),
      feature: feature,
      label: source && source.label
        ? String(source.label) : (feature || "Sensor input"),
      shortLabel: source && source.shortLabel
        ? String(source.shortLabel) : (feature || "Sensor"),
      inputKey: source && source.inputKey
        ? String(source.inputKey)
        : decodedSensorPart(parts.length > 4 ? parts[4] : ""),
      value: NaN,
      unit: source && source.unit
        ? String(source.unit) : (type === "fan" ? "RPM" : "°C"),
      max: source ? source.max : null,
      critical: source ? source.critical : null
    }
  }

  function buildSelectedSensorCards() {
    var readings = hostWidget && hostWidget.selectedSensorReadings
      ? hostWidget.selectedSensorReadings : []
    var unavailable = hostWidget && hostWidget.unavailableSelectedSensors
      ? hostWidget.unavailableSelectedSensors : []
    var monitors = hostWidget && hostWidget.chipMonitors
      ? hostWidget.chipMonitors : []
    var readingsById = ({})
    var unavailableById = ({})
    var cards = []
    var included = ({})

    for (var readingIndex = 0; readingIndex < readings.length; readingIndex++) {
      var reading = readings[readingIndex]
      if (reading && isDynamicSensorId(reading.id))
        readingsById[String(reading.id)] = reading
    }
    for (var missingIndex = 0; missingIndex < unavailable.length; missingIndex++) {
      var unavailableEntry = unavailable[missingIndex]
      var unavailableId = typeof unavailableEntry === "string"
        ? unavailableEntry : (unavailableEntry ? unavailableEntry.id : "")
      if (isDynamicSensorId(unavailableId))
        unavailableById[String(unavailableId)] = unavailableEntry
    }

    for (var monitorIndex = 0; monitorIndex < monitors.length; monitorIndex++) {
      var monitorId = String(monitors[monitorIndex] || "")
      if (!isDynamicSensorId(monitorId)) continue
      if (readingsById[monitorId])
        cards.push(readingsById[monitorId])
      else
        cards.push(missingSensorReading(monitorId, unavailableById[monitorId]))
      included[monitorId] = true
    }

    for (var selectedIndex = 0; selectedIndex < readings.length; selectedIndex++) {
      var selectedReading = readings[selectedIndex]
      var selectedId = selectedReading ? String(selectedReading.id || "") : ""
      if (isDynamicSensorId(selectedId) && !included[selectedId]) {
        cards.push(selectedReading)
        included[selectedId] = true
      }
    }
    for (var unavailableIndex = 0; unavailableIndex < unavailable.length; unavailableIndex++) {
      var missingEntry = unavailable[unavailableIndex]
      var missingId = typeof missingEntry === "string"
        ? String(missingEntry) : String(missingEntry ? missingEntry.id || "" : "")
      if (isDynamicSensorId(missingId) && !included[missingId]) {
        cards.push(missingSensorReading(missingId, missingEntry))
        included[missingId] = true
      }
    }
    return cards
  }

  function sensorHistoryFor(id) {
    if (!hostWidget || typeof hostWidget.sensorHistory !== "function") return []
    var history = hostWidget.sensorHistory(id)
    return history && history.length !== undefined ? history : []
  }

  function sensorScale(reading, history) {
    if (reading && reading.type === "fan") {
      var peak = 1000
      for (var index = 0; history && index < history.length; index++) {
        var sample = Number(history[index])
        if (isFinite(sample)) peak = Math.max(peak, sample)
      }
      var currentFan = reading ? Number(reading.value) : NaN
      if (isFinite(currentFan)) peak = Math.max(peak, currentFan)
      return peak
    }

    var critical = reading ? Number(reading.critical) : NaN
    if (isFinite(critical) && critical > 0) return critical
    var maximum = reading ? Number(reading.max) : NaN
    return isFinite(maximum) && maximum > 0 ? maximum : 100
  }

  function sensorValueText(reading) {
    var value = reading ? Number(reading.value) : NaN
    if (!isFinite(value)) return "—"
    var unit = reading && reading.unit
      ? String(reading.unit) : (reading.type === "fan" ? "RPM" : "°C")
    return reading.type === "fan"
      ? Math.round(value) + " " + unit
      : value.toFixed(1) + " " + unit
  }

  function sensorScaleText(reading, maximum) {
    var unit = reading && reading.unit
      ? String(reading.unit) : (reading && reading.type === "fan" ? "RPM" : "°C")
    var scale = reading && reading.type === "fan"
      ? Math.round(maximum) : Math.round(maximum)
    return "0–" + scale + " " + unit + "  /  60 SAMPLES"
  }

  function parseDiskOutput(output) {
    var result = MonitorModel.parseDiskOutput(output)
    if (!result) return false
    diskTotalBytes = result.totalBytes
    diskUsedBytes = result.usedBytes
    diskUsedPercent = result.usedPercent
    return true
  }

  function parseGpuOutput(output) {
    var result = MonitorModel.parseGpuOutput(output)
    if (!result) return false
    gpuUsage = MonitorModel.clampPercent(Math.round(result.usage))
    gpuMemoryUsedMiB = result.memoryUsedMiB
    gpuMemoryTotalMiB = result.memoryTotalMiB
    gpuTemperature = isFinite(result.temperature) ? Math.round(result.temperature) : -1
    return true
  }

  function startProbe(kind) {
    if (!active || probeProcess.running || probeKind !== "") return
    if (kind === "gpu" && !gpuCommandAvailable) return

    probeKind = kind
    probeOutput = ""
    probeStreamFinished = false
    probeProcessExited = false
    probeExitCode = -1
    probeCancelled = false
    probeProcess.command = kind === "disk"
      ? MonitorModel.buildBoundedCommand(boundedCommandPath, MonitorModel.commandOutputLimit("disk"),
        ["timeout", "--kill-after=1", "3", "df", "-P", "-B1", "/"])
      : MonitorModel.buildBoundedCommand(boundedCommandPath, MonitorModel.commandOutputLimit("gpu"),
        ["timeout", "--kill-after=1", "5", "/usr/bin/nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu", "--format=csv,noheader,nounits", "-i", "0"])
    probeProcess.running = true
  }

  function startProbeCycle() {
    if (active && probeKind === "" && !probeProcess.running) startProbe("disk")
  }

  function finishProbeIfReady() {
    if (!probeStreamFinished || !probeProcessExited || probeKind === "") return

    var finishedKind = probeKind
    var output = probeOutput
    var exitCode = probeExitCode
    var cancelled = probeCancelled
    probeKind = ""
    probeOutput = ""
    probeStreamFinished = false
    probeProcessExited = false

    if (!cancelled && finishedKind === "disk") {
      diskProbeComplete = true
      diskAvailable = exitCode === 0 && parseDiskOutput(output)
    } else if (!cancelled && finishedKind === "gpu") {
      gpuReadingAvailable = exitCode === 0 && parseGpuOutput(output)
      gpuProbeFailed = !gpuReadingAvailable
    }

    if (!active) {
      probeCancelled = false
      return
    }

    if (cancelled) {
      probeCancelled = false
      Qt.callLater(startProbeCycle)
    } else if (finishedKind === "disk" && gpuCommandAvailable) {
      Qt.callLater(function() { root.startProbe("gpu") })
    }
  }

  onActiveChanged: {
    if (active) {
      if (probeKind === "") Qt.callLater(startProbeCycle)
    } else if (probeKind !== "") {
      probeCancelled = true
      if (probeProcess.running) probeProcess.running = false
    }
  }

  Component.onCompleted: if (active) Qt.callLater(startProbeCycle)

  FileView {
    path: "/usr/bin/nvidia-smi"
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.gpuCommandAvailable = true
      root.gpuProbeFailed = false
      if (root.active && root.probeKind === "")
        Qt.callLater(function() { root.startProbe("gpu") })
    }
    onLoadFailed: {
      root.gpuCommandAvailable = false
      root.gpuProbeFailed = false
      root.gpuReadingAvailable = false
    }
  }

  Timer {
    interval: 10000
    repeat: true
    running: root.active
    onTriggered: root.startProbeCycle()
  }

  Process {
    id: probeProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.probeOutput = String(text || "")
        root.probeStreamFinished = true
        root.finishProbeIfReady()
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.probeExitCode = exitCode
      root.probeProcessExited = true
      root.finishProbeIfReady()
    }
  }

  component PercentGraph: Canvas {
    required property var history
    required property color lineColor
    required property color gridColor

    readonly property int sampleCapacity: 60
    Behavior on gridColor {
      ColorAnimation { duration: theme.animationDuration }
    }

    onHistoryChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onGridColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      var context = getContext("2d")
      context.clearRect(0, 0, width, height)
      var inset = Style.spacing.hairline
      var left = inset
      var right = Math.max(left, width - inset)
      var top = inset
      var bottom = Math.max(top, height - inset)

      context.strokeStyle = gridColor
      context.lineWidth = Style.spacing.hairline
      for (var gridIndex = 0; gridIndex <= 4; gridIndex++) {
        var gridY = top + (bottom - top) * gridIndex / 4
        context.beginPath()
        context.moveTo(left, gridY)
        context.lineTo(right, gridY)
        context.stroke()
      }
      for (var timeIndex = 0; timeIndex <= 4; timeIndex++) {
        var gridX = left + (right - left) * timeIndex / 4
        context.beginPath()
        context.moveTo(gridX, top)
        context.lineTo(gridX, bottom)
        context.stroke()
      }

      if (!history || history.length === 0) return
      var values = history.slice(Math.max(0, history.length - sampleCapacity))
      var xStep = (right - left) / (sampleCapacity - 1)
      var startX = right - xStep * (values.length - 1)

      function sampleX(index) { return startX + index * xStep }
      function sampleY(index) {
        var value = Math.max(0, Math.min(100, Number(values[index]) || 0))
        return bottom - (bottom - top) * value / 100
      }

      context.beginPath()
      context.moveTo(startX, bottom)
      for (var fillIndex = 0; fillIndex < values.length; fillIndex++)
        context.lineTo(sampleX(fillIndex), sampleY(fillIndex))
      context.lineTo(sampleX(values.length - 1), bottom)
      context.closePath()
      context.globalAlpha = 0.16
      context.fillStyle = lineColor
      context.fill()

      context.globalAlpha = 1
      context.strokeStyle = lineColor
      context.lineWidth = Math.max(Style.spacing.hairline, Style.spaceReal(1.5))
      context.lineJoin = "miter"
      context.beginPath()
      context.moveTo(sampleX(0), sampleY(0))
      for (var lineIndex = 1; lineIndex < values.length; lineIndex++)
        context.lineTo(sampleX(lineIndex), sampleY(lineIndex))
      context.stroke()

      context.beginPath()
      context.arc(sampleX(values.length - 1), sampleY(values.length - 1), Style.spacing.xxs, 0, Math.PI * 2)
      context.fillStyle = lineColor
      context.fill()
    }
  }

  component NetworkGraph: Canvas {
    required property var receiveHistory
    required property var transmitHistory
    required property real maximumRate
    required property color receiveColor
    required property color transmitColor
    required property color gridColor

    readonly property int sampleCapacity: 60
    Behavior on receiveColor {
      ColorAnimation { duration: theme.animationDuration }
    }
    Behavior on transmitColor {
      ColorAnimation { duration: theme.animationDuration }
    }
    Behavior on gridColor {
      ColorAnimation { duration: theme.animationDuration }
    }

    onReceiveHistoryChanged: requestPaint()
    onTransmitHistoryChanged: requestPaint()
    onMaximumRateChanged: requestPaint()
    onReceiveColorChanged: requestPaint()
    onTransmitColorChanged: requestPaint()
    onGridColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      var context = getContext("2d")
      context.clearRect(0, 0, width, height)
      var inset = Style.spacing.hairline
      var left = inset
      var right = Math.max(left, width - inset)
      var top = inset
      var bottom = Math.max(top, height - inset)
      var scale = Math.max(1, maximumRate)

      context.strokeStyle = gridColor
      context.lineWidth = Style.spacing.hairline
      for (var gridIndex = 0; gridIndex <= 4; gridIndex++) {
        var gridY = top + (bottom - top) * gridIndex / 4
        context.beginPath()
        context.moveTo(left, gridY)
        context.lineTo(right, gridY)
        context.stroke()
      }
      for (var timeIndex = 0; timeIndex <= 4; timeIndex++) {
        var gridX = left + (right - left) * timeIndex / 4
        context.beginPath()
        context.moveTo(gridX, top)
        context.lineTo(gridX, bottom)
        context.stroke()
      }

      function valuesFor(history) {
        return history ? history.slice(Math.max(0, history.length - sampleCapacity)) : []
      }
      function drawSeries(history, seriesColor, fillOnly) {
        var values = valuesFor(history)
        if (values.length === 0) return
        var xStep = (right - left) / (sampleCapacity - 1)
        var startX = right - xStep * (values.length - 1)
        function sampleX(index) { return startX + index * xStep }
        function sampleY(index) {
          var value = Math.max(0, Number(values[index]) || 0)
          return bottom - (bottom - top) * Math.min(1, value / scale)
        }

        context.beginPath()
        if (fillOnly) context.moveTo(startX, bottom)
        else context.moveTo(sampleX(0), sampleY(0))
        for (var index = fillOnly ? 0 : 1; index < values.length; index++)
          context.lineTo(sampleX(index), sampleY(index))

        if (fillOnly) {
          context.lineTo(sampleX(values.length - 1), bottom)
          context.closePath()
          context.globalAlpha = 0.11
          context.fillStyle = seriesColor
          context.fill()
        } else {
          context.globalAlpha = 1
          context.strokeStyle = seriesColor
          context.lineWidth = Math.max(Style.spacing.hairline, Style.spaceReal(1.5))
          context.lineJoin = "miter"
          context.stroke()
          context.beginPath()
          context.arc(sampleX(values.length - 1), sampleY(values.length - 1), Style.spacing.xxs, 0, Math.PI * 2)
          context.fillStyle = seriesColor
          context.fill()
        }
      }

      drawSeries(receiveHistory, receiveColor, true)
      drawSeries(transmitHistory, transmitColor, true)
      drawSeries(receiveHistory, receiveColor, false)
      drawSeries(transmitHistory, transmitColor, false)
      context.globalAlpha = 1
    }
  }

  component PercentCard: Rectangle {
    id: percentCard

    required property string title
    required property string valueText
    required property var history
    required property color accentColor

    color: theme.cardFill
    border.width: Style.spacing.hairline
    border.color: theme.cardBorder
    radius: 0

    Behavior on accentColor {
      ColorAnimation { duration: theme.animationDuration }
    }
    Behavior on color {
      ColorAnimation { duration: theme.animationDuration }
    }
    Behavior on border.color {
      ColorAnimation { duration: theme.animationDuration }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Style.spacing.sm
      color: percentCard.accentColor
    }

    Text {
      id: percentTitle
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.xxl
      anchors.top: parent.top
      anchors.topMargin: Style.spacing.lg
      text: percentCard.title
      color: theme.foreground
      font.family: theme.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Text {
      anchors.left: percentTitle.left
      anchors.top: percentTitle.bottom
      anchors.topMargin: Style.spacing.xxs
      text: "0–100%  /  LAST 60 SAMPLES"
      color: theme.muted
      font.family: theme.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.xxl
      anchors.top: parent.top
      anchors.topMargin: Style.spacing.sm
      text: percentCard.valueText
      color: percentCard.accentColor
      font.family: theme.fontFamily
      font.pixelSize: Style.font.display
      font.bold: true
    }

    PercentGraph {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.xxl
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.xxl
      anchors.top: parent.top
      anchors.topMargin: Style.space(50)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.spacing.lg
      history: percentCard.history
      lineColor: percentCard.accentColor
      gridColor: theme.graphGrid
    }

    Text {
      visible: !percentCard.history || percentCard.history.length === 0
      anchors.centerIn: parent
      anchors.verticalCenterOffset: Style.spacing.xxl
      text: "WAITING FOR SAMPLES"
      color: theme.muted
      font.family: theme.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  component ReadoutCell: Rectangle {
    id: readoutCell

    required property string label
    required property string valueText
    required property string detail
    required property color accentColor

    color: theme.cardFill
    border.width: Style.spacing.hairline
    border.color: theme.cardBorder
    radius: 0

    Behavior on accentColor {
      ColorAnimation { duration: theme.animationDuration }
    }
    Behavior on color {
      ColorAnimation { duration: theme.animationDuration }
    }
    Behavior on border.color {
      ColorAnimation { duration: theme.animationDuration }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      width: parent.width
      height: Style.spacing.xxs
      color: readoutCell.accentColor
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.lg
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.lg
      anchors.top: parent.top
      anchors.topMargin: Style.spacing.lg
      text: readoutCell.label
      color: theme.muted
      font.family: theme.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.lg
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      text: readoutCell.valueText
      color: readoutCell.accentColor
      font.family: theme.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.lg
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.lg
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.spacing.sm
      text: readoutCell.detail
      color: theme.muted
      font.family: theme.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  component SensorGraph: Canvas {
    required property var history
    required property real maximumValue
    required property color lineColor
    required property color gridColor

    readonly property int sampleCapacity: 60

    Behavior on lineColor {
      ColorAnimation { duration: theme.animationDuration }
    }
    Behavior on gridColor {
      ColorAnimation { duration: theme.animationDuration }
    }

    onHistoryChanged: requestPaint()
    onMaximumValueChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onGridColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      var context = getContext("2d")
      context.clearRect(0, 0, width, height)
      var inset = Style.spacing.hairline
      var left = inset
      var right = Math.max(left, width - inset)
      var top = inset
      var bottom = Math.max(top, height - inset)
      var scale = Math.max(1, maximumValue)

      context.strokeStyle = gridColor
      context.lineWidth = Style.spacing.hairline
      for (var gridIndex = 0; gridIndex <= 3; gridIndex++) {
        var gridY = top + (bottom - top) * gridIndex / 3
        context.beginPath()
        context.moveTo(left, gridY)
        context.lineTo(right, gridY)
        context.stroke()
      }
      for (var timeIndex = 0; timeIndex <= 4; timeIndex++) {
        var gridX = left + (right - left) * timeIndex / 4
        context.beginPath()
        context.moveTo(gridX, top)
        context.lineTo(gridX, bottom)
        context.stroke()
      }

      if (!history || history.length === 0) return
      var values = history.slice(Math.max(0, history.length - sampleCapacity))
      var xStep = (right - left) / (sampleCapacity - 1)
      var startX = right - xStep * (values.length - 1)

      function sampleX(index) {
        return startX + index * xStep
      }
      function sampleY(index) {
        var value = Number(values[index])
        if (!isFinite(value)) value = 0
        return bottom - (bottom - top) * Math.min(1, Math.max(0, value) / scale)
      }

      context.beginPath()
      context.moveTo(startX, bottom)
      for (var fillIndex = 0; fillIndex < values.length; fillIndex++)
        context.lineTo(sampleX(fillIndex), sampleY(fillIndex))
      context.lineTo(sampleX(values.length - 1), bottom)
      context.closePath()
      context.globalAlpha = 0.14
      context.fillStyle = lineColor
      context.fill()

      context.globalAlpha = 1
      context.strokeStyle = lineColor
      context.lineWidth = Math.max(Style.spacing.hairline, Style.spaceReal(1.5))
      context.lineJoin = "miter"
      context.beginPath()
      context.moveTo(sampleX(0), sampleY(0))
      for (var lineIndex = 1; lineIndex < values.length; lineIndex++)
        context.lineTo(sampleX(lineIndex), sampleY(lineIndex))
      context.stroke()

      context.beginPath()
      context.arc(sampleX(values.length - 1), sampleY(values.length - 1), Style.spacing.xxs, 0, Math.PI * 2)
      context.fillStyle = lineColor
      context.fill()
    }
  }

  component SensorCard: Rectangle {
    id: sensorCard

    required property var reading
    readonly property var graphHistory: root.sensorHistoryFor(reading ? reading.id : "")
    readonly property real graphMaximum: root.sensorScale(reading, graphHistory)
    readonly property bool readingAvailable: reading && isFinite(Number(reading.value))
    readonly property color accentColor: reading && reading.type === "fan"
      ? theme.fanColor : theme.temperatureColor

    color: theme.cardFill
    border.width: Style.spacing.hairline
    border.color: theme.cardBorder
    radius: 0

    Behavior on color {
      ColorAnimation { duration: theme.animationDuration }
    }
    Behavior on border.color {
      ColorAnimation { duration: theme.animationDuration }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Style.spacing.sm
      color: sensorCard.accentColor
    }

    Text {
      id: sensorDevice
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.xxl
      anchors.right: sensorValue.left
      anchors.rightMargin: Style.spacing.lg
      anchors.top: parent.top
      anchors.topMargin: Style.spacing.md
      text: sensorCard.reading && sensorCard.reading.deviceLabel
        ? String(sensorCard.reading.deviceLabel) : "Sensor device"
      textFormat: Text.PlainText
      color: theme.muted
      font.family: theme.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      anchors.left: sensorDevice.left
      anchors.right: sensorValue.left
      anchors.rightMargin: Style.spacing.lg
      anchors.top: sensorDevice.bottom
      anchors.topMargin: Style.spacing.xxs
      text: sensorCard.reading && sensorCard.reading.label
        ? String(sensorCard.reading.label)
        : (sensorCard.reading && sensorCard.reading.feature
          ? String(sensorCard.reading.feature) : "Sensor input")
      textFormat: Text.PlainText
      color: theme.foreground
      font.family: theme.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      id: sensorValue
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.xl
      anchors.top: parent.top
      anchors.topMargin: Style.spacing.md
      text: root.sensorValueText(sensorCard.reading)
      textFormat: Text.PlainText
      color: sensorCard.readingAvailable ? sensorCard.accentColor : theme.muted
      font.family: theme.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }

    Text {
      anchors.right: sensorValue.right
      anchors.top: sensorValue.bottom
      anchors.topMargin: Style.spacing.xxs
      text: sensorCard.readingAvailable
        ? root.sensorScaleText(sensorCard.reading, sensorCard.graphMaximum)
        : "TEMPORARILY UNAVAILABLE"
      textFormat: Text.PlainText
      color: theme.muted
      font.family: theme.fontFamily
      font.pixelSize: Style.font.caption
    }

    SensorGraph {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.xxl
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.xl
      anchors.top: parent.top
      anchors.topMargin: Style.space(56)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.spacing.lg
      history: sensorCard.graphHistory
      maximumValue: sensorCard.graphMaximum
      lineColor: sensorCard.accentColor
      gridColor: theme.graphGrid
    }

    Text {
      visible: sensorCard.graphHistory.length === 0
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(30)
      text: sensorCard.readingAvailable ? "WAITING FOR SAMPLES" : "NO CURRENT READING"
      color: theme.muted
      font.family: theme.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Flickable {
    id: performanceScroll

    anchors.fill: parent
    contentWidth: width
    contentHeight: performanceContent.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height

    Column {
      id: performanceContent

      width: performanceScroll.width
      spacing: theme.monitorGap
      Column {
        id: dashboard
        width: parent.width
        height: root.dashboardHeight
        spacing: Style.spacing.lg

    Item {
      width: parent.width
      height: root.headerHeight

      Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.md

        Rectangle { width: Style.spacing.sm; height: Style.space(20); color: theme.cpuColor }
        Rectangle { width: Style.spacing.sm; height: Style.space(20); color: theme.memoryColor }
        Rectangle { width: Style.spacing.sm; height: Style.space(20); color: theme.downloadColor }
        Rectangle { width: Style.spacing.sm; height: Style.space(20); color: theme.uploadColor }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.active ? "60-SAMPLE TRACE  /  LIVE" : "60-SAMPLE TRACE  /  PAUSED"
          color: theme.foreground
          font.family: theme.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }

      Button {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "OPEN BTOP"
        foreground: theme.foreground
        accent: theme.cpuColor
        fontFamily: theme.fontFamily
        fontSize: Style.font.bodySmall
        verticalPadding: Style.spacing.sm
        horizontalPadding: Style.spacing.xl
        bordered: true
        focusable: true
        onClicked: root.openBtopRequested()
      }
    }

    Row {
      width: parent.width
      height: root.percentGraphHeight
      spacing: Style.spacing.lg

      PercentCard {
        width: Math.max(0, (parent.width - parent.spacing) / 2)
        height: parent.height
        title: "CPU"
        valueText: MonitorModel.formatPercent(root.cpuUsage)
        history: root.cpuHistory
        accentColor: theme.cpuColor
      }

      PercentCard {
        width: Math.max(0, (parent.width - parent.spacing) / 2)
        height: parent.height
        title: "MEMORY"
        valueText: MonitorModel.formatPercent(root.memoryUsage)
        history: root.memoryHistory
        accentColor: theme.memoryColor
      }
    }

    Rectangle {
      id: networkCard
      width: parent.width
      height: root.networkGraphHeight
      color: theme.cardFill
      border.width: Style.spacing.hairline
      border.color: theme.cardBorder
      radius: 0

      Behavior on color {
        ColorAnimation { duration: theme.animationDuration }
      }
      Behavior on border.color {
        ColorAnimation { duration: theme.animationDuration }
      }

      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.spacing.sm
        color: theme.downloadColor
      }

      Text {
        id: networkTitle
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.xxl
        anchors.top: parent.top
        anchors.topMargin: Style.spacing.lg
        text: "NETWORK"
        color: theme.foreground
        font.family: theme.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        anchors.left: networkTitle.right
        anchors.leftMargin: Style.spacing.md
        anchors.baseline: networkTitle.baseline
        text: "ADAPTIVE 0–" + MonitorModel.formatRate(root.networkScale) + "  /  60 SAMPLES"
        color: theme.muted
        font.family: theme.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.xxl
        anchors.top: parent.top
        anchors.topMargin: Style.spacing.md
        spacing: Style.spacing.xxl

        Text {
          text: "↓ " + MonitorModel.formatRate(root.receiveRate)
          color: theme.downloadColor
          font.family: theme.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Text {
          text: "↑ " + MonitorModel.formatRate(root.transmitRate)
          color: theme.uploadColor
          font.family: theme.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }
      }

      NetworkGraph {
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.xxl
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.xxl
        anchors.top: parent.top
        anchors.topMargin: Style.space(38)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.spacing.lg
        receiveHistory: root.receiveHistory
        transmitHistory: root.transmitHistory
        maximumRate: root.networkScale
        receiveColor: theme.downloadColor
        transmitColor: theme.uploadColor
        gridColor: theme.graphGrid
      }

      Text {
        visible: root.receiveHistory.length === 0 && root.transmitHistory.length === 0
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Style.spacing.xxl
        text: "WAITING FOR NETWORK SAMPLES"
        color: theme.muted
        font.family: theme.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    Row {
      width: parent.width
      height: root.readoutHeight
      spacing: Style.spacing.lg

      readonly property real cellWidth: Math.max(0,
        (width - spacing * (root.visibleReadoutCount - 1)) / root.visibleReadoutCount)

      ReadoutCell {
        width: parent.cellWidth
        height: parent.height
        label: "LOAD AVERAGE"
        valueText: MonitorModel.formatLoad(root.loadOne)
        detail: "5M " + MonitorModel.formatLoad(root.loadFive) + "  ·  15M " + MonitorModel.formatLoad(root.loadFifteen)
        accentColor: theme.loadColor
      }

      ReadoutCell {
        width: parent.cellWidth
        height: parent.height
        label: "UPTIME"
        valueText: MonitorModel.formatUptime(root.uptimeSeconds)
        detail: "SINCE BOOT"
        accentColor: theme.uptimeColor
      }

      ReadoutCell {
        width: parent.cellWidth
        height: parent.height
        label: "ROOT DISK"
        valueText: root.diskAvailable ? root.diskUsedPercent + "%" : "—"
        detail: root.diskAvailable
          ? MonitorModel.formatBytes(root.diskUsedBytes) + " / " + MonitorModel.formatBytes(root.diskTotalBytes)
          : (root.active && !root.diskProbeComplete ? "WAITING FOR SAMPLE" : (root.diskProbeComplete ? "UNAVAILABLE" : "PROBE PAUSED"))
        accentColor: theme.diskColor
      }

      ReadoutCell {
        visible: root.gpuCommandAvailable && !root.gpuProbeFailed
        width: parent.cellWidth
        height: parent.height
        label: "NVIDIA GPU"
        valueText: root.gpuReadingAvailable ? root.gpuUsage + "%" : "—"
        detail: root.gpuReadingAvailable
          ? (root.gpuMemoryUsedMiB / 1024).toFixed(1) + "/" + (root.gpuMemoryTotalMiB / 1024).toFixed(1) + "G" + (root.gpuTemperature >= 0 ? "  ·  " + root.gpuTemperature + "°" : "")
          : (root.active ? "WAITING FOR SAMPLE" : "PROBE PAUSED")
        accentColor: theme.gpuColor
      }
    }
  }

      Column {
        id: selectedSensorsSection

        visible: root.hasSelectedSensors
        width: parent.width
        spacing: theme.monitorGap

        Item {
          width: parent.width
          height: root.headerHeight

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.md

            Rectangle {
              width: Style.spacing.sm
              height: Style.space(20)
              color: theme.temperatureColor
            }
            Rectangle {
              width: Style.spacing.sm
              height: Style.space(20)
              color: theme.fanColor
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "SELECTED SENSORS"
              color: theme.foreground
              font.family: theme.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.active ? "LIVE HISTORY" : "HISTORY PAUSED"
            color: theme.muted
            font.family: theme.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Grid {
          id: sensorGrid

          width: parent.width
          columns: 2
          spacing: theme.monitorGap

          Repeater {
            model: root.selectedSensorCards

            SensorCard {
              required property var modelData
              width: Math.max(0, (sensorGrid.width - sensorGrid.spacing) / 2)
              height: root.sensorCardHeight
              reading: modelData
            }
          }
        }
      }
    }
  }
}
