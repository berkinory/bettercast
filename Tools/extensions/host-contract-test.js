#!/usr/bin/env node

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { spawn } = require("node:child_process");

const root = path.resolve(__dirname, "../..");
const hostPath = process.env.OPENCAST_EXTENSION_HOST || path.join(root, "build/ExtensionHostDerived/Build/Products/Debug/OpencastExtensionHost");

function session(bundlePath) {
  const child = spawn(hostPath, ["--stdio"], { stdio: ["pipe", "pipe", "pipe"] });
  let buffer = Buffer.alloc(0);
  const messages = [];
  const waiters = [];
  child.stdout.on("data", (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    while (buffer.length >= 4) {
      const length = buffer.readUInt32BE(0);
      if (buffer.length < length + 4) break;
      const message = JSON.parse(buffer.subarray(4, length + 4).toString("utf8"));
      buffer = buffer.subarray(length + 4);
      const waiter = waiters.shift();
      if (waiter) waiter(message); else messages.push(message);
    }
  });
  child.stderr.on("data", (chunk) => process.stderr.write(chunk));
  function send(message) {
    const payload = Buffer.from(JSON.stringify(message));
    const frame = Buffer.alloc(4 + payload.length);
    frame.writeUInt32BE(payload.length, 0);
    payload.copy(frame, 4);
    child.stdin.write(frame);
  }
  function next() {
    if (messages.length) return Promise.resolve(messages.shift());
    return new Promise((resolve) => waiters.push(resolve));
  }
  async function close() {
    send({ type: "dispose", reason: "closed" });
    child.stdin.end();
    await new Promise((resolve) => child.once("close", resolve));
  }
  return { child, send, next, close, bundlePath };
}

async function checkList() {
  const bundlePath = path.join(root, "build/extensions/list-clipboard.ocx");
  const host = session(bundlePath);
  host.send({ type: "launch", requestID: "list-launch", bundlePath, mode: "view" });
  const render = await host.next();
  assert.equal(render.type, "render");
  assert.equal(render.root, "list");
  assert.equal(render.items.length, 3);
  assert.equal(render.items[0].id, "alpha");
  assert.equal(render.items[0].actions.length, 2);

  host.send({
    type: "event",
    requestID: "list-action",
    event: "actionInvoked",
    actionID: render.items[0].actions[0].id,
    itemID: "alpha"
  });
  const capability = await host.next();
  assert.equal(capability.type, "capabilityRequest");
  assert.equal(capability.capability, "clipboard.write");
  assert.equal(capability.payload.text, "alpha");
  host.send({ type: "capabilityResponse", requestID: capability.requestID, ok: true, value: true });
  assert.equal((await host.next()).type, "render");
  await host.close();
}

async function checkNoView() {
  const bundlePath = path.join(root, "build/extensions/no-view-process.ocx");
  const host = session(bundlePath);
  host.send({ type: "launch", requestID: "no-view-launch", bundlePath, mode: "no-view" });
  for (const [capability, value] of [
    ["selectedText.read", "{\"hello\":true}"],
    ["process.execute", "{\n  \"hello\": true\n}"],
    ["clipboard.write", true]
  ]) {
    const request = await host.next();
    assert.equal(request.type, "capabilityRequest");
    assert.equal(request.capability, capability);
    host.send({ type: "capabilityResponse", requestID: request.requestID, ok: true, value });
  }
  assert.equal((await host.next()).type, "log");
  assert.equal((await host.next()).reason, "completed");
  host.child.stdin.end();
  await new Promise((resolve) => host.child.once("close", resolve));
}

async function checkDetail() {
  const bundlePath = path.join(root, "build/extensions/detail-open.ocx");
  const host = session(bundlePath);
  host.send({ type: "launch", requestID: "detail-launch", bundlePath, mode: "view" });
  const render = await host.next();
  assert.equal(render.root, "detail");
  assert.equal(render.detail.metadata.length, 0);
  assert.equal(render.detail.sections.length, 1);
  assert.equal(render.detail.sections[0].metadata.length, 2);
  assert.equal(render.detail.links[0].url, "https://opencast.app");
  await host.close();
}

async function checkForm() {
  const bundlePath = path.join(root, "build/extensions/form-preferences.ocx");
  const host = session(bundlePath);
  host.send({ type: "launch", requestID: "form-launch", bundlePath, mode: "view", preferences: { defaultLabel: "Default" } });
  const render = await host.next();
  assert.equal(render.root, "form");
  assert.deepEqual(render.fields.map((field) => field.kind), ["text", "checkbox", "dropdown", "date"]);
  assert.equal(render.fields[2].options[0].value, "fast");
  await host.close();
}

