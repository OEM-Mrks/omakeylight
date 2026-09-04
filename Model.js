// Pure helpers for the omakeylight panel. Kept free of QML types so the
// parsing and label logic stays readable and testable on its own.

function parseStatus(raw) {
  var out = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx <= 0) continue
    out[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
  }
  return out
}

function parseTimeouts(value) {
  var parts = String(value || "").trim().split(/\s+/)
  var list = []
  for (var i = 0; i < parts.length; i++) if (parts[i]) list.push(parts[i])
  return list
}

// "90s" -> 90, "5m" -> 300, "1h" -> 3600. Used only for ordering and for the
// human-readable label; the driver always gets the original string back.
function timeoutSeconds(value) {
  var m = String(value || "").match(/^(\d+)\s*([smhd])$/)
  if (!m) return 0
  var n = parseInt(m[1], 10)
  var unit = m[2]
  if (unit === "s") return n
  if (unit === "m") return n * 60
  if (unit === "h") return n * 3600
  return n * 86400
}

function timeoutLabel(value) {
  var secs = timeoutSeconds(value)
  if (secs === 0) return String(value || "—")
  if (secs < 60) return secs + "s"
  if (secs < 3600) return (secs / 60) + "m"
  if (secs < 86400) return (secs / 3600) + "h"
  return (secs / 86400) + "d"
}

function timeoutSentence(value) {
  var secs = timeoutSeconds(value)
  if (secs === 0) return "Stays on"
  if (secs < 60) return "Off after " + secs + " seconds"
  if (secs < 3600) {
    var mins = secs / 60
    return "Off after " + mins + (mins === 1 ? " minute" : " minutes")
  }
  var hours = secs / 3600
  return "Off after " + hours + (hours === 1 ? " hour" : " hours")
}

function clampLevel(level, max) {
  var n = Number(level)
  if (!isFinite(n)) return 0
  return Math.max(0, Math.min(Number(max) || 0, Math.round(n)))
}

// Three named steps read better than "2/2" on the hardware this targets,
// where max_brightness is almost always 1 or 2. Anything with more steps
// falls back to a plain level readout.
function levelLabel(level, max) {
  var n = clampLevel(level, max)
  var m = Number(max) || 0
  if (n === 0) return "Off"
  if (m <= 1) return "On"
  if (m === 2) return n === 1 ? "Dim" : "Bright"
  if (n === m) return "Bright"
  return "Level " + n + " of " + m
}

function icon(level) {
  return clampLevel(level, 99) > 0 ? "󰌌" : "󰌐"
}

function fraction(level, max) {
  var m = Number(max) || 0
  if (m <= 0) return 0
  return clampLevel(level, m) / m
}

if (typeof module !== "undefined") {
  module.exports = {
    parseStatus: parseStatus,
    parseTimeouts: parseTimeouts,
    timeoutSeconds: timeoutSeconds,
    timeoutLabel: timeoutLabel,
    timeoutSentence: timeoutSentence,
    clampLevel: clampLevel,
    levelLabel: levelLabel,
    icon: icon,
    fraction: fraction
  }
}
