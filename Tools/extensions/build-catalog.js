#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

function argument(name, fallback) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

const output = argument("--out", "build/extensions-catalog.json");
const version = argument("--version");
const releaseBase = argument("--release-base");
const packages = process.argv.slice(2).filter((value, index, values) => {
  return !["--out", "--version", "--release-base"].includes(value) && values[index - 1]?.startsWith("--") === false;
});

if (!version || !releaseBase || packages.length === 0) {
  throw new Error("usage: build-catalog.js --version 0.1.3 --release-base https://github.com/.../download/v0.1.3 --out catalog.json package.ocx ...");
}

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

const entries = packages.map((packagePath) => {
  const root = path.resolve(packagePath);
  const manifest = readJSON(path.join(root, "manifest.json"));
  const build = readJSON(path.join(root, "build.json"));
  const capabilities = readJSON(path.join(root, "capabilities.json"));
  const archiveName = `${manifest.name}-${version}.ocx.zip`;
  return {
    name: manifest.name,
    title: manifest.title,
    description: manifest.description,
    version,
    packageURL: `${releaseBase.replace(/\/$/, "")}/${archiveName}`,
    bundleHash: build.bundleHash,
    bundleBytes: build.bundleBytes,
    minimumAppVersion: "0.1.3",
    capabilities: capabilities.capabilities.map((item) => item.name).sort(),
    sourceRepository: "https://github.com/berkinory/opencast",
    license: manifest.license || null,
    verified: true
  };
});

fs.mkdirSync(path.dirname(path.resolve(output)), { recursive: true });
fs.writeFileSync(path.resolve(output), `${JSON.stringify({
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  packages: entries
}, null, 2)}\n`);
