#!/usr/bin/env node

const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "../..");
const runtimePath = path.join(root, "Extensions/Runtime");

function parseArguments(argv) {
  const options = { packagePath: null, out: null };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--package") options.packagePath = argv[++index];
    else if (argument === "--out") options.out = argv[++index];
    else if (argument === "--help") options.help = true;
    else throw new Error(`unknown argument: ${argument}`);
  }
  return options;
}

function usage() {
  return "usage: node Tools/extensions/build-extension.js --package Extensions/Packages/kill-process --out build/kill-process.ocx";
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

function manifestFor(packageManifest, buildCommands, capabilitiesByCommand) {
  const packageCommands = packageManifest.commands || [];
  if (!packageCommands.length) throw new Error("package.json must contain one command");
  return {
    schemaVersion: 1,
    name: packageManifest.name,
    title: packageManifest.title,
    description: packageManifest.description,
    author: packageManifest.author,
    license: packageManifest.license,
    preferences: packageManifest.preferences,
    commands: buildCommands.map((buildCommand) => {
      const command = packageCommands.find((entry) => entry.name === buildCommand.name) || packageCommands[0];
      const scopes = buildCommand.capabilities || {};
      return {
        name: command.name,
        title: command.title,
        subtitle: command.subtitle,
        icon: command.icon,
        entry: "bundle.js",
        mode: buildCommand.mode || command.mode || "view",
        interval: buildCommand.interval || command.interval,
        menuBar: buildCommand.mode === "menu-bar" || command.menuBar,
        networkDomains: scopes.networkDomains || command.networkDomains || [],
        preferences: command.preferences,
        capabilities: capabilitiesByCommand.get(buildCommand.name) || [],
        executables: scopes.executables || command.executables || [],
        filesystemRoots: scopes.filesystemRoots || command.filesystemRoots || [],
        shell: scopes.shell === true || command.shell === true
      };
    })
  };
}

function loadBuildManifest(packageRoot) {
  const manifestPath = path.join(packageRoot, "opencast.json");
  if (!fs.existsSync(manifestPath)) throw new Error("opencast.json is required");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (manifest.schemaVersion !== 1 || !Array.isArray(manifest.commands) || manifest.commands.length === 0) {
    throw new Error("opencast.json must declare schemaVersion 1 and at least one command");
  }
  return manifest;
}

function selectedCapabilities(names) {
  const registry = JSON.parse(fs.readFileSync(path.join(root, "Extensions/Capabilities.json"), "utf8"));
  const available = new Map(registry.capabilities.map((capability) => [capability.name, capability]));
  for (const name of names) if (!available.has(name)) throw new Error(`unknown capability: ${name}`);
  return names.map((name) => available.get(name));
}

function usedCapabilityNames(source) {
  const matches = source.matchAll(/requestCapability\(\s*["']([^"']+)["']/g);
  const names = new Set([...matches].map((match) => match[1]));
  const patterns = {
    "network.request": /\b(?:fetch|useFetch)\s*\(/,
    "process.execute": /\b(?:exec|useExec|Process\.start)\s*\(/,
    "clipboard.read": /Clipboard\.readText\s*\(/,
    "selectedText.read": /\bgetSelectedText\s*\(/,
    "finder.selection.read": /\bgetSelectedFinderItems\s*\(/,
    "open.url": /\bopen\s*\(|\bAction\.(?:OpenInBrowser|Open)\b/,
    "open.application": /\bopenApplication\s*\(/,
    "finder.reveal": /\bAction\.ShowInFinder\b|\brevealInFinder\s*\(/,
    "clipboard.write": /Clipboard\.(?:copy|write)\s*\(|\bAction\.CopyToClipboard\b/,
    "clipboard.paste": /Clipboard\.paste\s*\(|\bAction\.Paste\b/,
    "filesystem.pick": /FilePicker\.(?:pickFile|pickDirectory)\s*\(/,
    "filesystem.read": /\bFilesystem\.read\s*\(/,
    "filesystem.write": /\bFilesystem\.write\s*\(/,
    "filesystem.list": /\bFilesystem\.list\s*\(/,
    "filesystem.quickLook": /\bFilesystem\.quickLook\s*\(/,
    "application.list": /\bgetApplications\s*\(/,
    "application.frontmost": /\bgetFrontmostApplication\s*\(/,
    "preferences.read": /\bgetPreferenceValues\s*\(/,
    "applescript.execute": /\brunAppleScript\s*\(/,
    "browser.read": /Browser\.(?:tabs|history|bookmarks)\s*\(/,
    "browser.mutate": /Browser\.(?:closeTab|createBookmark)\s*\(/,
    "storage.read": /(?:LocalStorage|Cache)\.get\w*\s*\(/,
    "storage.write": /(?:LocalStorage|Cache)\.set\w*\s*\(/,
    "storage.delete": /(?:LocalStorage|Cache)\.remove\w*\s*\(/,
    "storage.sqlite": /\buseSQL\s*\(/,
    "process.inspect": /Process\.list\s*\(/,
    "process.terminate": /Process\.terminate\s*\(/,
    "process.restart": /Process\.restart\s*\(/,
    "process.cancel": /Process\.cancel\s*\(/,
    "ports.inspect": /Ports\.list\s*\(/,
    "system.metrics.read": /System\.metrics\s*\(/,
  };
  for (const [name, pattern] of Object.entries(patterns)) if (pattern.test(source)) names.add(name);
  return names;
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (!options.packagePath || !options.out) throw new Error(`${usage()}\n--package and --out are required`);

  const packageRoot = path.resolve(options.packagePath);
  const packageManifest = JSON.parse(fs.readFileSync(path.join(packageRoot, "package.json"), "utf8"));
  const buildManifest = loadBuildManifest(packageRoot);
  const commands = buildManifest.commands.map((buildCommand) => {
    const command = packageManifest.commands?.find((entry) => entry.name === buildCommand.name) || packageManifest.commands?.[0];
    const sourcePath = buildCommand.src || command?.src;
    if (!command?.src || !sourcePath) throw new Error(`package command ${buildCommand.name} must declare src`);
    const resolvedSource = path.resolve(packageRoot, sourcePath);
    const relativeSource = path.relative(packageRoot, resolvedSource);
    if (!relativeSource || relativeSource.startsWith("..") || path.isAbsolute(relativeSource)) {
      throw new Error(`package command ${buildCommand.name} has an unsafe src path`);
    }
    return {
      buildCommand,
      command,
      sourcePath,
      source: fs.readFileSync(resolvedSource, "utf8")
    };
  });
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "opencast-extension-build-"));
  const output = path.resolve(options.out);
  const capabilitiesByCommand = new Map();
  const allDeclaredNames = new Set();
  const allUsedNames = new Set();
  for (const { buildCommand, source } of commands) {
    const declaredNames = buildCommand.capabilities?.names;
    if (!Array.isArray(declaredNames)) throw new Error("opencast.json command capabilities.names must be an array");
    capabilitiesByCommand.set(buildCommand.name, selectedCapabilities(declaredNames).map((capability) => capability.name));
    declaredNames.forEach((name) => allDeclaredNames.add(name));
    const usedNames = usedCapabilityNames(source);
    for (const name of usedNames) {
      allUsedNames.add(name);
      if (!declaredNames.includes(name)) throw new Error(`capability ${name} is used but not declared in opencast.json`);
    }
    if (declaredNames.includes("network.request") && !(buildCommand.capabilities?.networkDomains || []).length) {
      throw new Error("network.request requires declared networkDomains");
    }
    if (declaredNames.includes("process.execute") && !(buildCommand.capabilities?.executables || []).length) {
      throw new Error("process.execute requires declared executables");
    }
    const filesystemNames = ["filesystem.read", "filesystem.write", "filesystem.list", "filesystem.quickLook"];
    if (declaredNames.some((name) => filesystemNames.includes(name))
      && !(buildCommand.capabilities?.filesystemRoots || []).length) {
      throw new Error("filesystem capabilities require declared filesystemRoots");
    }
  }
  const capabilities = selectedCapabilities([...allDeclaredNames]);
  const sourceText = `${commands.map(({ source }) => source).join("\n")}\n${fs.readFileSync(path.join(runtimePath, "opencast-api.js"), "utf8")}`;
  if (commands.some(({ source }) => /from\s+["'](?:@raycast\/api|@raycast\/utils)["']/.test(source) && /\bAI\b/.test(source))) {
    throw new Error("AI APIs are not supported. Remove AI commands before building for Opencast.");
  }
  if (/\.(?:node|dylib|so)\b|child_process|process\.mainModule|eval\s*\(|new Function\s*\(|import\s*\(\s*["']https?:/.test(sourceText)) {
    throw new Error("native addons, dynamic code, and direct Node process APIs are not supported");
  }

  try {
    copyRuntime(tempRoot);
    const imports = commands.map(({ sourcePath, source }, index) => {
      const relativeSource = sourcePath.replaceAll("\\", "/");
      writeFile(path.join(tempRoot, relativeSource), source);
      return `import Command${index} from "./${relativeSource}";`;
    });
    const commandMap = commands
      .map(({ buildCommand }, index) => `${JSON.stringify(buildCommand.name)}: Command${index}`)
      .join(",");
    const firstCommand = commands[0].buildCommand;
    writeFile(
      path.join(tempRoot, "entry.ts"),
      `${imports.join("\n")}\nimport { mount } from "@raycast/api";\nconst commands = {${commandMap}};\nconst commandName = globalThis.__opencastCommandName || ${JSON.stringify(firstCommand.name)};\nmount(commands[commandName] || commands[${JSON.stringify(firstCommand.name)}], globalThis.__opencastCommandMode || ${JSON.stringify(firstCommand.mode || "view")});\n`
    );
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
    const manifest = manifestFor(packageManifest, commands.map(({ buildCommand }) => buildCommand), capabilitiesByCommand);
    const manifestData = Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`);
    const capabilitiesData = Buffer.from(`${JSON.stringify({ schemaVersion: 1, capabilities }, null, 2)}\n`);
    const capabilityHash = crypto.createHash("sha256")
      .update(Buffer.concat([manifestData, capabilitiesData]))
      .digest("hex");
    writeFile(path.join(output, "manifest.json"), manifestData);
    writeFile(path.join(output, "capabilities.json"), capabilitiesData);
    writeFile(path.join(output, "build.json"), `${JSON.stringify({
      schemaVersion: 1,
      builder: "opencast-bun-build-1",
      version: packageManifest.version || null,
      minimumAppVersion: packageManifest.minimumAppVersion || null,
      sourceHash: crypto.createHash("sha256").update(commands.map(({ source }) => source).join("\n")).digest("hex"),
      bundleHash: crypto.createHash("sha256").update(bundle).digest("hex"),
      capabilityHash,
      bundleBytes: bundle.length,
      command: commands.length === 1 ? commands[0].command.name : commands.map(({ command }) => command.name),
      capabilitiesUsed: [...allUsedNames]
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
