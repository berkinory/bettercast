#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");
const allowlist = JSON.parse(fs.readFileSync(path.join(root, "Store/approved-extensions.json"), "utf8"));
const changedFiles = fs.readFileSync(0, "utf8").split(/\r?\n/).filter(Boolean);
const globalPrefixes = [
  "Extensions/Runtime/",
  "Extensions/Capabilities.json",
  "Store/approved-extensions.json",
  "Tools/extensions/build-extension.js",
  "Tools/extensions/build-store.js",
  "Tools/extensions/changed-store-extensions.js",
  ".github/workflows/extension-store.yml"
];

const rebuildAll = changedFiles.some((file) => globalPrefixes.some((prefix) => file === prefix || file.startsWith(prefix)));
const names = allowlist.extensions
  .filter((entry) => {
    const fixture = `${entry.fixture.replace(/\\/g, "/")}/`;
    return changedFiles.some((file) => file === entry.fixture || file.startsWith(fixture));
  })
  .map((entry) => JSON.parse(fs.readFileSync(path.join(root, entry.fixture, "package.json"), "utf8")).name);

process.stdout.write(`mode=${rebuildAll ? "all" : names.length > 0 ? "only" : "none"}\n`);
process.stdout.write(`only=${names.join(",")}\n`);
