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

// ---------------------------------------------------------------- transport

function queryString(params) {
  var parts = []
  var keys = Object.keys(params || {})
  for (var i = 0; i < keys.length; i++) {
    var v = params[keys[i]]
    if (v === undefined || v === null || v === "") continue
    parts.push(encodeURIComponent(keys[i]) + "=" + encodeURIComponent(String(v)))
  }
  return parts.length ? "?" + parts.join("&") : ""
}

function apiUrl(baseUrl, path, params) {
  return baseUrl + "/api" + path + queryString(params)
}

// The token goes to curl on stdin as a config line, never as an argument,
// so it does not show up in `ps`.
function curlConfig(token) {
  var t = String(token || "").replace(/[\r\n]/g, "")
  return 'header = "Authorization: Bearer ' + t.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"\n'
}

function buildCurlArgs(method, url, body) {
  var args = ["curl", "-sS", "--max-time", "15", "--config", "-", "-X", String(method || "GET"),
              "-H", "Accept: application/json", "-w", "\n%{http_code}"]
  if (body !== undefined && body !== null)
    args.push("-H", "Content-Type: application/json", "--data-binary", JSON.stringify(body))
  args.push(url)
  return args
}

function parseCurlOutput(stdout) {
  var text = String(stdout || "")
  var cut = text.lastIndexOf("\n")
  var status = parseInt((cut === -1 ? text : text.slice(cut + 1)).trim(), 10)
  return { status: isFinite(status) ? status : 0, body: cut === -1 ? "" : text.slice(0, cut) }
}

function networkMessage(exitCode, stderr) {
  var lines = String(stderr || "").trim().split("\n")
  var last = lines[lines.length - 1]
  return last ? last.replace(/^curl: \(\d+\)\s*/, "") : "Network error (curl exit " + exitCode + ")"
}

function extractError(data, fallback) {
  var messages = []
  function walk(node) {
    if (!node || typeof node !== "object") return
    if (Array.isArray(node.errors)) {
      for (var i = 0; i < node.errors.length; i++) messages.push(String(node.errors[i]))
    } else if (node.errors && typeof node.errors === "object") {
      walk(node.errors)
    }
    if (node.children && typeof node.children === "object") {
      var keys = Object.keys(node.children)
      for (var k = 0; k < keys.length; k++) walk(node.children[keys[k]])
    }
  }
  walk(data)
  if (messages.length) return messages.join(" ")
  if (data && typeof data === "object" && data.message) return String(data.message)
  return fallback || "Kimai rejected the request"
}

// Result shape every caller of Service.api() receives:
// { kind: ok|invalid|unauthorized|notfound|server|network, status, data, message }
function classifyResponse(exitCode, stdout, stderr) {
  if (exitCode !== 0) return { kind: "network", status: 0, data: null, message: networkMessage(exitCode, stderr) }
  var res = parseCurlOutput(stdout)
  var data = null
  var parsed = true
  if (res.body.trim() !== "") {
    try { data = JSON.parse(res.body) } catch (e) { parsed = false }
  }
  if (res.status >= 200 && res.status < 300) {
    if (!parsed) return { kind: "server", status: res.status, data: null, message: "Unexpected response from the server" }
    return { kind: "ok", status: res.status, data: data, message: "" }
  }
  if (res.status === 401 || res.status === 403) return { kind: "unauthorized", status: res.status, data: data, message: "Kimai rejected the API token" }
  if (res.status === 400) return { kind: "invalid", status: 400, data: data, message: extractError(data) }
  if (res.status === 404) return { kind: "notfound", status: 404, data: data, message: extractError(data, "Not found") }
  return { kind: "server", status: res.status, data: data, message: "Kimai answered HTTP " + (res.status || "?") }
}

// Normal interval while healthy; doubling back-off from 30 s, capped at 300 s.
function nextPollSeconds(failures, pollSeconds) {
  if (!failures) return pollSeconds
  return Math.max(pollSeconds, Math.min(300, 30 * Math.pow(2, failures - 1)))
}

function secretToolArgs(action, url) {
  var attrs = ["application", KEYRING_APP, "url", url]
  if (action === "store") return ["secret-tool", "store", "--label=Omarchy Kimai (" + url + ")"].concat(attrs)
  return ["secret-tool", action].concat(attrs)
}

