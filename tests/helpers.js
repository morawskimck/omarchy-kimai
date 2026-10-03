// Loads Model.js the way QML does (a plain script, no module system) into a
// vm context, so its top-level `var`s and functions become properties we can
// call. Values from the vm realm have foreign prototypes, so compare them
// with `same()` (JSON round trip) instead of deepStrictEqual directly.
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const assert = require("node:assert/strict")

function loadModel() {
  const file = path.join(__dirname, "..", "Model.js")
  const context = vm.createContext({})
  vm.runInContext(fs.readFileSync(file, "utf8"), context, { filename: file })
  return context
}

function same(actual, expected) {
  assert.deepStrictEqual(JSON.parse(JSON.stringify(actual)), expected)
}

module.exports = { loadModel, same, assert }