async function checkGridAndMenuBar() {
  const gridPath = path.join(root, "build/extensions/grid-status.ocx");
  const grid = session(gridPath);
  grid.send({ type: "launch", requestID: "grid-launch", bundlePath: gridPath, mode: "view" });
  const gridRender = await grid.next();
  assert.equal(gridRender.root, "grid");
  assert.equal(gridRender.items.length, 2);
  await grid.close();

  const menuBarPath = path.join(root, "build/extensions/menubar-snapshot.ocx");
  const menuBar = session(menuBarPath);
  menuBar.send({ type: "launch", requestID: "menu-launch", bundlePath: menuBarPath, mode: "view" });
  const menuRender = await menuBar.next();
  assert.equal(menuRender.root, "menuBarSnapshot");
  assert.equal(menuRender.items[0].title, "Brewed");
  await menuBar.close();
}

async function checkStoreCapabilities() {
  const killPath = path.join(root, "build/extensions/kill-process.ocx");
  const kill = session(killPath);
  kill.send({ type: "launch", requestID: "kill-launch", bundlePath: killPath, mode: "view" });
  const killRequest = await kill.next();
  assert.equal(killRequest.capability, "process.inspect");
  kill.send({
    type: "capabilityResponse",
    requestID: killRequest.requestID,
    ok: true,
    value: [{ pid: 42, parentPID: 1, user: "tester", cpuPercent: 12.5, memoryPercent: 3.25, name: "Demo", path: "/Applications/Demo.app/Contents/MacOS/Demo" }]
  });
  const killRender = await kill.next();
  assert.equal(killRender.type, "render");
  assert.deepEqual(killRender.listDropdown.options.map((option) => option.value), ["cpu", "memory", "name"]);
  assert.equal(killRender.items[0].icon, "process:42|/Applications/Demo.app/Contents/MacOS/Demo");
  assert.deepEqual(killRender.items[0].accessories, [
    { icon: "gauge.with.dots.needle.33percent", text: "12.5%" },
    { icon: "memorychip", text: "3.3%" }
  ]);
  assert.deepEqual(killRender.items[0].actions.map((action) => action.title), [
    "Kill", "Force Kill", "Restart", "Force Restart"
  ]);
  kill.send({
    type: "event",
    requestID: "kill-sort-memory",
    event: "dropdownChanged",
    dropdownID: killRender.listDropdown.id,
    value: "memory"
  });
  const killSortRequest = await kill.next();
  assert.equal(killSortRequest.capability, "process.inspect");
  assert.equal(killSortRequest.payload.sortBy, "memory");
  await kill.close();

  const portsPath = path.join(root, "build/extensions/port-manager.ocx");
  const ports = session(portsPath);
  ports.send({ type: "launch", requestID: "ports-launch", bundlePath: portsPath, mode: "view" });
  const portsRequest = await ports.next();
  assert.equal(portsRequest.capability, "ports.inspect");
  ports.send({ type: "capabilityResponse", requestID: portsRequest.requestID, ok: true, value: [] });
  assert.equal((await ports.next()).type, "render");
  await ports.close();

  const monitorPath = path.join(root, "build/extensions/system-monitor.ocx");
  const monitor = session(monitorPath);
  monitor.send({ type: "launch", requestID: "monitor-launch", bundlePath: monitorPath, mode: "view" });
  const monitorRequest = await monitor.next();
  assert.equal(monitorRequest.capability, "system.metrics.read");
  monitor.send({
    type: "capabilityResponse",
    requestID: monitorRequest.requestID,
    ok: true,
    value: {
      cpuPercent: 12.5, memoryUsedBytes: 1024, memoryTotalBytes: 2048,
      diskUsedBytes: 4096, diskTotalBytes: 8192, batteryPercent: null,
      isCharging: null, networkDownloadBytesPerSecond: 0,
      networkUploadBytesPerSecond: 0, temperatureCelsius: null,
      sampledAt: "2026-01-01T00:00:00.000Z"
    }
  });
  const monitorRender = await monitor.next();
  assert.equal(monitorRender.root, "detail");
  await monitor.close();
}

async function run() {
  if (!fs.existsSync(hostPath)) throw new Error(`host binary not found: ${hostPath}`);
  await checkList();
  await checkNoView();
  await checkDetail();
  await checkForm();
  await checkGridAndMenuBar();
  await checkStoreCapabilities();
  process.stdout.write("extension host contract checks passed\n");
}

run().catch((error) => {
  process.stderr.write(`error: ${error.stack || error.message}\n`);
  process.exitCode = 1;
});
