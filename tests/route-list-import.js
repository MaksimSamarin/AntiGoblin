const fs = require("fs");
const vm = require("vm");

const source = fs.readFileSync("ui/xkeen-manager/app.js", "utf8").replace(/\r\n/g, "\n");
const names = [
  "splitLinesOrCsv", "uniq", "looksLikeDomain", "looksLikeIpOrCidr",
  "partitionList", "dedupeDomainsList", "parseCidrEntry", "dedupeCidrsList",
  "parseRouteListText", "buildRoutingDocument"
];
const extract = (name) => {
  const start = source.indexOf(`function ${name}(`);
  const next = source.indexOf("\n}\n", start);
  if (start < 0 || next < 0) throw new Error(`${name} not found`);
  return source.slice(start, next + 2);
};
const domainStart = source.indexOf("const DOMAIN_RE =");
const domainEnd = source.indexOf("\nfunction looksLikeDomain", domainStart);
const program = source.slice(domainStart, domainEnd) + "\n" + names.map(extract).join("\n");
const context = {};
vm.createContext(context);
vm.runInContext(program, context);

const fixture = {
  "youtube.com": {
    name: "youtube.com",
    domains: ["youtube.com", "music.youtube.com", "googlevideo.com"],
    ip4: ["8.8.8.8"],
    cidr4: ["142.250.0.0/15", "142.250.1.1/32"],
    cidr6: ["2a00:1450:4000::/37"],
    external: { domains: ["https://example.invalid/list"] }
  }
};
const result = context.parseRouteListText(JSON.stringify(fixture));
if (JSON.stringify(result.domains) !== JSON.stringify(["googlevideo.com", "youtube.com"])) {
  throw new Error(`unexpected domains: ${JSON.stringify(result.domains)}`);
}
if (JSON.stringify(result.cidrs) !== JSON.stringify(["142.250.0.0/15", "8.8.8.8"])) {
  throw new Error(`unexpected cidrs: ${JSON.stringify(result.cidrs)}`);
}
const plain = context.parseRouteListText("example.com\n203.0.113.0/24\ninvalid value");
if (plain.domains[0] !== "example.com" || plain.cidrs[0] !== "203.0.113.0/24") {
  throw new Error("plain-list import failed");
}
const geo = context.parseRouteListText("geosite:youtube\ngeoip:google\nGEOSITE:category-games@cn\ngeosite:geolocation-!cn");
if (JSON.stringify(geo.domains) !== JSON.stringify(["geosite:youtube", "geosite:category-games@cn", "geosite:geolocation-!cn"]) || geo.cidrs[0] !== "geoip:google") {
  throw new Error(`geo rule import failed: ${JSON.stringify(geo)}`);
}
const routing = context.buildRoutingDocument({
  domainStrategy: "IPIfNonMatch",
  fallbackOutbound: "direct",
  groups: [
    { enabled: true, outboundTag: "vless-reality", domains: ["geosite:youtube"], cidrs: ["geoip:google"] },
    { enabled: true, outboundTag: "bypass", domains: ["geosite:private"], cidrs: ["geoip:private"] }
  ]
});
if (!routing.routing.rules.some((rule) => rule.domain?.includes("geosite:youtube") && rule.outboundTag === "vless-reality")) throw new Error("VPN geosite routing missing");
if (!routing.routing.rules.some((rule) => rule.ip?.includes("geoip:private") && rule.outboundTag === "direct")) throw new Error("bypass geoip routing missing");
console.log("PASS: list import and routing support domains, CIDRs, GeoSite and GeoIP rules");
