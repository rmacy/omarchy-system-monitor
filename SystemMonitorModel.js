// Pure model for the system monitor: the bar widget (BarWidget.qml), the
// performance tab (SystemPerformanceView.qml), the processes tab
// (SystemProcessView.qml) and the system info tab (SystemInfoView.qml).
// Extracted so every caller shares one implementation.
//
// Dual-mode script: import from QML as
//   import "SystemMonitorModel.js" as MonitorModel
// or require from CommonJS. Uses only standard ECMAScript globals so the same
// file runs under both the Qt QML engine and Node.

var HISTORY_CAPACITY = 60
var NETWORK_SCALE_STOPS = [
  32 * 1024, 64 * 1024, 128 * 1024, 256 * 1024, 512 * 1024,
  1024 * 1024, 2 * 1024 * 1024, 4 * 1024 * 1024, 8 * 1024 * 1024,
  16 * 1024 * 1024, 32 * 1024 * 1024, 64 * 1024 * 1024,
  128 * 1024 * 1024, 256 * 1024 * 1024, 512 * 1024 * 1024,
  1024 * 1024 * 1024
]

function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function recentHistory(history) {
  if (!history || history.length === undefined) return []
  return history.slice(Math.max(0, history.length - HISTORY_CAPACITY))
}

function appendHistory(history, value) {
  var source = history || []
  var next = source.slice(Math.max(0, source.length - (HISTORY_CAPACITY - 1)))
  next.push(value)
  return next
}

function clampPercent(value) {
  return Math.max(0, Math.min(100, finiteNumber(value, 0)))
}

function formatPercent(value) {
  return Math.round(clampPercent(value)) + "%"
}

function formatRate(bytesPerSecond) {
  var value = Math.max(0, finiteNumber(bytesPerSecond, 0))
  if (value >= 1024 * 1024 * 1024)
    return (value / (1024 * 1024 * 1024)).toFixed(value < 10 * 1024 * 1024 * 1024 ? 1 : 0) + " GiB/s"
  if (value >= 1024 * 1024)
    return (value / (1024 * 1024)).toFixed(value < 10 * 1024 * 1024 ? 1 : 0) + " MiB/s"
  if (value >= 1024)
    return (value / 1024).toFixed(value < 10 * 1024 ? 1 : 0) + " KiB/s"
  return Math.round(value) + " B/s"
}

function formatCompactRate(bytesPerSecond) {
  var value = Math.max(0, finiteNumber(bytesPerSecond, 0))
  var kibibyte = 1024
  var mebibyte = kibibyte * 1024
  var gibibyte = mebibyte * 1024
  var tebibyte = gibibyte * 1024
  if (value >= tebibyte) {
    var tebibytes = value / tebibyte
    return (tebibytes < 10 ? tebibytes.toFixed(1) : Math.round(tebibytes)) + "T"
  }
  if (value >= gibibyte) {
    var gibibytes = value / gibibyte
    if (gibibytes >= 999.5) return "1.0T"
    return (gibibytes < 10 ? gibibytes.toFixed(1) : Math.round(gibibytes)) + "G"
  }
  if (value >= mebibyte) {
    var mebibytes = value / mebibyte
    if (mebibytes >= 999.5) return "1.0G"
    return (mebibytes < 10 ? mebibytes.toFixed(1) : Math.round(mebibytes)) + "M"
  }
  if (value >= kibibyte) {
    var kibibytes = value / kibibyte
    if (kibibytes >= 999.5) return "1.0M"
    return Math.round(kibibytes) + "K"
  }
  if (value >= 999.5) return "1.0K"
  return Math.round(value) + "B"
}

function formatBytes(bytes) {
  var value = Math.max(0, finiteNumber(bytes, 0))
  if (value >= 1024 * 1024 * 1024 * 1024)
    return (value / (1024 * 1024 * 1024 * 1024)).toFixed(1) + " TiB"
  if (value >= 1024 * 1024 * 1024)
    return (value / (1024 * 1024 * 1024)).toFixed(1) + " GiB"
  if (value >= 1024 * 1024)
    return (value / (1024 * 1024)).toFixed(1) + " MiB"
  if (value >= 1024)
    return (value / 1024).toFixed(1) + " KiB"
  return Math.round(value) + " B"
}

function formatUptime(seconds) {
  var totalMinutes = Math.max(0, Math.floor(finiteNumber(seconds, 0) / 60))
  var days = Math.floor(totalMinutes / (24 * 60))
  var hours = Math.floor((totalMinutes % (24 * 60)) / 60)
  var minutes = totalMinutes % 60
  if (days > 0) return days + "d " + hours + "h " + minutes + "m"
  if (hours > 0) return hours + "h " + minutes + "m"
  return Math.max(1, minutes) + "m"
}

