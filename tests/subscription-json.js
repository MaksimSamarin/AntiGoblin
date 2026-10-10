const fs = require("fs");
const vm = require("vm");

const source = fs.readFileSync("ui/xkeen-manager/app.js", "utf8").replace(/\r\n/g, "\n");
const names = [
  "createDefaultProxyConfig", "normalizeProxyConfig", "parseVlessUri",
  "parseVmessUri", "parseHysteria2Uri", "parseSubscriptionUri",
  "parseSingboxSubscriptionOutbound", "parseXraySubscriptionOutbound",
  "parseSubscriptionText"
];
const extract = (name) => {
  const start = source.indexOf(`function ${name}(`);
  const end = source.indexOf("\n}\n", start);
  if (start < 0 || end < 0) throw new Error(`${name} not found`);
  return source.slice(start, end + 2);
};
const context = { atob: (value) => Buffer.from(value, "base64").toString("binary") };
vm.createContext(context);
vm.runInContext(names.map(extract).join("\n"), context);

const document = {
  outbounds: [
    {
      type: "hysteria2", tag: "HY2 JSON", server: "hy2.example", server_port: 443,
      password: "test-password", tls: { enabled: true, server_name: "hy2.example" }
    },
    {
      type: "vless", tag: "VLESS JSON", server: "vless.example", server_port: 8443,
      uuid: "00000000-0000-0000-0000-000000000012",
      tls: { enabled: true, reality: { enabled: true, public_key: "public", short_id: ["abcd"] } },
      transport: { type: "grpc", service_name: "lab" }
    }
  ],
  nested: { uri: "vless://00000000-0000-0000-0000-000000000013@uri.example:443?security=none#URI" }
};
const result = context.parseSubscriptionText(JSON.stringify(document));
if (result.configs.length !== 3) throw new Error(`expected 3 configs, got ${result.configs.length}`);
if (!result.configs.some((item) => item.protocol === "hysteria2" && item.address === "hy2.example")) {
  throw new Error("sing-box hysteria2 not parsed");
}
if (!result.configs.some((item) => item.protocol === "vless" && item.network === "grpc" && item.publicKey === "public")) {
  throw new Error("sing-box vless/reality not parsed");
}
if (!result.configs.some((item) => item.address === "uri.example")) {
  throw new Error("nested URI not parsed");
}
console.log("PASS: JSON subscriptions parse sing-box outbounds and nested URIs");
