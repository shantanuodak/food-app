#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const repoRoot = path.resolve(__dirname, "../..");
const manifestPath = process.argv.includes("--manifest")
  ? path.resolve(process.argv[process.argv.indexOf("--manifest") + 1])
  : path.join(__dirname, "states.json");
const includePlanned = process.argv.includes("--include-planned");
const skipBuild = process.argv.includes("--skip-build");
const onlyArgIndex = process.argv.indexOf("--only");
const onlyPattern = onlyArgIndex >= 0 ? process.argv[onlyArgIndex + 1] : null;

const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
const outputRoot = path.resolve(repoRoot, manifest.outputDirectory, timestamp);
const derivedDataPath = path.resolve(repoRoot, "artifacts/visual-qa/DerivedData");
const appPath = path.join(
  derivedDataPath,
  "Build/Products/Debug-iphonesimulator/Food App.app"
);

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    stdio: options.capture ? "pipe" : "inherit"
  });
  if (result.status !== 0) {
    const output = [result.stdout, result.stderr].filter(Boolean).join("\n");
    if (options.allowFailure) {
      return output;
    }
    throw new Error(`${command} ${args.join(" ")} failed\n${output}`);
  }
  return result.stdout || "";
}

function safeFilename(state) {
  const idSlug = state.id.replace(/[^a-zA-Z0-9]+/g, "_").replace(/^_|_$/g, "");
  const nameSlug = state.name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_|_$/g, "");
  return `${idSlug}__${nameSlug}.png`;
}

function latestAvailableRuntimeIdentifier() {
  const runtimes = JSON.parse(run("xcrun", ["simctl", "list", "runtimes", "--json"], { capture: true })).runtimes;
  const iosRuntimes = runtimes
    .filter((runtime) => runtime.isAvailable && runtime.platform === "iOS")
    .sort((a, b) => a.version.localeCompare(b.version, undefined, { numeric: true }));
  if (!iosRuntimes.length) {
    throw new Error("No available iOS simulator runtimes found.");
  }
  return iosRuntimes[iosRuntimes.length - 1].identifier;
}

function deviceTypeIdentifier(deviceName) {
  const deviceTypes = JSON.parse(run("xcrun", ["simctl", "list", "devicetypes", "--json"], { capture: true })).devicetypes;
  const exact = deviceTypes.find((type) => type.name === deviceName);
  if (exact) return exact.identifier;

  const fallback = deviceTypes.find((type) => type.name.includes("iPhone") && type.name.includes("Pro"));
  if (!fallback) {
    throw new Error(`No simulator device type found for ${deviceName}.`);
  }
  console.warn(`Device type "${deviceName}" not found. Falling back to "${fallback.name}".`);
  return fallback.identifier;
}

function findOrCreateDevice(deviceName) {
  const devices = JSON.parse(run("xcrun", ["simctl", "list", "devices", "--json"], { capture: true })).devices;
  for (const runtimeDevices of Object.values(devices)) {
    const match = runtimeDevices.find((device) => device.name === deviceName && device.isAvailable);
    if (match) return match.udid;
  }

  const runtime = latestAvailableRuntimeIdentifier();
  const deviceType = deviceTypeIdentifier(deviceName);
  return run("xcrun", ["simctl", "create", deviceName, deviceType, runtime], { capture: true }).trim();
}

function bootDevice(udid) {
  const devices = JSON.parse(run("xcrun", ["simctl", "list", "devices", "--json"], { capture: true })).devices;
  const allDevices = Object.values(devices).flat();
  const device = allDevices.find((candidate) => candidate.udid === udid);
  if (device?.state !== "Booted") {
    run("xcrun", ["simctl", "boot", udid]);
  }
  run("xcrun", ["simctl", "bootstatus", udid, "-b"]);
  run("xcrun", ["simctl", "ui", udid, "appearance", "light"]);
}

function buildApp(deviceName) {
  run("xcodebuild", [
    "-project", "Food App.xcodeproj",
    "-scheme", "Food App",
    "-configuration", "Debug",
    "-destination", `platform=iOS Simulator,name=${deviceName}`,
    "-derivedDataPath", derivedDataPath,
    "build"
  ]);
}

function captureState(udid, state, index, total) {
  const filename = safeFilename(state);
  const outputPath = path.join(outputRoot, filename);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });

  console.log(`[${index + 1}/${total}] ${state.id} -> ${filename}`);
  run("xcrun", ["simctl", "terminate", udid, manifest.bundleIdentifier], {
    capture: true,
    allowFailure: true
  });
  run("xcrun", ["simctl", "launch", udid, manifest.bundleIdentifier, "--visual-qa-state", state.id]);
  run("sleep", ["2"]);
  run("xcrun", ["simctl", "io", udid, "screenshot", outputPath]);

  const stat = fs.statSync(outputPath);
  return {
    id: state.id,
    name: state.name,
    implemented: state.implemented,
    filename,
    bytes: stat.size,
    status: stat.size > 10_000 ? "captured" : "suspicious-small-file"
  };
}

function main() {
  const allStates = manifest.states
    .filter((state) => includePlanned || state.implemented)
    .filter((state) => !onlyPattern || state.id.includes(onlyPattern) || state.name.includes(onlyPattern));

  if (!allStates.length) {
    throw new Error("No states selected for capture.");
  }

  fs.mkdirSync(outputRoot, { recursive: true });

  const deviceName = manifest.device || "iPhone 17 Pro";
  const udid = findOrCreateDevice(deviceName);
  bootDevice(udid);
  if (!skipBuild) {
    buildApp(deviceName);
  }
  run("xcrun", ["simctl", "install", udid, appPath]);

  const results = [];
  for (let index = 0; index < allStates.length; index += 1) {
    results.push(captureState(udid, allStates[index], index, allStates.length));
  }

  const report = {
    capturedAt: new Date().toISOString(),
    deviceName,
    udid,
    appearance: manifest.appearance,
    outputRoot,
    totalSelected: allStates.length,
    totalCaptured: results.filter((result) => result.status === "captured").length,
    totalSuspicious: results.filter((result) => result.status !== "captured").length,
    results
  };

  fs.writeFileSync(path.join(outputRoot, "report.json"), JSON.stringify(report, null, 2));
  console.log(`\nSaved ${report.totalCaptured}/${report.totalSelected} screenshots to ${outputRoot}`);
  if (report.totalSuspicious > 0) {
    console.warn(`${report.totalSuspicious} captures look suspiciously small; inspect report.json.`);
  }
}

main();
