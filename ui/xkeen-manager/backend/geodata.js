(function () {
  const isNode = typeof process !== "undefined" && process.versions?.node;
  const nodeFs = isNode ? require("fs") : null;
  const args = isNode ? process.argv.slice(2) : scriptArgs.slice(-5);
  if (args.length < 4 || args[0] !== "singbox") {
    throw new Error("usage: geodata.js singbox STATE GEOIP_DAT GEOSITE_DAT OUT_JSON");
  }
  const [, statePath, geoipPath, geositePath, outputPath] = args;

  function readText(path) {
    return isNode ? nodeFs.readFileSync(path, "utf8") : std.loadFile(path);
  }

  function writeText(path, value) {
    if (isNode) {
      nodeFs.writeFileSync(path, value);
      return;
    }
    const file = std.open(path, "w");
    if (!file) throw new Error(`cannot open ${path}`);
    file.puts(value);
    file.close();
  }

  class BinaryReader {
    constructor(path) {
      this.nodeBuffer = isNode ? nodeFs.readFileSync(path) : null;
      this.position = 0;
      this.file = null;
      if (isNode) {
        this.length = this.nodeBuffer.length;
      } else {
        this.file = std.open(path, "rb");
        if (!this.file) throw new Error(`cannot open ${path}`);
        this.file.seek(0, std.SEEK_END);
        this.length = Number(this.file.tell());
        this.file.seek(0, std.SEEK_SET);
      }
    }

    tell() { return isNode ? this.position : Number(this.file.tell()); }

    seek(position) {
      if (position < 0 || position > this.length) throw new Error("protobuf seek out of range");
      if (isNode) this.position = position;
      else if (this.file.seek(position, std.SEEK_SET) !== 0) throw new Error("protobuf seek failed");
    }

    byte() {
      if (this.tell() >= this.length) throw new Error("unexpected end of protobuf file");
      if (isNode) return this.nodeBuffer[this.position++];
      const value = this.file.getByte();
      if (value < 0) throw new Error("unexpected end of protobuf file");
      return value;
    }

    varint() {
      let value = 0;
      let factor = 1;
      for (let index = 0; index < 10; index++) {
        const byte = this.byte();
        value += (byte & 0x7f) * factor;
        if ((byte & 0x80) === 0) {
          if (!Number.isSafeInteger(value)) throw new Error("protobuf integer is too large");
          return value;
        }
        factor *= 128;
      }
      throw new Error("invalid protobuf varint");
    }

    bytes(length) {
      if (!Number.isSafeInteger(length) || length < 0 || this.tell() + length > this.length) {
        throw new Error("invalid protobuf length");
      }
      if (isNode) {
        const start = this.position;
        this.position += length;
        return this.nodeBuffer.subarray(start, start + length);
      }
      const buffer = new ArrayBuffer(length);
      const read = this.file.read(buffer, 0, length);
      if (read !== length) throw new Error("short protobuf read");
      return new Uint8Array(buffer);
    }

    close() { if (this.file) this.file.close(); }
  }

  function utf8(bytes) {
    let result = "";
    for (let index = 0; index < bytes.length;) {
      const first = bytes[index++];
      if (first < 0x80) { result += String.fromCharCode(first); continue; }
      let code;
      if ((first & 0xe0) === 0xc0 && index < bytes.length) {
        code = ((first & 0x1f) << 6) | (bytes[index++] & 0x3f);
      } else if ((first & 0xf0) === 0xe0 && index + 1 < bytes.length) {
        code = ((first & 0x0f) << 12) | ((bytes[index++] & 0x3f) << 6) | (bytes[index++] & 0x3f);
      } else if ((first & 0xf8) === 0xf0 && index + 2 < bytes.length) {
        code = ((first & 0x07) << 18) | ((bytes[index++] & 0x3f) << 12)
          | ((bytes[index++] & 0x3f) << 6) | (bytes[index++] & 0x3f);
      } else {
        result += "\ufffd";
        continue;
      }
      if (code <= 0xffff) result += String.fromCharCode(code);
      else {
        code -= 0x10000;
        result += String.fromCharCode(0xd800 + (code >> 10), 0xdc00 + (code & 0x3ff));
      }
    }
    return result;
  }

  function readString(reader) {
    const length = reader.varint();
    if (length > 4 * 1024 * 1024) throw new Error("protobuf string too large");
    return utf8(reader.bytes(length));
  }

  function skipField(reader, wire) {
    if (wire === 0) { reader.varint(); return; }
    if (wire === 1) { reader.seek(reader.tell() + 8); return; }
    if (wire === 2) {
      const length = reader.varint();
      reader.seek(reader.tell() + length);
      return;
    }
    if (wire === 5) { reader.seek(reader.tell() + 4); return; }
    throw new Error(`unsupported protobuf wire type ${wire}`);
  }

  function messageEnd(reader, outerEnd) {
    const length = reader.varint();
    const end = reader.tell() + length;
    if (end > outerEnd || end > reader.length) throw new Error("protobuf message exceeds file");
    return end;
  }

  function findEntryCode(reader, end) {
    const start = reader.tell();
    let code = "";
    while (reader.tell() < end) {
      const key = reader.varint();
      const field = Math.floor(key / 8);
      const wire = key & 7;
      if (field === 1 && wire === 2) code = readString(reader);
      else skipField(reader, wire);
    }
    reader.seek(start);
    return code.toLowerCase();
  }

  function parseGeoToken(value, prefix) {
    const raw = String(value || "").trim().toLowerCase();
    if (!raw.startsWith(`${prefix}:`)) return null;
    const body = raw.slice(prefix.length + 1);
    const parts = body.split("@");
    const code = parts.shift();
    const codePattern = prefix === "geosite"
      ? /^[a-z0-9][a-z0-9_!-]{0,63}$/
      : /^[a-z0-9][a-z0-9_-]{0,63}$/;
    if (!codePattern.test(code)) return null;
    const attrs = [];
    for (const part of parts) {
      const negative = part.startsWith("!");
      const name = negative ? part.slice(1) : part;
      if (!/^[a-z0-9][a-z0-9_-]{0,63}$/.test(name)) return null;
      attrs.push({ name, negative });
    }
    return { token: raw, code, attrs };
  }

  function parseAttribute(reader, end) {
    let name = "";
    let enabled = true;
    while (reader.tell() < end) {
      const key = reader.varint();
      const field = Math.floor(key / 8);
      const wire = key & 7;
      if (field === 1 && wire === 2) name = readString(reader).toLowerCase();
      else if (field === 2 && wire === 0) enabled = reader.varint() !== 0;
      else if (field === 3 && wire === 0) { reader.varint(); enabled = true; }
      else skipField(reader, wire);
    }
    return enabled ? name : "";
  }

  function parseDomain(reader, end) {
    let type = 0;
    let value = "";
    const attrs = new Set();
    while (reader.tell() < end) {
      const key = reader.varint();
      const field = Math.floor(key / 8);
      const wire = key & 7;
      if (field === 1 && wire === 0) type = reader.varint();
      else if (field === 2 && wire === 2) value = readString(reader);
      else if (field === 3 && wire === 2) {
        const attrEnd = messageEnd(reader, end);
        const attribute = parseAttribute(reader, attrEnd);
        if (attribute) attrs.add(attribute);
        reader.seek(attrEnd);
      } else skipField(reader, wire);
    }
    return { type, value, attrs };
  }

  function matchesAttrs(spec, attributes) {
    return spec.attrs.every((attr) => attr.negative ? !attributes.has(attr.name) : attributes.has(attr.name));
  }

  function loadGeoSite(path, specs) {
    const wantedCodes = new Set(specs.map((item) => item.code));
    const result = new Map(specs.map((item) => [item.token, {
      domain: [], domain_suffix: [], domain_keyword: [], domain_regex: []
    }]));
    if (!wantedCodes.size) return result;
    const reader = new BinaryReader(path);
    try {
      while (reader.tell() < reader.length) {
        const key = reader.varint();
        const field = Math.floor(key / 8);
        const wire = key & 7;
        if (field !== 1 || wire !== 2) { skipField(reader, wire); continue; }
        const entryEnd = messageEnd(reader, reader.length);
        const code = findEntryCode(reader, entryEnd);
        if (!wantedCodes.has(code)) { reader.seek(entryEnd); continue; }
        while (reader.tell() < entryEnd) {
          const entryKey = reader.varint();
          const entryField = Math.floor(entryKey / 8);
          const entryWire = entryKey & 7;
          if (entryField === 2 && entryWire === 2) {
            const domainEnd = messageEnd(reader, entryEnd);
            const domain = parseDomain(reader, domainEnd);
            reader.seek(domainEnd);
            if (!domain.value) continue;
            for (const spec of specs) {
              if (spec.code !== code || !matchesAttrs(spec, domain.attrs)) continue;
              const target = result.get(spec.token);
              const fieldName = ["domain_keyword", "domain_regex", "domain_suffix", "domain"][domain.type];
              if (fieldName) target[fieldName].push(domain.value);
            }
          } else skipField(reader, entryWire);
        }
        reader.seek(entryEnd);
      }
    } finally { reader.close(); }
    return result;
  }

  function ipv6(bytes) {
    const groups = [];
    for (let index = 0; index < 16; index += 2) groups.push(((bytes[index] << 8) | bytes[index + 1]).toString(16));
    return groups.join(":");
  }

  function parseCidr(reader, end) {
    let ip = null;
    let prefix = null;
    while (reader.tell() < end) {
      const key = reader.varint();
      const field = Math.floor(key / 8);
      const wire = key & 7;
      if (field === 1 && wire === 2) ip = reader.bytes(reader.varint());
      else if (field === 2 && wire === 0) prefix = reader.varint();
      else skipField(reader, wire);
    }
    if (!ip || prefix === null) return null;
    if (ip.length === 4 && prefix <= 32) return `${ip[0]}.${ip[1]}.${ip[2]}.${ip[3]}/${prefix}`;
    if (ip.length === 16 && prefix <= 128) return `${ipv6(ip)}/${prefix}`;
    return null;
  }

  function loadGeoIp(path, specs) {
    const wantedCodes = new Set(specs.map((item) => item.code));
    const result = new Map(specs.map((item) => [item.token, []]));
    if (!wantedCodes.size) return result;
    const reader = new BinaryReader(path);
    try {
      while (reader.tell() < reader.length) {
        const key = reader.varint();
        const field = Math.floor(key / 8);
        const wire = key & 7;
        if (field !== 1 || wire !== 2) { skipField(reader, wire); continue; }
        const entryEnd = messageEnd(reader, reader.length);
        const code = findEntryCode(reader, entryEnd);
        if (!wantedCodes.has(code)) { reader.seek(entryEnd); continue; }
        while (reader.tell() < entryEnd) {
          const entryKey = reader.varint();
          const entryField = Math.floor(entryKey / 8);
          const entryWire = entryKey & 7;
          if (entryField === 2 && entryWire === 2) {
            const cidrEnd = messageEnd(reader, entryEnd);
            const cidr = parseCidr(reader, cidrEnd);
            reader.seek(cidrEnd);
            if (cidr) for (const spec of specs) if (spec.code === code) result.get(spec.token).push(cidr);
          } else skipField(reader, entryWire);
        }
        reader.seek(entryEnd);
      }
    } finally { reader.close(); }
    return result;
  }

  function unique(values) { return [...new Set(values.filter(Boolean))]; }
  function routeRule(inbound, field, values, outbound) {
    const items = unique(values);
    return items.length ? {
      inbound: [inbound],
      [field]: items,
      action: "route",
      outbound
    } : null;
  }

  const state = JSON.parse(readText(statePath));
  const profile = (state.profiles || []).find((item) => item.id === state.activeProfileId) || (state.profiles || [])[0];
  if (!profile) throw new Error("active profile not found");
  const groups = Array.isArray(profile.groups) ? profile.groups.filter((item) => item.enabled !== false) : [];
  const siteSpecs = [];
  const ipSpecs = [];
  for (const group of groups) {
    for (const value of group.domains || []) {
      const spec = parseGeoToken(value, "geosite");
      if (spec && !siteSpecs.some((item) => item.token === spec.token)) siteSpecs.push(spec);
    }
    for (const value of group.cidrs || []) {
      const spec = parseGeoToken(value, "geoip");
      if (spec && !ipSpecs.some((item) => item.token === spec.token)) ipSpecs.push(spec);
    }
  }
  if (!siteSpecs.length && !ipSpecs.length) throw new Error("active profile has no geo rules");

  const sites = loadGeoSite(geositePath, siteSpecs);
  const ips = loadGeoIp(geoipPath, ipSpecs);
  for (const spec of siteSpecs) {
    const count = Object.values(sites.get(spec.token)).reduce((sum, values) => sum + values.length, 0);
    if (!count) throw new Error(`geosite category not found: ${spec.token}`);
  }
  for (const spec of ipSpecs) {
    if (!ips.get(spec.token).length) throw new Error(`geoip category not found: ${spec.token}`);
  }

  const isBypass = (group) => group.outboundTag === "direct" || group.outboundTag === "bypass";
  const groupIsCatchAll = (group) => {
    const domains = Array.isArray(group.domains) ? group.domains.filter(Boolean) : [];
    const cidrs = Array.isArray(group.cidrs) ? group.cidrs.filter(Boolean) : [];
    return (!domains.length && !cidrs.length) || cidrs.includes("0.0.0.0/0");
  };
  const fullTunnel = profile.fallbackOutbound === "vless-reality"
    || groups.some((group) => !isBypass(group) && groupIsCatchAll(group));
  const quicEnabled = !fullTunnel && groups.some((group) =>
    !isBypass(group) && (group.domains || []).some((value) => parseGeoToken(value, "geosite"))
  );
  const routeInbound = fullTunnel ? "xkeen-udp-tproxy" : "xkeen-quic-tproxy";
  const rules = [{
    inbound: ["xkeen-udp-tproxy", "xkeen-quic-tproxy"],
    ip_is_private: true,
    action: "route",
    outbound: "direct"
  }];
  if (siteSpecs.length && (fullTunnel || quicEnabled)) {
    rules.push({ inbound: [routeInbound], action: "sniff" });
  }
  const vpnCidrs = [];
  const bypassCidrs = [];
  let expandedEntries = 0;
  const MAX_EXPANDED_ENTRIES = 100000;
  for (const group of groups) {
    const bypass = isBypass(group);
    const outbound = bypass ? "direct" : "proxy";
    const plainDomains = [];
    const expanded = { domain: [], domain_suffix: [], domain_keyword: [], domain_regex: [] };
    for (const value of group.domains || []) {
      const spec = parseGeoToken(value, "geosite");
      if (!spec) plainDomains.push(String(value).toLowerCase());
      else {
        const values = sites.get(spec.token);
        for (const field of ["domain", "domain_suffix", "domain_keyword", "domain_regex"]) {
          expanded[field].push(...values[field]);
        }
      }
    }
    for (const value of group.cidrs || []) {
      const spec = parseGeoToken(value, "geoip");
      if (!spec) continue;
      (bypass ? bypassCidrs : vpnCidrs).push(
        ...ips.get(spec.token).filter((cidr) => !String(cidr).includes(":"))
      );
    }
    expandedEntries += Object.values(expanded).reduce((sum, values) => sum + values.length, 0)
      + (group.cidrs || []).reduce((sum, value) => {
        const spec = parseGeoToken(value, "geoip");
        return sum + (spec ? ips.get(spec.token).length : 0);
      }, 0);
    if (expandedEntries > MAX_EXPANDED_ENTRIES) throw new Error("selected geo categories exceed 100000 expanded rules");

    // In full-tunnel mode every UDP packet already uses the proxy. Only
    // bypass GeoSite rules need to be materialized. In selective mode the
    // separate :61222 inbound sees UDP/443 and applies both VPN and bypass
    // GeoSite rules before sending an unmatched QUIC flow direct.
    if ((!fullTunnel || bypass) && (fullTunnel || quicEnabled)) {
      for (const [field, values] of [
        ["domain_suffix", plainDomains],
        ["domain", expanded.domain],
        ["domain_suffix", expanded.domain_suffix],
        ["domain_keyword", expanded.domain_keyword],
        ["domain_regex", expanded.domain_regex]
      ]) {
        const rule = routeRule(routeInbound, field, values, outbound);
        if (rule) rules.push(rule);
      }
    }
  }
  if (fullTunnel) {
    rules.push({ inbound: ["xkeen-udp-tproxy"], action: "route", outbound: "proxy" });
  } else if (quicEnabled) {
    rules.push({ inbound: ["xkeen-quic-tproxy"], action: "route", outbound: "direct" });
  }
  const result = {
    hasGeo: true,
    rules,
    final: "proxy",
    fullTunnel,
    quicEnabled,
    vpnCidrs: unique(vpnCidrs),
    bypassCidrs: unique(bypassCidrs),
    stats: {
      geositeCategories: siteSpecs.length,
      geoipCategories: ipSpecs.length,
      expandedEntries,
      singboxEntries: rules.reduce((sum, rule) => sum + [
        "domain", "domain_suffix", "domain_keyword", "domain_regex", "ip_cidr"
      ].reduce((count, field) => count + (rule[field] || []).length, 0), 0),
      vpnIpEntries: unique(vpnCidrs).length,
      bypassIpEntries: unique(bypassCidrs).length
    }
  };
  const serialized = JSON.stringify(result, null, 2) + "\n";
  if (serialized.length > 16 * 1024 * 1024) throw new Error("expanded sing-box rules exceed 16 MiB");
  writeText(outputPath, serialized);
})();
