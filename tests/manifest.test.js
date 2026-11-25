"use strict"

// Mirrors the checks `omarchy plugin validate` applies, for CI without Omarchy.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.join(__dirname, "..")
const m = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))
assert.equal(m.schemaVersion, 1)
for (const field of ["id", "name", "version", "kinds", "entryPoints"]) assert.ok(field in m, "missing " + field)
assert.match(m.id, /^[A-Za-z0-9][A-Za-z0-9._-]*$/)
assert.ok(!m.id.includes("..") && !m.id.startsWith("omarchy."))
assert.ok(Array.isArray(m.kinds) && m.kinds.length > 0)
const entryFor = { service: "service", panel: "panel", "bar-widget": "barWidget" }
for (const kind of m.kinds) {
  const rel = m.entryPoints[entryFor[kind]]
  assert.ok(rel, "no entry point for " + kind)
  assert.ok(!path.isAbsolute(rel) && !rel.split("/").includes(".."), "unsafe entry point " + rel)
  const file = path.join(root, rel)
  assert.ok(fs.existsSync(file) && !fs.lstatSync(file).isSymbolicLink(), "missing entry point " + rel)
}
// The packaged version must match the manifest.
const pkgver = fs.readFileSync(path.join(root, "packaging/pkg/PKGBUILD"), "utf8").match(/^pkgver=(.+)$/m)[1]
assert.equal(pkgver, m.version)
console.log("manifest tests: ok")