// Compact uptime for the minimal text chip: at most two components ("1d 3h",
// "2h 5m") so the chip stays narrow. Mirrors formatUptime's flooring and its
// one-minute minimum so a just-booted machine reads "1m" in both modes.
function formatCompactUptime(seconds) {
  var totalMinutes = Math.max(0, Math.floor(finiteNumber(seconds, 0) / 60))
  var days = Math.floor(totalMinutes / (24 * 60))
  var hours = Math.floor((totalMinutes % (24 * 60)) / 60)
  if (days > 0) return days + "d " + hours + "h"
  if (hours > 0) return hours + "h " + (totalMinutes % 60) + "m"
  return Math.max(1, totalMinutes) + "m"
}

function formatLoad(value) {
  return Math.max(0, finiteNumber(value, 0)).toFixed(2)
}

function networkScaleFor(receive, transmit) {
  var maximum = 0
  var histories = [receive || [], transmit || []]
  for (var listIndex = 0; listIndex < histories.length; listIndex++) {
    var history = histories[listIndex]
    for (var sampleIndex = 0; sampleIndex < history.length; sampleIndex++)
      maximum = Math.max(maximum, Math.max(0, finiteNumber(history[sampleIndex], 0)))
  }

  for (var stopIndex = 0; stopIndex < NETWORK_SCALE_STOPS.length; stopIndex++) {
    if (maximum <= NETWORK_SCALE_STOPS[stopIndex]) return NETWORK_SCALE_STOPS[stopIndex]
  }

  var scale = NETWORK_SCALE_STOPS[NETWORK_SCALE_STOPS.length - 1]
  while (scale < maximum) scale *= 2
  return scale
}

// `df -P -B1 /` output -> { totalBytes, usedBytes, usedPercent } or null.
function parseDiskOutput(output) {
  var lines = String(output || "").trim().split("\n")
  if (lines.length < 2) return null
  var fields = String(lines[lines.length - 1] || "").trim().split(/\s+/)
  if (fields.length < 6) return null

  var total = Number(fields[fields.length - 5])
  var used = Number(fields[fields.length - 4])
  if (!isFinite(total) || total <= 0 || !isFinite(used) || used < 0) return null

  return {
    totalBytes: total,
    usedBytes: used,
    usedPercent: Math.max(0, Math.min(100, Math.round(100 * used / total)))
  }
}

// `nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu
//  --format=csv,noheader,nounits` output -> { usage, memoryUsedMiB,
// memoryTotalMiB, temperature } or null. A missing temperature parses as -1.
function parseGpuOutput(output) {
  var firstLine = String(output || "").trim().split("\n")[0] || ""
  var fields = firstLine.split(",")
  if (fields.length < 4) return null

  var usage = Number(fields[0].trim())
  var memoryUsed = Number(fields[1].trim())
  var memoryTotal = Number(fields[2].trim())
  var temperature = Number(fields[3].trim())
  if (!isFinite(usage) || !isFinite(memoryUsed) || !isFinite(memoryTotal) || memoryTotal <= 0)
    return null

  return {
    usage: Math.max(0, Math.min(100, Math.round(usage))),
    memoryUsedMiB: Math.max(0, memoryUsed),
    memoryTotalMiB: memoryTotal,
    temperature: isFinite(temperature) ? Math.round(temperature) : -1
  }
}

// Stats script output: ten whitespace-separated numbers -> stats object or
// null. Field order: cpuTotal cpuIdle memTotal memAvailable rxBytes txBytes
// load1 load5 load15 uptimeSeconds.
function parseStatsOutput(output) {
  var fields = String(output).trim().split(/\s+/)
  if (fields.length !== 10) return null

  var stats = {
    total: Number(fields[0]),
    idle: Number(fields[1]),
    memoryTotal: Number(fields[2]),
    memoryAvailable: Number(fields[3]),
    received: Number(fields[4]),
    transmitted: Number(fields[5]),
    loadOne: Number(fields[6]),
    loadFive: Number(fields[7]),
    loadFifteen: Number(fields[8]),
    uptime: Number(fields[9])
  }

  if (!isFinite(stats.total) || !isFinite(stats.idle) || !isFinite(stats.memoryTotal) ||
      !isFinite(stats.memoryAvailable) || !isFinite(stats.received) || !isFinite(stats.transmitted) ||
      !isFinite(stats.loadOne) || !isFinite(stats.loadFive) || !isFinite(stats.loadFifteen) ||
      !isFinite(stats.uptime)) return null

  return stats
}

// Delta step over consecutive stats samples. `previousSampleTime` and `now`
// are millisecond timestamps; `previous` is null on the first sample.
// cpuValue is null whenever no valid prior CPU delta exists (first sample,
// counter reset); rates fall back to 0.
function calculateSystemMetrics(current, previous, previousSampleTime, now) {
  if (!current) return null

  var metrics = {
    cpuValue: null,
    memoryValue: 0,
    receiveRate: 0,
    transmitRate: 0
  }

  if (previous && previous.total >= 0 && current.total > previous.total) {
    var cpuValue = 100 * (1 - (current.idle - previous.idle) / (current.total - previous.total))
    metrics.cpuValue = Math.max(0, Math.min(100, cpuValue))
  }

  var memoryValue = current.memoryTotal > 0
    ? 100 * (1 - current.memoryAvailable / current.memoryTotal)
    : 0
  metrics.memoryValue = Math.max(0, Math.min(100, memoryValue))

  var elapsedSeconds = (finiteNumber(now, 0) - finiteNumber(previousSampleTime, 0)) / 1000
  if (previous && elapsedSeconds > 0) {
    metrics.receiveRate = Math.max(0, (current.received - previous.received) / elapsedSeconds)
    metrics.transmitRate = Math.max(0, (current.transmitted - previous.transmitted) / elapsedSeconds)
  }

  return metrics
}

