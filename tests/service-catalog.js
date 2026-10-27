const assert = require("assert");
const fs = require("fs");
const vm = require("vm");
const C = require("../ui/xkeen-manager/service-catalog.js");
assert.equal(C.catalog.length, 32);
assert.equal(C.catalog.filter((s) => s.popular).length, 12);
assert.equal(new Set(C.catalog.map((s) => s.id)).size, 32);
assert.deepEqual(C.get("copilot").domains, ["geosite:github-copilot"]);
const ipv4 = (value) => value.split(".").reduce((acc, octet) => (acc * 256 + Number(octet)) >>> 0, 0);
const containsIp = (cidr, address) => {
  const [network, prefix] = cidr.split("/");
  const mask = (0xffffffff << (32 - Number(prefix))) >>> 0;
  return (ipv4(network) & mask) === (ipv4(address) & mask);
};
for (const address of ["104.29.0.0", "104.29.255.255", "104.29.149.57", "104.29.149.250", "104.29.136.15", "104.29.155.250", "104.29.155.205", "104.29.149.28", "104.29.136.201", "104.29.149.21", "104.29.149.25", "104.29.155.203", "104.29.149.31", "66.22.192.0", "66.22.255.255", "66.22.200.1"]) {
  assert(C.get("discord").cidrs.some((cidr) => containsIp(cidr, address)), "media coverage must include newly assigned addresses, not just recorded hosts");
}
for (const address of ["104.28.255.255", "104.30.0.0", "66.22.191.255", "66.23.0.0", "34.158.72.125", "172.64.1.1", "162.158.1.1"]) {
  assert(!C.get("discord").cidrs.some((cidr) => containsIp(cidr, address)), "Discord must not capture the legacy broad cloud networks");
}
const legacyDiscord = C.normalizeGroup({ id: "legacy", enabled: true, serviceIds: ["discord"],
  serviceManualDomains: [], serviceManualCidrs: ["104.29.149.25/32"],
  serviceVoiceCidrs: ["104.29.155.203/32"],
  domains: ["geosite:discord"], cidrs: ["66.22.192.0/18", "104.29.149.25/32", "104.29.155.203/32"] });
assert(legacyDiscord.cidrs.some((cidr) => containsIp(cidr, "104.29.149.57")), "saved catalog groups adopt range coverage on normalization");
assert.deepEqual(C.normalizeGroup(JSON.parse(JSON.stringify(legacyDiscord))), legacyDiscord, "migrated Discord groups survive export/reload");
const legacyDiscordNoMedia = C.selectServices(legacyDiscord, ["discord"], { voiceEnabled: false });
assert(legacyDiscordNoMedia.cidrs.includes("104.29.149.25/32"), "manual host rules survive disabling range coverage");
assert(!legacyDiscordNoMedia.cidrs.includes("104.29.155.203/32"), "automatically imported host rules follow the media toggle");
const voice = ["203.0.113.7/32", "203.0.113.8/32"];
const old = { id: "group", name: "Existing", enabled: true, outboundTag: "bypass", domains: ["example.org", "geosite:discord"], cidrs: ["198.51.100.0/24"] };
assert.strictEqual(C.normalizeGroup(old), old, "plain manual groups are not silently migrated");
const first = C.selectServices(old, ["discord", "telegram"], { voiceCidrs: voice });
assert.equal(first.outboundTag, "bypass");
assert(first.domains.includes("example.org"));
assert(first.cidrs.includes("geoip:telegram"));
assert(voice.every((v) => first.cidrs.includes(v)));
assert(C.get("discord").cidrs.every((v) => first.cidrs.includes(v)), "all known media routes belong to the Discord preset");
const duplicateVoice = C.selectServices(first, ["discord", "telegram"], { voiceCidrs: [C.get("discord").cidrs[1]] });
assert.equal(new Set(duplicateVoice.cidrs).size, duplicateVoice.cidrs.length, "local observations overlapping known media routes are deduplicated");
const withoutDiscord = C.selectServices(first, ["telegram"]);
assert(withoutDiscord.domains.includes("geosite:discord"), "a pre-existing manual token must survive deselection");
assert(withoutDiscord.cidrs.includes("198.51.100.0/24"));
assert(!withoutDiscord.cidrs.includes(voice[0]), "only the deselected preset's owned rules are removed");
assert(!C.get("discord").cidrs.some((v) => withoutDiscord.cidrs.includes(v)), "deselecting Discord removes all of its known media routes");
const roundtrip = C.normalizeGroup(JSON.parse(JSON.stringify(first)));
assert.deepEqual(roundtrip, first);
const edited = C.normalizeGroup({ ...first, serviceManualCidrs: ["192.0.2.0/24"] });
assert(edited.cidrs.includes("192.0.2.0/24") && edited.cidrs.includes(voice[0]));
const noVoice = C.selectServices(first, ["discord"], { voiceEnabled: false });
assert(!noVoice.cidrs.includes("66.22.192.0/18") && !noVoice.cidrs.includes(voice[0]));
assert(!C.get("discord").cidrs.some((v) => noVoice.cidrs.includes(v)), "disabling media routing removes both voice and stream preset routes");
assert(noVoice.domains.includes("geosite:discord"), "Discord websites stay selected when media routing is disabled");
assert(noVoice.cidrs.includes("198.51.100.0/24"));
const blank = { id: "new", enabled: true, domains: [], cidrs: [] };
const nad = C.get("nad-bluos");
const nadOnly = C.selectServices(blank, ["nad-bluos"]);
assert.equal(nadOnly.enabled, true, "the NAD preset must materialize nonempty selective rules");
assert.equal(nad.category, "media");
for (const host of ["ca2.upgrade.bluos.net", "1.ntp.bluos.net", "main.news.bluos.net",
  "upgrade.nadelectronics.com", "d27y2nb09d21cl.cloudfront.net"]) {
  assert(nadOnly.domains.some((domain) => host === domain || host.endsWith(`.${domain}`)),
    `the NAD preset must cover its observed endpoint: ${host}`);
}
assert.equal(nad.cidrs.length, 0, "shared CDN IP ranges must not be captured by the NAD preset");
assert(!nad.domains.some((domain) => ["cloudfront.net", "amazonaws.com"].includes(domain)
  || domain.startsWith("geosite:")), "NAD uses vendor domains and its exact CDN, not broad or nonexistent categories");