// ---------------------------------------------------------------- view logic

function sortActive(list) {
  var arr = Array.isArray(list) ? list.slice() : []
  arr.sort(function(a, b) { return parseKimaiDate(b.begin) - parseKimaiDate(a.begin) })
  return arr
}

function activityName(entry) {
  if (entry && entry.activity && entry.activity.name) return String(entry.activity.name)
  if (entry && entry.project && entry.project.name) return String(entry.project.name)
  return "Timer"
}

function projectLine(entry) {
  var p = entry && entry.project ? entry.project : null
  if (!p || !p.name) return ""
  return String(p.name) + (p.customer && p.customer.name ? " · " + p.customer.name : "")
}

// Bar label pieces; the widget elides `name` to labelMaxWidth on its own.
function barParts(active, nowMs) {
  if (!active || !active.length) return { elapsed: "", name: "", extra: "" }
  var newest = active[0]
  return {
    elapsed: formatElapsed(elapsedSeconds(newest.begin, nowMs)),
    name: activityName(newest),
    extra: active.length > 1 ? " +" + (active.length - 1) : ""
  }
}

function tooltip(status, active, nowMs, lastSync, errorText) {
  if (status === "unconfigured") return "Kimai · Set up Kimai"
  if (status === "unauthorized" || status === "error") return "Kimai · " + (errorText || "Error")
  var lines = []
  var list = active || []
  if (!list.length) lines.push("Kimai · No timer running")
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    if (i > 0) lines.push("")
    lines.push(activityName(e) + " — " + formatElapsed(elapsedSeconds(e.begin, nowMs)))
    var pl = projectLine(e)
    if (pl) lines.push(pl)
    if (e.description) lines.push(String(e.description))
    lines.push("Started " + wallTime(e.begin))
  }
  if (status === "stale") lines.push("Offline · last sync " + (lastSync ? formatClock(lastSync) : "never"))
  return lines.join("\n")
}

function entrySeconds(entry, nowMs) {
  if (!entry.end) return elapsedSeconds(entry.begin, nowMs)
  if (isFinite(Number(entry.duration)) && entry.duration !== null) return Math.max(0, Number(entry.duration))
  return Math.max(0, Math.round((parseKimaiDate(entry.end) - parseKimaiDate(entry.begin)) / 1000))
}

function entryRow(entry, nowMs) {
  var running = !entry.end
  return {
    id: entry.id,
    running: running,
    range: wallTime(entry.begin) + "–" + (running ? "now" : wallTime(entry.end)),
    duration: formatElapsed(entrySeconds(entry, nowMs)),
    title: activityName(entry) + (entry.project && entry.project.name ? " · " + entry.project.name : ""),
    description: String(entry.description || "")
  }
}

function dayTotalSeconds(entries, nowMs) {
  var total = 0
  for (var i = 0; i < (entries || []).length; i++) total += entrySeconds(entries[i], nowMs)
  return total
}

// SearchableDropdown options. `parentTitle` is the customer (projects) or the
// project (activities); the dropdown also searches descriptions.
function toOptions(list) {
  var out = []
  for (var i = 0; i < (list || []).length; i++) {
    var item = list[i]
    if (!item || item.id === undefined || item.id === null) continue
    out.push({ value: String(item.id), label: String(item.name || ("#" + item.id)), description: String(item.parentTitle || "") })
  }
  out.sort(function(a, b) { return a.label.localeCompare(b.label) })
  return out
}

function mergeById(a, b) {
  var seen = {}
  var out = []
  var all = (a || []).concat(b || [])
  for (var i = 0; i < all.length; i++) {
    if (!all[i] || seen[all[i].id]) continue
    seen[all[i].id] = true
    out.push(all[i])
  }
  return out
}

function tagOptions(names) {
  var seen = {}
  var out = []
  for (var i = 0; i < (names || []).length; i++) {
    var n = typeof names[i] === "object" && names[i] ? names[i].name : names[i]
    n = String(n || "").trim()
    if (!n || seen[n]) continue
    seen[n] = true
    out.push(n)
  }
  out.sort(function(a, b) { return a.localeCompare(b) })
  return out
}