// argv list, never a shell string; the username rides as a single element.
// The hard 3s deadline escalates to SIGKILL after one more second, and the
// pinned LC_ALL=C keeps lstart's five-token birth time
// ("Mon Aug 25 20:29:30 2026") stable no matter the host locale.
function buildPsCommand(user) {
  var name = String(user || "").trim()
  var argv = ["timeout", "--kill-after=1", "3", "env", "LC_ALL=C", "ps"]
  if (name) argv.push("-u", name)
  argv.push("-o", "pid=,lstart=,pcpu=,pmem=,comm=", "--sort=-pcpu")
  return argv
}

// ps output -> bounded array of process rows. Field order matches
// buildPsCommand: pid, five lstart tokens, pcpu, pmem, then comm. The five
// lstart tokens join into `startToken` — the process's locale-C birth time —
// so selections can be reconciled against PID *and* identity and a reused
// PID never inherits a stale selection. Whitespace runs collapse (ps pads
// single-digit days), and comm is everything after the numeric columns, so
// executable names containing spaces survive.
function parsePsOutput(raw, limit) {
  if (raw === null || raw === undefined || String(raw).trim() === "") return null
  var bound = isFinite(limit) && limit > 0 ? limit : 400
  var lines = String(raw).split("\n")
  var entries = []
  for (var i = 0; i < lines.length && entries.length < bound; i++) {
    var line = lines[i].replace(/^\s+|\s+$/g, "")
    if (!line) continue
    var fields = line.split(/\s+/)
    if (fields.length < 9) continue
    var pid = parseInt(fields[0], 10)
    var cpu = Number(fields[6])
    var memory = Number(fields[7])
    if (!isFinite(pid) || pid <= 0 || !isFinite(cpu) || !isFinite(memory)) continue
    var name = fields.slice(8).join(" ")
    entries.push({
      pid: pid,
      name: name,
      search: name.toLowerCase() + " " + String(pid),
      startToken: fields.slice(1, 6).join(" "),
      cpu: cpu,
      memory: memory
    })
  }
  return entries
}

function compareProcessRows(a, b, sortKey, descending) {
  var key = sortKey === "memory" || sortKey === "name" ? sortKey : "cpu"
  var descendingOrder = descending === undefined ? key !== "name" : !!descending

  if (key === "name") {
    var leftName = String(a.name || "").toLowerCase()
    var rightName = String(b.name || "").toLowerCase()
    var nameDelta = leftName < rightName ? -1 : (leftName > rightName ? 1 : 0)
    if (nameDelta !== 0) return descendingOrder ? -nameDelta : nameDelta
    return 0
  }

  var leftValue = key === "memory" ? Number(a.memory || 0) : Number(a.cpu || 0)
  var rightValue = key === "memory" ? Number(b.memory || 0) : Number(b.cpu || 0)
  var valueDelta = leftValue - rightValue
  if (valueDelta !== 0) return descendingOrder ? -valueDelta : valueDelta

  var leftTieName = String(a.name || "").toLowerCase()
  var rightTieName = String(b.name || "").toLowerCase()
  if (leftTieName < rightTieName) return -1
  if (leftTieName > rightTieName) return 1
  return 0
}

function filterAndSortProcesses(processes, query, sortKey, limit, descending) {
  var needle = String(query || "").trim().toLowerCase()
  var bound = isFinite(limit) && limit > 0 ? limit : 200
  var source = processes || []
  var rows = []
  for (var i = 0; i < source.length; i++) {
    var entry = source[i]
    if (needle && entry.search.indexOf(needle) < 0) continue
    rows.push(entry)
  }
  rows.sort(function(left, right) {
    return compareProcessRows(left, right, sortKey, descending)
  })
  return rows.length > bound ? rows.slice(0, bound) : rows
}

// Row for a still-live selection: the PID must match and, when a start
// token is supplied, so must the process's birth time — a reused PID never
// inherits a selection made for its predecessor. An empty token matches by
// PID alone (legacy callers and fixtures without lstart data).
function findProcessByPid(rows, pid, startToken) {
  var token = normalizeStartToken(startToken)
  var source = rows || []
  for (var i = 0; i < source.length; i++) {
    if (source[i].pid !== pid) continue
    if (token !== "" && normalizeStartToken(source[i].startToken) !== token) continue
    return source[i]
  }
  return null
}

// lstart text -> canonical comparison form: trimmed with whitespace runs
// collapsed to single spaces, so "Mon Aug  5 ..." (ps pads single-digit
// days) compares equal to itself however it was split. Blank or missing
// input normalizes to "".
function normalizeStartToken(raw) {
  if (raw === null || raw === undefined) return ""
  return String(raw).trim().split(/\s+/).join(" ")
}

