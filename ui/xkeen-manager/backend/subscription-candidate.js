(function () {
  const isNode = typeof process !== "undefined" && process.versions?.node;
  const nodeFs = isNode ? require("fs") : null;
  const rawArgs = isNode ? process.argv.slice(2) : scriptArgs.slice(-4);
  if (rawArgs.length < 4) throw new Error("usage: subscription-candidate.js STATE PROXY_ID OUT_DIR APP_JS");
  const [statePath, proxyId, outputDir, appPath] = rawArgs;
  const readText = (path) => isNode ? nodeFs.readFileSync(path, "utf8") : std.loadFile(path);
  const writeText = (path, value) => {
    if (isNode) { nodeFs.writeFileSync(path, value); return; }
    const file = std.open(path, "w");
    if (!file) throw new Error(`cannot open ${path}`);
    file.puts(value); file.close();
  };

  // Load the exact browser builders in headless mode. This keeps candidate
  // test/apply configs byte-for-byte aligned with Save & Apply semantics.
  globalThis.__ANTIGOBLIN_HEADLESS__ = true;
  globalThis.localStorage = { getItem: () => null, setItem: () => {}, removeItem: () => {} };
  const dummy = new Proxy({}, { get: () => () => {} });
  globalThis.document = {
    getElementById: () => dummy,
    querySelectorAll: () => [],
    addEventListener: () => {},
    documentElement: dummy,
    body: dummy
  };
  globalThis.window = globalThis;
  globalThis.addEventListener = () => {};
  globalThis.navigator = {};
  globalThis.setTimeout = () => 0;
  globalThis.clearTimeout = () => {};
  globalThis.fetch = () => Promise.reject(new Error("headless fetch disabled"));
  globalThis.AbortController = class { constructor() { this.signal = {}; } abort() {} };
  const source = readText(appPath) + "\n;globalThis.__agBuilders={buildOutboundsDocument,buildSingboxDocument,buildRoutingDocument};";
  globalThis.eval(source);

  const state = JSON.parse(readText(statePath));
  const profile = (state.profiles || []).find((item) => (item.proxies || []).some((proxy) => proxy.id === proxyId));
  if (!profile) throw new Error("proxy not found");
  profile.groups = Array.isArray(profile.groups) ? profile.groups : [];
  profile.muxConfig = profile.muxConfig && typeof profile.muxConfig === "object"
    ? profile.muxConfig
    : { mode: "off" };
  profile.activeProxyId = proxyId;
  const proxy = profile.proxies.find((item) => item.id === proxyId);
  writeText(`${outputDir}/outbounds.json`, JSON.stringify(__agBuilders.buildOutboundsDocument(profile), null, 2) + "\n");
  writeText(`${outputDir}/singbox.json`, JSON.stringify(__agBuilders.buildSingboxDocument(profile), null, 2) + "\n");
  writeText(`${outputDir}/routing.json`, JSON.stringify(__agBuilders.buildRoutingDocument(profile), null, 2) + "\n");
  writeText(`${outputDir}/candidate.json`, JSON.stringify({ id: proxy.id, protocol: proxy.config.protocol || "vless" }) + "\n");
})();
