const fs = require("fs");
const vm = require("vm");

// The UI renders the sing-box outbound that talks to Xray's loopback SS relay.
// Both sides must agree on an AEAD cipher: Xray 25.x+ rejects "none".
const source = fs.readFileSync("ui/xkeen-manager/app.js", "utf8").replace(/\r\n/g, "\n");
const start = source.indexOf("function buildSingboxDocument(");
const end = source.indexOf("\n}\n", start);
if (start < 0 || end < 0) throw new Error("buildSingboxDocument not found");

const context = {
  SINGBOX_XRAY_RELAY_PORT: 61225,
  SINGBOX_QUIC_TPROXY_PORT: 61222,
  getActiveProxyConfig: (profile) => profile.config
};
vm.createContext(context);
vm.runInContext(source.slice(start, end + 2), context);

const relayDoc = context.buildSingboxDocument({ config: { protocol: "vless", address: "vpn.example", port: 443 } });
const relay = relayDoc.outbounds.find((item) => item.type === "shadowsocks");
if (!relay) throw new Error("xray-native profile lost its shadowsocks relay outbound");
if (relay.server !== "127.0.0.1" || relay.server_port !== 62640) {
  throw new Error("relay outbound must target 127.0.0.1:62640");
}
if (relay.method === "none") throw new Error("cipher none is rejected by Xray 25.x+");

const relaySample = JSON.parse(fs.readFileSync("configs/xkeen/02_relay.sample.json", "utf8"));
const inbound = relaySample.inbounds.find((item) => item.tag === "proxy-relay-ss");
if (!inbound) throw new Error("02_relay.sample.json lost the proxy-relay-ss inbound");
if (inbound.settings.method !== relay.method || inbound.settings.password !== relay.password || inbound.port !== relay.server_port) {
  throw new Error(`02_relay.sample.json (${inbound.settings.method}) and the UI generator (${relay.method}) disagree on the relay`);
}

const singboxSample = JSON.parse(fs.readFileSync("configs/xkeen/sing-box-xkeen.sample.json", "utf8"));
const sampleRelay = singboxSample.outbounds.find((item) => item.type === "shadowsocks");
if (!sampleRelay || sampleRelay.method !== relay.method || sampleRelay.password !== relay.password) {
  throw new Error("sing-box-xkeen.sample.json disagrees with the UI generator on the relay cipher");
}

const hy2Doc = context.buildSingboxDocument({
  config: { protocol: "hysteria2", address: "hy2.example", port: 443, password: "secret" }
});
if (hy2Doc.outbounds.some((item) => item.type === "shadowsocks")) {
  throw new Error("hysteria2 profile must not carry the shadowsocks relay");
}
if (!hy2Doc.inbounds.some((item) => item.tag === "xray-relay")) {
  throw new Error("hysteria2 profile lost the xray-relay mixed inbound");
}
console.log(`PASS: sing-box relay outbound uses ${relay.method} like 02_relay.json; hysteria2 path unchanged`);