// argv list for the race-free termination helper. `pidfd-signal` opens a
// pidfd for the PID, re-derives its lstart birth token from kernel truth
// (/proc/PID/stat + /proc/stat), compares it with the token captured at
// selection, and only then sends SIGTERM through the pidfd — so a reused
// PID can never be signalled and no validation-then-kill window exists.
// The PID and token ride as separate argv elements; invalid input (bad
// PID, blank token, missing helper) yields [] so a caller can never launch
// the helper with garbage.
function buildPidfdSignalCommand(helperPath, pid, startToken) {
  var numeric = Number(pid)
  if (!isFinite(numeric) || numeric <= 0 || numeric % 1 !== 0) return []
  var token = normalizeStartToken(startToken)
  if (token === "") return []
  var helper = String(helperPath || "").trim()
  if (helper === "") return []
  return [helper, String(numeric), token]
}

function utilizationLevel(value) {
  if (value >= 90) return "critical"
  if (value >= 70) return "warning"
  return "normal"
}

// ---- chip settings --------------------------------------------------------
//
// The bar chip renders a configurable subset of monitors; the selection is a
// plain array of ids persisted flat as `monitors` next to `chipMode`. Every
// function here is pure and returns fresh arrays so QML callers reassign the
// result whole, exactly like the history helpers above.

var CHIP_MONITOR_IDS = ["cpu", "memory", "gpu", "network", "load", "uptime"]
var CHIP_MODES = ["instrument", "minimal"]

function chipMonitorIds() {
  return CHIP_MONITOR_IDS.slice()
}

function defaultChipMonitors() {
  return ["cpu", "memory", "network"]
}

// Only the two chip modes are valid; anything else (null, a typo, an old
// persisted value) falls back to the default instrument chip.
function normalizeChipMode(value) {
  for (var index = 0; index < CHIP_MODES.length; index++) {
    if (value === CHIP_MODES[index]) return CHIP_MODES[index]
  }
  return CHIP_MODES[0]
}

// Keep known ids, drop duplicates, and restore the canonical chip order so
// toggles and persisted selections converge on one representation: the
// fixed monitors first in canonical order, then valid dynamic sensor ids in
// their input (first-seen) order. Dynamic ids survive temporary sensor
// absence because validity is structural, not availability-based; unknown
// ids drop. An empty selection is valid (the chip then falls back to its
// SYS label); a non-array falls back to the defaults.
function normalizeChipMonitors(value) {
  if (!value || value.length === undefined) return defaultChipMonitors()
  var normalized = []
  for (var order = 0; order < CHIP_MONITOR_IDS.length; order++) {
    var id = CHIP_MONITOR_IDS[order]
    for (var index = 0; index < value.length; index++) {
      if (value[index] === id) {
        normalized.push(id)
        break
      }
    }
  }
  for (var dynamic = 0; dynamic < value.length; dynamic++) {
    var sensorId = value[dynamic]
    if (!isSensorMonitorId(sensorId)) continue
    if (normalized.indexOf(sensorId) !== -1) continue
    normalized.push(sensorId)
  }
  return normalized
}

// Immutable toggle: never mutates `value`, always returns a fresh (or
// freshly normalized) array in canonical order. Unknown ids change nothing;
// valid dynamic sensor ids toggle exactly like the fixed monitors.
function toggleChipMonitor(value, id, enabled) {
  var normalized = normalizeChipMonitors(value)
  if (normalized.indexOf(id) === -1 && CHIP_MONITOR_IDS.indexOf(id) === -1 &&
      !isSensorMonitorId(id))
    return normalized
  if (!enabled) {
    var without = []
    for (var index = 0; index < normalized.length; index++) {
      if (normalized[index] !== id) without.push(normalized[index])
    }
    return without
  }
  if (normalized.indexOf(id) !== -1) return normalized
  normalized.push(id)
  return normalizeChipMonitors(normalized)
}

function chipMonitorEnabled(value, id) {
  return normalizeChipMonitors(value).indexOf(id) !== -1
}

// ---- dynamic sensor monitors ----------------------------------------------
//
// Per-device temperature and fan monitors join the fixed chip ids above,
// sourced from `sensors -j` output. A dynamic monitor id encodes its origin
// so the persisted selection survives sensor churn:
//   sensor:<temperature|fan>:<device>:<feature>:<input>
// with device, feature and input URI-encoded; encodeURIComponent never
// leaves ":" in a component, so ids split cleanly on ":" and stay stable
// across polls regardless of enumeration order.

var SENSOR_MONITOR_TYPES = ["temperature", "fan"]

function isSensorMonitorType(type) {
  return type === SENSOR_MONITOR_TYPES[0] || type === SENSOR_MONITOR_TYPES[1]
}

