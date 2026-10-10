const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const repo = path.resolve(__dirname, "..");
const worker = path.join(repo, "ui/xkeen-manager/backend/geodata.js");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "antigoblin-geodata-"));

function varint(value) {
  const bytes = [];
  do {
    let byte = value & 0x7f;
    value = Math.floor(value / 128);
    if (value) byte |= 0x80;
    bytes.push(byte);
  } while (value);
  return Buffer.from(bytes);
}
function bytesField(field, value) {
  const data = Buffer.isBuffer(value) ? value : Buffer.from(value);
  return Buffer.concat([varint((field << 3) | 2), varint(data.length), data]);
}
function intField(field, value) { return Buffer.concat([varint(field << 3), varint(value)]); }
function message(...fields) { return Buffer.concat(fields); }
function list(entries) { return Buffer.concat(entries.map((entry) => bytesField(1, entry))); }

function attribute(name) { return message(bytesField(1, name), intField(2, 1)); }
function domain(type, value, attrs = []) {
  return message(intField(1, type), bytesField(2, value), ...attrs.map((item) => bytesField(3, attribute(item))));
}
const geosite = list([
  message(
    bytesField(1, "YOUTUBE"),
    bytesField(2, domain(2, "youtube.com")),
    bytesField(2, domain(3, "www.youtube.com", ["cn"])),
    bytesField(2, domain(0, "googlevideo")),
    bytesField(2, domain(1, "^yt[0-9]+\\.googleusercontent\\.com$"))
  )
]);
function cidr(ip, prefix) { return message(bytesField(1, Buffer.from(ip)), intField(2, prefix)); }
const geoip = list([
  message(
    bytesField(1, "GOOGLE"),
    bytesField(2, cidr([8, 8, 8, 0], 24)),
    bytesField(2, cidr([0x20, 0x01, 0x48, 0x60, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 32))
  )
]);
const state = {
  activeProfileId: "profile-1",
  profiles: [{
    id: "profile-1",
    fallbackOutbound: "direct",
    groups: [
      { id: "vpn", enabled: true, outboundTag: "vless-reality", domains: ["geosite:youtube"], cidrs: ["geoip:google"] },
      { id: "bypass", enabled: true, outboundTag: "bypass", domains: ["example.org"], cidrs: ["203.0.113.0/24"] }
    ]
  }]
};

const geoipPath = path.join(tmp, "geoip.dat");
const geositePath = path.join(tmp, "geosite.dat");
const statePath = path.join(tmp, "state.json");
const outputPath = path.join(tmp, "rules.json");
fs.writeFileSync(geoipPath, geoip);
fs.writeFileSync(geositePath, geosite);
fs.writeFileSync(statePath, JSON.stringify(state));

let run = spawnSync(process.execPath, [worker, "singbox", statePath, geoipPath, geositePath, outputPath], { encoding: "utf8" });
if (run.status !== 0) throw new Error(run.stderr || run.stdout);
let result = JSON.parse(fs.readFileSync(outputPath, "utf8"));
if (!result.hasGeo || result.stats.expandedEntries !== 6) throw new Error("geo expansion stats are incorrect");
if (!result.rules.some((rule) => rule.action === "sniff")) throw new Error("UDP sniff action missing");
if (!result.rules.some((rule) => rule.domain_suffix?.includes("youtube.com") && rule.outbound === "proxy")) throw new Error("geosite domain suffix missing");
if (!result.rules.some((rule) => rule.domain?.includes("www.youtube.com"))) throw new Error("geosite full domain missing");
if (!result.rules.some((rule) => rule.domain_keyword?.includes("googlevideo"))) throw new Error("geosite keyword missing");
if (!result.rules.some((rule) => rule.domain_regex?.includes("^yt[0-9]+\\.googleusercontent\\.com$"))) throw new Error("geosite regexp missing");
if (!result.rules.some((rule) => rule.ip_cidr?.includes("8.8.8.0/24") && rule.ip_cidr?.includes("2001:4860:0:0:0:0:0:0/32"))) throw new Error("geoip CIDRs missing");
if (!result.rules.some((rule) => rule.domain_suffix?.includes("example.org") && rule.outbound === "direct")) throw new Error("bypass domain rule missing");

state.profiles[0].groups[0].domains = ["geosite:youtube@cn"];
state.profiles[0].groups[0].cidrs = [];
fs.writeFileSync(statePath, JSON.stringify(state));
run = spawnSync(process.execPath, [worker, "singbox", statePath, geoipPath, geositePath, outputPath], { encoding: "utf8" });
if (run.status !== 0) throw new Error(run.stderr || run.stdout);
result = JSON.parse(fs.readFileSync(outputPath, "utf8"));
if (result.stats.expandedEntries !== 1 || !result.rules.some((rule) => rule.domain?.includes("www.youtube.com"))) {
  throw new Error("geosite attribute filter is incorrect");
}

fs.rmSync(tmp, { recursive: true, force: true });
console.log("PASS: geoip/geosite protobuf data expands into ordered sing-box UDP rules");
