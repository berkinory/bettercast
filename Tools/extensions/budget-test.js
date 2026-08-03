#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");
const app = path.resolve(process.env.OPENCAST_APP || path.join(root, "build/Phase5Derived/Build/Products/Debug/Opencast Dev.app"));
const packageRoot = path.join(root, "build/extensions");

function filesIn(directory) {
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const item = path.join(directory, entry.name);
    return entry.isDirectory() ? filesIn(item) : [item];
  });
}

function bytes(directory) {
  return filesIn(directory).reduce((total, file) => total + fs.statSync(file).size, 0);
}

if (!fs.existsSync(app)) throw new Error(`app not found: ${app}`);
const appFiles = filesIn(app);
if (appFiles.some((file) => file.endsWith(".ocx") || /\/(node|bun)(\.js)?$/.test(file))) {
  throw new Error("app bundle contains extension package or JavaScript runtime");
}

const packages = fs.existsSync(packageRoot)
  ? fs.readdirSync(packageRoot).filter((name) => name.endsWith(".ocx"))
  : [];
for (const name of packages) {
  const size = bytes(path.join(packageRoot, name));
  if (size > 8 * 1024 * 1024) throw new Error(`${name} exceeds the 8 MB package budget`);
  process.stdout.write(`${name}: ${size} bytes\n`);
}
process.stdout.write(`app bundle: ${bytes(app)} bytes\n`);