// Deterministic id for one reading source, or null unless the type is
// temperature/fan and every component is a non-empty string.
function sensorMonitorId(type, device, feature, inputKey) {
  if (!isSensorMonitorType(type)) return null
  if (typeof device !== "string" || !device) return null
  if (typeof feature !== "string" || !feature) return null
  if (typeof inputKey !== "string" || !inputKey) return null
  return "sensor:" + type + ":" + encodeURIComponent(device) + ":" +
    encodeURIComponent(feature) + ":" + encodeURIComponent(inputKey)
}

// Structural validation only (no decoding, so no throw path for malformed
// percent escapes): five colon-separated parts, a "sensor" head, a known
// type and non-empty components.
function isSensorMonitorId(id) {
  if (typeof id !== "string") return false
  var parts = id.split(":")
  return parts.length === 5 && parts[0] === "sensor" &&
    isSensorMonitorType(parts[1]) && !!parts[2] && !!parts[3] && !!parts[4]
}

// The temperature/fan half of a dynamic id, or null for anything else.
function sensorMonitorType(id) {
  return isSensorMonitorId(id) ? id.split(":")[1] : null
}

// lm-sensors chip keys look like "<name>-<bus>-<address>"
// ("k10temp-pci-00c3", "z53-hid-3-8"); the name before the first dash reads
// best once lm-sensors' per-instance "_<n>" suffixes for repeated chips are
// stripped ("acpitz_0" -> "acpitz", "iwlwifi_1_1" -> "iwlwifi", while
// "gigabyte_wmi" stays whole).
function sensorDeviceLabel(device) {
  var raw = String(device)
  var lower = raw.toLowerCase()
  var nvme = /^nvme-pci-([a-z0-9]+)/i.exec(raw)
  if (nvme) return "NVMe " + nvme[1].toUpperCase()
  if (lower.indexOf("k10temp") === 0) return "CPU"
  if (lower.indexOf("amdgpu") === 0) return "AMD GPU"
  if (lower.indexOf("gigabyte_wmi") === 0) return "Motherboard"
  if (lower.indexOf("iwlwifi") === 0) return "Wi-Fi"
  if (lower.indexOf("r8169") === 0) return "Ethernet"
  if (lower.indexOf("z53") === 0) return "Liquid cooler"
  if (lower.indexOf("acpitz") === 0) return "ACPI"
  var dash = raw.indexOf("-")
  var name = dash > 0 ? raw.slice(0, dash) : raw
  name = name.replace(/(?:_[0-9]+)+$/, "")
  return name || raw
}

// Feature names pass through verbatim ("Tctl", "Pump speed", "Composite")
// except raw hwmon channel names ("temp1", "fan2"), which expand to
// readable "Temperature 1" / "Fan 2" forms.
function sensorFeatureLabel(feature) {
  var name = String(feature).replace(/\s+/g, " ").replace(/^ /, "").replace(/ $/, "")
  var generic = /^(temp|fan)([0-9]+)$/.exec(name)
  if (generic)
    return (generic[1] === "temp" ? "Temperature " : "Fan ") + generic[2]
  return name
}

// Compact chip label: the feature alone, first word for multi-word names
// ("Pump speed" -> "Pump"), with the generic temperature form shortened
// ("Temperature 1" -> "Temp 1") while keeping its distinguishing number.
function sensorShortLabel(featureLabel) {
  if (featureLabel.indexOf("Temperature ") === 0)
    return "Temp" + featureLabel.slice(11)
  var space = featureLabel.indexOf(" ")
  return space === -1 ? featureLabel : featureLabel.slice(0, space)
}

var SENSOR_INPUT_PATTERN = /^(temp|fan)([0-9]+)_input$/

function compareSensorReadings(a, b) {
  if (a.device < b.device) return -1
  if (a.device > b.device) return 1
  if (a.feature < b.feature) return -1
  if (a.feature > b.feature) return 1
  if (a.inputKey < b.inputKey) return -1
  if (a.inputKey > b.inputKey) return 1
  return 0
}

// `sensors -j` output -> sorted array of readings, or null when the payload
// is not JSON or its root is not an object. Only finite tempN_input /
// fanN_input values become readings (pwm, voltage, power, frequency, limit
// and alarm fields never match the input pattern), and each reading carries
// its max/critical threshold when the JSON holds a finite one. Readings sort
// by device, then feature, then input key, so the order never depends on
// JSON key order.
function parseSensorsJson(raw) {
  var root
  try {
    root = JSON.parse(raw)
  } catch (error) {
    return null
  }
  if (!root || typeof root !== "object" || root.length !== undefined) return null
  var readings = []
  for (var device in root) {
    if (!Object.prototype.hasOwnProperty.call(root, device)) continue
    var features = root[device]
    if (!features || typeof features !== "object" ||
        features.length !== undefined) continue
    for (var feature in features) {
      if (!Object.prototype.hasOwnProperty.call(features, feature)) continue
      if (feature === "Adapter") continue
      var fields = features[feature]
      if (!fields || typeof fields !== "object" ||
          fields.length !== undefined) continue
      for (var inputKey in fields) {
        if (!Object.prototype.hasOwnProperty.call(fields, inputKey)) continue
        var input = SENSOR_INPUT_PATTERN.exec(inputKey)
        if (!input) continue
        var value = fields[inputKey]
        if (typeof value !== "number" || !isFinite(value)) continue
        var type = input[1] === "temp" ? "temperature" : "fan"
        var channel = input[1] + input[2]
        var max = fields[channel + "_max"]
        var critical = fields[channel + "_crit"]
        var deviceLabel = sensorDeviceLabel(device)
        var featureLabel = sensorFeatureLabel(feature)
        readings.push({
          id: sensorMonitorId(type, device, feature, inputKey),
          type: type,
          device: device,
          deviceLabel: deviceLabel,
          feature: feature,
          label: deviceLabel + " " + featureLabel,
          shortLabel: sensorShortLabel(featureLabel),
          inputKey: inputKey,
          value: value,
          unit: type === "temperature" ? "\u00B0C" : "RPM",
          max: typeof max === "number" && isFinite(max) ? max : null,
          critical: typeof critical === "number" && isFinite(critical) ? critical : null
        })
      }
    }
  }
  readings.sort(compareSensorReadings)
  return readings
}

