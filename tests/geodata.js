const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const repo = path.resolve(__dirname, "..");
const worker = path.join(repo, "ui/xkeen-manager/backend/geodata.js");
const appSource = fs.readFileSync(path.join(repo, "ui/xkeen-manager/app.js"), "utf8");
const indexSource = fs.readFileSync(path.join(repo, "ui/xkeen-manager/index.html"), "utf8");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "antigoblin-geodata-"));

if (!appSource.includes("const SINGBOX_APPLY_TIMEOUT_MS = 90000;")
    || !/fetchWithTimeout\(SINGBOX_URL,[\s\S]*SINGBOX_APPLY_TIMEOUT_MS\)/.test(appSource)) {
  throw new Error("sing-box Geo apply must allow the router-side QuickJS expansion to finish");
}
if (!indexSource.includes("app.js?v=93") || !indexSource.includes("styles.css?v=93")) {
  throw new Error("Geo apply UI cache-buster was not updated");
}
if (!appSource.includes('tag: "xkeen-quic-tproxy"') || !appSource.includes("listen_port: SINGBOX_QUIC_TPROXY_PORT")) {
  throw new Error("sing-box config is missing the dedicated selective QUIC inbound");
}

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
if (!result.quicEnabled || result.fullTunnel) throw new Error("selective GeoSite must use QUIC-only interception");
if (!result.rules.some((rule) => rule.action === "sniff" && rule.inbound?.includes("xkeen-quic-tproxy"))) throw new Error("QUIC sniff action missing");
if (!result.rules.some((rule) => rule.domain_suffix?.includes("youtube.com") && rule.outbound === "proxy")) throw new Error("geosite domain suffix missing");
if (!result.rules.some((rule) => rule.domain?.includes("www.youtube.com"))) throw new Error("geosite full domain missing");
if (!result.rules.some((rule) => rule.domain_keyword?.includes("googlevideo"))) throw new Error("geosite keyword missing");
if (!result.rules.some((rule) => rule.domain_regex?.includes("^yt[0-9]+\\.googleusercontent\\.com$"))) throw new Error("geosite regexp missing");
if (!result.vpnCidrs.includes("8.8.8.0/24") || result.vpnCidrs.some((cidr) => cidr.includes(":"))) throw new Error("IPv4 GeoIP cache is incorrect");
if (result.rules.some((rule) => (rule.ip_cidr || []).length)) throw new Error("GeoIP must stay in kernel ipset, not sing-box rules");
if (!result.rules.some((rule) => rule.domain_suffix?.includes("example.org") && rule.outbound === "direct")) throw new Error("bypass domain rule missing");

state.profiles[0].fallbackOutbound = "vless-reality";
state.profiles[0].groups[0].cidrs = [];
state.profiles[0].groups[1].cidrs = ["geoip:google"];
fs.writeFileSync(statePath, JSON.stringify(state));
run = spawnSync(process.execPath, [worker, "singbox", statePath, geoipPath, geositePath, outputPath], { encoding: "utf8" });
if (run.status !== 0) throw new Error(run.stderr || run.stdout);
result = JSON.parse(fs.readFileSync(outputPath, "utf8"));
if (!result.fullTunnel || result.quicEnabled) throw new Error("full tunnel must not create a second QUIC interception path");
if (!result.bypassCidrs.includes("8.8.8.0/24") || result.vpnCidrs.length) throw new Error("GeoIP bypass cache is incorrect");
if (!result.rules.some((rule) => rule.inbound?.includes("xkeen-udp-tproxy") && rule.outbound === "proxy")) {
  throw new Error("full tunnel final proxy rule missing");
}

state.profiles[0].fallbackOutbound = "direct";
state.profiles[0].groups[0].domains = ["geosite:youtube@cn"];
state.profiles[0].groups[0].cidrs = [];
state.profiles[0].groups[1].cidrs = ["203.0.113.0/24"];
fs.writeFileSync(statePath, JSON.stringify(state));
run = spawnSync(process.execPath, [worker, "singbox", statePath, geoipPath, geositePath, outputPath], { encoding: "utf8" });
if (run.status !== 0) throw new Error(run.stderr || run.stdout);
result = JSON.parse(fs.readFileSync(outputPath, "utf8"));
if (result.stats.expandedEntries !== 1 || !result.rules.some((rule) => rule.domain?.includes("www.youtube.com"))) {
  throw new Error("geosite attribute filter is incorrect");
}

fs.rmSync(tmp, { recursive: true, force: true });
console.log("PASS: geoip/geosite protobuf data expands into ordered sing-box UDP rules");