// Names in `wanted` that Kimai doesn't have yet. Kimai treats tag names
// case-insensitively, so "Review" matches an existing "review".
function missingTags(wanted, existing) {
  var have = {}
  var list = tagOptions(existing)
  for (var i = 0; i < list.length; i++) have[list[i].toLowerCase()] = true
  return tagOptions(wanted).filter(function(name) { return !have[name.toLowerCase()] })
}

function mergeTags(selected, extraText) {
  var extra = String(extraText || "").split(",")
  return tagOptions((selected || []).concat(extra))
}

function tagsOf(entry) {
  return tagOptions(entry && entry.tags ? entry.tags : [])
}

function prefillFromRecent(recent) {
  var r = recent && recent.length ? recent[0] : null
  if (!r) return { projectId: "", activityId: "", description: "", tags: [] }
  return {
    projectId: r.project ? String(r.project.id) : "",
    activityId: r.activity ? String(r.activity.id) : "",
    description: String(r.description || ""),
    tags: tagsOf(r)
  }
}

function startPayload(f) {
  if (!f || !f.projectId || !f.activityId) return { ok: false, error: "Pick a project and an activity", payload: null }
  return {
    ok: true,
    error: "",
    payload: {
      project: Number(f.projectId),
      activity: Number(f.activityId),
      description: String(f.description || "").trim(),
      tags: (f.tags || []).join(",")
    }
  }
}

function parseHHMM(s) {
  var m = /^(\d{1,2}):(\d{2})$/.exec(String(s || "").trim())
  if (!m) return null
  var h = +m[1]
  var min = +m[2]
  if (h > 23 || min > 59) return null
  return pad2(h) + ":" + pad2(min)
}

// f: { entry, projectId, activityId, description, tags, beginTime, endTime, allowTimes }
// Times are only sent when they changed, so untouched seconds and dates stay
// exactly as Kimai stored them.
function validateEdit(f) {
  if (!f || !f.projectId || !f.activityId) return { ok: false, error: "Pick a project and an activity", payload: null }
  var payload = {
    project: Number(f.projectId),
    activity: Number(f.activityId),
    description: String(f.description || "").trim(),
    tags: (f.tags || []).join(",")
  }
  if (f.allowTimes && f.entry) {
    var b = parseHHMM(f.beginTime)
    if (!b) return { ok: false, error: "Start time must look like 09:30", payload: null }
    var beginStamp = b === wallTime(f.entry.begin) ? wallStamp(f.entry.begin) : wallDate(f.entry.begin) + "T" + b + ":00"
    if (b !== wallTime(f.entry.begin)) payload.begin = beginStamp
    if (f.entry.end) {
      var e = parseHHMM(f.endTime)
      if (!e) return { ok: false, error: "End time must look like 17:00", payload: null }
      var endStamp = e === wallTime(f.entry.end) ? wallStamp(f.entry.end) : wallDate(f.entry.end) + "T" + e + ":00"
      if (e !== wallTime(f.entry.end)) payload.end = endStamp
      if (endStamp <= beginStamp) return { ok: false, error: "End must be after start", payload: null }
    }
  }
  return { ok: true, error: "", payload: payload }
}

function isPunchMode(mode) {
  return mode === "punch"
}

function editUrl(baseUrl, id) {
  return baseUrl + "/en/timesheet/" + id + "/edit"
}

function userLabel(user) {
  if (!user) return ""
  return String(user.alias || user.username || "")
}

// Short text for the popup header.
function statusLabel(status, user) {
  if (status === "ok") return userLabel(user) || "Connected"
  if (status === "unconfigured") return "Not connected"
  if (status === "connecting") return "Connecting…"
  if (status === "stale") return "Offline"
  if (status === "unauthorized") return "Token rejected"
  return "Error"
}

function statusSnapshot(status, active, nowMs, errorText) {
  var list = active || []
  var parts = barParts(list, nowMs)
  var timers = []
  for (var i = 0; i < list.length; i++) {
    timers.push({
      id: list[i].id,
      activity: activityName(list[i]),
      project: projectLine(list[i]),
      begin: list[i].begin,
      elapsed: formatElapsed(elapsedSeconds(list[i].begin, nowMs))
    })
  }
  return {
    status: status,
    running: list.length > 0,
    label: parts.elapsed ? parts.elapsed + " · " + parts.name + parts.extra : "",
    error: errorText || "",
    timers: timers
  }
}