// ---- hardware inventory (system info tab) ---------------------------------
//
// Pure parsers behind the system info tab's unprivileged sources: /proc and
// DMI files read through FileView plus `lspci -mm -D`, `uname -srmo` and the
// optional nvidia-smi query, all captured as argv commands without shell
// interpolation. As everywhere else in this file the logic is deterministic
// and side-effect free so the same source runs under Node and the Qt V4
// engine.

// Firmware vendors ship placeholder text for unpopulated DMI fields ("To be
// filled by O.E.M.", "Default string", "x.x"); values matching one of these
// (case-insensitively, after whitespace collapsing) read as absent.
var HARDWARE_SENTINELS = [
  "", "n/a", "na", "none", "null", "oem", "x.x",
  "default string", "not applicable", "not available", "not specified",
  "to be filled", "to be filled by o.e.m.", "to be filled by oem",
  "unknown", "system manufacturer", "system product name",
  "base board version"
]

// Firmware string -> trimmed single-line value, or "" when the field is
// blank or a placeholder. Real values ("B650 AORUS ELITE AX ICE",
// "08/14/2024") pass through untouched.
function normalizeHardwareValue(raw) {
  var value = String(raw == null ? "" : raw).replace(/\s+/g, " ").trim()
  if (!value) return ""
  var folded = value.toLowerCase()
  for (var index = 0; index < HARDWARE_SENTINELS.length; index++) {
    if (folded === HARDWARE_SENTINELS[index]) return ""
  }
  return value
}

// /proc/cpuinfo -> { model, vendor, logicalProcessors, physicalCores,
// sockets, cache } or null when no processor entry exists. Topology repeats
// per logical CPU, so "cpu cores" is read once and multiplied by the count
// of distinct "physical id" values; kernels or hypervisors that omit
// "cpu cores" fall back to the count of distinct physical-id/core-id pairs,
// and physicalCores is null when neither source exists.
function parseCpuInfo(raw) {
  var model = null
  var vendor = null
  var cache = null
  var logicalProcessors = 0
  var physicalIds = []
  var corePairs = []
  var coresPerSocket = null
  var currentPhysicalId = ""
  var lines = String(raw || "").split("\n")

  for (var index = 0; index < lines.length; index++) {
    var sep = lines[index].indexOf(":")
    if (sep === -1) continue
    var key = lines[index].slice(0, sep).trim()
    var value = lines[index].slice(sep + 1).trim()

    if (key === "processor") {
      if (/^\d+$/.test(value)) logicalProcessors += 1
    } else if (key === "model name") {
      if (!model && value) model = value
    } else if (key === "vendor_id") {
      if (!vendor && value) vendor = value
    } else if (key === "physical id") {
      if (value) {
        currentPhysicalId = value
        if (physicalIds.indexOf(value) === -1) physicalIds.push(value)
      }
    } else if (key === "core id") {
      if (value) {
        var pair = currentPhysicalId + ":" + value
        if (corePairs.indexOf(pair) === -1) corePairs.push(pair)
      }
    } else if (key === "cpu cores" && coresPerSocket === null) {
      var cores = Number(value)
      if (isFinite(cores) && cores > 0) coresPerSocket = cores
    } else if (key === "cache size") {
      if (value) cache = value
    }
  }

  if (logicalProcessors === 0) return null

  var sockets = physicalIds.length > 0 ? physicalIds.length : 1
  var physicalCores = null
  if (coresPerSocket !== null) physicalCores = coresPerSocket * sockets
  else if (corePairs.length > 0) physicalCores = corePairs.length

  return {
    model: model,
    vendor: vendor,
    logicalProcessors: logicalProcessors,
    physicalCores: physicalCores,
    sockets: sockets,
    cache: cache
  }
}

