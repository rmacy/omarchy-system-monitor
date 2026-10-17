import QtQuick
import qs.Commons

QtObject {
  id: root

  property QtObject bar: null
  property bool useSystemTheme: false

  function fullKey(key) {
    return "system-monitor." + key
  }

  function malformedHex(value) {
    if (typeof value !== "string") return false
    var token = Color.firstColorToken(value).replace(/^\s+|\s+$/g, "")
    return token.charAt(0) === "#"
      && !token.match(/^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/)
  }

  function flatColorToken(key, fallback) {
    var picked = Color.pick(fullKey(key), fallback)
    if (malformedHex(picked)) picked = fallback
    return Color.flatColor(picked, fallback)
  }

  function composedColorToken(key, fallback, fallbackAlpha) {
    var colorKey = fullKey(key)
    var alphaKey = fullKey(key + "-alpha")
    var picked = Color.pick(colorKey, fallback)
    if (malformedHex(picked)) {
      return Util.alpha(
        Color.flatColor(fallback, fallback),
        Color.pickAlpha(alphaKey, fallbackAlpha))
    }
    return Color.composed(colorKey, alphaKey, fallback, fallbackAlpha)
  }

  function numberToken(key, fallback, minimum, maximum) {
    var raw = Color.shellValues[fullKey(key)]
    if (raw === undefined || raw === null) return fallback
    var text = String(raw).replace(/^\s+|\s+$/g, "")
    if (text.length === 0) return fallback
    var value = Number(text)
    if (!isFinite(value) || value < minimum || value > maximum) return fallback
    return value
  }

  function integerToken(key, fallback, minimum, maximum) {
    return Math.round(numberToken(key, fallback, minimum, maximum))
  }

  function stringToken(key, fallback, maximumLength) {
    var raw = Color.shellValues[fullKey(key)]
    if (typeof raw !== "string") return fallback
    var trimmed = raw.replace(/^\s+|\s+$/g, "")
    if (trimmed.length === 0 || raw.length > maximumLength) return fallback
    return raw
  }

  function chipFallbackAlpha() {
    return bar && bar.transparent === false ? 0.94 : 0.68
  }

  readonly property color foreground: flatColorToken(
    "text", bar ? bar.barForeground : Color.foreground)
  readonly property color muted: flatColorToken("muted", Color.muted)
  readonly property string fontFamily: bar && bar.fontFamily
    ? bar.fontFamily
    : Style.font.family
  readonly property color accentColor: flatColorToken("accent", Color.accent)

  // Blend only theme roles, so signal tones follow theme changes live.
  function blend(first, second, amount) {
    return Qt.rgba(first.r + (second.r - first.r) * amount,
      first.g + (second.g - first.g) * amount,
      first.b + (second.b - first.b) * amount, 1)
  }

  readonly property color themeUrgent: bar ? bar.urgent : Color.urgent
  readonly property color separatorColor: useSystemTheme
    ? Util.alpha(foreground, 0.16) : chipBorder

  readonly property color cpuColor: flatColorToken("cpu", useSystemTheme ? accentColor : "#61d5f8")
  readonly property color memoryColor: flatColorToken("memory", useSystemTheme ? blend(accentColor, foreground, 0.7) : "#c7a6ff")
  readonly property color downloadColor: flatColorToken("download", useSystemTheme ? accentColor : "#5eead4")
  readonly property color uploadColor: flatColorToken("upload", useSystemTheme ? foreground : "#a3e635")
  readonly property color loadColor: flatColorToken("load", useSystemTheme ? blend(accentColor, foreground, 0.35) : "#fbbf24")
  readonly property color uptimeColor: flatColorToken("uptime", useSystemTheme ? foreground : "#94a3b8")
  readonly property color diskColor: flatColorToken("disk", useSystemTheme ? accentColor : "#38bdf8")
  readonly property color gpuColor: flatColorToken("gpu", useSystemTheme ? blend(accentColor, foreground, 0.35) : "#f472b6")
  readonly property color temperatureColor: flatColorToken("temperature", useSystemTheme ? accentColor : "#fb923c")
  readonly property color fanColor: flatColorToken("fan", useSystemTheme ? blend(accentColor, foreground, 0.7) : "#38bdf8")
  readonly property color warningColor: flatColorToken("warning", useSystemTheme ? blend(themeUrgent, accentColor, 0.5) : "#fbbf24")
  readonly property color criticalColor: flatColorToken("critical", useSystemTheme ? themeUrgent : "#fb7185")

  readonly property color chipBackground: composedColorToken(
    "chip-background", Color.background, chipFallbackAlpha())
  readonly property color chipBorder: composedColorToken(
    "chip-border", cpuColor, 0.48)
  readonly property color cardFill: composedColorToken(
    "card-background", foreground, 0.045)
  readonly property color cardBorder: composedColorToken(
    "card-border", foreground, 0.18)
  readonly property color graphGrid: composedColorToken(
    "graph-grid", foreground, 0.12)

  readonly property int animationDuration: integerToken(
    "animation-duration", 180, 0, 5000)
  readonly property real chipPadding: numberToken(
    "chip-padding", Style.spacing.lg, 0, 64)
  readonly property real monitorGap: numberToken(
    "monitor-gap", Style.spacing.lg, 0, 64)
  readonly property real graphWidth: numberToken(
    "graph-width", Style.space(42), 16, 256)
  readonly property real graphHeight: numberToken(
    "graph-height", Style.space(12), 4, 128)
  readonly property string minimalSeparator: stringToken(
    "minimal-separator", " · ", 16)
}
