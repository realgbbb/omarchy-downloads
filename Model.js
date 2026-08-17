// Pure formatting helpers for the Downloads panel. No QML types in here, so
// the whole file is unit-testable with plain node (see test/model.test.js).

var IMAGE_EXTENSIONS = {
  jpg: true, jpeg: true, png: true, gif: true, webp: true, avif: true,
  heic: true, svg: true, bmp: true, tif: true, tiff: true, ico: true
}

var VIDEO_EXTENSIONS = {
  mp4: true, mov: true, mkv: true, webm: true, avi: true, m4v: true,
  mpg: true, mpeg: true, wmv: true, flv: true
}

var AUDIO_EXTENSIONS = {
  mp3: true, flac: true, wav: true, ogg: true, opus: true, m4a: true,
  aac: true, wma: true, aiff: true
}

var DOCUMENT_EXTENSIONS = {
  pdf: true, txt: true, md: true, doc: true, docx: true, xls: true,
  xlsx: true, ppt: true, pptx: true, odt: true, ods: true, odp: true,
  rtf: true, csv: true, epub: true, pages: true, numbers: true, key: true
}

var ARCHIVE_EXTENSIONS = {
  zip: true, tar: true, gz: true, tgz: true, bz2: true, xz: true, zst: true,
  rar: true, "7z": true, iso: true, img: true, dmg: true
}

var PACKAGE_EXTENSIONS = {
  apk: true, aab: true, deb: true, rpm: true, appimage: true, exe: true,
  msi: true, pkg: true, whl: true, jar: true, ipa: true
}

var CODE_EXTENSIONS = {
  js: true, ts: true, tsx: true, jsx: true, py: true, rb: true, go: true,
  rs: true, c: true, h: true, cpp: true, sh: true, lua: true, json: true,
  yaml: true, yml: true, toml: true, xml: true, html: true, css: true,
  qml: true, sql: true, patch: true, diff: true, p8: true, pem: true
}

function fileExtension(name) {
  var value = String(name || "").toLowerCase()
  var index = value.lastIndexOf(".")
  return index > 0 ? value.substring(index + 1) : ""
}

function fileKind(file) {
  if (file && file.isDir) return "folder"
  if (file && file.partial) return "partial"
  var ext = fileExtension(file ? file.name : file)
  if (IMAGE_EXTENSIONS[ext]) return "image"
  if (VIDEO_EXTENSIONS[ext]) return "video"
  if (AUDIO_EXTENSIONS[ext]) return "audio"
  if (DOCUMENT_EXTENSIONS[ext]) return "document"
  if (ARCHIVE_EXTENSIONS[ext]) return "archive"
  if (PACKAGE_EXTENSIONS[ext]) return "package"
  if (CODE_EXTENSIONS[ext]) return "code"
  return "misc"
}

// Nerd Font glyphs, all from the Material Design range the stock panels
// already draw from (omarchy.dropbox uses f0219 / f02e9 / f022b / f0214).
function fileGlyph(file) {
  switch (fileKind(file)) {
    case "folder": return "󰉋"
    case "partial": return "󰇚"
    case "image": return "󰋩"
    case "video": return "󰈫"
    case "audio": return "󰈣"
    case "document": return "󰈙"
    case "archive": return "󰗄"
    case "package": return "󰏓"
    case "code": return "󰈮"
    default: return "󰈔"
  }
}

function formatBytes(bytes) {
  var value = Number(bytes || 0)
  if (!isFinite(value) || value <= 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var index = 0
  while (value >= 1000 && index < units.length - 1) {
    value = value / 1000
    index++
  }
  var decimals = value >= 100 || index === 0 ? 0 : (value >= 10 ? 1 : 2)
  return value.toFixed(decimals).replace(/\.0+$/, "").replace(/(\.\d)0$/, "$1") + " " + units[index]
}

function relativeTime(timestampSec, nowMs) {
  var ts = Number(timestampSec || 0)
  if (!isFinite(ts) || ts <= 0) return "Unknown time"
  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  var diff = Math.max(0, Math.floor((now - ts * 1000) / 1000))
  if (diff < 60) return "Just now"
  var minutes = Math.floor(diff / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d ago"
  var months = Math.floor(days / 30)
  if (months < 12) return months + "mo ago"
  return Math.floor(days / 365) + "y ago"
}

function fileMeta(file, nowMs) {
  if (!file) return ""
  var parts = [relativeTime(file.modifiedTs, nowMs)]
  if (file.isDir) parts.push("Folder")
  else parts.push(formatBytes(file.sizeBytes))
  if (file.partial) parts.push("Downloading")
  return parts.join(" · ")
}

// Hero subtitle. In-flight downloads outrank the resting count, because that's
// the thing you opened the panel to check.
function summaryText(total, partials) {
  var count = Number(total || 0)
  var busy = Number(partials || 0)
  if (busy > 0) return busy === 1 ? "1 downloading" : busy + " downloading"
  if (count === 0) return "Nothing here yet"
  return count === 1 ? "1 file" : count + " files"
}

// Rows 1-9 carry a one-key shortcut. It stops at nine on purpose: a two-digit
// shortcut needs a timeout to know when you have finished typing, and a panel
// whose whole point is being over in one keystroke cannot afford to wait.
var SHORTCUT_ROWS = 9

// Badge text for a row, or "" for rows past the shortcut range.
function shortcutKey(index) {
  var n = Number(index)
  if (!isFinite(n) || n < 0 || n >= SHORTCUT_ROWS) return ""
  return String(n + 1)
}

// The row a typed character opens, or -1 when it is not a shortcut key.
function shortcutIndex(text) {
  var s = String(text || "")
  if (s.length !== 1 || s < "1" || s > "9") return -1
  var n = Number(s) - 1
  return n < SHORTCUT_ROWS ? n : -1
}

// Path with $HOME collapsed, for the folder button's tooltip.
function displayPath(path, home) {
  var value = String(path || "")
  var prefix = String(home || "")
  if (prefix !== "" && value.indexOf(prefix) === 0) return "~" + value.substring(prefix.length)
  return value
}

if (typeof module !== "undefined") {
  module.exports = {
    fileExtension: fileExtension,
    fileKind: fileKind,
    fileGlyph: fileGlyph,
    formatBytes: formatBytes,
    relativeTime: relativeTime,
    fileMeta: fileMeta,
    summaryText: summaryText,
    shortcutKey: shortcutKey,
    shortcutIndex: shortcutIndex,
    displayPath: displayPath
  }
}