// /proc/meminfo -> { totalBytes, availableBytes, swapTotalBytes,
// swapFreeBytes } with kB lines converted to bytes, or null without a
// positive MemTotal. Kernels without MemAvailable and swapless systems
// report the missing fields as 0.
function parseMemInfo(raw) {
  var fields = {}
  var lines = String(raw || "").split("\n")
  for (var index = 0; index < lines.length; index++) {
    var match = /^([A-Za-z0-9_()]+):\s+(\d+)\s+kB/.exec(lines[index])
    if (match && fields[match[1]] === undefined) fields[match[1]] = Number(match[2])
  }
  var total = fields.MemTotal
  if (!(total > 0)) return null
  return {
    totalBytes: total * 1024,
    availableBytes: (fields.MemAvailable || 0) * 1024,
    swapTotalBytes: (fields.SwapTotal || 0) * 1024,
    swapFreeBytes: (fields.SwapFree || 0) * 1024
  }
}

// /etc/os-release -> { prettyName, name, id, versionId, buildId } or null
// without a single parsable KEY=value assignment. Double-quoted, single-
// quoted and bare values are all accepted; keys absent from the file (Arch
// carries no VERSION_ID) stay null and the first assignment of a duplicated
// key wins.
function parseOsRelease(raw) {
  var values = {}
  var seen = false
  var lines = String(raw || "").split("\n")
  for (var index = 0; index < lines.length; index++) {
    var line = lines[index].trim()
    if (!line || line.charAt(0) === "#") continue
    var eq = line.indexOf("=")
    if (eq <= 0) continue
    var key = line.slice(0, eq)
    if (!/^[A-Za-z0-9_]+$/.test(key)) continue
    var value = line.slice(eq + 1).trim()
    if (value.length > 1 &&
        (value.charAt(0) === '"' || value.charAt(0) === "'") &&
        value.charAt(value.length - 1) === value.charAt(0)) {
      value = value.slice(1, value.length - 1)
    }
    if (values[key] === undefined) {
      values[key] = value
      seen = true
    }
  }
  if (!seen) return null
  return {
    prettyName: values.PRETTY_NAME !== undefined ? values.PRETTY_NAME : null,
    name: values.NAME !== undefined ? values.NAME : null,
    id: values.ID !== undefined ? values.ID : null,
    versionId: values.VERSION_ID !== undefined ? values.VERSION_ID : null,
    buildId: values.BUILD_ID !== undefined ? values.BUILD_ID : null
  }
}

// `uname -srmo` output, e.g. "Linux 7.1.8-arch1-3 x86_64 GNU/Linux" ->
// { full, kernel, architecture } or null when fewer than three fields
// survive; `full` keeps the whole line including the operating-system name.
function parseKernelInfo(raw) {
  var full = String(raw || "").replace(/\s+/g, " ").trim()
  var fields = full.split(" ")
  if (fields.length < 3) return null
  return { full: full, kernel: fields[1], architecture: fields[2] }
}

// lspci -mm quoted field, with backslash escapes folded back to raw text.
function unquoteLspciField(value) {
  return value.replace(/\\(.)/g, "$1")
}

function isGraphicsClassName(className) {
  var folded = String(className).toLowerCase()
  return folded.indexOf("vga") !== -1 ||
    folded.indexOf("3d controller") !== -1 ||
    folded.indexOf("display controller") !== -1
}

// `lspci -mm -D` output -> ordered array of { address, className, vendor,
// device } for display-class hardware (VGA, 3D and Display controllers).
// Blank or unparsable input yields [] — the caller renders it as absent.
function parseLspciGraphics(raw) {
  var gpus = []
  var lines = String(raw || "").split("\n")
  for (var index = 0; index < lines.length; index++) {
    var line = lines[index]
    var quote = line.indexOf('"')
    if (quote <= 0) continue
    var address = line.slice(0, quote).trim()

    var fields = []
    var pattern = /"((?:[^"\\]|\\.)*)"/g
    var match
    while (fields.length < 3 && (match = pattern.exec(line)) !== null) {
      fields.push(unquoteLspciField(match[1]))
    }
    if (fields.length < 3 || !isGraphicsClassName(fields[0])) continue

    gpus.push({
      address: address,
      className: fields[0],
      vendor: fields[1],
      device: fields[2]
    })
  }
  return gpus
}

// `nvidia-smi --query-gpu=name,driver_version,memory.total
//  --format=csv,noheader,nounits` output -> { name, driverVersion,
// memoryTotalMiB } or null. Only the first non-empty CSV row is used
// (multi-GPU hosts print one row per card); unparsable output reports
// null so the caller can fall back to the lspci listing.
function parseNvidiaHardware(raw) {
  var firstLine = ""
  var lines = String(raw || "").split("\n")
  for (var index = 0; index < lines.length; index++) {
    var candidate = lines[index].trim()
    if (candidate) {
      firstLine = candidate
      break
    }
  }
  if (!firstLine) return null

  var fields = firstLine.split(",")
  if (fields.length < 3) return null
  var memoryTotal = Number(fields[2].trim())
  if (!(memoryTotal > 0)) return null
  return {
    name: fields[0].trim(),
    driverVersion: fields[1].trim(),
    memoryTotalMiB: memoryTotal
  }
}