assert(!nadOnly.domains.includes("geosite:spotify"), "Spotify is selected independently");
const nadWithSpotify = C.selectServices({ ...blank, domains: ["bluos.net", "example.org"] }, ["nad-bluos", "spotify"]);
const nadRemoved = C.selectServices(nadWithSpotify, ["spotify"]);
assert(nadRemoved.domains.includes("bluos.net"), "manual rules overlapping NAD must survive deselection");
assert(nadRemoved.domains.includes("example.org") && nadRemoved.domains.includes("geosite:spotify"));
assert(!nadRemoved.domains.includes("d27y2nb09d21cl.cloudfront.net"), "removing NAD removes its owned CDN route");
assert.deepEqual(C.normalizeGroup(JSON.parse(JSON.stringify(nadWithSpotify))), nadWithSpotify);
const lastRemoved = C.selectServices(C.selectServices(blank, ["chatgpt"]), []);
assert.equal(lastRemoved.enabled, false, "removing the last service must never create a full tunnel");
const manualFullTunnel = C.normalizeGroup(blank);
assert.equal(manualFullTunnel.enabled, true, "legacy explicit empty groups retain their semantics");
const future = C.normalizeGroup({ ...first, serviceIds: ["future-service"], domains: ["future.example"], cidrs: ["192.0.2.6/32"] });
assert(future.domains.includes("future.example") && future.cidrs.includes("192.0.2.6/32"));
assert.deepEqual(C.localVoiceCidrs({ groups: [{ id: "discord-voice-observed", cidrs: voice.concat("bad", "999.0.0.1/32", "0.0.0.0/0", "198.51.100.0/24") }] }), voice);
assert(!voice.some((cidr) => JSON.stringify(C.catalog).includes(cidr)), "arbitrary profile observations must not modify the shared catalog");
// Exercise the real UI profile normalizer, including JSON export/reload.
const source = fs.readFileSync("ui/xkeen-manager/app.js", "utf8").replace(/\r\n/g, "\n");
const extract = (name) => { const start = source.indexOf(`function ${name}(`); return source.slice(start, source.indexOf("\n}\n", start) + 2); };
const context = { AntiGoblinServices: C, T: {}, uniq: C.unique, newId: () => "generated", normalizeProxyEntry: (x) => x,
  normalizeSubscriptionEntry: (x) => x, normalizeProxyConfig: () => ({}), normalizeMuxConfig: () => ({}), createEmptyGroup: () => blank };
vm.createContext(context); vm.runInContext(extract("normalizeProfile"), context);
const profile = context.normalizeProfile({ id: "p", groups: [JSON.parse(JSON.stringify(first))] });
assert.deepEqual(JSON.parse(JSON.stringify(profile.groups[0])), { ...first, note: "" });
console.log("PASS: catalog ownership, custom rules, local voice CIDRs, unknown presets and safe empty groups");
