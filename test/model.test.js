// Plain-node tests for the pure formatting layer. QML never enters into it.
//
//   node test/model.test.js

const assert = require("node:assert/strict")
const Model = require("../Model.js")

const NOW = Date.UTC(2026, 0, 2, 12, 0, 0)
const secondsAgo = (n) => Math.floor(NOW / 1000) - n

const tests = {
  "extensions are case-insensitive and dotfiles have none"() {
    assert.equal(Model.fileExtension("Report.PDF"), "pdf")
    assert.equal(Model.fileExtension("archive.tar.gz"), "gz")
    assert.equal(Model.fileExtension(".bashrc"), "")
    assert.equal(Model.fileExtension("Makefile"), "")
  },

  "kind falls back to misc, and partial/folder win over extension"() {
    assert.equal(Model.fileKind({ name: "holiday.JPEG" }), "image")
    assert.equal(Model.fileKind({ name: "talk.mkv" }), "video")
    assert.equal(Model.fileKind({ name: "app.apk" }), "package")
    assert.equal(Model.fileKind({ name: "notes.qwerty" }), "misc")
    assert.equal(Model.fileKind({ name: "holiday.jpeg", partial: true }), "partial")
    assert.equal(Model.fileKind({ name: "holiday.jpeg", isDir: true }), "folder")
  },

  "every kind has a glyph"() {
    const names = ["a.png", "a.mkv", "a.mp3", "a.pdf", "a.zip", "a.deb", "a.ts", "a.zzz"]
    for (const name of names) {
      const glyph = Model.fileGlyph({ name })
      assert.ok(glyph && glyph.length > 0, `no glyph for ${name}`)
    }
    assert.notEqual(Model.fileGlyph({ name: "a.png" }), Model.fileGlyph({ name: "a.zip" }))
  },

  "bytes read as a human would say them"() {
    assert.equal(Model.formatBytes(0), "0 B")
    assert.equal(Model.formatBytes(999), "999 B")
    assert.equal(Model.formatBytes(1000), "1 KB")
    assert.equal(Model.formatBytes(1536), "1.54 KB")
    assert.equal(Model.formatBytes(15360), "15.4 KB")
    assert.equal(Model.formatBytes(2.5e9), "2.5 GB")
  },

  "relative time buckets"() {
    assert.equal(Model.relativeTime(secondsAgo(5), NOW), "Just now")
    assert.equal(Model.relativeTime(secondsAgo(90), NOW), "1m ago")
    assert.equal(Model.relativeTime(secondsAgo(3 * 3600), NOW), "3h ago")
    assert.equal(Model.relativeTime(secondsAgo(2 * 86400), NOW), "2d ago")
    assert.equal(Model.relativeTime(0, NOW), "Unknown time")
  },

  "row meta combines age, size and progress"() {
    const file = { name: "a.pdf", sizeBytes: 2215, modifiedTs: secondsAgo(120) }
    assert.equal(Model.fileMeta(file, NOW), "2m ago · 2.21 KB")
    assert.equal(Model.fileMeta({ ...file, partial: true }, NOW), "2m ago · 2.21 KB · Downloading")
    assert.equal(Model.fileMeta({ ...file, isDir: true }, NOW), "2m ago · Folder")
    assert.equal(Model.fileMeta(null, NOW), "")
  },

  "in-flight downloads outrank the resting count"() {
    assert.equal(Model.summaryText(0, 0), "Nothing here yet")
    assert.equal(Model.summaryText(1, 0), "1 file")
    assert.equal(Model.summaryText(137, 0), "137 files")
    assert.equal(Model.summaryText(137, 1), "1 downloading")
    assert.equal(Model.summaryText(137, 4), "4 downloading")
  },

  "row shortcuts cover the first nine rows and nothing else"() {
    assert.equal(Model.shortcutKey(0), "1")
    assert.equal(Model.shortcutKey(8), "9")
    assert.equal(Model.shortcutKey(9), "")
    assert.equal(Model.shortcutKey(-1), "")
    assert.equal(Model.shortcutKey("x"), "")
  },

  "typed keys map back to the row they open"() {
    assert.equal(Model.shortcutIndex("1"), 0)
    assert.equal(Model.shortcutIndex("9"), 8)
    assert.equal(Model.shortcutIndex("0"), -1)
    assert.equal(Model.shortcutIndex("o"), -1)
    assert.equal(Model.shortcutIndex("12"), -1)
    assert.equal(Model.shortcutIndex(""), -1)
    for (let row = 0; row < 9; row++) {
      assert.equal(Model.shortcutIndex(Model.shortcutKey(row)), row)
    }
  },

  "home is collapsed to a tilde, other paths are untouched"() {
    assert.equal(Model.displayPath("/home/ada/Downloads", "/home/ada"), "~/Downloads")
    assert.equal(Model.displayPath("/mnt/big/Downloads", "/home/ada"), "/mnt/big/Downloads")
    assert.equal(Model.displayPath("", "/home/ada"), "")
  }
}

let failed = 0
for (const [name, run] of Object.entries(tests)) {
  try {
    run()
    console.log(`ok   ${name}`)
  } catch (error) {
    failed++
    console.error(`FAIL ${name}\n     ${error.message}`)
  }
}
console.log(`\n${Object.keys(tests).length - failed}/${Object.keys(tests).length} passed`)
process.exit(failed === 0 ? 0 : 1)