// ---- bounded command boundary ----------------------------------------------
//
// Every persistent StdioCollector producer routes its command through the
// plugin-local bin/bounded-command helper, so output reaches the QML engine
// only after passing a producer-side cap (the helper buffers at most
// MAX_BYTES of child stdout, discards child stderr, and emits the buffer only
// when the child exits cleanly). These helpers are the one shared convention
// every QML root uses to locate the helper, pick its per-source cap and wrap
// an argv; no collector builds its own wrapping.

// Hard ceiling the helper itself enforces (8 MiB); the per-kind caps below
// stay far beneath it. Each cap covers the largest payload its producer
// realistically emits, so healthy output always fits while a runaway
// producer is cut off long before it can exhaust memory.
var BOUNDED_COMMAND_MAX_BYTES = 8 * 1024 * 1024
var COMMAND_OUTPUT_LIMITS = {
  stats: 4096,
  sensors: 1048576,
  disk: 16384,
  gpu: 65536,
  processes: 2097152,
  lspci: 1048576,
  uname: 8192,
  nvidiaInfo: 65536
}

// QUrl (as Qt.resolvedUrl hands to QML) or plain string -> local filesystem
// path: only a *leading* "file://" is stripped and valid percent escapes
// decode ("/my%20dir" -> "/my dir"). Malformed escapes ("%zz", a truncated
// or trailing "%") return the undecoded stripped value instead of throwing,
// so a surprising URL can never take a collector down.
function localFilePath(value) {
  var text = String(value || "")
  if (text.indexOf("file://") === 0) text = text.substring(7)
  try {
    return decodeURIComponent(text)
  } catch (error) {
    return text
  }
}

// Byte cap for one producer kind, or 0 when the kind is unknown. The builder
// treats 0 as invalid and refuses to launch rather than falling back unbounded.
function commandOutputLimit(kind) {
  var key = String(kind || "")
  return Object.prototype.hasOwnProperty.call(COMMAND_OUTPUT_LIMITS, key)
    ? COMMAND_OUTPUT_LIMITS[key]
    : 0
}

// argv list routing COMMAND through the bounded helper, or [] when the helper
// path is blank, the cap is not an integer in 1..8388608, or argv is empty —
// mirroring buildPidfdSignalCommand's "never launch garbage" contract. The
// result is a fresh array per call and the producer argv is never mutated.
function buildBoundedCommand(helperPath, maxBytes, argv) {
  var helper = String(helperPath || "").trim()
  if (helper === "") return []
  var cap = Number(maxBytes)
  if (!isFinite(cap) || cap < 1 || cap > BOUNDED_COMMAND_MAX_BYTES || cap % 1 !== 0)
    return []
  if (!Array.isArray(argv) || argv.length < 1) return []
  var wrapped = [helper, String(cap)]
  for (var index = 0; index < argv.length; index++) wrapped.push(argv[index])
  return wrapped
}

if (typeof module === "object" && typeof module.exports === "object") {
  module.exports = {
    finiteNumber: finiteNumber,
    recentHistory: recentHistory,
    appendHistory: appendHistory,
    clampPercent: clampPercent,
    formatPercent: formatPercent,
    formatRate: formatRate,
    formatCompactRate: formatCompactRate,
    formatBytes: formatBytes,
    formatUptime: formatUptime,
    formatCompactUptime: formatCompactUptime,
    formatLoad: formatLoad,
    networkScaleFor: networkScaleFor,
    parseDiskOutput: parseDiskOutput,
    parseGpuOutput: parseGpuOutput,
    parseStatsOutput: parseStatsOutput,
    calculateSystemMetrics: calculateSystemMetrics,
    buildPsCommand: buildPsCommand,
    parsePsOutput: parsePsOutput,
    compareProcessRows: compareProcessRows,
    filterAndSortProcesses: filterAndSortProcesses,
    findProcessByPid: findProcessByPid,
    normalizeStartToken: normalizeStartToken,
    buildPidfdSignalCommand: buildPidfdSignalCommand,
    utilizationLevel: utilizationLevel,
    chipMonitorIds: chipMonitorIds,
    defaultChipMonitors: defaultChipMonitors,
    normalizeChipMode: normalizeChipMode,
    normalizeChipMonitors: normalizeChipMonitors,
    toggleChipMonitor: toggleChipMonitor,
    chipMonitorEnabled: chipMonitorEnabled,
    sensorMonitorId: sensorMonitorId,
    isSensorMonitorId: isSensorMonitorId,
    sensorMonitorType: sensorMonitorType,
    parseSensorsJson: parseSensorsJson,
    normalizeHardwareValue: normalizeHardwareValue,
    parseCpuInfo: parseCpuInfo,
    parseMemInfo: parseMemInfo,
    parseOsRelease: parseOsRelease,
    parseKernelInfo: parseKernelInfo,
    parseLspciGraphics: parseLspciGraphics,
    parseNvidiaHardware: parseNvidiaHardware,
    localFilePath: localFilePath,
    commandOutputLimit: commandOutputLimit,
    buildBoundedCommand: buildBoundedCommand
  }
}
