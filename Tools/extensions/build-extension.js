#!/usr/bin/env node

const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "../..");
const runtimePath = path.join(root, "Extensions/Runtime");

function parseArguments(argv) {
  const options = { fixture: null, out: null, capability: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--fixture") options.fixture = argv[++index];
    else if (argument === "--out") options.out = argv[++index];
    else if (argument === "--capability") options.capability.push(argv[++index]);
    else if (argument === "--help") options.help = true;
    else throw new Error(`unknown argument: ${argument}`);
  }
  return options;
}

function usage() {
  return "usage: node Tools/extensions/build-extension.js --fixture Extensions/Fixtures/list-clipboard --out build/list-clipboard.ocx [--capability clipboard.write]";
}

function writeFile(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content);
}

function copyRuntime(tempRoot) {
  const modules = {
    "@raycast/api/index.js": "opencast-api.js",
    "@raycast/utils/index.js": "raycast-utils.js",
    "react/index.js": "opencast-api.js",
    "react/jsx-runtime.js": "jsx-runtime.js",
    "react/jsx-dev-runtime.js": "jsx-dev-runtime.js"
  };
  for (const [destination, source] of Object.entries(modules)) {
    writeFile(path.join(tempRoot, "node_modules", destination), fs.readFileSync(path.join(runtimePath, source)));
  }
  writeFile(path.join(tempRoot, "node_modules", "@raycast/api/package.json"), JSON.stringify({ name: "@raycast/api", type: "module" }));
  writeFile(path.join(tempRoot, "node_modules", "@raycast/utils/package.json"), JSON.stringify({ name: "@raycast/utils", type: "module" }));
  writeFile(path.join(tempRoot, "node_modules", "react/package.json"), JSON.stringify({ name: "react", type: "module" }));
}

function manifestFor(packageManifest, capabilities) {
  const command = packageManifest.commands?.[0];
  if (!command) throw new Error("fixture package.json must contain one command");
  return {
    schemaVersion: 1,
    name: packageManifest.name,
    title: packageManifest.title,
    description: packageManifest.description,
    author: packageManifest.author,
    license: packageManifest.license,
    preferences: packageManifest.preferences,
    commands: [{
      name: command.name,
      title: command.title,
      subtitle: command.subtitle,
      icon: command.icon,
      entry: "bundle.js",
      mode: command.mode || "view",
      interval: command.interval,
      menuBar: command.menuBar,
      networkDomains: command.networkDomains,
      preferences: command.preferences,
      capabilities
    }]
  };
}

function selectedCapabilities(names) {
  const registry = JSON.parse(fs.readFileSync(path.join(root, "Extensions/Capabilities.json"), "utf8"));
  const available = new Map(registry.capabilities.map((capability) => [capability.name, capability]));
  for (const name of names) if (!available.has(name)) throw new Error(`unknown capability: ${name}`);
  return names.map((name) => available.get(name));
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (!options.fixture || !options.out) throw new Error(`${usage()}\n--fixture and --out are required`);

  const fixture = path.resolve(options.fixture);
  const packageManifest = JSON.parse(fs.readFileSync(path.join(fixture, "package.json"), "utf8"));
  const command = packageManifest.commands?.[0];
  if (!command?.src) throw new Error("fixture command must declare src");
  const source = fs.readFileSync(path.join(fixture, command.src), "utf8");
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "opencast-extension-build-"));
  const output = path.resolve(options.out);
  const capabilities = selectedCapabilities(options.capability);

  try {
    copyRuntime(tempRoot);
    const sourceName = path.basename(command.src);
    writeFile(path.join(tempRoot, sourceName), source);
    writeFile(path.join(tempRoot, "entry.ts"), `import Command from "./${sourceName}";\nimport { mount } from "@raycast/api";\nmount(Command, ${JSON.stringify(command.mode || "view")});\n`);
    fs.mkdirSync(output, { recursive: true });

    const bun = process.env.OPENCAST_BUN || "bun";
    const result = spawnSync(bun, [
      "build",
      "--target=browser",
      "--format=iife",
      "--production",
      "--outfile",
      path.join(output, "bundle.js"),
      path.join(tempRoot, "entry.ts")
    ], { cwd: tempRoot, stdio: "inherit" });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`build failed with exit code ${result.status}`);

    const bundle = fs.readFileSync(path.join(output, "bundle.js"));
    const manifest = manifestFor(packageManifest, capabilities.map((capability) => capability.name));
    writeFile(path.join(output, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
    writeFile(path.join(output, "capabilities.json"), `${JSON.stringify({ schemaVersion: 1, capabilities }, null, 2)}\n`);
    writeFile(path.join(output, "build.json"), `${JSON.stringify({
      schemaVersion: 1,
      builder: "opencast-bun-build-1",
      version: packageManifest.version || null,
      minimumAppVersion: packageManifest.minimumAppVersion || null,
      sourceHash: crypto.createHash("sha256").update(source).digest("hex"),
      bundleHash: crypto.createHash("sha256").update(bundle).digest("hex"),
      bundleBytes: bundle.length,
      command: command.name,
      capabilitiesUsed: capabilities.map((capability) => capability.name)
    }, null, 2)}\n`);
    if (packageManifest.version) {
      writeFile(path.join(output, "verification.json"), `${JSON.stringify({
        version: packageManifest.version,
        sourceRepository: packageManifest.sourceRepository || "https://github.com/berkinory/opencast",
        license: packageManifest.license || null,
        verified: true
      }, null, 2)}\n`);
    }
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

try {
  main();
} catch (error) {
  process.stderr.write(`error: ${error.message}\n`);
  process.exitCode = 1;
}
