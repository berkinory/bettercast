#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "../..");
const buildExtension = path.join(root, "Tools/extensions/build-extension.js");
const allowlistPath = path.join(root, "Store/approved-extensions.json");

function argument(name, fallback) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

const output = path.resolve(argument("--out", "build/extension-store"));
const catalogPath = path.resolve(argument("--catalog", path.join(output, "extensions-catalog.json")));
const catalogInputArgument = argument("--catalog-input");
const catalogInput = catalogInputArgument ? path.resolve(catalogInputArgument) : null;
const releaseBase = argument("--release-base");
const only = new Set((argument("--only", "") || "").split(",").filter(Boolean));

if (!releaseBase) {
  throw new Error("usage: build-store.js --release-base https://github.com/.../releases/download/extensions [--out build/extension-store] [--catalog build/extensions-catalog.json]");
}

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function validVersion(value) {
  return typeof value === "string" && /^\d+\.\d+\.\d+$/.test(value);
}

function buildPackage(entry) {
  const packagePath = path.resolve(root, entry.package);
  const packageManifest = readJSON(path.join(packagePath, "package.json"));
  if (!validVersion(packageManifest.version)) {
    throw new Error(`${entry.package} must declare a semver version`);
  }
  if (!validVersion(packageManifest.minimumAppVersion)) {
    throw new Error(`${entry.package} must declare minimumAppVersion`);
  }
  if (!Array.isArray(entry.capabilities)) throw new Error(`${entry.package} allowlist entry needs capabilities`);

  const packageRoot = path.join(output, `${packageManifest.name}.ocx`);
  fs.rmSync(packageRoot, { recursive: true, force: true });
  const argumentsForBuild = ["--package", packagePath, "--out", packageRoot];
  const result = spawnSync(process.execPath, [buildExtension, ...argumentsForBuild], {
    cwd: root,
    stdio: "inherit"
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`failed to build ${packageManifest.name}`);

  const manifest = readJSON(path.join(packageRoot, "manifest.json"));
  const build = readJSON(path.join(packageRoot, "build.json"));
  const capabilities = readJSON(path.join(packageRoot, "capabilities.json"));
  if (manifest.name !== packageManifest.name || build.version !== packageManifest.version) {
    throw new Error(`${packageManifest.name} metadata does not match package.json`);
  }
  const declaredCapabilities = capabilities.capabilities.map((item) => item.name).sort();
  if (JSON.stringify(declaredCapabilities) !== JSON.stringify([...entry.capabilities].sort())) {
    throw new Error(`${packageManifest.name} capabilities do not match the Store allowlist`);
  }
  const archiveName = `${packageManifest.name}-${packageManifest.version}.ocx.zip`;
  const archivePath = path.join(output, archiveName);
  fs.rmSync(archivePath, { force: true });
  const archive = spawnSync("ditto", [
    "-c",
    "-k",
    "--sequesterRsrc",
    "--keepParent",
    packageRoot,
    archivePath
  ], { cwd: root, stdio: "inherit" });
  if (archive.error) throw archive.error;
  if (archive.status !== 0) throw new Error(`failed to archive ${packageManifest.name}`);

  return {
    name: manifest.name,
    title: manifest.title,
    description: manifest.description,
    version: packageManifest.version,
    packageURL: `${releaseBase.replace(/\/$/, "")}/${archiveName}`,
    bundleHash: build.bundleHash,
    capabilityHash: build.capabilityHash,
    bundleBytes: build.bundleBytes,
    minimumAppVersion: packageManifest.minimumAppVersion,
    capabilities: declaredCapabilities,
    sourceRepository: packageManifest.sourceRepository || "https://github.com/berkinory/opencast",
    license: packageManifest.license || null,
    verified: true
  };
}

function catalogFromInput() {
  if (!catalogInput) return null;
  if (!fs.existsSync(catalogInput)) return null;
  const catalog = readJSON(catalogInput);
  if (catalog.schemaVersion !== 1 || !Array.isArray(catalog.packages)) {
    throw new Error("existing extension catalog is invalid");
  }
  return catalog;
}

function main() {
  const allowlist = readJSON(allowlistPath);
  if (allowlist.schemaVersion !== 1 || !Array.isArray(allowlist.extensions) || allowlist.extensions.length === 0) {
    throw new Error("approved extension allowlist is invalid");
  }
  fs.mkdirSync(output, { recursive: true });
  const existingCatalog = catalogFromInput();
  const partialBuild = only.size > 0 && existingCatalog !== null;
  const entries = allowlist.extensions.filter((entry) => {
    const name = readJSON(path.join(root, entry.package, "package.json")).name;
    return !partialBuild || only.has(name);
  });
  if (partialBuild && entries.length !== only.size) {
    throw new Error("changed extension list contains an unapproved package");
  }
  const builtPackages = entries.map(buildPackage);
  const builtByName = new Map(builtPackages.map((item) => [item.name, item]));
  const previousByName = new Map((existingCatalog?.packages || []).map((item) => [item.name, item]));
  for (const packageInfo of builtPackages) {
    const previous = previousByName.get(packageInfo.name);
    if (previous && previous.version === packageInfo.version
      && (previous.bundleHash !== packageInfo.bundleHash || previous.capabilityHash !== packageInfo.capabilityHash)) {
      throw new Error(`${packageInfo.name} changed without a version bump`);
    }
  }
  const packages = allowlist.extensions
    .map((entry) => readJSON(path.join(root, entry.package, "package.json")).name)
    .map((name) => builtByName.get(name) || previousByName.get(name))
    .filter(Boolean);
  writeJSON(catalogPath, {
    schemaVersion: 1,
    generatedAt: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
    packages
  });
}

try {
  main();
} catch (error) {
  process.stderr.write(`error: ${error.message}\n`);
  process.exitCode = 1;
}
