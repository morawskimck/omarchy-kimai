// Pure logic for the Kimai plugin. No QML or Quickshell APIs in here, so
// tests/model.test.js can run this file under plain node (vm context).
// Use `var` and function declarations only: they become properties of the
// vm context, which is how the tests reach them.

var ID = "io.github.morawskimck.kimai"
var ICON = String.fromCodePoint(0xf13ab) // nf-md-timer_outline
var DEFAULT_CONFIG = { url: "", pollSeconds: 30, labelMaxWidth: 180 }
var KEYRING_APP = "omarchy-kimai"

// ---------------------------------------------------------------- config

function clamp(value, min, max, fallback) {
  if (value === undefined || value === null || value === "") return fallback
  var n = Number(value)
  if (!isFinite(n)) return fallback
  return Math.min(max, Math.max(min, Math.round(n)))
}

function normalizeUrl(input) {
  var s = String(input === undefined || input === null ? "" : input).trim()
  if (!s) return { ok: false, url: "", error: "Enter your Kimai URL" }
  if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(s)) s = "https://" + s
  s = s.replace(/\/+$/, "").replace(/\/api$/i, "").replace(/\/+$/, "")
  var m = /^(https?):\/\/([^\/:?#\s]+)(:\d+)?(\/[^?#\s]*)?$/i.exec(s)
  if (!m) return { ok: false, url: "", error: "That doesn't look like a URL" }
  var scheme = m[1].toLowerCase()
  var host = m[2].toLowerCase()
  if (scheme === "http" && host !== "localhost" && host !== "127.0.0.1")
    return { ok: false, url: "", error: "Use https:// (plain http only works for localhost)" }
  return { ok: true, url: scheme + "://" + host + (m[3] || "") + (m[4] || ""), error: "" }
}

function parseConfig(text) {
  var raw = {}
  try { raw = JSON.parse(String(text || "")) } catch (e) { raw = {} }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) raw = {}
  var url = normalizeUrl(raw.url)
  return {
    url: url.ok ? url.url : "",
    pollSeconds: clamp(raw.pollSeconds, 10, 600, DEFAULT_CONFIG.pollSeconds),
    labelMaxWidth: clamp(raw.labelMaxWidth, 60, 400, DEFAULT_CONFIG.labelMaxWidth)
  }
}

function serializeConfig(config) {
  return JSON.stringify(parseConfig(JSON.stringify(config || {})), null, 2) + "\n"
}

// ---------------------------------------------------------------- dates

// Kimai sends wall-clock time in the user's profile timezone plus an offset,
// e.g. 2026-10-03T09:15:00+0200.
var KIMAI_DATE = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?(Z|[+-]\d{2}:?\d{2})?$/

function pad2(n) { return (n < 10 ? "0" : "") + n }

function kimaiOffsetMinutes(s) {
  var m = KIMAI_DATE.exec(String(s || ""))
  if (!m || !m[7]) return null
  if (m[7] === "Z") return 0
  var sign = m[7][0] === "-" ? -1 : 1
  var digits = m[7].replace(/[^0-9]/g, "")
  return sign * (parseInt(digits.slice(0, 2), 10) * 60 + parseInt(digits.slice(2, 4), 10))
}

function parseKimaiDate(s) {
  var m = KIMAI_DATE.exec(String(s || ""))
  if (!m) return NaN
  var parts = [+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0)]
  var offset = kimaiOffsetMinutes(s)
  if (offset === null) return new Date(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]).getTime()
  return Date.UTC(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]) - offset * 60000
}

function wallDate(s) {
  var m = KIMAI_DATE.exec(String(s || ""))
  return m ? m[1] + "-" + m[2] + "-" + m[3] : ""
}

function wallTime(s) {
  var m = KIMAI_DATE.exec(String(s || ""))
  return m ? m[4] + ":" + m[5] : ""
}

function wallStamp(s) {
  var m = KIMAI_DATE.exec(String(s || ""))
  return m ? m[1] + "-" + m[2] + "-" + m[3] + "T" + m[4] + ":" + m[5] + ":" + (m[6] || "00") : ""
}

function elapsedSeconds(begin, nowMs) {
  var t = parseKimaiDate(begin)
  if (isNaN(t)) return 0
  return Math.max(0, Math.floor((nowMs - t) / 1000))
}

function formatElapsed(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  return Math.floor(s / 3600) + ":" + pad2(Math.floor((s % 3600) / 60))
}

function formatClock(ms) {
  var d = new Date(ms)
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

function localDateString(ms) {
  var d = new Date(ms)
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

function addDays(dateStr, days) {
  var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(dateStr || ""))
  if (!m) return ""
  var d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3] + days))
  return d.getUTCFullYear() + "-" + pad2(d.getUTCMonth() + 1) + "-" + pad2(d.getUTCDate())
}

var DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function formatDayHeader(dateStr) {
  var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(dateStr || ""))
  if (!m) return ""
  var d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]))
  return DAY_NAMES[d.getUTCDay()] + " " + d.getUTCDate() + " " + MONTH_NAMES[d.getUTCMonth()]
}

function dayRange(dateStr) {
  return { begin: dateStr + "T00:00:00", end: dateStr + "T23:59:59" }
}

function localOffsetAt(ms) {
  return -new Date(ms).getTimezoneOffset()
}

function timezoneMismatch(kimaiDate, localOffsetMinutes) {
  var offset = kimaiOffsetMinutes(kimaiDate)
  return offset !== null && offset !== localOffsetMinutes
}
