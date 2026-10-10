(function () {
  const isNode = typeof process !== "undefined" && process.versions?.node;
  const nodeFs = isNode ? require("fs") : null;
  const rawArgs = isNode ? process.argv.slice(2) : scriptArgs.slice(-4);
  if (rawArgs.length < 4) throw new Error("usage: subscription-refresh.js STATE JOBS OUT APP_JS");
  const [statePath, jobsPath, outputPath, appPath] = rawArgs;

  const readText = (path) => isNode
    ? nodeFs.readFileSync(path, "utf8")
    : std.loadFile(path);
  const writeText = (path, value) => {
    if (isNode) {
      nodeFs.writeFileSync(path, value);
      return;
    }
    const file = std.open(path, "w");
    if (!file) throw new Error(`cannot open ${path}`);
    file.puts(value);
    file.close();
  };
  const printLine = (value) => {
    if (isNode) console.log(value);
    else std.out.puts(value + "\n");
  };

  // app.js is the single source of truth for subscription parsing. Extract
  // its pure parser block rather than maintaining a second router-only parser.
  const appSource = readText(appPath);
  const parserStart = appSource.indexOf("function createDefaultProxyConfig()");
  const parserEnd = appSource.indexOf("// Build xray outbound", parserStart);
  if (parserStart < 0 || parserEnd < 0) throw new Error("subscription parser block not found in app.js");

  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  globalThis.atob = globalThis.atob || function (input) {
    const value = String(input || "").replace(/\s+/g, "").replace(/-/g, "+").replace(/_/g, "/");
    let bits = 0, bitCount = 0, output = "";
    for (const char of value.replace(/=+$/, "")) {
      const index = alphabet.indexOf(char);
      if (index < 0) throw new Error("invalid base64");
      bits = (bits << 6) | index;
      bitCount += 6;
      if (bitCount >= 8) {
        bitCount -= 8;
        output += String.fromCharCode((bits >> bitCount) & 255);
      }
    }
    return output;
  };
  const decodeUtf8 = (binary) => {
    let escaped = "";
    for (let i = 0; i < binary.length; i++) escaped += `%${binary.charCodeAt(i).toString(16).padStart(2, "0")}`;
    try { return decodeURIComponent(escaped); }
    catch { return binary; }
  };
  globalThis.eval(appSource.slice(parserStart, parserEnd));

  const decodeBody = (encoded) => {
    const body = decodeUtf8(atob(encoded));
    const compact = body.replace(/\s+/g, "");
    if (compact.length < 8 || !/^[A-Za-z0-9+/_-]+={0,2}$/.test(compact)) return body;
    try {
      const decoded = decodeUtf8(atob(compact));
      const trimmed = decoded.trim();
      if (/^(?:[\[{]|vless:\/\/|vmess:\/\/|hysteria2:\/\/|hy2:\/\/)/i.test(trimmed)) return decoded;
    } catch { /* raw body is the payload */ }
    return body;
  };
  const keyOf = (config) => `${config.protocol || "vless"}:${config.address}:${config.port}/${config.uuid || config.password || ""}`;
  const stableId = (subId, key) => {
    let hash = 2166136261;
    for (let i = 0; i < key.length; i++) {
      hash ^= key.charCodeAt(i);
      hash = Math.imul(hash, 16777619) >>> 0;
    }
    return `proxy-${subId}-${hash.toString(16).padStart(8, "0")}`;
  };

  const state = JSON.parse(readText(statePath));
  const jobs = readText(jobsPath).split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line));
  let refreshed = 0, failed = 0, addedTotal = 0, removedTotal = 0;

  for (const job of jobs) {
    const profile = (state.profiles || []).find((item) => item.id === job.profileId);
    const sub = profile && (profile.subscriptions || []).find((item) => item.id === job.subId);
    if (!profile || !sub || sub.autoRefresh !== true) continue;
    sub.lastRefreshAttempt = job.now;
    if (!job.ok) {
      sub.lastError = String(job.error || "scheduled fetch failed").slice(0, 200);
      failed++;
      continue;
    }
    const parsed = parseSubscriptionText(decodeBody(job.bodyBase64));
    if (!parsed.configs.length) {
      sub.lastError = "scheduled refresh returned no recognised keys";
      failed++;
      continue;
    }

    const old = (profile.proxies || []).filter((item) => item.source === sub.id);
    const oldByKey = new Map(old.map((item) => [keyOf(item.config), item]));
    const activeOld = old.find((item) => item.id === profile.activeProxyId);
    const next = [];
    const seenKeys = new Set();
    let added = 0, kept = 0;
    for (const config of parsed.configs) {
      const key = keyOf(config);
      if (seenKeys.has(key)) continue;
      seenKeys.add(key);
      const existing = oldByKey.get(key);
      if (existing) {
        next.push({ ...existing, name: config.name, config, stale: false });
        oldByKey.delete(key);
        kept++;
      } else {
        next.push({ id: stableId(sub.id, key), name: config.name, source: sub.id, config, stale: false });
        added++;
      }
    }
    const removed = Array.from(oldByKey.values()).filter((item) => item.id !== profile.activeProxyId);
    const activeRemoved = activeOld && oldByKey.has(keyOf(activeOld.config));
    if (activeRemoved) next.push({ ...activeOld, stale: true });
    profile.proxies = [
      ...(profile.proxies || []).filter((item) => item.source !== sub.id),
      ...next
    ];
    sub.lastFetched = job.now;
    sub.lastError = activeRemoved ? "active key disappeared upstream; kept last-known config" : null;
    sub.lastRefreshStats = { added, kept, removed: removed.length };
    refreshed++;
    addedTotal += added;
    removedTotal += removed.length;
  }

  writeText(outputPath, JSON.stringify(state, null, 2) + "\n");
  printLine(`subscription_refresh refreshed=${refreshed} failed=${failed} added=${addedTotal} removed=${removedTotal}`);
})();
