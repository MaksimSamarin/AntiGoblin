const STORAGE_KEY = "xkeen-manager-state-v7";

// Default timeout for router-side fetches. Without this, a stuck CGI
// (waiting on lock, dead nslookup, etc) freezes Save/Apply/Restart
// buttons in "disabled" state forever because `await response.json()`
// never resolves. Wraps fetch with AbortController — polyfills the
// browsers that don't support AbortSignal.timeout yet.
const ROUTER_FETCH_TIMEOUT_MS = 20000;

// Try to parse the response body as JSON. If the response is not-OK, throw
// a "HTTP N" error BEFORE attempting to parse — a 500 with an empty body
// otherwise produces the confusing "Unexpected end of JSON input" instead
// of the useful HTTP status. If the body parses to `{ok:false, error}`,
// honour that too.
async function parseResponseOrThrow(response) {
  if (!response.ok) {
    // Try to read the body for extra context, but don't rely on it being JSON.
    let extra = "";
    try {
      const raw = await response.text();
      if (raw) extra = ": " + raw.slice(0, 200);
    } catch { /* ignore */ }
    throw new Error(response.status === 401 ? AUTH_REQUIRED_MESSAGE : `HTTP ${response.status}${extra}`);
  }
  const text = await response.text();
  if (!text) throw new Error("empty response body");
  let payload;
  try { payload = JSON.parse(text); } catch (err) {
    throw new Error(`invalid JSON response: ${err.message}`);
  }
  if (payload && payload.ok === false) {
    throw new Error(payload.error || "backend returned ok:false");
  }
  return payload;
}

function fetchWithTimeout(url, init, timeoutMs) {
  const ms = typeof timeoutMs === "number" ? timeoutMs : ROUTER_FETCH_TIMEOUT_MS;
  const opts = init ? { ...init } : {};
  // Respect a caller-provided signal by racing; otherwise create our own.
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  if (opts.signal) {
    const outer = opts.signal;
    if (outer.aborted) controller.abort();
    else outer.addEventListener("abort", () => controller.abort(), { once: true });
  }
  opts.signal = controller.signal;
  return fetch(url, opts).finally(() => clearTimeout(timer));
}
const LANGUAGE_KEY = "xkeen-manager-lang-v1";
const STATE_URL = "./api/routing.cgi?kind=state";
const OUTBOUNDS_URL = "./api/routing.cgi?kind=outbounds";
const SINGBOX_URL = "./api/routing.cgi?kind=singbox";
const PROBE_URL = "./api/routing.cgi?kind=probe";
const REPAIR_URL = "./api/routing.cgi?kind=repair-runtime";
const LOGIN_URL = "./api/routing.cgi?kind=login";
const LOGOUT_URL = "./api/routing.cgi?kind=logout";
const LIVE_ROUTING_URL = "./api/routing.cgi";
const HEALTH_URL = "./api/routing.cgi?kind=health";
const LOGS_URL = "./api/routing.cgi?kind=logs";
const RESTART_SVC_URL = "./api/routing.cgi?kind=restart-svc";
const STACK_INFO_URL = "./api/routing.cgi?kind=stack-info";
const MUX_MODES = new Set(["off", "xudp"]);
const MUX_UDP443_MODES = new Set(["reject", "skip", "allow"]);

const LOCALES = {
  ru: {
    documentTitle: "AntiGoblin",
    authTitle: "\u0412\u0445\u043e\u0434 \u0432 \u043f\u0430\u043d\u0435\u043b\u044c",
    authLead: "\u0412\u043e\u0439\u0434\u0438 \u043b\u043e\u0433\u0438\u043d\u043e\u043c \u0438 \u043f\u0430\u0440\u043e\u043b\u0435\u043c \u043e\u0442 \u0432\u0435\u0431-\u0438\u043d\u0442\u0435\u0440\u0444\u0435\u0439\u0441\u0430 Keenetic.",
    authLoginLabel: "\u041b\u043e\u0433\u0438\u043d",
    authPasswordLabel: "\u041f\u0430\u0440\u043e\u043b\u044c",
    authSubmit: "\u0412\u043e\u0439\u0442\u0438",
    authSubmitting: "\u0412\u0445\u043e\u0434...",
    heroTitle: "\u041f\u0430\u043d\u0435\u043b\u044c \u0443\u043f\u0440\u0430\u0432\u043b\u0435\u043d\u0438\u044f XKeen/xray",
    heroLead: "\u0423\u043f\u0440\u0430\u0432\u043b\u044f\u0439 \u043f\u0440\u043e\u0444\u0438\u043b\u044f\u043c\u0438, \u0433\u0440\u0443\u043f\u043f\u0430\u043c\u0438 \u0438 VLESS-\u043a\u043e\u043d\u0444\u0438\u0433\u043e\u043c \u0434\u043b\u044f XKeen/xray \u0432 \u043e\u0434\u043d\u043e\u0439 \u043f\u0430\u043d\u0435\u043b\u0438.",
    langLabel: "Language",
    profileKicker: "\u0411\u0430\u0437\u043e\u0432\u044b\u0435 \u043d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438",
    profileTitle: "\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438 \u043f\u0440\u043e\u0444\u0438\u043b\u044f",
    activeProfileLabel: "\u0410\u043a\u0442\u0438\u0432\u043d\u044b\u0439 \u043f\u0440\u043e\u0444\u0438\u043b\u044c",
    profileNameLabel: "\u041d\u0430\u0437\u0432\u0430\u043d\u0438\u0435 \u043d\u0430\u0431\u043e\u0440\u0430",
    domainStrategyLabel: "\u0421\u0442\u0440\u0430\u0442\u0435\u0433\u0438\u044f \u0434\u043e\u043c\u0435\u043d\u043e\u0432",
    fallbackLabel: "\u041c\u0430\u0440\u0448\u0440\u0443\u0442 \u043f\u043e \u0443\u043c\u043e\u043b\u0447\u0430\u043d\u0438\u044e",
    trafficTypeLabel: "\u041d\u0430\u043f\u0440\u0430\u0432\u043b\u0435\u043d\u0438\u0435",
    trafficTypeVpn: "\u0427\u0435\u0440\u0435\u0437 VPN",
    trafficTypeBypass: "\u041c\u0438\u043c\u043e VPN",
    proxyTitle: "\u041a\u043e\u043d\u0444\u0438\u0433 \u043f\u0440\u043e\u043a\u0441\u0438",
    proxyUrlLabel: "VLESS URL",
    proxyAddressLabel: "\u0421\u0435\u0440\u0432\u0435\u0440",
    proxyPortLabel: "\u041f\u043e\u0440\u0442",
    muxKicker: "Mux / XUDP",
    muxTitle: "Mux режим",
    muxModeLabel: "Режим",
    muxUdp443Label: "UDP/443",
    muxXudpConcurrencyLabel: "XUDP concurrency",
    muxModeOff: "Off",
    muxModeXudp: "XUDP only",
    previewKicker: "\u041f\u0440\u0435\u0434\u043f\u0440\u043e\u0441\u043c\u043e\u0442\u0440",
    previewTitle: "\u0418\u0442\u043e\u0433\u043e\u0432\u044b\u0439 routing.json",
    groupsKicker: "\u0413\u0440\u0443\u043f\u043f\u044b",
    groupsTitle: "\u041f\u0440\u0430\u0432\u0438\u043b\u0430 \u0442\u0440\u0430\u0444\u0438\u043a\u0430",
    importBtn: "\u0418\u043c\u043f\u043e\u0440\u0442",
    exportBtn: "\u0421\u043a\u0430\u0447\u0430\u0442\u044c",
    repairBtn: "\u0420\u0435\u0441\u0442\u0430\u0440\u0442",
    saveApplyBtn: "\u0421\u043e\u0445\u0440\u0430\u043d\u0438\u0442\u044c \u0438 \u043f\u0440\u0438\u043c\u0435\u043d\u0438\u0442\u044c",
    logoutBtn: "\u0412\u044b\u0439\u0442\u0438",
    addProfileBtn: "\u041d\u043e\u0432\u044b\u0439",
    duplicateProfileBtn: "\u0414\u0443\u0431\u043b\u0438\u0440\u043e\u0432\u0430\u0442\u044c",
    removeProfileBtn: "\u0423\u0434\u0430\u043b\u0438\u0442\u044c",
    saveStateBtn: "\u0421\u043e\u0445\u0440\u0430\u043d\u0438\u0442\u044c",
    importProxyBtn: "\u0418\u043c\u043f\u043e\u0440\u0442 vless://",
    probeProxyBtn: "\u041f\u0440\u043e\u0432\u0435\u0440\u0438\u0442\u044c",
    addGroupBtn: "\u0414\u043e\u0431\u0430\u0432\u0438\u0442\u044c \u0433\u0440\u0443\u043f\u043f\u0443",
    profileName: "\u041f\u0440\u043e\u0444\u0438\u043b\u044c 1",
    defaultProfileName: "\u041f\u0440\u043e\u0444\u0438\u043b\u044c",
    fallbackNote: "\u0420\u0435\u0437\u0435\u0440\u0432\u043d\u043e\u0435 \u0441\u043e\u0441\u0442\u043e\u044f\u043d\u0438\u0435, \u0435\u0441\u043b\u0438 state \u043d\u0435 \u0437\u0430\u0433\u0440\u0443\u0437\u0438\u043b\u0441\u044f",
    copied: "\u0421\u043a\u043e\u043f\u0438\u0440\u043e\u0432\u0430\u043d\u043e",
    imported: "\u0418\u043c\u043f\u043e\u0440\u0442 \u0438\u0437 xray routing",
    noGroups: "\u041d\u0435\u0442 \u0433\u0440\u0443\u043f\u043f. \u041d\u0430\u0436\u043c\u0438 \"\u0414\u043e\u0431\u0430\u0432\u0438\u0442\u044c \u0433\u0440\u0443\u043f\u043f\u0443\".",
    newGroup: "\u041d\u043e\u0432\u0430\u044f \u0433\u0440\u0443\u043f\u043f\u0430",
    active: "\u0410\u043a\u0442\u0438\u0432\u043d\u0430",
    remove: "\u0423\u0434\u0430\u043b\u0438\u0442\u044c",
    comment: "\u041a\u043e\u043c\u043c\u0435\u043d\u0442\u0430\u0440\u0438\u0439",
    commentPlaceholder: "\u041d\u0430\u043f\u0440\u0438\u043c\u0435\u0440: Copilot / Telegram / AI",
    domains: "\u0414\u043e\u043c\u0435\u043d\u044b",
    cidr: "CIDR / IP \u0441\u0435\u0442\u0438",
    currentState: "\u0422\u0435\u043a\u0443\u0449\u0438\u0439 state \u0441 \u0440\u043e\u0443\u0442\u0435\u0440\u0430",
    groups: "\u0413\u0440\u0443\u043f\u043f",
    activeGroups: "\u0410\u043a\u0442\u0438\u0432\u043d\u044b\u0445",
    vpnDomains: "VPN-\u0434\u043e\u043c\u0435\u043d\u043e\u0432",
    bypassDomains: "\u041c\u0438\u043c\u043e VPN",
    cidrShort: "CIDR",
    bypassGroupName: "\u041c\u0438\u043c\u043e VPN",
    profileAdded: "\u041d\u043e\u0432\u044b\u0439 \u043f\u0440\u043e\u0444\u0438\u043b\u044c",
    profileCopySuffix: " \u043a\u043e\u043f\u0438\u044f",
    saveApplyDone: "\u0421\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u043e \u0438 \u043f\u0440\u0438\u043c\u0435\u043d\u0435\u043d\u043e",
    saveStateDone: "\u041f\u0440\u043e\u0444\u0438\u043b\u044c \u0441\u043e\u0445\u0440\u0430\u043d\u0435\u043d",
    // Subscription form / list / actions
    subUrlEmpty: "URL \u043d\u0435 \u0437\u0430\u043f\u043e\u043b\u043d\u0435\u043d",
    subUrlNeedHttps: "URL \u0434\u043e\u043b\u0436\u0435\u043d \u043d\u0430\u0447\u0438\u043d\u0430\u0442\u044c\u0441\u044f \u0441 https://",
    subRefreshingFmt: "\u041e\u0431\u043d\u043e\u0432\u043b\u044f\u044e \u00ab{name}\u00bb\u2026",
    subEmpty: "\u043f\u043e\u0434\u043f\u0438\u0441\u043a\u0430 \u043f\u0443\u0441\u0442\u0430",
    subCancelled: "\u043e\u0431\u043d\u043e\u0432\u043b\u0435\u043d\u0438\u0435 \u043e\u0442\u043c\u0435\u043d\u0435\u043d\u043e (\u043f\u043e\u0434\u043f\u0438\u0441\u043a\u0430 \u0441\u043d\u044f\u0442\u0430)",
    noSubscriptions: "\u041d\u0435\u0442 \u043f\u043e\u0434\u043f\u0438\u0441\u043e\u043a",
    noManualKeys: "\u041d\u0435\u0442 \u0440\u0443\u0447\u043d\u044b\u0445 \u043a\u043b\u044e\u0447\u0435\u0439",
    confirmDeleteKey: "\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u044d\u0442\u043e\u0442 \u043a\u043b\u044e\u0447?",
    confirmDeleteSubFmt: "\u0423\u0434\u0430\u043b\u0438\u0442\u044c \u043f\u043e\u0434\u043f\u0438\u0441\u043a\u0443 \u00ab{name}\u00bb \u0438 \u0432\u0441\u0435 \u0435\u0451 \u043a\u043b\u044e\u0447\u0438?",
    subRevealHint: "\u041f\u043e\u043a\u0430\u0437\u0430\u0442\u044c URL \u2014 \u043a\u043d\u043e\u043f\u043a\u0430 \ud83d\udc41",
    // UX helpers
    panelCollapseAria: "\u0421\u0432\u0435\u0440\u043d\u0443\u0442\u044c/\u0440\u0430\u0437\u0432\u0435\u0440\u043d\u0443\u0442\u044c",
    cidrPlaceholder: "# 0.0.0.0/0 \u2014 \u0432\u0435\u0441\u044c IPv4 (\u043f\u043e\u043b\u043d\u043e\u0435 \u043f\u043e\u043a\u0440\u044b\u0442\u0438\u0435)",
    // Exit-IP
    exitDirect: "\u043f\u0440\u044f\u043c\u043e\u0439 ({ip}) \u2014 \u0434\u043e\u0431\u0430\u0432\u044c api.ipify.org \u0432 VPN-\u0433\u0440\u0443\u043f\u043f\u0443",
    exitError: "\u043e\u0448\u0438\u0431\u043a\u0430",
    exitVpnPrefix: "VPN:",
    // Persist
    persistQuotaError: "\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u0441\u043e\u0445\u0440\u0430\u043d\u0438\u0442\u044c state \u0432 \u0431\u0440\u0430\u0443\u0437\u0435\u0440\u0435 ({name}). \u042d\u043a\u0441\u043f\u043e\u0440\u0442\u0438\u0440\u0443\u0439 state \u0438 \u043e\u0447\u0438\u0441\u0442\u0438 \u0441\u0442\u0430\u0440\u044b\u0435 \u0431\u044d\u043a\u0430\u043f\u044b.",
    // Save & apply stepwise error
    saveApplyFailedStepFmt: "{msg} \u043d\u0430 \u0448\u0430\u0433\u0435 {step}: {err}",
    // Multi-key panel (HTML + JS)
    proxyPanelTitle: "\u041f\u043e\u0434\u043f\u0438\u0441\u043a\u0438 \u0438 \u043a\u043b\u044e\u0447\u0438",
    subsHeading: "\u041f\u043e\u0434\u043f\u0438\u0441\u043a\u0438",
    manualKeysHeading: "\u0420\u0443\u0447\u043d\u044b\u0435 \u043a\u043b\u044e\u0447\u0438",
    activeKeyHeading: "\u0410\u043a\u0442\u0438\u0432\u043d\u044b\u0439 \u043a\u043b\u044e\u0447",
    addManualKeyBtn: "+ \u0420\u0443\u0447\u043d\u043e\u0439 \u043a\u043b\u044e\u0447",
    addSubscriptionBtn: "+ \u041f\u043e\u0434\u043f\u0438\u0441\u043a\u0430",
    probeActiveBtn: "\u041f\u0440\u043e\u0432\u0435\u0440\u0438\u0442\u044c \u0430\u043a\u0442\u0438\u0432\u043d\u044b\u0439",
    manualKeyFormTitleNew: "\u041d\u043e\u0432\u044b\u0439 \u043a\u043b\u044e\u0447",
    manualKeyFormTitleEdit: "\u0420\u0435\u0434\u0430\u043a\u0442\u0438\u0440\u043e\u0432\u0430\u0442\u044c \u043a\u043b\u044e\u0447",
    parseUriBtn: "\u0420\u0430\u0441\u043f\u0430\u0440\u0441\u0438\u0442\u044c URI \u0432 \u043f\u043e\u043b\u044f",
    keyNameLabel: "\u0418\u043c\u044f \u043a\u043b\u044e\u0447\u0430",
    keyNamePlaceholder: "My VPN",
    advancedFieldsSummary: "\u0420\u0430\u0441\u0448\u0438\u0440\u0435\u043d\u043d\u044b\u0435 \u043f\u043e\u043b\u044f (\u0437\u0430\u043f\u043e\u043b\u043d\u044f\u044e\u0442\u0441\u044f \u0430\u0432\u0442\u043e\u043c\u0430\u0442\u0438\u0447\u0435\u0441\u043a\u0438)",
    saveBtn: "\u0421\u043e\u0445\u0440\u0430\u043d\u0438\u0442\u044c",
    cancelBtn: "\u041e\u0442\u043c\u0435\u043d\u0430",
    newSubTitle: "\u041d\u043e\u0432\u0430\u044f \u043f\u043e\u0434\u043f\u0438\u0441\u043a\u0430",
    subNameLabel: "\u0418\u043c\u044f",
    subNamePlaceholder: "My subscription",
    subUrlLabel: "URL (\u0442\u043e\u043b\u044c\u043a\u043e https://)",
    saveSubscriptionBtn: "\u0417\u0430\u0433\u0440\u0443\u0437\u0438\u0442\u044c \u0438 \u0441\u043e\u0445\u0440\u0430\u043d\u0438\u0442\u044c",
    // Cards / status
    manualKeySrc: "\u0440\u0443\u0447\u043d\u043e\u0439",
    keyEditBtn: "\u0418\u0437\u043c.",
    urlHideTitle: "\u0421\u043a\u0440\u044b\u0442\u044c URL",
    urlShowTitle: "\u041f\u043e\u043a\u0430\u0437\u0430\u0442\u044c URL",
    urlCopyTitle: "\u0421\u043a\u043e\u043f\u0438\u0440\u043e\u0432\u0430\u0442\u044c URL",
    subCopiedFmt: "URL \u00ab{name}\u00bb \u0441\u043a\u043e\u043f\u0438\u0440\u043e\u0432\u0430\u043d",
    subCopyManual: "\u0421\u043a\u043e\u043f\u0438\u0440\u0443\u0439 URL \u0432\u0440\u0443\u0447\u043d\u0443\u044e:",
    subNoConfigs: "\u041f\u043e\u0434\u043f\u0438\u0441\u043a\u0430 \u043d\u0435 \u0441\u043e\u0434\u0435\u0440\u0436\u0438\u0442 \u0440\u0430\u0441\u043f\u043e\u0437\u043d\u0430\u043d\u043d\u044b\u0445 \u043a\u043b\u044e\u0447\u0435\u0439",
    subLoading: "\u0417\u0430\u0433\u0440\u0443\u0436\u0430\u044e\u2026",
    subLoadedFmt: "\u0417\u0430\u0433\u0440\u0443\u0436\u0435\u043d\u043e {n} \u043a\u043b\u044e\u0447(\u0435\u0439){errPart}",
    subLoadedErrPart: ", \u043e\u0448\u0438\u0431\u043e\u043a: {n}",
    subKeysNoneAddFirst: "\u0421\u043d\u0430\u0447\u0430\u043b\u0430 \u0434\u043e\u0431\u0430\u0432\u044c \u0445\u043e\u0442\u044f \u0431\u044b \u043e\u0434\u0438\u043d \u043a\u043b\u044e\u0447.",
    keysPluralForms: { one: "\u043a\u043b\u044e\u0447", few: "\u043a\u043b\u044e\u0447\u0430", many: "\u043a\u043b\u044e\u0447\u0435\u0439", other: "\u043a\u043b\u044e\u0447\u0435\u0439" },
    subRefreshBtn: "\u21bb \u041e\u0431\u043d\u043e\u0432\u0438\u0442\u044c",
    subRefreshAddedFmt: "+{n} \u043d\u043e\u0432\u044b\u0445",
    subRefreshKeptFmt: "~{n} \u0431\u0435\u0437 \u0438\u0437\u043c\u0435\u043d\u0435\u043d\u0438\u0439",
    subRefreshRemovedFmt: "\u2212{n} \u0443\u0434\u0430\u043b\u0451\u043d\u043e",
    subRefreshNoChanges: "\u0431\u0435\u0437 \u0438\u0437\u043c\u0435\u043d\u0435\u043d\u0438\u0439",
    manualKeyMissingFmt: "\u041d\u0435 \u0445\u0432\u0430\u0442\u0430\u0435\u0442: {fields}. \u0417\u0430\u043f\u043e\u043b\u043d\u0438 \u043f\u043e\u043b\u044f \u0438\u043b\u0438 \u0432\u0441\u0442\u0430\u0432\u044c vless:// / vmess:// / hysteria2:// URI.",
    fieldAddress: "\u0430\u0434\u0440\u0435\u0441",
    fieldUUID: "UUID",
    fieldPassword: "\u043f\u0430\u0440\u043e\u043b\u044c",
    fieldPortRange: "\u043f\u043e\u0440\u0442 (1..65535)",
    stackSecondsFmt: "{n} \u0441\u0435\u043a",
    subActiveResetToFmt: " \u00b7 \u0430\u043a\u0442\u0438\u0432\u043d\u044b\u0439 \u0441\u0431\u0440\u043e\u0448\u0435\u043d \u043d\u0430 \u00ab{name}\u00bb",
    subActiveResetPlain: " \u00b7 \u0430\u043a\u0442\u0438\u0432\u043d\u044b\u0439 \u0441\u0431\u0440\u043e\u0448\u0435\u043d",
    // last-fetched relative time
    fetchJustNow: "\u0442\u043e\u043b\u044c\u043a\u043e \u0447\u0442\u043e",
    fetchMinAgoFmt: "{n} \u043c\u0438\u043d \u043d\u0430\u0437\u0430\u0434",
    fetchHourAgoFmt: "{n} \u0447 \u043d\u0430\u0437\u0430\u0434",
    fetchDayAgoFmt: "{n} \u0434 \u043d\u0430\u0437\u0430\u0434",
    fetchNever: "\u043d\u0435 \u0437\u0430\u0433\u0440\u0443\u0436\u0430\u043b\u0430\u0441\u044c",
    // login validation
    loginRequiredFill: "\u0417\u0430\u043f\u043e\u043b\u043d\u0438 \u043b\u043e\u0433\u0438\u043d \u0438 \u043f\u0430\u0440\u043e\u043b\u044c",
    repairDone: "\u0420\u0435\u0441\u0442\u0430\u0440\u0442 \u0432\u044b\u043f\u043e\u043b\u043d\u0435\u043d",
    importStateTitle: "\u0417\u0430\u0433\u0440\u0443\u0436\u0430\u0435\u0442 state-\u0444\u0430\u0439\u043b \u0441 \u043f\u0440\u043e\u0444\u0438\u043b\u044f\u043c\u0438 \u0438 \u0433\u0440\u0443\u043f\u043f\u0430\u043c\u0438.",
    exportStateTitle: "\u0421\u043a\u0430\u0447\u0438\u0432\u0430\u0435\u0442 state-\u0444\u0430\u0439\u043b \u0441 \u0442\u0435\u043a\u0443\u0449\u0438\u043c\u0438 \u043f\u0440\u043e\u0444\u0438\u043b\u044f\u043c\u0438 \u0438 \u0433\u0440\u0443\u043f\u043f\u0430\u043c\u0438.",
    saveStateTitle: "\u0421\u043e\u0445\u0440\u0430\u043d\u044f\u0435\u0442 state \u043d\u0430 \u0440\u043e\u0443\u0442\u0435\u0440\u0435 \u0431\u0435\u0437 \u0438\u0437\u043c\u0435\u043d\u0435\u043d\u0438\u044f xray \u0438 \u0431\u0435\u0437 \u043f\u0440\u0438\u043c\u0435\u043d\u0435\u043d\u0438\u044f \u043c\u0430\u0440\u0448\u0440\u0443\u0442\u0438\u0437\u0430\u0446\u0438\u0438.",
    saveApplyTitle: "\u0421\u043e\u0445\u0440\u0430\u043d\u044f\u0435\u0442 state \u043d\u0430 \u0440\u043e\u0443\u0442\u0435\u0440\u0435, \u0433\u0435\u043d\u0435\u0440\u0438\u0440\u0443\u0435\u0442 05_routing.json, \u0434\u0435\u043b\u0430\u0435\u0442 backup \u0438 \u043f\u0435\u0440\u0435\u0437\u0430\u043f\u0443\u0441\u043a\u0430\u0435\u0442 xray.",
    repairTitle: "\u041f\u0435\u0440\u0435\u0441\u043e\u0431\u0438\u0440\u0430\u0435\u0442 runtime XKeen/xray: \u0446\u0435\u043f\u043e\u0447\u043a\u0443 xkeen \u0438 \u043f\u0440\u043e\u0446\u0435\u0441\u0441 xray.",
    importProxyTitle: "\u0412\u0441\u0442\u0430\u0432\u043b\u044f\u0435\u0442 \u043f\u043e\u043b\u044f \u043f\u0440\u043e\u043a\u0441\u0438 \u0438\u0437 \u0441\u0441\u044b\u043b\u043a\u0438 vless://",
    probeProxyTitle: "\u041f\u0440\u043e\u0432\u0435\u0440\u044f\u0435\u0442 \u0441 \u0440\u043e\u0443\u0442\u0435\u0440\u0430, \u0440\u0435\u0437\u043e\u043b\u0432\u0438\u0442\u0441\u044f \u043b\u0438 \u0445\u043e\u0441\u0442 \u0438 \u043e\u0442\u043a\u0440\u044b\u0432\u0430\u0435\u0442\u0441\u044f \u043b\u0438 TCP-\u043f\u043e\u0440\u0442.",
    authRequiredMessage: "\u041d\u0443\u0436\u043d\u0430 \u0430\u043a\u0442\u0438\u0432\u043d\u0430\u044f \u0441\u0435\u0441\u0441\u0438\u044f \u0432 \u0432\u0435\u0431-\u0438\u043d\u0442\u0435\u0440\u0444\u0435\u0439\u0441\u0435 Keenetic. \u0412\u043e\u0439\u0434\u0438 \u0432 \u0432\u0435\u0431-\u043c\u043e\u0440\u0434\u0443 \u0440\u043e\u0443\u0442\u0435\u0440\u0430 \u0438 \u043e\u0431\u043d\u043e\u0432\u0438 \u0441\u0442\u0440\u0430\u043d\u0438\u0446\u0443.",
    authLoginHint: "\u041c\u043e\u0436\u043d\u043e \u0432\u043e\u0439\u0442\u0438 \u043a\u0430\u043a \u0447\u0435\u0440\u0435\u0437 \u0443\u0436\u0435 \u043e\u0442\u043a\u0440\u044b\u0442\u0443\u044e \u0441\u0435\u0441\u0441\u0438\u044e Keenetic, \u0442\u0430\u043a \u0438 \u043d\u0430\u043f\u0440\u044f\u043c\u0443\u044e \u043b\u043e\u0433\u0438\u043d\u043e\u043c \u0438 \u043f\u0430\u0440\u043e\u043b\u0435\u043c \u043e\u0442 \u0432\u0435\u0431-\u043c\u043e\u0440\u0434\u044b.",
    loginImported: "VLESS URL \u0438\u043c\u043f\u043e\u0440\u0442\u0438\u0440\u043e\u0432\u0430\u043d",
    importError: "\u041e\u0448\u0438\u0431\u043a\u0430 \u0438\u043c\u043f\u043e\u0440\u0442\u0430",
    probeAvailable: "TCP {address}:{port} \u0434\u043e\u0441\u0442\u0443\u043f\u0435\u043d{ipPart}",
    probeFailed: "\u041f\u0440\u043e\u0432\u0435\u0440\u043a\u0430 \u043d\u0435 \u043f\u0440\u043e\u0448\u043b\u0430",
    probeError: "\u041e\u0448\u0438\u0431\u043a\u0430 \u043f\u0440\u043e\u0432\u0435\u0440\u043a\u0438",
    invalidLogin: "\u041e\u0448\u0438\u0431\u043a\u0430 \u0432\u0445\u043e\u0434\u0430",
    logoutDone: "\u0421\u0435\u0441\u0441\u0438\u044f \u0437\u0430\u0432\u0435\u0440\u0448\u0435\u043d\u0430. \u0412\u043e\u0439\u0434\u0438 \u0441\u043d\u043e\u0432\u0430 \u043b\u043e\u0433\u0438\u043d\u043e\u043c \u0438 \u043f\u0430\u0440\u043e\u043b\u0435\u043c Keenetic.",
    logoutTitle: "\u0417\u0430\u0432\u0435\u0440\u0448\u0430\u0435\u0442 \u0441\u0435\u0441\u0441\u0438\u044e UI \u0438 \u0432\u043e\u0437\u0432\u0440\u0430\u0449\u0430\u0435\u0442 \u044d\u043a\u0440\u0430\u043d \u0432\u0445\u043e\u0434\u0430.",
    loginRequired: "\u0417\u0430\u043f\u043e\u043b\u043d\u0438 \u043b\u043e\u0433\u0438\u043d \u0438 \u043f\u0430\u0440\u043e\u043b\u044c",
    invalidVlessUrl: "\u041d\u0443\u0436\u043d\u0430 \u0441\u0441\u044b\u043b\u043a\u0430 \u0432\u0438\u0434\u0430 vless://...",
    invalidRealitySecurity: "\u041e\u0436\u0438\u0434\u0430\u043b\u0441\u044f security=reality",
    needOneProfile: "Need at least one profile",
    repairFailed: "Restart failed",
    saveStateFailed: "Save profile failed",
    saveApplyFailed: "Save/apply failed",
    stateFetchFailed: "state fetch failed",
    outboundsFetchFailed: "outbounds fetch failed",
    routerSessionRequired: "router ui authorization required",
    healthKicker: "Состояние",
    healthTitle: "Здоровье и логи",
    healthRefreshBtn: "Обновить",
    healthRunning: "работает",
    healthStopped: "остановлен",
    healthCheckTproxy: "Правило TPROXY в конце mangle PREROUTING",
    healthCheckIpRule: "ip rule с маской 0x111/0x111",
    healthCheckUdpIpset: "ipset xkeen_udp_route существует",
    healthCheckBypassIpset: "ipset xkeen_bypass существует",
    healthCheckPass: "ок",
    healthCheckFail: "сбой",
    healthCheckNa: "не нужно",
    healthFetchFailed: "Не удалось загрузить статус",
    restartXrayBtn: "↻ xray",
    restartSingboxBtn: "↻ sing-box",
    restartSelfhealBtn: "↻ self-heal",
    restartSvcDone: "Перезапуск выполнен",
    restartSvcFailed: "Ошибка перезапуска",
    logsSelectLabel: "Лог",
    logsLinesLabel: "Строк",
    loadLogsBtn: "Загрузить",
    logsLoadFailed: "Не удалось загрузить лог",
    logsEmpty: "(лог пуст)",
    logsCopyBtn: "Скопировать",
    logsCopiedDone: "Скопировано",
    dedupDomainsRemoved: "Убрано лишних доменов: {n} (покрыты родительским)",
    dedupCidrsRemoved: "Убрано лишних IP/CIDR: {n} (покрыты более широкой сетью)",
    stackInfoFetchFailed: "Не удалось загрузить параметры стека",
    stackVersions: "Версии",
    stackXrayVer: "xray", stackSingboxVer: "sing-box", stackKernel: "ядро", stackUptime: "uptime",
    stackVpnSection: "VPN",
    stackVpnHost: "сервер", stackVpnExitIp: "exit IP", stackVpnSni: "Reality SNI",
    stackNetSection: "Сеть",
    stackWanIface: "WAN-интерфейс", stackWanIp: "WAN IP", stackGw: "default gateway", stackLan: "LAN сеть",
    stackXkeenSection: "xkeen",
    stackPolicy: "Keenetic policy", stackMark: "mark", stackTproxyPort: "TPROXY UDP", stackRedirectPort: "REDIRECT TCP", stackSsRelay: "SS-relay",
    stackRuntimeSection: "Runtime",
    stackSelfhealInterval: "интервал self-heal", stackLogRotate: "ротация логов", stackLogRotateValue: "раз в сутки", stackBackupRetention: "хранение бэкапов", stackBackupRetentionValue: "{n} последних копий", stackFdThresh: "FD warn / critical",
    stackResourcesSection: "Ресурсы",
    stackMem: "память", stackDisk: "диск", stackConntrack: "conntrack", stackXrayFd: "xray FD",
    stackCopyHint: "Кликни — скопировать",
    toastSvcRestarting: "Перезапуск {svc}…",
    toastSvcRestarted: "{svc} перезапущен",
    toastSvcRestartFailed: "Ошибка перезапуска {svc}: {error}",
    toastRepairing: "Перестройка runtime…",
    toastSavingState: "Сохранение профиля…",
    toastSavingApplying: "Сохранение и применение…",
    toastProbing: "Проверка {addr}:{port}…",
    toastInvalidDomains: "Удалены не-домены: {list}",
    toastInvalidCidrs: "Удалены не-IP/CIDR: {list}",
    ipsetUdpLabel: "UDP route ipset",
    ipsetBypassLabel: "Bypass ipset"
  },
  en: {
    documentTitle: "AntiGoblin",
    authTitle: "Sign In",
    authLead: "Use your Keenetic web UI username and password to access the panel.",
    authLoginLabel: "Username",
    authPasswordLabel: "Password",
    authSubmit: "Sign in",
    authSubmitting: "Signing in...",
    heroTitle: "XKeen/xray Control Panel",
    heroLead: "Manage profiles, groups, and VLESS config for XKeen/xray in one panel.",
    langLabel: "Language",
    profileKicker: "Profile setup",
    profileTitle: "Profile settings",
    activeProfileLabel: "Active profile",
    profileNameLabel: "Profile name",
    domainStrategyLabel: "Domain strategy",
    fallbackLabel: "Default route",
    trafficTypeLabel: "Direction",
    trafficTypeVpn: "Through VPN",
    trafficTypeBypass: "Outside VPN",
    proxyTitle: "Proxy config",
    proxyUrlLabel: "VLESS URL",
    proxyAddressLabel: "Server",
    proxyPortLabel: "Port",
    muxKicker: "Mux / XUDP",
    muxTitle: "Mux mode",
    muxModeLabel: "Mode",
    muxUdp443Label: "UDP/443",
    muxXudpConcurrencyLabel: "XUDP concurrency",
    muxModeOff: "Off",
    muxModeXudp: "XUDP only",
    previewKicker: "Preview",
    previewTitle: "Generated routing.json",
    groupsKicker: "Groups",
    groupsTitle: "Traffic rules",
    importBtn: "Import",
    exportBtn: "Download",
    repairBtn: "Restart",
    saveApplyBtn: "Save and apply",
    logoutBtn: "Log out",
    addProfileBtn: "New",
    duplicateProfileBtn: "Duplicate",
    removeProfileBtn: "Delete",
    saveStateBtn: "Save",
    importProxyBtn: "Import vless://",
    probeProxyBtn: "Probe",
    addGroupBtn: "Add group",
    profileName: "Profile 1",
    defaultProfileName: "Profile",
    fallbackNote: "Fallback state when live state could not be loaded",
    copied: "Copied",
    imported: "Imported from xray routing",
    noGroups: "No groups yet. Click \"Add group\".",
    newGroup: "New group",
    active: "Active",
    remove: "Delete",
    comment: "Comment",
    commentPlaceholder: "For example: Copilot / Telegram / AI",
    domains: "Domains",
    cidr: "CIDR / IP ranges",
    currentState: "Current router state",
    groups: "Groups",
    activeGroups: "Active",
    vpnDomains: "VPN domains",
    bypassDomains: "Outside VPN",
    cidrShort: "CIDR",
    bypassGroupName: "Outside VPN",
    profileAdded: "New profile",
    profileCopySuffix: " copy",
    saveApplyDone: "Saved and applied",
    saveStateDone: "Profile saved",
    // Subscription form / list / actions
    subUrlEmpty: "URL is empty",
    subUrlNeedHttps: "URL must start with https://",
    subRefreshingFmt: "Refreshing \"{name}\"…",
    subEmpty: "subscription is empty",
    subCancelled: "refresh cancelled (subscription removed)",
    noSubscriptions: "No subscriptions",
    noManualKeys: "No manual keys",
    confirmDeleteKey: "Delete this key?",
    confirmDeleteSubFmt: "Delete subscription \"{name}\" and all its keys?",
    subRevealHint: "Reveal URL — button 👁",
    // UX helpers
    panelCollapseAria: "Collapse/expand",
    cidrPlaceholder: "# 0.0.0.0/0 — entire IPv4 (full coverage)",
    // Exit-IP
    exitDirect: "direct ({ip}) — add api.ipify.org to a VPN group",
    exitError: "error",
    exitVpnPrefix: "VPN:",
    // Persist
    persistQuotaError: "Could not save state in browser ({name}). Export state and clean old backups.",
    // Save & apply stepwise error
    saveApplyFailedStepFmt: "{msg} at step {step}: {err}",
    // Multi-key panel
    proxyPanelTitle: "Subscriptions & keys",
    subsHeading: "Subscriptions",
    manualKeysHeading: "Manual keys",
    activeKeyHeading: "Active key",
    addManualKeyBtn: "+ Manual key",
    addSubscriptionBtn: "+ Subscription",
    probeActiveBtn: "Probe active",
    manualKeyFormTitleNew: "New key",
    manualKeyFormTitleEdit: "Edit key",
    parseUriBtn: "Parse URI into fields",
    keyNameLabel: "Key name",
    keyNamePlaceholder: "My VPN",
    advancedFieldsSummary: "Advanced fields (auto-filled)",
    saveBtn: "Save",
    cancelBtn: "Cancel",
    newSubTitle: "New subscription",
    subNameLabel: "Name",
    subNamePlaceholder: "My subscription",
    subUrlLabel: "URL (https:// only)",
    saveSubscriptionBtn: "Fetch and save",
    manualKeySrc: "manual",
    keyEditBtn: "Edit",
    urlHideTitle: "Hide URL",
    urlShowTitle: "Show URL",
    urlCopyTitle: "Copy URL",
    subCopiedFmt: "URL \"{name}\" copied",
    subCopyManual: "Copy the URL manually:",
    subNoConfigs: "Subscription has no recognisable keys",
    subLoading: "Loading…",
    subLoadedFmt: "Loaded {n} key(s){errPart}",
    subLoadedErrPart: ", errors: {n}",
    subKeysNoneAddFirst: "Add at least one key first.",
    keysPluralForms: { one: "key", other: "keys" },
    subRefreshBtn: "↻ Refresh",
    subRefreshAddedFmt: "+{n} new",
    subRefreshKeptFmt: "~{n} unchanged",
    subRefreshRemovedFmt: "−{n} removed",
    subRefreshNoChanges: "no changes",
    manualKeyMissingFmt: "Missing: {fields}. Fill the fields or paste a vless:// / vmess:// / hysteria2:// URI.",
    fieldAddress: "address",
    fieldUUID: "UUID",
    fieldPassword: "password",
    fieldPortRange: "port (1..65535)",
    stackSecondsFmt: "{n} sec",
    subActiveResetToFmt: " · active reset to \"{name}\"",
    subActiveResetPlain: " · active reset",
    fetchJustNow: "just now",
    fetchMinAgoFmt: "{n} min ago",
    fetchHourAgoFmt: "{n} h ago",
    fetchDayAgoFmt: "{n} d ago",
    fetchNever: "never fetched",
    loginRequiredFill: "Enter both login and password",
    repairDone: "Restart completed",
    importStateTitle: "Load a saved state file with profiles and groups.",
    exportStateTitle: "Download the current state file with profiles and groups.",
    saveStateTitle: "Save state on the router without applying xray changes.",
    saveApplyTitle: "Save state, generate 05_routing.json, back up files, and restart xray.",
    repairTitle: "Rebuild XKeen/xray runtime: xkeen chain and xray process.",
    importProxyTitle: "Fill proxy fields from a vless:// link.",
    probeProxyTitle: "Check from the router whether the host resolves and the TCP port opens.",
    authRequiredMessage: "An active Keenetic web session is required. Sign in to the router web UI and refresh the page.",
    authLoginHint: "You can use either an existing Keenetic web session or sign in here with the same router UI credentials.",
    loginImported: "VLESS URL imported",
    importError: "Import error",
    probeAvailable: "TCP {address}:{port} is reachable{ipPart}",
    probeFailed: "Probe failed",
    probeError: "Probe error",
    invalidLogin: "Sign-in failed",
    logoutDone: "Session ended. Sign in again with your Keenetic credentials.",
    logoutTitle: "Ends the UI session and returns to the sign-in screen.",
    loginRequired: "Enter both username and password",
    invalidVlessUrl: "Expected a vless:// link",
    invalidRealitySecurity: "Expected security=reality",
    needOneProfile: "Need at least one profile",
    repairFailed: "Restart failed",
    saveStateFailed: "Save profile failed",
    saveApplyFailed: "Save/apply failed",
    stateFetchFailed: "state fetch failed",
    outboundsFetchFailed: "outbounds fetch failed",
    routerSessionRequired: "router ui authorization required",
    healthKicker: "Status",
    healthTitle: "Health and logs",
    healthRefreshBtn: "Refresh",
    healthRunning: "running",
    healthStopped: "stopped",
    healthCheckTproxy: "TPROXY rule at end of mangle PREROUTING",
    healthCheckIpRule: "ip rule with mask 0x111/0x111",
    healthCheckUdpIpset: "xkeen_udp_route ipset present",
    healthCheckBypassIpset: "xkeen_bypass ipset present",
    healthCheckPass: "ok",
    healthCheckFail: "fail",
    healthCheckNa: "not needed",
    healthFetchFailed: "Failed to load health status",
    restartXrayBtn: "↻ xray",
    restartSingboxBtn: "↻ sing-box",
    restartSelfhealBtn: "↻ self-heal",
    restartSvcDone: "Restart done",
    restartSvcFailed: "Restart failed",
    logsSelectLabel: "Log",
    logsLinesLabel: "Lines",
    loadLogsBtn: "Load",
    logsLoadFailed: "Failed to load log",
    logsEmpty: "(log file is empty)",
    logsCopyBtn: "Copy",
    logsCopiedDone: "Copied",
    dedupDomainsRemoved: "Removed redundant domains: {n} (covered by a parent domain)",
    dedupCidrsRemoved: "Removed redundant IP/CIDR: {n} (covered by a broader network)",
    stackInfoFetchFailed: "Failed to load stack info",
    stackVersions: "Versions",
    stackXrayVer: "xray", stackSingboxVer: "sing-box", stackKernel: "kernel", stackUptime: "uptime",
    stackVpnSection: "VPN",
    stackVpnHost: "server", stackVpnExitIp: "exit IP", stackVpnSni: "Reality SNI",
    stackNetSection: "Network",
    stackWanIface: "WAN interface", stackWanIp: "WAN IP", stackGw: "default gateway", stackLan: "LAN net",
    stackXkeenSection: "xkeen",
    stackPolicy: "Keenetic policy", stackMark: "mark", stackTproxyPort: "TPROXY UDP", stackRedirectPort: "REDIRECT TCP", stackSsRelay: "SS-relay",
    stackRuntimeSection: "Runtime",
    stackSelfhealInterval: "self-heal interval", stackLogRotate: "log rotation", stackLogRotateValue: "once a day", stackBackupRetention: "backup retention", stackBackupRetentionValue: "last {n} files", stackFdThresh: "FD warn / critical",
    stackResourcesSection: "Resources",
    stackMem: "memory", stackDisk: "disk", stackConntrack: "conntrack", stackXrayFd: "xray FD",
    stackCopyHint: "Click to copy",
    toastSvcRestarting: "Restarting {svc}…",
    toastSvcRestarted: "{svc} restarted",
    toastSvcRestartFailed: "Failed to restart {svc}: {error}",
    toastRepairing: "Rebuilding runtime…",
    toastSavingState: "Saving profile…",
    toastSavingApplying: "Saving and applying…",
    toastProbing: "Probing {addr}:{port}…",
    toastInvalidDomains: "Removed non-domain entries: {list}",
    toastInvalidCidrs: "Removed non-IP/CIDR entries: {list}",
    ipsetUdpLabel: "UDP route ipset",
    ipsetBypassLabel: "Bypass ipset"
  }
};

let currentLang = localStorage.getItem(LANGUAGE_KEY) || "ru";
if (!LOCALES[currentLang]) currentLang = "ru";
let T = LOCALES[currentLang];
let AUTH_REQUIRED_MESSAGE = T.authRequiredMessage;
let AUTH_LOGIN_HINT = T.authLoginHint;

const debugState = { messages: [] };

const fallbackState = {
  activeProfileId: "profile-main",
  profiles: [
    {
      id: "profile-main",
      name: T.profileName,
      domainStrategy: "IPIfNonMatch",
      fallbackOutbound: "direct",
      proxyConfig: createDefaultProxyConfig(),
      muxConfig: createDefaultMuxConfig(),
      groups: [
        {
          id: "fallback-vpn",
          name: "VPN",
          note: T.fallbackNote,
          enabled: true,
          outboundTag: "vless-reality",
          domains: [],
          cidrs: []
        },
        {
          id: "fallback-bypass",
          name: T.bypassGroupName,
          note: "",
          enabled: true,
          outboundTag: "bypass",
          domains: [],
          cidrs: []
        }
      ]
    }
  ]
};

let state = null;

const els = {
  authOverlay: document.getElementById("authOverlay"),
  authTitle: document.getElementById("authTitle"),
  authLead: document.getElementById("authLead"),
  authLoginLabel: document.getElementById("authLoginLabel"),
  authPasswordLabel: document.getElementById("authPasswordLabel"),
  authLogin: document.getElementById("authLogin"),
  authPassword: document.getElementById("authPassword"),
  authStatus: document.getElementById("authStatus"),
  authSubmitBtn: document.getElementById("authSubmitBtn"),
  langLabel: document.getElementById("langLabel"),
  langSelect: document.getElementById("langSelect"),
  heroTitle: document.getElementById("heroTitle"),
  heroLead: document.getElementById("heroLead"),
  profileKicker: document.getElementById("profileKicker"),
  profileTitle: document.getElementById("profileTitle"),
  activeProfileLabel: document.getElementById("activeProfileLabel"),
  profileNameLabel: document.getElementById("profileNameLabel"),
  activeProfile: document.getElementById("activeProfile"),
  profileName: document.getElementById("profileName"),
  domainStrategyLabel: document.getElementById("domainStrategyLabel"),
  domainStrategy: document.getElementById("domainStrategy"),
  fallbackLabel: document.getElementById("fallbackLabel"),
  fallbackOutbound: document.getElementById("fallbackOutbound"),
  proxyTitle: document.getElementById("proxyTitle"),
  proxyUrlLabel: document.getElementById("proxyUrlLabel"),
  proxyAddressLabel: document.getElementById("proxyAddressLabel"),
  proxyPortLabel: document.getElementById("proxyPortLabel"),
  proxyAddress: document.getElementById("proxyAddress"),
  proxyPort: document.getElementById("proxyPort"),
  proxyUuid: document.getElementById("proxyUuid"),
  proxyFlow: document.getElementById("proxyFlow"),
  proxyPublicKey: document.getElementById("proxyPublicKey"),
  proxyServerName: document.getElementById("proxyServerName"),
  proxyShortId: document.getElementById("proxyShortId"),
  proxyFingerprint: document.getElementById("proxyFingerprint"),
  muxKicker: document.getElementById("muxKicker"),
  muxTitle: document.getElementById("muxTitle"),
  muxSummary: document.getElementById("muxSummary"),
  muxModeLabel: document.getElementById("muxModeLabel"),
  muxMode: document.getElementById("muxMode"),
  muxUdp443Label: document.getElementById("muxUdp443Label"),
  muxUdp443: document.getElementById("muxUdp443"),
  muxXudpConcurrencyLabel: document.getElementById("muxXudpConcurrencyLabel"),
  muxXudpConcurrency: document.getElementById("muxXudpConcurrency"),
  proxyImportUrl: document.getElementById("proxyImportUrl"),
  importProxyBtn: document.getElementById("importProxyBtn"),
  probeProxyBtn: document.getElementById("probeProxyBtn"),
  proxyProbeStatus: document.getElementById("proxyProbeStatus"),
  addManualKeyBtn: document.getElementById("addManualKeyBtn"),
  addSubscriptionBtn: document.getElementById("addSubscriptionBtn"),
  subscriptionsList: document.getElementById("subscriptionsList"),
  manualKeysList: document.getElementById("manualKeysList"),
  activeProxyList: document.getElementById("activeProxyList"),
  manualKeyForm: document.getElementById("manualKeyForm"),
  manualKeyFormTitle: document.getElementById("manualKeyFormTitle"),
  manualKeyName: document.getElementById("manualKeyName"),
  saveManualKeyBtn: document.getElementById("saveManualKeyBtn"),
  cancelManualKeyBtn: document.getElementById("cancelManualKeyBtn"),
  subscriptionForm: document.getElementById("subscriptionForm"),
  newSubscriptionName: document.getElementById("newSubscriptionName"),
  newSubscriptionUrl: document.getElementById("newSubscriptionUrl"),
  subscriptionFormStatus: document.getElementById("subscriptionFormStatus"),
  saveSubscriptionBtn: document.getElementById("saveSubscriptionBtn"),
  cancelSubscriptionBtn: document.getElementById("cancelSubscriptionBtn"),
  subsHeading: document.getElementById("subsHeading"),
  manualKeysHeading: document.getElementById("manualKeysHeading"),
  activeKeyHeading: document.getElementById("activeKeyHeading"),
  keyNameLabelSpan: document.getElementById("keyNameLabelSpan"),
  advancedFieldsSummary: document.getElementById("advancedFieldsSummary"),
  newSubTitle: document.getElementById("newSubTitle"),
  subNameLabelSpan: document.getElementById("subNameLabelSpan"),
  subUrlLabelSpan: document.getElementById("subUrlLabelSpan"),
  addManualKeyBtn: document.getElementById("addManualKeyBtn"),
  addSubscriptionBtn: document.getElementById("addSubscriptionBtn"),
  previewKicker: document.getElementById("previewKicker"),
  previewTitle: document.getElementById("previewTitle"),
  groups: document.getElementById("groups"),
  stats: document.getElementById("stats"),
  preview: document.getElementById("routingPreview"),
  groupsKicker: document.getElementById("groupsKicker"),
  groupsTitle: document.getElementById("groupsTitle"),
  addGroupBtn: document.getElementById("addGroupBtn"),
  addProfileBtn: document.getElementById("addProfileBtn"),
  duplicateProfileBtn: document.getElementById("duplicateProfileBtn"),
  removeProfileBtn: document.getElementById("removeProfileBtn"),
  exportStateBtn: document.getElementById("exportStateBtn"),
  repairRuntimeBtn: document.getElementById("repairRuntimeBtn"),
  logoutBtn: document.getElementById("logoutBtn"),
  importStateBtn: document.getElementById("importStateBtn"),
  importStateInput: document.getElementById("importStateInput"),
  saveStateBtn: document.getElementById("saveStateBtn"),
  saveApplyBtn: document.getElementById("saveApplyBtn"),
  healthKicker: document.getElementById("healthKicker"),
  healthTitle: document.getElementById("healthTitle"),
  refreshHealthBtn: document.getElementById("refreshHealthBtn"),
  healthBadges: document.getElementById("healthBadges"),
  exitIpRow: document.getElementById("exitIpRow"),
  healthChecks: document.getElementById("healthChecks"),
  stackInfo: document.getElementById("stackInfo"),
  restartXrayBtn: document.getElementById("restartXrayBtn"),
  restartSingboxBtn: document.getElementById("restartSingboxBtn"),
  restartSelfhealBtn: document.getElementById("restartSelfhealBtn"),
  logsSelectLabel: document.getElementById("logsSelectLabel"),
  logsSelect: document.getElementById("logsSelect"),
  logsLinesLabel: document.getElementById("logsLinesLabel"),
  logsLinesSelect: document.getElementById("logsLinesSelect"),
  loadLogsBtn: document.getElementById("loadLogsBtn"),
  logsPreview: document.getElementById("logsPreview"),
  logsPreviewWrap: document.getElementById("logsPreviewWrap"),
  logsCopyBtn: document.getElementById("logsCopyBtn")
};

window.addEventListener("error", (event) => {
  pushDebug(`window.error: ${event.message}`);
});

window.addEventListener("unhandledrejection", (event) => {
  pushDebug(`unhandledrejection: ${String(event.reason)}`);
});

bindTopLevel();
setupPanelCollapse();
bootstrap();

function setupPanelCollapse() {
  const panels = document.querySelectorAll(".panel");
  panels.forEach((panel, idx) => {
    const header = panel.querySelector(".panel-header");
    if (!header) return;
    if (header.querySelector(".panel-collapse-toggle")) return;
    const id = panel.dataset.panelId || `panel-${idx}`;
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "panel-collapse-toggle";
    btn.setAttribute("aria-expanded", "true");
    header.insertBefore(btn, header.firstChild);
    const saved = localStorage.getItem(`panel-collapsed-${id}`);
    btn.setAttribute("aria-label", T.panelCollapseAria);
    const apply = (collapsed) => {
      panel.classList.toggle("collapsed", collapsed);
      btn.setAttribute("aria-expanded", String(!collapsed));
    };
    apply(saved === "1");
    btn.addEventListener("click", (event) => {
      event.stopPropagation();
      const next = !panel.classList.contains("collapsed");
      apply(next);
      localStorage.setItem(`panel-collapsed-${id}`, next ? "1" : "0");
    });
  });
}

async function bootstrap() {
  try {
    state = await loadRemoteState();
    await hydrateProxyConfigFromRemote();
    pushDebug(`loaded live state: profiles=${state.profiles.length}, activeGroups=${getActiveProfile()?.groups?.length ?? 0}`);
    hideAuthOverlay();
    persistAndRender();
    renderHealth().catch(() => {});
    renderStackInfo().catch(() => {});
    startExitIpCheck();
  } catch (error) {
    pushDebug(`bootstrap failed: ${error.message}`);
    if (isAuthError(error)) {
      state = cloneFallback();
      render();
      showAuthOverlay(T.authLoginHint);
      return;
    }
    const saved = loadState();
    if (saved) {
      const savedProfile = (saved.profiles || []).find((profile) => profile.id === saved.activeProfileId) || saved.profiles?.[0];
      pushDebug(`loaded from localStorage after live failure: profiles=${saved.profiles?.length ?? 0}, activeGroups=${savedProfile?.groups?.length ?? 0}`);
      state = saved;
      render();
      return;
    }

    state = cloneFallback();
    persistAndRender();
  }
}

function bindTopLevel() {
  if (els.langSelect) {
    els.langSelect.value = currentLang;
    els.langSelect.addEventListener("change", () => {
      currentLang = LOCALES[els.langSelect.value] ? els.langSelect.value : "ru";
      localStorage.setItem(LANGUAGE_KEY, currentLang);
      T = LOCALES[currentLang];
      AUTH_REQUIRED_MESSAGE = T.authRequiredMessage;
      AUTH_LOGIN_HINT = T.authLoginHint;
      render();
      // render() re-renders profile/proxies/groups/preview but not the
      // health and stack-info panels — those pull from the router and
      // are refreshed on their own cadence. Kick a redraw so the running
      // /stopped badges, section titles and value labels flip languages
      // instead of showing yesterday's locale until the next probe.
      renderHealth().catch(() => {});
      renderStackInfo().catch(() => {});
    });
  }

  els.authSubmitBtn.addEventListener("click", async () => {
    const previous = els.authSubmitBtn.textContent;
    els.authSubmitBtn.disabled = true;
    els.authSubmitBtn.textContent = T.authSubmitting;
    setAuthStatus("info", "");
    try {
      await loginToRouter(els.authLogin.value, els.authPassword.value);
      els.authPassword.value = "";
      await bootstrap();
    } catch (error) {
      // Only the status-badge — showAuthOverlay would overwrite the
      // authLead hint with the same error, showing the text twice.
      setAuthStatus("error", error.message || T.invalidLogin);
    } finally {
      els.authSubmitBtn.disabled = false;
      els.authSubmitBtn.textContent = previous;
    }
  });

  els.authPassword.addEventListener("keydown", async (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      els.authSubmitBtn.click();
    }
  });

  els.authLogin.addEventListener("keydown", async (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      els.authSubmitBtn.click();
    }
  });

  els.importStateBtn.title = T.importStateTitle;
  els.exportStateBtn.title = T.exportStateTitle;
  els.saveStateBtn.title = T.saveStateTitle;
  els.saveApplyBtn.title = T.saveApplyTitle;
  els.repairRuntimeBtn.title = T.repairTitle;
  els.importProxyBtn.title = T.importProxyTitle;
  els.probeProxyBtn.title = T.probeProxyTitle;
  els.logoutBtn.title = T.logoutTitle;

  els.logoutBtn.addEventListener("click", async () => {
    try {
      await logoutFromRouter();
    } catch (error) {
      pushDebug(`logout failed: ${error.message}`);
    }
    // Stop background polling — after logout every CGI call will 401,
    // and the visibilitychange listener would keep re-triggering it.
    if (exitIpTimer) { clearInterval(exitIpTimer); exitIpTimer = null; }
    lastKnownVpnIp = null;
    EXIT_IP_LOG.length = 0;
    if (els.exitIpRow) els.exitIpRow.innerHTML = "";
    state = cloneFallback();
    render();
    showAuthOverlay(T.logoutDone);
  });

  els.activeProfile.addEventListener("change", () => {
    state.activeProfileId = els.activeProfile.value;
    persistAndRender();
  });

  els.profileName.addEventListener("input", () => {
    const profile = getActiveProfile();
    if (!profile) return;
    profile.name = els.profileName.value;
    persistState();
    renderProfiles();
    els.activeProfile.value = state.activeProfileId || "";
  });

  els.domainStrategy.addEventListener("change", () => {
    const profile = getActiveProfile();
    if (!profile) return;
    profile.domainStrategy = els.domainStrategy.value;
    persistState();
    renderPreview();
  });

  els.fallbackOutbound.addEventListener("change", () => {
    const profile = getActiveProfile();
    if (!profile) return;
    profile.fallbackOutbound = els.fallbackOutbound.value;
    persistState();
    renderPreview();
  });

  bindProxyField(els.proxyAddress, "address");
  bindProxyField(els.proxyPort, "port", (value) => sanitizeProxyPort(value));
  bindProxyField(els.proxyUuid, "uuid");
  bindProxyField(els.proxyFlow, "flow");
  bindProxyField(els.proxyPublicKey, "publicKey");
  bindProxyField(els.proxyServerName, "serverName");
  bindProxyField(els.proxyShortId, "shortId");
  bindProxyField(els.proxyFingerprint, "fingerprint");
  bindMuxField(els.muxMode, "mode");
  bindMuxField(els.muxUdp443, "xudpProxyUDP443");
  // Concurrency: validate on `change` (blur / commit), not on every keystroke.
  // Otherwise clampInt turns "70000" into "1024" mid-typing and the cursor
  // jumps to the end. Same reason we can't clear the field to retype it.
  bindMuxField(els.muxXudpConcurrency, "xudpConcurrency", (value) => clampInt(value, 8, 1, 1024), "change");

  els.importProxyBtn.addEventListener("click", () => {
    const raw = (els.proxyImportUrl.value || "").trim();
    const profile = getActiveProfile();
    if (!profile) return;

    // Multi-protocol: vmess and hysteria2 don't fit the legacy "fill form
    // fields" flow (their schemas differ), so we add them directly as a
    // proxy entry and close the form.
    let parsed = null;
    if (/^(hysteria2|hy2):\/\//i.test(raw)) parsed = parseHysteria2Uri(raw);
    else if (/^vmess:\/\//i.test(raw)) parsed = parseVmessUri(raw);

    if (parsed) {
      if (!parsed.ok) {
        setProbeStatus("error", `${T.importError || "Import error"}: ${parsed.error}`);
        return;
      }
      const name = (els.manualKeyName?.value || "").trim() || parsed.config.name || parsed.config.address;
      profile.proxies = profile.proxies || [];
      if (editingProxyId) {
        // Edit-mode: patch the existing key instead of pushing a duplicate.
        // Symmetric with the vless flow below (which fills form fields
        // that saveManualKey then commits to the existing entry).
        const existing = profile.proxies.find((p) => p.id === editingProxyId);
        if (existing) {
          existing.name = name;
          existing.config = parsed.config;
        }
      } else {
        const newProxy = {
          id: `proxy-${newId()}`,
          name,
          source: "manual",
          config: parsed.config
        };
        profile.proxies.push(newProxy);
        if (!profile.activeProxyId) profile.activeProxyId = newProxy.id;
      }
      // Import committed the buffer — don't let closeManualKeyForm revert.
      manualKeyFormSnapshot = null;
      closeManualKeyForm();
      persistState();
      renderProxiesPanel(profile);
      return;
    }

    // Vless URL that didn't hit the multi-key path above: use the same
    // wider parser (parseVlessUri) so vless-tls / vless-none also work
    // from the manual form, not only through subscription.
    const vlessParsed = parseVlessUri(raw);
    if (!vlessParsed.ok) {
      setProbeStatus("error", `${T.importError || "Ошибка импорта"}: ${vlessParsed.error}`);
      return;
    }
    profile.proxyConfig = {
      ...normalizeProxyConfig(profile.proxyConfig),
      ...vlessParsed.config
    };
    persistState();
    renderProxyConfig(profile);
    setProbeStatus("success", T.loginImported);
  });

  els.probeProxyBtn.addEventListener("click", async () => {
    const profile = getActiveProfile();
    if (!profile) return;
    const config = getActiveProxyConfig(profile);
    els.probeProxyBtn.disabled = true;
    const toast = showToast(formatMessage(T.toastProbing || "Проверка {addr}:{port}...", { addr: config.address, port: config.port }), { kind: "progress" });
    try {
      const probe = await probeProxy(config);
      if (probe.ok) {
        const ipPart = probe.resolvedIp ? `, IP ${probe.resolvedIp}` : "";
        toast.update(formatMessage(T.probeAvailable, { address: probe.address, port: probe.port, ipPart }), "success");
      } else {
        toast.update(probe.error || T.probeFailed, "error");
      }
    } catch (error) {
      toast.update(`${T.probeError}: ${error.message}`, "error");
    } finally {
      els.probeProxyBtn.disabled = false;
    }
  });

  // --- Multi-key UI wiring ---

  if (els.addManualKeyBtn) {
    els.addManualKeyBtn.addEventListener("click", () => openManualKeyForm(null));
  }
  if (els.addSubscriptionBtn) {
    els.addSubscriptionBtn.addEventListener("click", () => openSubscriptionForm());
  }
  if (els.cancelManualKeyBtn) {
    els.cancelManualKeyBtn.addEventListener("click", () => closeManualKeyForm());
  }
  if (els.saveManualKeyBtn) {
    els.saveManualKeyBtn.addEventListener("click", () => saveManualKey());
  }
  if (els.cancelSubscriptionBtn) {
    els.cancelSubscriptionBtn.addEventListener("click", () => closeSubscriptionForm());
  }
  if (els.saveSubscriptionBtn) {
    els.saveSubscriptionBtn.addEventListener("click", () => saveSubscription());
  }

  if (els.subscriptionsList) {
    els.subscriptionsList.addEventListener("click", (event) => {
      const btn = event.target.closest("button[data-act]");
      if (!btn) return;
      const id = btn.dataset.id;
      switch (btn.dataset.act) {
        case "refresh-sub": refreshSubscription(id); break;
        case "delete-sub":  deleteSubscription(id); break;
        case "reveal-sub":  toggleRevealSub(id); break;
        case "copy-sub":    copySubUrl(id); break;
      }
    });
  }

  if (els.manualKeysList) {
    els.manualKeysList.addEventListener("click", (event) => {
      const btn = event.target.closest("button[data-act]");
      if (!btn) return;
      const id = btn.dataset.id;
      if (btn.dataset.act === "edit-proxy") openManualKeyForm(id);
      else if (btn.dataset.act === "delete-proxy") deleteProxy(id);
    });
  }

  if (els.activeProxyList) {
    els.activeProxyList.addEventListener("click", (event) => {
      const row = event.target.closest(".active-row");
      if (!row) return;
      const proxyId = row.dataset.proxyId;
      if (proxyId) setActiveProxy(proxyId);
    });
    // Keyboard nav on the radios (Tab + arrow keys) fires `change` but
    // not `click`, so without this handler a keyboard-only user could
    // never switch the active key — the next re-render would reset the
    // visual selection back to the persisted activeProxyId.
    els.activeProxyList.addEventListener("change", (event) => {
      const target = event.target;
      if (target && target.matches && target.matches('input[type="radio"][name="activeProxy"]')) {
        setActiveProxy(target.value);
      }
    });
  }

  els.addGroupBtn.addEventListener("click", () => {
    const profile = getActiveProfile();
    if (!profile) return;
    profile.groups.unshift(createEmptyGroup());
    persistAndRender();
  });

  els.addProfileBtn.addEventListener("click", () => {
    const profile = createEmptyProfile(T.profileAdded);
    state.profiles.push(profile);
    state.activeProfileId = profile.id;
    persistAndRender();
  });

  els.duplicateProfileBtn.addEventListener("click", () => {
    const profile = getActiveProfile();
    if (!profile) return;
    const copy = cloneProfile(profile);
    copy.id = newId();
    copy.name = `${profile.name || T.defaultProfileName}${T.profileCopySuffix}`;
    copy.groups = copy.groups.map((group) => ({ ...group, id: newId() }));
    state.profiles.push(copy);
    state.activeProfileId = copy.id;
    persistAndRender();
  });

  els.removeProfileBtn.addEventListener("click", () => {
    if ((state.profiles || []).length <= 1) {
      alert(T.needOneProfile);
      return;
    }
    state.profiles = state.profiles.filter((profile) => profile.id !== state.activeProfileId);
    state.activeProfileId = state.profiles[0].id;
    persistAndRender();
  });

  els.exportStateBtn.addEventListener("click", () => {
    const profile = getActiveProfile();
    downloadJson(`${slugify(profile?.name || "xkeen")}-state.json`, state);
  });

  if (els.refreshHealthBtn) {
    els.refreshHealthBtn.addEventListener("click", async () => {
      els.refreshHealthBtn.disabled = true;
      try {
        await Promise.all([
          renderHealth().catch(() => {}),
          renderStackInfo().catch(() => {})
        ]);
      } finally {
        els.refreshHealthBtn.disabled = false;
      }
    });
  }
  for (const [btn, svc, label] of [
    [els.restartXrayBtn, "xray", "xray"],
    [els.restartSingboxBtn, "singbox", "sing-box"],
    [els.restartSelfhealBtn, "selfheal", "self-heal"]
  ]) {
    if (!btn) continue;
    btn.title = formatMessage(T.toastSvcRestarting || "Restart {svc}", { svc: label });
    btn.addEventListener("click", async () => {
      btn.disabled = true;
      const toast = showToast(formatMessage(T.toastSvcRestarting || "Перезапуск {svc}...", { svc: label }), { kind: "progress" });
      try {
        await restartService(svc);
        toast.update(formatMessage(T.toastSvcRestarted || "{svc} перезапущен", { svc: label }), "success");
        // Same anti-pattern as saveApply had: awaiting health+stack refresh
        // in the try keeps the button greyed-out for up to ~40s after the
        // success toast if either CGI stalls to its timeout. Re-enable now
        // and refresh the panels fire-and-forget.
        btn.disabled = false;
        renderHealth().catch(() => {});
        renderStackInfo().catch(() => {});
        return;
      } catch (error) {
        toast.update(formatMessage(T.toastSvcRestartFailed || "Ошибка перезапуска {svc}: {error}", { svc: label, error: error.message }), "error");
      } finally {
        btn.disabled = false;
      }
    });
  }
  if (els.logsCopyBtn) {
    els.logsCopyBtn.addEventListener("click", async () => {
      const text = els.logsPreview ? (els.logsPreview.textContent || "") : "";
      if (!text.trim()) return;
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          await navigator.clipboard.writeText(text);
        } else {
          const ta = document.createElement("textarea");
          ta.value = text;
          ta.setAttribute("readonly", "");
          ta.style.position = "absolute";
          ta.style.left = "-9999px";
          document.body.appendChild(ta);
          ta.select();
          document.execCommand("copy");
          document.body.removeChild(ta);
        }
        const previous = els.logsCopyBtn.textContent;
        els.logsCopyBtn.classList.add("copied");
        els.logsCopyBtn.textContent = T.logsCopiedDone || "Скопировано";
        setTimeout(() => {
          els.logsCopyBtn.classList.remove("copied");
          els.logsCopyBtn.textContent = previous;
        }, 1500);
      } catch (_e) {
        /* noop */
      }
    });
  }
  if (els.loadLogsBtn) {
    els.loadLogsBtn.addEventListener("click", async () => {
      const svc = els.logsSelect ? els.logsSelect.value : "selfheal";
      const lines = els.logsLinesSelect ? els.logsLinesSelect.value : "100";
      els.loadLogsBtn.disabled = true;
      const previous = els.loadLogsBtn.textContent;
      els.loadLogsBtn.textContent = `${previous}...`;
      try {
        const text = await fetchLogs(svc, lines);
        els.logsPreview.textContent = text && text.trim() ? text : T.logsEmpty;
        if (els.logsPreviewWrap) els.logsPreviewWrap.hidden = false;
      } catch (error) {
        els.logsPreview.textContent = `${T.logsLoadFailed}: ${error.message}`;
        if (els.logsPreviewWrap) els.logsPreviewWrap.hidden = false;
      } finally {
        els.loadLogsBtn.textContent = previous;
        els.loadLogsBtn.disabled = false;
      }
    });
  }

  els.repairRuntimeBtn.addEventListener("click", async () => {
    els.repairRuntimeBtn.disabled = true;
    const toast = showToast(T.toastRepairing || "Перестройка runtime...", { kind: "progress" });
    try {
      await repairRemoteRuntime();
      toast.update(T.repairDone, "success");
      els.repairRuntimeBtn.disabled = false;
      renderHealth().catch(() => {});
      renderStackInfo().catch(() => {});
      return;
    } catch (error) {
      if (isAuthError(error)) showAuthOverlay(AUTH_LOGIN_HINT);
      toast.update(`${T.repairFailed}: ${error.message}`, "error");
    } finally {
      els.repairRuntimeBtn.disabled = false;
    }
  });

  els.importStateBtn.addEventListener("click", () => els.importStateInput.click());

  els.importStateInput.addEventListener("change", async (event) => {
    const file = event.target.files?.[0];
    if (!file) return;
    const text = await file.text();
    state = normalizeState(JSON.parse(text));
    pushDebug(`imported state: profiles=${state.profiles.length}, activeGroups=${getActiveProfile()?.groups?.length ?? 0}`);
    persistAndRender();
    event.target.value = "";
  });

  els.saveStateBtn.addEventListener("click", async () => {
    els.saveStateBtn.disabled = true;
    const toast = showToast(T.toastSavingState || "Сохранение профиля...", { kind: "progress" });
    try {
      await saveRemoteState();
      persistState();
      toast.update(T.saveStateDone, "success");
    } catch (error) {
      if (isAuthError(error)) showAuthOverlay(AUTH_LOGIN_HINT);
      toast.update(`${T.saveStateFailed}: ${error.message}`, "error");
    } finally {
      els.saveStateBtn.disabled = false;
    }
  });

  els.saveApplyBtn.addEventListener("click", async () => {
    els.saveApplyBtn.disabled = true;
    const toast = showToast(T.toastSavingApplying || "Сохранение и применение...", { kind: "progress" });
    // Save is a 4-step pipeline. Each step can partially succeed on the
    // router; if step 3 fails, step 1+2 already committed. Tag the current
    // step so the user sees WHICH one failed, not a generic "Save failed".
    let step = "state";
    try {
      step = "state";       await saveRemoteState();
      step = "outbounds";   await saveRemoteOutbounds();
      step = "sing-box";    await saveRemoteSingbox();
      step = "routing";
      // Routing apply is the heaviest CGI call in the pipeline: validate the
      // whole confdir with `xray -test`, then a graceful xray restart (up to
      // ~8s waiting for the old PID + ~12s polling :61219 to come back up).
      // Under a busy apply lock or slow flash it can push past the 20s
      // default. 45s comfortably covers a real restart while still cutting
      // in well before uhttpd's own `-t 120` timeout.
      const routingResponse = await fetchWithTimeout(LIVE_ROUTING_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=utf-8" },
        body: JSON.stringify(buildRoutingDocument(getActiveProfile()))
      }, 45000);
      await parseResponseOrThrow(routingResponse);
      step = "done";
      persistState();
      // Active key / VPN host might have changed by this apply; drop
      // cached exit-IP so the next tick can re-detect.
      lastKnownVpnIp = null;
      EXIT_IP_LOG.length = 0;
      toast.update(T.saveApplyDone, "success");
      // Re-enable Save & Apply BEFORE health/stack refreshes — otherwise
      // if both /health and /stack-info stall on their 20s timeouts the
      // user sits with a greyed-out button for ~40s after the toast
      // already said success, and thinks the apply is still in flight.
      els.saveApplyBtn.disabled = false;
      renderHealth().catch(() => {});
      renderStackInfo().catch(() => {});
      return;
    } catch (error) {
      if (isAuthError(error)) showAuthOverlay(AUTH_LOGIN_HINT);
      const stepLabel = step === "state" ? "state" :
                        step === "outbounds" ? "outbounds" :
                        step === "sing-box" ? "sing-box" :
                        "routing";
      toast.update(formatMessage(T.saveApplyFailedStepFmt, { msg: T.saveApplyFailed, step: stepLabel, err: error.message }), "error");
      pushDebug(`saveApply failed at step=${step}: ${error.message}`);
    } finally {
      els.saveApplyBtn.disabled = false;
    }
  });
}

async function saveRemoteState() {
  const stateResponse = await fetchWithTimeout(STATE_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8"
    },
    body: JSON.stringify(state)
  });
  await parseResponseOrThrow(stateResponse);
}

async function saveRemoteOutbounds() {
  const profile = getActiveProfile();
  if (!profile) throw new Error("active profile missing");
  const outboundsResponse = await fetchWithTimeout(OUTBOUNDS_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8"
    },
    body: JSON.stringify(buildOutboundsDocument(profile))
  });
  await parseResponseOrThrow(outboundsResponse);
}

async function saveRemoteSingbox() {
  const profile = getActiveProfile();
  if (!profile) throw new Error("active profile missing");
  const response = await fetchWithTimeout(SINGBOX_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8"
    },
    body: JSON.stringify(buildSingboxDocument(profile))
  });
  await parseResponseOrThrow(response);
}

async function repairRemoteRuntime() {
  const response = await fetchWithTimeout(REPAIR_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8"
    },
    body: "{}"
  });
  await parseResponseOrThrow(response);
}

function healthSeverity(status) {
  if (!status || status === "ok") return "ok";
  if (status.endsWith("_critical") || status === "xray_down") return "critical";
  if (status.endsWith("_warn")) return "warn";
  return "ok";
}

function fdSeverity(fd, limit) {
  if (!fd || !limit) return "ok";
  if (fd >= 600) return "critical";
  if (fd >= 400) return "warn";
  return "ok";
}

function ctSeverity(count, max) {
  if (!max) return "ok";
  const pct = (count / max) * 100;
  if (pct >= 95) return "critical";
  if (pct >= 85) return "warn";
  return "ok";
}

function vpnSeverity(established, finWait, orphanFin) {
  if (orphanFin >= 30 || finWait >= 50) return "critical";
  if (orphanFin >= 20 || finWait >= 20) return "warn";
  if (established === 0) return "warn";
  return "ok";
}

function severityClass(sev) {
  if (sev === "critical") return "health-bad";
  if (sev === "warn") return "health-warn";
  return "health-ok";
}

async function renderHealth() {
  if (!els.healthBadges || !els.healthChecks) return;
  els.healthBadges.innerHTML = '<div class="health-loading">…</div>';
  els.healthChecks.innerHTML = "";
  let payload;
  try {
    payload = await fetchHealth();
  } catch (error) {
    els.healthBadges.innerHTML = `<div class="health-error">${escapeHtml(T.healthFetchFailed)}: ${escapeHtml(error.message)}</div>`;
    return;
  }
  const services = payload.services || {};
  const checks = payload.checks || {};
  const sizes = payload.ipsetSize || {};
  const fd = payload.xrayFd || {};
  const ct = payload.conntrack || {};
  const vpn = payload.vpnTunnel || {};
  const overallStatus = payload.healthStatus || "ok";
  const overallSev = healthSeverity(overallStatus);

  // Overall status banner (only shown when not ok)
  let bannerHtml = "";
  if (overallSev !== "ok") {
    const bannerClass = overallSev === "critical" ? "health-banner-critical" : "health-banner-warn";
    bannerHtml = `<div class="health-banner ${bannerClass}"><span class="health-banner-icon">${overallSev === "critical" ? "✗" : "!"}</span> ${escapeHtml(overallStatus)}</div>`;
  }

  // Service badges
  const fdSev = fdSeverity(fd.count, fd.limit);
  const fdLabel = fd.limit ? `FD ${fd.count}/${fd.limit}` : "";

  const badges = [
    { name: "xray", svc: services.xray, sev: services.xray?.running ? (fdSev !== "ok" ? fdSev : "ok") : "critical", extras: [
      services.xray?.listenTcp ? "tcp 61219" : null,
      services.xray?.listenRelayUdp ? "relay 62640" : null,
      fdLabel || null
    ] },
    { name: "sing-box", svc: services.singbox, sev: services.singbox?.running ? "ok" : "critical", extras: [
      services.singbox?.listenUdp ? "udp 61221" : null
    ] },
    { name: "self-heal", svc: services.selfheal, sev: services.selfheal?.running ? "ok" : "critical", extras: [] }
  ];

  const badgesHtml = badges.map((item) => {
    if (!item.svc) {
      return `<div class="health-badge health-bad"><span class="health-dot" aria-hidden="true"></span><span class="health-text"><span class="health-name">${escapeHtml(item.name)}</span><span class="health-status">?</span></span></div>`;
    }
    const cls = severityClass(item.sev);
    const status = item.svc.running ? T.healthRunning : T.healthStopped;
    const pid = item.svc.pid ? `<span class="health-pid">pid ${escapeHtml(String(item.svc.pid))}</span>` : "";
    const extras = item.extras.filter(Boolean).map((x) => `<span class="health-extra">${escapeHtml(x)}</span>`).join("");
    return `<div class="health-badge ${cls}">
      <span class="health-dot" aria-hidden="true"></span>
      <span class="health-text">
        <span class="health-name">${escapeHtml(item.name)}</span>
        <span class="health-status">${escapeHtml(status)}</span>
      </span>
      ${pid}
      ${extras ? `<span class="health-extra">${extras}</span>` : ""}
    </div>`;
  }).join("");

  // VPN tunnel block
  const vpnSev = vpnSeverity(vpn.established || 0, vpn.finWait || 0, vpn.orphanFin || 0);
  const vpnCls = severityClass(vpnSev);
  const vpnHtml = `<div class="health-badge ${vpnCls}">
    <span class="health-dot" aria-hidden="true"></span>
    <span class="health-text">
      <span class="health-name">VPN tunnel</span>
      <span class="health-status">${escapeHtml(vpn.host || "—")}</span>
    </span>
    <span class="health-extra health-metric ${vpn.established > 0 ? "" : "metric-warn"}">upstream TCP: ${vpn.established || 0}</span>
    ${(vpn.finWait || 0) > 0 ? `<span class="health-extra health-metric ${(vpn.finWait || 0) >= 20 ? "metric-warn" : ""}">FIN_WAIT: ${vpn.finWait}</span>` : ""}
    ${(vpn.orphanFin || 0) > 0 ? `<span class="health-extra health-metric ${(vpn.orphanFin || 0) >= 20 ? "metric-crit" : ""}">orphan FIN: ${vpn.orphanFin}</span>` : ""}
  </div>`;

  // Conntrack block
  const ctSev = ctSeverity(ct.count || 0, ct.max || 0);
  const ctCls = severityClass(ctSev);
  const ctPct = ct.max ? Math.round((ct.count / ct.max) * 100) : null;
  const ctHtml = `<div class="health-badge ${ctCls}">
    <span class="health-dot" aria-hidden="true"></span>
    <span class="health-text">
      <span class="health-name">conntrack</span>
      <span class="health-status">${ct.count || 0}${ct.max ? ` / ${ct.max}` : ""}</span>
    </span>
    ${ctPct !== null ? `<span class="health-extra">${ctPct}%</span>` : ""}
  </div>`;

  els.healthBadges.innerHTML = bannerHtml + badgesHtml + vpnHtml + ctHtml;

  // checks.* is a tri-state string: "ok" | "fail" | "na". Legacy backend
  // returned booleans (true/false) — normalize them so the UI works
  // against both old and new backends while a rolling upgrade is in
  // progress.
  const normStatus = (v) => {
    if (v === true) return "ok";
    if (v === false) return "fail";
    if (v === "ok" || v === "fail" || v === "na") return v;
    return "fail";
  };
  const checkRows = [
    { label: T.healthCheckTproxy, status: normStatus(checks.tproxyRuleAtEnd) },
    { label: T.healthCheckIpRule, status: normStatus(checks.ipRuleMasked) },
    { label: T.healthCheckUdpIpset, status: normStatus(checks.udpIpsetExists),
      extra: sizes.udpRoute != null ? `${sizes.udpRoute} ${T.cidrShort}` : null },
    { label: T.healthCheckBypassIpset, status: normStatus(checks.bypassIpsetExists),
      extra: sizes.bypass != null ? `${sizes.bypass} ${T.cidrShort}` : null }
  ];
  els.healthChecks.innerHTML = checkRows.map((row) => {
    const cls = { ok: "check-ok", fail: "check-bad", na: "check-na" }[row.status];
    const mark = { ok: "✓", fail: "✗", na: "—" }[row.status];
    const text = { ok: T.healthCheckPass, fail: T.healthCheckFail, na: T.healthCheckNa || "не требуется" }[row.status];
    const extra = row.extra ? escapeHtml(row.extra) : "";
    return `<div class="check-row ${cls}"><span class="check-mark">${mark}</span><span class="check-label">${escapeHtml(row.label)}</span><span class="check-extra">${extra}</span><span class="check-status">${escapeHtml(text)}</span></div>`;
  }).join("");
}

// Exit IP check — runs every 60s, logs last 20 results
const EXIT_IP_LOG = [];
const EXIT_IP_MAX_LOG = 20;
let exitIpTimer = null;
let lastKnownVpnIp = null;

async function checkExitIp() {
  if (!els.exitIpRow) return;
  const ts = new Date().toLocaleTimeString();
  let ip = null;
  let err = null;
  try {
    const res = await fetchWithTimeout("https://api.ipify.org?format=json", { cache: "no-cache" }, 8000);
    const json = await res.json();
    ip = json.ip || null;
  } catch (e) {
    err = e.message || "timeout";
  }

  // Resolve VPN server IP from stack-info cache if available
  if (!lastKnownVpnIp) {
    try {
      const si = await fetchWithTimeout(STACK_INFO_URL, { cache: "no-store" }, 8000).then(r => r.json());
      lastKnownVpnIp = si?.vpn?.exitIp || null;
    } catch (_) {}
  }

  const entry = { ts, ip, err };
  EXIT_IP_LOG.unshift(entry);
  if (EXIT_IP_LOG.length > EXIT_IP_MAX_LOG) EXIT_IP_LOG.pop();

  renderExitIpRow();
}

function renderExitIpRow() {
  if (!els.exitIpRow) return;
  const latest = EXIT_IP_LOG[0];
  if (!latest) { els.exitIpRow.innerHTML = ""; return; }

  const isVpn = lastKnownVpnIp && latest.ip && latest.ip === lastKnownVpnIp;
  const isErr = !!latest.err;
  const isDirect = !isErr && !isVpn && lastKnownVpnIp;

  const statusCls = isErr ? "exit-ip-err" : isVpn ? "exit-ip-vpn" : isDirect ? "exit-ip-direct" : "exit-ip-unknown";
  const statusIcon = isErr ? "✗" : isVpn ? "✓" : isDirect ? "!" : "?";
  const statusText = isErr ? `${T.exitError}: ${latest.err}` : isVpn ? `${T.exitVpnPrefix.replace(/:$/, "")} (${latest.ip})` : isDirect ? formatMessage(T.exitDirect, { ip: latest.ip }) : (latest.ip || "—");

  const logRows = EXIT_IP_LOG.map((e, i) => {
    const cls = e.err ? "exit-log-err" : (lastKnownVpnIp && e.ip === lastKnownVpnIp) ? "exit-log-vpn" : (lastKnownVpnIp && e.ip) ? "exit-log-direct" : "";
    const dot = e.err ? "✗" : (lastKnownVpnIp && e.ip === lastKnownVpnIp) ? "✓" : "!";
    return `<div class="exit-log-row ${cls}"><span class="exit-log-dot">${dot}</span><span class="exit-log-ts">${escapeHtml(e.ts)}</span><span class="exit-log-ip">${escapeHtml(e.ip || e.err || "—")}</span></div>`;
  }).join("");

  els.exitIpRow.innerHTML = `
    <div class="exit-ip-header">
      <div class="exit-ip-current ${statusCls}">
        <span class="exit-ip-icon">${statusIcon}</span>
        <span class="exit-ip-label">exit IP</span>
        <span class="exit-ip-value">${escapeHtml(statusText)}</span>
        <span class="exit-ip-time">${escapeHtml(latest.ts)}</span>
      </div>
      ${lastKnownVpnIp ? `<span class="exit-ip-expected">${escapeHtml(T.exitVpnPrefix)} ${escapeHtml(lastKnownVpnIp)}</span>` : ""}
    </div>
    ${EXIT_IP_LOG.length > 1 ? `<div class="exit-ip-log">${logRows}</div>` : ""}
  `;
}

let exitIpVisibilityBound = false;
function startExitIpCheck() {
  // bootstrap() runs on every fresh load AND every re-login. Without clearing
  // the previous interval, each re-login adds another checkExitIp() timer —
  // the request rate grows over time and health-check pressure on the CGI
  // increases each cycle.
  if (exitIpTimer) clearInterval(exitIpTimer);
  // Reset cached VPN exit-IP so a profile switch / re-login doesn't keep
  // the previous session's IP as "known" and mislabel new checks.
  lastKnownVpnIp = null;
  EXIT_IP_LOG.length = 0;
  checkExitIp();
  exitIpTimer = setInterval(() => {
    // Skip while the tab is hidden — no point burning a third-party fetch
    // and a CGI health-check every minute for a panel nobody's looking at.
    if (document.hidden) return;
    checkExitIp();
  }, 60000);
  // When the user returns to the tab, refresh immediately instead of
  // waiting up to a minute for the next tick.
  if (!exitIpVisibilityBound) {
    exitIpVisibilityBound = true;
    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) checkExitIp();
    });
  }
}

async function fetchStackInfo() {
  const response = await fetchWithTimeout(STACK_INFO_URL, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(response.status === 401 ? AUTH_REQUIRED_MESSAGE : `HTTP ${response.status}`);
  }
  return response.json();
}

const toastState = { container: null, nextId: 0, items: new Map() };

function ensureToastContainer() {
  if (toastState.container && document.body.contains(toastState.container)) return toastState.container;
  const el = document.createElement("div");
  el.className = "toast-container";
  document.body.appendChild(el);
  toastState.container = el;
  return el;
}

function showToast(text, opts) {
  opts = opts || {};
  const kind = opts.kind || "info";
  const id = ++toastState.nextId;
  const persistent = kind === "progress" || opts.persistent === true;
  const ttl = opts.ttl != null ? opts.ttl : 3200;

  const container = ensureToastContainer();
  const node = document.createElement("div");
  node.className = `toast toast-${kind}`;
  node.innerHTML = `<span class="toast-icon" aria-hidden="true"></span><span class="toast-text"></span>`;
  node.querySelector(".toast-text").textContent = text;
  container.appendChild(node);

  let timer;
  let currentKind = kind;
  const dismiss = () => {
    if (timer) clearTimeout(timer);
    node.classList.add("toast-dismissing");
    setTimeout(() => { node.remove(); toastState.items.delete(id); }, 220);
  };
  const handle = {
    id,
    update(newText, newKind) {
      if (newText != null) node.querySelector(".toast-text").textContent = newText;
      if (newKind && newKind !== currentKind) {
        node.classList.remove(`toast-${currentKind}`);
        node.classList.add(`toast-${newKind}`);
        currentKind = newKind;
        if (newKind !== "progress") {
          if (timer) clearTimeout(timer);
          timer = setTimeout(dismiss, ttl);
        }
      }
    },
    dismiss
  };
  toastState.items.set(id, handle);
  if (!persistent) timer = setTimeout(dismiss, ttl);
  node.addEventListener("click", dismiss);
  return handle;
}

function fmtUptime(sec) {
  if (!sec || sec < 0) return "—";
  const d = Math.floor(sec / 86400);
  const h = Math.floor((sec % 86400) / 3600);
  const m = Math.floor((sec % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

function fmtBytesKb(kb) {
  if (!kb || kb <= 0) return "—";
  if (kb >= 1024 * 1024) return `${(kb / 1024 / 1024).toFixed(1)} GB`;
  if (kb >= 1024) return `${(kb / 1024).toFixed(0)} MB`;
  return `${kb} KB`;
}
function fmtKbPair(used, total) {
  if (!total || total <= 0) return "—";
  if (total >= 1024 * 1024) return `${(used / 1024 / 1024).toFixed(1)} / ${(total / 1024 / 1024).toFixed(1)} GB`;
  if (total >= 1024) return `${Math.round(used / 1024)} / ${Math.round(total / 1024)} MB`;
  return `${used} / ${total} KB`;
}

async function renderStackInfo() {
  if (!els.stackInfo) return;
  let payload;
  try {
    payload = await fetchStackInfo();
  } catch (error) {
    els.stackInfo.innerHTML = `<div class="health-error">${escapeHtml(T.stackInfoFetchFailed || "Failed to load stack info")}: ${escapeHtml(error.message)}</div>`;
    return;
  }
  const v = payload.versions || {};
  const vpn = payload.vpn || {};
  const net = payload.network || {};
  const xk = payload.xkeen || {};
  const rt = payload.runtime || {};
  const r = payload.resources || {};

  const policyLabel = xk.policyDescription
    ? `${xk.policyName || "?"} · ${xk.policyDescription}`
    : (xk.policyName || "—");
  const memTxt = (r.memAvailKb && r.memTotalKb)
    ? fmtKbPair(r.memTotalKb - r.memAvailKb, r.memTotalKb)
    : "—";
  const diskTxt = (r.diskAvailKb && r.diskTotalKb)
    ? fmtKbPair(r.diskUsedKb || 0, r.diskTotalKb)
    : "—";
  const ctTxt = r.conntrackMax ? `${r.conntrackCount} / ${r.conntrackMax}` : "—";
  const fdTxt = r.xrayFdLimit ? `${r.xrayFd} / ${r.xrayFdLimit}` : "—";

  const sections = [
    {
      title: T.stackVersions || "Версии",
      rows: [
        [T.stackXrayVer || "xray", v.xray || "—"],
        [T.stackSingboxVer || "sing-box", v.singbox || "—"],
        [T.stackKernel || "ядро", `${v.kernel || ""} (${v.hostname || ""})`.trim()],
        [T.stackUptime || "uptime", fmtUptime(v.uptimeSec)]
      ]
    },
    {
      title: T.stackVpnSection || "VPN",
      rows: [
        [T.stackVpnHost || "сервер", vpn.host ? `${vpn.host}:${vpn.port}` : "—"],
        [T.stackVpnExitIp || "exit IP", vpn.exitIp || "—"],
        [T.stackVpnSni || "Reality SNI", vpn.sni || "—"]
      ]
    },
    {
      title: T.stackNetSection || "Сеть",
      rows: [
        [T.stackWanIface || "WAN-интерфейс", net.wanIface || "—"],
        [T.stackWanIp || "WAN IP", net.wanIp || "—"],
        [T.stackGw || "Default gateway", net.gateway || "—"],
        [T.stackLan || "LAN сеть", net.lanNet || "—"]
      ]
    },
    {
      title: T.stackXkeenSection || "xkeen",
      rows: [
        [T.stackPolicy || "policy", policyLabel],
        [T.stackMark || "mark", xk.mark ? `0x${xk.mark}` : "—"],
        [T.stackTproxyPort || "TPROXY UDP", String(xk.tproxyUdp || "—")],
        [T.stackRedirectPort || "REDIRECT TCP", String(xk.redirectTcp || "—")],
        [T.stackSsRelay || "SS-relay", xk.ssRelay || "—"]
      ]
    },
    {
      title: T.stackRuntimeSection || "Runtime",
      rows: [
        [T.stackSelfhealInterval || "self-heal интервал", formatMessage(T.stackSecondsFmt || "{n} sec", { n: rt.selfhealIntervalSec || 0 })],
        [T.stackLogRotate || "ротация логов", T.stackLogRotateValue || "раз в сутки"],
        [T.stackBackupRetention || "хранение бэкапов", formatMessage(T.stackBackupRetentionValue || "{n} последних копий", { n: rt.backupRetention || 0 })],
        [T.stackFdThresh || "FD warn / critical", `${rt.fdWarn || 0} / ${rt.fdCritical || 0}`]
      ]
    },
    {
      title: T.stackResourcesSection || "Ресурсы",
      rows: [
        [T.stackMem || "память", memTxt],
        [T.stackDisk || "диск", diskTxt, r.diskMount || null],
        [T.stackConntrack || "conntrack", ctTxt],
        [T.stackXrayFd || "xray FD", fdTxt]
      ]
    }
  ];

  els.stackInfo.innerHTML = sections.map((section) => `
    <div class="stack-section">
      <div class="stack-section-title">${escapeHtml(section.title)}</div>
      <dl class="stack-dl">
        ${section.rows.map((row) => {
          const k = row[0];
          const v = row[1];
          const note = row[2];
          const noteHtml = note ? `<small>${escapeHtml(String(note))}</small>` : "";
          return `<dt>${escapeHtml(k)}</dt><dd><span class="stack-value" title="${escapeHtml(T.stackCopyHint || "Кликни — скопировать")}">${escapeHtml(String(v))}</span>${noteHtml}</dd>`;
        }).join("")}
      </dl>
    </div>
  `).join("");

  els.stackInfo.querySelectorAll(".stack-value").forEach((node) => {
    node.addEventListener("click", async () => {
      const text = node.textContent || "";
      if (!text || text === "—") return;
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          await navigator.clipboard.writeText(text);
        }
        const original = node.textContent;
        node.classList.add("stack-value-copied");
        node.textContent = T.logsCopiedDone || "Скопировано";
        setTimeout(() => {
          node.classList.remove("stack-value-copied");
          node.textContent = original;
        }, 1100);
      } catch (_e) { /* noop */ }
    });
  });
}

async function fetchHealth() {
  const response = await fetchWithTimeout(HEALTH_URL, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(response.status === 401 ? AUTH_REQUIRED_MESSAGE : `HTTP ${response.status}`);
  }
  return response.json();
}

async function fetchLogs(svc, lines) {
  const url = `${LOGS_URL}&svc=${encodeURIComponent(svc)}&n=${encodeURIComponent(lines)}`;
  const response = await fetchWithTimeout(url, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(response.status === 401 ? AUTH_REQUIRED_MESSAGE : `HTTP ${response.status}`);
  }
  return response.text();
}

async function restartService(svc) {
  const response = await fetchWithTimeout(RESTART_SVC_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({ svc })
  });
  return await parseResponseOrThrow(response);
}

async function probeProxy(config) {
  const response = await fetchWithTimeout(PROBE_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8"
    },
    body: JSON.stringify({
      address: config.address,
      port: Number(config.port)
    })
  });
  return await parseResponseOrThrow(response);
}

async function loginToRouter(login, password) {
  const safeLogin = String(login || "").trim();
  const safePassword = String(password || "");
  if (!safeLogin || !safePassword) {
    throw new Error(T.loginRequiredFill || "Enter both login and password");
  }

  const response = await fetchWithTimeout(LOGIN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8"
    },
    body: JSON.stringify({
      loginB64: encodeBase64Unicode(safeLogin),
      passwordB64: encodeBase64Unicode(safePassword)
    })
  });
  return await parseResponseOrThrow(response);
}

async function logoutFromRouter() {
  const response = await fetchWithTimeout(LOGOUT_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8"
    },
    body: "{}"
  });
  return await parseResponseOrThrow(response);
}

function render() {
  if (!state) return;
  applyTranslations();
  renderProfiles();
  const profile = getActiveProfile();
  if (!profile) return;
  els.profileName.value = profile.name;
  els.domainStrategy.value = profile.domainStrategy;
  els.fallbackOutbound.value = profile.fallbackOutbound;
  renderProxyConfig(profile);
  renderProxiesPanel(profile);

  renderGroups();
  renderPreview();
}

function renderProfiles() {
  const profiles = state.profiles || [];
  els.activeProfile.innerHTML = "";
  for (const profile of profiles) {
    const option = document.createElement("option");
    option.value = profile.id;
    option.textContent = profile.name;
    els.activeProfile.appendChild(option);
  }

  if (!profiles.some((profile) => profile.id === state.activeProfileId) && profiles[0]) {
    state.activeProfileId = profiles[0].id;
  }
  els.activeProfile.value = state.activeProfileId || "";
}

// UI-only state: which group cards the user has expanded. Not persisted
// in state.json — kept in a module-level Map so add/remove/duplicate a
// group doesn't collapse all previously-expanded cards.
const groupExpanded = new Map();

function renderGroups() {
  const profile = getActiveProfile();
  els.groups.innerHTML = "";

  if (!profile || !Array.isArray(profile.groups) || !profile.groups.length) {
    els.groups.innerHTML = `<div class="empty-box">${escapeHtml(T.noGroups)}</div>`;
    pushDebug("renderGroups: empty");
    return;
  }

  for (const group of profile.groups) {
    const card = document.createElement("article");
    card.className = "group-card";
    card.innerHTML = `
      <div class="group-head">
        <div class="group-head-main">
          <button class="collapse-toggle" type="button" aria-expanded="true">▾</button>
          <input class="group-name" type="text" placeholder="${escapeHtml(T.newGroup)}">
        </div>
        <div class="group-head-actions">
          <label class="toggle">
            <input class="group-enabled" type="checkbox">
            <span>${escapeHtml(T.active)}</span>
          </label>
          <button class="danger remove-group" type="button">${escapeHtml(T.remove)}</button>
        </div>
      </div>
      <div class="group-body">
        <div class="grid two">
          <label>
            <span>${escapeHtml(T.trafficTypeLabel)}</span>
            <select class="group-outbound">
              <option value="vless-reality">${escapeHtml(T.trafficTypeVpn)}</option>
              <option value="bypass">${escapeHtml(T.trafficTypeBypass)}</option>
            </select>
          </label>
          <label>
            <span>${escapeHtml(T.comment)}</span>
            <input class="group-note" type="text" placeholder="${escapeHtml(T.commentPlaceholder)}">
          </label>
        </div>
        <div class="grid two">
          <label>
            <span>${escapeHtml(T.domains)}</span>
            <textarea class="group-domains" rows="9" placeholder="chatgpt.com&#10;openai.com"></textarea>
          </label>
          <label>
            <span>${escapeHtml(T.cidr)}</span>
            <textarea class="group-cidrs" rows="9" placeholder="${escapeHtml("140.82.112.0/20\n20.199.39.0/24\n\n" + (T.cidrPlaceholder || "# 0.0.0.0/0 — full IPv4 catch-all"))}"></textarea>
          </label>
        </div>
      </div>
    `;

    const collapseBtn = card.querySelector(".collapse-toggle");
    const bodyEl = card.querySelector(".group-body");
    const nameEl = card.querySelector(".group-name");
    const noteEl = card.querySelector(".group-note");
    const enabledEl = card.querySelector(".group-enabled");
    const outboundEl = card.querySelector(".group-outbound");
    const domainsEl = card.querySelector(".group-domains");
    const cidrsEl = card.querySelector(".group-cidrs");
    const removeBtn = card.querySelector(".remove-group");

    // Restore expanded/collapsed state per group id so re-render (from
    // add/remove/rename group) doesn't collapse everything again.
    let collapsed = !groupExpanded.get(group.id);
    const setCollapsed = (value) => {
      collapsed = value;
      groupExpanded.set(group.id, !collapsed);
      card.classList.toggle("collapsed", collapsed);
      bodyEl.hidden = collapsed;
      collapseBtn.textContent = collapsed ? "▸" : "▾";
      collapseBtn.setAttribute("aria-expanded", String(!collapsed));
    };

    nameEl.value = group.name;
    noteEl.value = group.note || "";
    enabledEl.checked = group.enabled;
    outboundEl.value = group.outboundTag;
    domainsEl.value = group.domains.join("\n");
    cidrsEl.value = group.cidrs.join("\n");

    collapseBtn.addEventListener("click", () => setCollapsed(!collapsed));
    nameEl.addEventListener("input", () => updateGroup(group.id, { name: nameEl.value }));
    noteEl.addEventListener("input", () => updateGroup(group.id, { note: noteEl.value }));
    enabledEl.addEventListener("change", () => updateGroup(group.id, { enabled: enabledEl.checked }));
    outboundEl.addEventListener("change", () => updateGroup(group.id, { outboundTag: outboundEl.value }));
    domainsEl.addEventListener("input", () => updateGroup(group.id, { domains: splitLinesOrCsv(domainsEl.value) }));
    cidrsEl.addEventListener("input", () => updateGroup(group.id, { cidrs: splitLinesOrCsv(cidrsEl.value) }));
    domainsEl.addEventListener("blur", () => {
      const raw = splitLinesOrCsv(domainsEl.value);
      const part = partitionList(raw, looksLikeDomain);
      const after = dedupeDomainsList(part.valid);
      const dedupRemoved = part.valid.length - after.length;
      const changed = (after.length !== raw.length) || part.invalid.length > 0;
      if (changed) {
        domainsEl.value = after.join("\n");
        updateGroup(group.id, { domains: after });
        if (part.invalid.length > 0) {
          showToast(
            formatMessage(T.toastInvalidDomains || "Удалены не-домены: {list}", { list: part.invalid.slice(0, 3).join(", ") + (part.invalid.length > 3 ? "…" : "") }),
            { kind: "error", ttl: 4500 }
          );
        }
        if (dedupRemoved > 0) {
          showFieldFlash(domainsEl, formatMessage(T.dedupDomainsRemoved, { n: dedupRemoved }));
        }
      }
    });
    cidrsEl.addEventListener("blur", () => {
      const raw = splitLinesOrCsv(cidrsEl.value);
      const part = partitionList(raw, looksLikeIpOrCidr);
      const after = dedupeCidrsList(part.valid);
      const dedupRemoved = part.valid.length - after.length;
      const changed = (after.length !== raw.length) || part.invalid.length > 0;
      if (changed) {
        cidrsEl.value = after.join("\n");
        updateGroup(group.id, { cidrs: after });
        if (part.invalid.length > 0) {
          showToast(
            formatMessage(T.toastInvalidCidrs || "Удалены не-IP/CIDR: {list}", { list: part.invalid.slice(0, 3).join(", ") + (part.invalid.length > 3 ? "…" : "") }),
            { kind: "error", ttl: 4500 }
          );
        }
        if (dedupRemoved > 0) {
          showFieldFlash(cidrsEl, formatMessage(T.dedupCidrsRemoved, { n: dedupRemoved }));
        }
      }
    });
    removeBtn.addEventListener("click", () => {
      profile.groups = profile.groups.filter((item) => item.id !== group.id);
      groupExpanded.delete(group.id);
      persistAndRender();
    });

    // Apply the persisted state (default collapsed for a brand-new group).
    setCollapsed(collapsed);

    els.groups.appendChild(card);
  }
}

function renderPreview() {
  const profile = getActiveProfile();
  if (!profile) return;
  const routing = buildRoutingDocument(profile);
  els.preview.textContent = JSON.stringify(routing, null, 2);

  const activeGroups = profile.groups.filter((group) => group.enabled);
  const bypassGroups = activeGroups.filter((group) => group.outboundTag === "bypass" || group.outboundTag === "direct");
  const vpnGroups = activeGroups.filter((group) => group.outboundTag !== "bypass" && group.outboundTag !== "direct");

  const bypassDomainCount = uniq(bypassGroups.flatMap((group) => group.domains)).length;
  const vpnDomainCount = uniq(vpnGroups.flatMap((group) => group.domains)).length;
  const cidrCount = uniq(activeGroups.flatMap((group) => group.cidrs)).length;

  els.stats.innerHTML = [
    statPill(`${T.groups}: ${profile.groups.length}`),
    statPill(`${T.activeGroups}: ${activeGroups.length}`),
    statPill(`${T.vpnDomains}: ${vpnDomainCount}`),
    statPill(`${T.bypassDomains}: ${bypassDomainCount}`),
    statPill(`${T.cidrShort}: ${cidrCount}`)
  ].join("");
}

function buildRoutingDocument(inputState) {
  const inboundTags = ["redirect"];
  const rules = [];
  rules.push({
    type: "field",
    inboundTag: ["proxy-relay-ss"],
    outboundTag: "vless-reality"
  });
  rules.push({
    type: "field",
    inboundTag: ["socks-in"],
    outboundTag: "vless-reality"
  });

  for (const group of inputState.groups.filter((item) => item.enabled && item.outboundTag !== "direct" && item.outboundTag !== "bypass")) {
    const domains = uniq(group.domains);
    const cidrs = uniq(group.cidrs);

    // Catch-all: "0.0.0.0/0" (весь IPv4) или пустая группа означают
    // "весь трафик через этот outbound". В xray это правило без ip/domain
    // фильтра. Гарантирует что пустая группа vless-reality не превращается
    // в тихий no-op.
    const isCatchAll = cidrs.includes("0.0.0.0/0") || (!domains.length && !cidrs.length);
    if (isCatchAll) {
      rules.push({
        type: "field",
        inboundTag: inboundTags,
        outboundTag: group.outboundTag
      });
      continue;
    }

    if (domains.length) {
      rules.push({
        type: "field",
        inboundTag: inboundTags,
        domain: domains,
        outboundTag: group.outboundTag
      });
    }

    if (cidrs.length) {
      rules.push({
        type: "field",
        inboundTag: inboundTags,
        ip: cidrs,
        outboundTag: group.outboundTag
      });
    }
  }

  rules.push({
    type: "field",
    inboundTag: inboundTags,
    outboundTag: inputState.fallbackOutbound || "direct"
  });

  return {
    routing: {
      domainStrategy: inputState.domainStrategy || "IPIfNonMatch",
      rules
    }
  };
}

function updateGroup(id, patch) {
  const profile = getActiveProfile();
  if (!profile) return;
  profile.groups = profile.groups.map((group) => group.id === id ? { ...group, ...patch } : group);
  persistState();
  renderPreview();
}

function persistAndRender() {
  persistState();
  render();
}

let persistQuotaWarned = false;
function persistState() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    persistQuotaWarned = false;
  } catch (error) {
    // QuotaExceededError, SecurityError (Safari private mode), etc. Drop
    // the write but keep in-memory state alive. Warn once so the user
    // knows their state is not being persisted — otherwise a tab reload
    // silently loses everything since last successful save.
    if (!persistQuotaWarned) {
      persistQuotaWarned = true;
      try {
        showToast(formatMessage(T.persistQuotaError, { name: (error && error.name) || "storage error" }), { kind: "error", ttl: 8000 });
      } catch { /* toast may not be ready yet */ }
      pushDebug(`persistState failed: ${error && error.message}`);
    }
  }
}

function loadState() {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) return null;

  try {
    return normalizeState(JSON.parse(raw));
  } catch (error) {
    pushDebug(`loadState failed: ${error.message}`);
    return null;
  }
}

async function loadRemoteState() {
  const response = await fetchWithTimeout(STATE_URL, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(response.status === 401 ? AUTH_REQUIRED_MESSAGE : `state fetch failed: ${response.status}`);
  }
  return normalizeState(parseJsonText(await response.text()));
}

async function loadRemoteOutbounds() {
  const response = await fetchWithTimeout(OUTBOUNDS_URL, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(response.status === 401 ? AUTH_REQUIRED_MESSAGE : `outbounds fetch failed: ${response.status}`);
  }
  return parseJsonText(await response.text());
}

function isAuthError(error) {
  const message = String(error?.message || "");
  return /\b401\b/.test(message) || message.includes("router ui authorization required") || message.includes(AUTH_REQUIRED_MESSAGE);
}

// Auth-overlay focus trap and Escape handling. Both listeners are scoped
// to the overlay element itself (not the document) so they can't interfere
// with future modals that might want their own Escape/Tab behaviour.
let authKeydownHandler = null;

function _authFocusables() {
  const card = els.authOverlay && els.authOverlay.querySelector(".auth-card");
  if (!card) return [];
  return Array.from(card.querySelectorAll(
    'input:not([disabled]):not([type="hidden"]), button:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
  ));
}

function showAuthOverlay(message = AUTH_LOGIN_HINT) {
  if (!els.authOverlay) return;
  els.authOverlay.hidden = false;
  els.authOverlay.setAttribute("aria-modal", "true");
  els.authOverlay.setAttribute("role", "dialog");
  els.authOverlay.setAttribute("tabindex", "-1");
  els.authLead.textContent = message || AUTH_LOGIN_HINT;
  if (!els.authLogin.value) {
    els.authLogin.value = "admin";
  }
  setAuthStatus("info", "");
  setTimeout(() => els.authLogin.focus(), 0);
  if (!authKeydownHandler) {
    authKeydownHandler = (event) => {
      if (event.key === "Escape") {
        if (els.authPassword) els.authPassword.value = "";
        setAuthStatus("info", "");
        event.preventDefault();
        return;
      }
      if (event.key !== "Tab") return;
      const focusables = _authFocusables();
      if (focusables.length === 0) return;
      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        last.focus();
        event.preventDefault();
      } else if (!event.shiftKey && document.activeElement === last) {
        first.focus();
        event.preventDefault();
      }
    };
    els.authOverlay.addEventListener("keydown", authKeydownHandler);
  }
}

function hideAuthOverlay() {
  if (!els.authOverlay) return;
  els.authOverlay.hidden = true;
  els.authOverlay.removeAttribute("aria-modal");
  els.authOverlay.removeAttribute("role");
  els.authOverlay.removeAttribute("tabindex");
  setAuthStatus("info", "");
  if (authKeydownHandler) {
    els.authOverlay.removeEventListener("keydown", authKeydownHandler);
    authKeydownHandler = null;
  }
}

function setAuthStatus(kind, message) {
  if (!els.authStatus) return;
  if (!message) {
    els.authStatus.hidden = true;
    els.authStatus.textContent = "";
    els.authStatus.className = "probe-status";
    return;
  }
  els.authStatus.hidden = false;
  els.authStatus.className = `probe-status ${kind === "error" ? "error" : kind === "success" ? "success" : ""}`.trim();
  els.authStatus.textContent = message;
}

async function hydrateProxyConfigFromRemote() {
  try {
    const remoteOutbounds = await loadRemoteOutbounds();
    const remoteConfig = extractProxyConfig(remoteOutbounds);
    const remoteMuxConfig = extractMuxConfig(remoteOutbounds);
    if (!remoteConfig && !remoteMuxConfig) return;
    // Only touch the active profile. Other profiles may be empty
    // intentionally (drafts the user is preparing) and copying the same
    // remote key into all of them destroys that intent — and, if the user
    // then edits one, propagates the edits' opposite: they think each
    // profile has its own key while they all still share proxyConfig.
    const profile = getActiveProfile();
    if (!profile) return;
    const current = normalizeProxyConfig(profile.proxyConfig);
    if (remoteConfig && isProxyConfigEmpty(current)) {
      profile.proxyConfig = { ...remoteConfig };
    }
    // If proxies[] is still empty, promote the remote config as proxy[0]
    // so the multi-key panel shows *something* (otherwise the UI says
    // "Add at least one key first" while the router actually has a live
    // outbound). Idempotent: only when proxies is empty AND remoteConfig
    // has enough fields (address + uuid/password).
    const remoteHasAuth = remoteConfig && remoteConfig.address
      && (remoteConfig.uuid || remoteConfig.password);
    if (remoteHasAuth && (!profile.proxies || profile.proxies.length === 0)) {
      profile.proxies = profile.proxies || [];
      const promoted = {
        id: `proxy-${newId()}`,
        name: remoteConfig.address || "Imported key",
        source: "manual",
        config: { ...remoteConfig }
      };
      profile.proxies.push(promoted);
      if (!profile.activeProxyId) profile.activeProxyId = promoted.id;
    }
    // extractMuxConfig returns a normalised object even for empty input, so
    // it's always truthy. Only overwrite when the local muxConfig hasn't
    // been touched — otherwise a bootstrap after remote apply would silently
    // reset the user's Mux/XUDP choices to the remote default.
    if (remoteMuxConfig && (!profile.muxConfig || isMuxConfigEmpty(profile.muxConfig))) {
      profile.muxConfig = { ...remoteMuxConfig };
    }
  } catch (error) {
    pushDebug(`hydrateProxyConfigFromRemote failed: ${error.message}`);
  }
}

function parseJsonText(text) {
  return JSON.parse(String(text).replace(/^\uFEFF/, ""));
}

function bindProxyField(element, key, transform = (value) => value) {
  element.addEventListener("input", () => {
    const profile = getActiveProfile();
    if (!profile) return;
    profile.proxyConfig = {
      ...normalizeProxyConfig(profile.proxyConfig),
      [key]: transform(element.value)
    };
    persistState();
  });
}

function bindMuxField(element, key, transform = (value) => value, forcedEvent) {
  if (!element) return;
  const eventName = forcedEvent || (element.tagName === "SELECT" ? "change" : "input");
  element.addEventListener(eventName, () => {
    const profile = getActiveProfile();
    if (!profile) return;
    profile.muxConfig = normalizeMuxConfig({
      ...profile.muxConfig,
      [key]: transform(element.value)
    });
    persistState();
    renderMuxConfig(profile);
  });
}

function renderProxyConfig(profile) {
  const config = normalizeProxyConfig(profile.proxyConfig);
  els.proxyAddress.value = config.address;
  els.proxyPort.value = config.port || "";
  els.proxyUuid.value = config.uuid;
  els.proxyFlow.value = config.flow;
  els.proxyPublicKey.value = config.publicKey;
  els.proxyServerName.value = config.serverName;
  els.proxyShortId.value = config.shortId;
  els.proxyFingerprint.value = config.fingerprint;
  renderMuxConfig(profile);
}

function renderMuxConfig(profile) {
  const config = normalizeMuxConfig(profile.muxConfig);
  if (els.muxMode) els.muxMode.value = config.mode;
  if (els.muxUdp443) els.muxUdp443.value = config.xudpProxyUDP443;
  if (els.muxXudpConcurrency) els.muxXudpConcurrency.value = config.xudpConcurrency;

  const numbersHidden = config.mode === "off";
  const numberGrid = els.muxXudpConcurrency?.closest(".mux-number-grid");
  if (numberGrid) numberGrid.hidden = numbersHidden;
  if (els.muxXudpConcurrency) els.muxXudpConcurrency.disabled = config.mode === "off";
  if (els.muxUdp443) els.muxUdp443.disabled = config.mode === "off";
  if (els.muxSummary) els.muxSummary.textContent = muxModeLabel(config.mode);
}

function muxModeLabel(mode) {
  if (mode === "xudp") return T.muxModeXudp || "XUDP only";
  return T.muxModeOff || "Off";
}

function setProbeStatus(kind, message) {
  els.proxyProbeStatus.hidden = false;
  els.proxyProbeStatus.className = `probe-status ${kind}`;
  els.proxyProbeStatus.textContent = message;
}

// --- Multi-key UI: render + CRUD ---

// Tracks which proxy id the manual-key form is currently editing (null = new).
let editingProxyId = null;

function maskUrl(url) {
  // Hide the secret token portion of subscription URLs in the list view.
  // Keeps host + first path segment visible, masks the rest.
  if (!url) return "";
  try {
    const u = new URL(url);
    const segs = u.pathname.split("/").filter(Boolean);
    if (segs.length === 0) return `${u.host}/`;
    const tailMasked = segs.length > 1 ? `…***` : "***";
    return `${u.host}/${segs[0]}/${tailMasked}`;
  } catch {
    return url.slice(0, 24) + "…";
  }
}

function formatLastFetched(ts) {
  if (!ts) return T.fetchNever || "never fetched";
  const diffMs = Date.now() - ts;
  const sec = Math.floor(diffMs / 1000);
  if (sec < 60) return T.fetchJustNow || "just now";
  const min = Math.floor(sec / 60);
  if (min < 60) return formatMessage(T.fetchMinAgoFmt || "{n} min ago", { n: min });
  const hr = Math.floor(min / 60);
  if (hr < 24) return formatMessage(T.fetchHourAgoFmt || "{n} h ago", { n: hr });
  const days = Math.floor(hr / 24);
  return formatMessage(T.fetchDayAgoFmt || "{n} d ago", { n: days });
}

function securityBadge(config) {
  const sec = (config.security || "none").toLowerCase();
  const net = (config.network || "tcp").toLowerCase();
  const proto = (config.protocol || "vless").toLowerCase();
  if (proto === "hysteria2") return "hy2+tls+quic";
  return `${proto}+${sec}+${net}`;
}

function renderProxiesPanel(profile) {
  if (!profile) return;
  renderSubscriptionsList(profile);
  renderManualKeysList(profile);
  renderActiveProxyList(profile);
}

function renderSubscriptionsList(profile) {
  if (!els.subscriptionsList) return;
  els.subscriptionsList.innerHTML = "";
  const subs = profile.subscriptions || [];
  if (subs.length === 0) {
    // Hide the empty hint entirely if user already has any keys in the
    // other section — keeps the UI quiet once setup is done.
    const hasAnyProxies = (profile.proxies || []).length > 0;
    if (hasAnyProxies) return;
    const li = document.createElement("li");
    li.className = "card-empty";
    li.textContent = T.noSubscriptions;
    els.subscriptionsList.appendChild(li);
    return;
  }
  for (const sub of subs) {
    const keysCount = (profile.proxies || []).filter((p) => p.source === sub.id).length;
    const li = document.createElement("li");
    li.className = "key-card";
    li.dataset.subId = sub.id;
    const errorBlock = sub.lastError
      ? `<div class="card-error">⚠ ${escapeHtml(sub.lastError)}</div>`
      : "";
    const isRevealed = revealedSubs.has(sub.id);
    const isBusy = refreshingSubs.has(sub.id);
    const urlDisplay = isRevealed ? sub.url : maskUrl(sub.url);
    li.innerHTML = `
      <div class="card-main">
        <div class="card-title">${escapeHtml(sub.name)}</div>
        <div class="card-meta">
          <span>${escapeHtml(pluralize(keysCount, "keysPluralForms"))}</span>
          <span>·</span>
          <span>${formatLastFetched(sub.lastFetched)}</span>
        </div>
        <div class="card-url${isRevealed ? " revealed" : ""}" title="${escapeHtml(isRevealed ? sub.url : T.subRevealHint)}">${escapeHtml(urlDisplay)}</div>
        ${errorBlock}
      </div>
      <div class="card-actions">
        <button type="button" data-act="reveal-sub" data-id="${sub.id}" title="${escapeHtml(isRevealed ? (T.urlHideTitle || "Hide URL") : (T.urlShowTitle || "Show URL"))}">${isRevealed ? "🙈" : "👁"}</button>
        <button type="button" data-act="copy-sub" data-id="${sub.id}" title="${escapeHtml(T.urlCopyTitle || "Copy URL")}">📋</button>
        <button type="button" data-act="refresh-sub" data-id="${sub.id}"${isBusy ? " disabled" : ""}>${isBusy ? "⏳…" : escapeHtml(T.subRefreshBtn || "↻ Refresh")}</button>
        <button type="button" data-act="delete-sub" data-id="${sub.id}" class="danger">✕</button>
      </div>
    `;
    els.subscriptionsList.appendChild(li);
  }
}

// Tracks subs currently mid-refresh (used to disable the button and swap
// label to a spinner glyph) and subs whose full URL is temporarily revealed.
const refreshingSubs = new Set();
const revealedSubs = new Set();
const revealedTimers = new Map();

function toggleRevealSub(subId) {
  if (revealedSubs.has(subId)) {
    revealedSubs.delete(subId);
    const t = revealedTimers.get(subId);
    if (t) { clearTimeout(t); revealedTimers.delete(subId); }
  } else {
    revealedSubs.add(subId);
    // auto-hide after 10s so it doesn't stay open on shared screens
    const t = setTimeout(() => {
      revealedSubs.delete(subId);
      revealedTimers.delete(subId);
      const profile = getActiveProfile();
      if (profile) renderSubscriptionsList(profile);
    }, 10000);
    revealedTimers.set(subId, t);
  }
  const profile = getActiveProfile();
  if (profile) renderSubscriptionsList(profile);
}

async function copySubUrl(subId) {
  const profile = getActiveProfile();
  if (!profile) return;
  const sub = (profile.subscriptions || []).find((s) => s.id === subId);
  if (!sub) return;
  try {
    await navigator.clipboard.writeText(sub.url);
    showToast(formatMessage(T.subCopiedFmt, { name: sub.name }), { kind: "success", ttl: 2000 });
  } catch (err) {
    // Fallback for non-secure contexts: present in a prompt() so user can copy
    window.prompt(T.subCopyManual || "Copy URL manually:", sub.url);
  }
}

function renderManualKeysList(profile) {
  if (!els.manualKeysList) return;
  els.manualKeysList.innerHTML = "";
  const proxies = (profile.proxies || []).filter((p) => p.source === "manual");
  if (proxies.length === 0) {
    // Skip the empty hint if user already has a subscription with proxies.
    const hasSubProxies = (profile.proxies || []).some((p) => p.source !== "manual");
    const hasSubs = (profile.subscriptions || []).length > 0;
    if (hasSubProxies || hasSubs) return;
    const li = document.createElement("li");
    li.className = "card-empty";
    li.textContent = T.noManualKeys;
    els.manualKeysList.appendChild(li);
    return;
  }
  for (const p of proxies) {
    const li = document.createElement("li");
    li.className = "key-card";
    li.dataset.proxyId = p.id;
    li.innerHTML = `
      <div class="card-main">
        <div class="card-title">${escapeHtml(p.name)}</div>
        <div class="card-meta">
          <span class="card-badge">${escapeHtml(securityBadge(p.config))}</span>
          <span>${escapeHtml(p.config.address)}:${p.config.port}</span>
        </div>
      </div>
      <div class="card-actions">
        <button type="button" data-act="edit-proxy" data-id="${p.id}">${escapeHtml(T.keyEditBtn || "Edit")}</button>
        <button type="button" data-act="delete-proxy" data-id="${p.id}" class="danger">✕</button>
      </div>
    `;
    els.manualKeysList.appendChild(li);
  }
}

function renderActiveProxyList(profile) {
  if (!els.activeProxyList) return;
  els.activeProxyList.innerHTML = "";
  const proxies = profile.proxies || [];
  if (proxies.length === 0) {
    const li = document.createElement("li");
    li.className = "card-empty";
    li.textContent = T.subKeysNoneAddFirst || "Add at least one key first.";
    els.activeProxyList.appendChild(li);
    return;
  }
  const activeId = profile.activeProxyId;
  for (const p of proxies) {
    const sub = (profile.subscriptions || []).find((s) => s.id === p.source);
    const srcLabel = sub ? sub.name : (T.manualKeySrc || "manual");
    const li = document.createElement("li");
    li.className = "active-row" + (p.id === activeId ? " selected" : "");
    li.dataset.proxyId = p.id;
    li.innerHTML = `
      <input type="radio" name="activeProxy" value="${p.id}" ${p.id === activeId ? "checked" : ""} class="active-radio-input">
      <div class="active-info">
        <div class="active-name">${escapeHtml(p.name)}</div>
        <div class="active-meta">
          <span>${escapeHtml(srcLabel)}</span>
          <span>·</span>
          <span class="card-badge">${escapeHtml(securityBadge(p.config))}</span>
          <span>${escapeHtml(p.config.address)}:${p.config.port}</span>
        </div>
      </div>
    `;
    els.activeProxyList.appendChild(li);
  }
}

function escapeHtml(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  })[c]);
}

// Form open/close

// Snapshot of profile.proxyConfig taken when the manual-key form opens,
// so `closeManualKeyForm` can restore it on Cancel — otherwise the form
// treats `profile.proxyConfig` as its edit buffer and `bindProxyField`
// persists dirty state to localStorage on every keystroke.
let manualKeyFormSnapshot = null;

function openManualKeyForm(proxyId = null) {
  editingProxyId = proxyId;
  els.manualKeyFormTitle.textContent = proxyId ? (T.manualKeyFormTitleEdit || "Edit key") : (T.manualKeyFormTitleNew || "New key");
  els.manualKeyForm.hidden = false;
  els.subscriptionForm.hidden = true;

  const profile = getActiveProfile();
  if (!profile) return;

  manualKeyFormSnapshot = profile.proxyConfig ? { ...profile.proxyConfig } : null;

  if (proxyId) {
    const p = (profile.proxies || []).find((x) => x.id === proxyId);
    if (p) {
      profile.proxyConfig = { ...p.config };
      els.manualKeyName.value = p.name;
    }
  } else {
    profile.proxyConfig = createDefaultProxyConfig();
    els.manualKeyName.value = "";
    els.proxyImportUrl.value = "";
  }
  renderProxyConfig(profile);
}

function closeManualKeyForm() {
  editingProxyId = null;
  els.manualKeyForm.hidden = true;
  els.proxyImportUrl.value = "";
  // Restore the pre-edit snapshot so keystrokes into the form don't leak
  // into localStorage as a "committed" state after Cancel.
  const profile = getActiveProfile();
  if (profile && manualKeyFormSnapshot !== null) {
    profile.proxyConfig = manualKeyFormSnapshot;
    persistState();
  }
  manualKeyFormSnapshot = null;
}

function openSubscriptionForm() {
  els.subscriptionForm.hidden = false;
  els.manualKeyForm.hidden = true;
  els.newSubscriptionName.value = "";
  els.newSubscriptionUrl.value = "";
  setSubscriptionFormStatus("info", "");
}

function closeSubscriptionForm() {
  els.subscriptionForm.hidden = true;
}

function setSubscriptionFormStatus(kind, message) {
  if (!els.subscriptionFormStatus) return;
  if (!message) {
    els.subscriptionFormStatus.hidden = true;
    els.subscriptionFormStatus.textContent = "";
    return;
  }
  els.subscriptionFormStatus.hidden = false;
  els.subscriptionFormStatus.className = `probe-status ${kind}`;
  els.subscriptionFormStatus.textContent = message;
}

// CRUD handlers

function saveManualKey() {
  const profile = getActiveProfile();
  if (!profile) return;
  const config = normalizeProxyConfig(profile.proxyConfig);
  const proto = (config.protocol || "vless").toLowerCase();
  const needsSecret = proto === "hysteria2" ? !!config.password : !!config.uuid;
  const port = sanitizeProxyPort(config.port);
  if (!config.address || !needsSecret || !port) {
    const secretLabel = proto === "hysteria2" ? (T.fieldPassword || "password") : (T.fieldUUID || "UUID");
    const what = !config.address ? (T.fieldAddress || "address")
               : !needsSecret ? secretLabel
               : (T.fieldPortRange || "port (1..65535)");
    setProbeStatus("error", formatMessage(
      T.manualKeyMissingFmt || "Missing: {fields}. Fill the fields or paste a vless:// / vmess:// / hysteria2:// URI.",
      { fields: what }
    ));
    return;
  }
  config.port = port;
  const name = els.manualKeyName.value.trim() || config.address;
  if (editingProxyId) {
    const existing = profile.proxies.find((p) => p.id === editingProxyId);
    if (existing) {
      existing.name = name;
      existing.config = config;
    }
  } else {
    profile.proxies.push({
      id: `proxy-${newId()}`,
      name,
      source: "manual",
      config
    });
    if (!profile.activeProxyId) {
      profile.activeProxyId = profile.proxies[profile.proxies.length - 1].id;
    }
  }
  // Save committed the buffer, so don't let closeManualKeyForm revert to
  // the pre-open snapshot.
  manualKeyFormSnapshot = null;
  closeManualKeyForm();
  persistState();
  renderProxiesPanel(profile);
}

function deleteProxy(proxyId) {
  const profile = getActiveProfile();
  if (!profile) return;
  if (!confirm(T.confirmDeleteKey)) return;
  profile.proxies = (profile.proxies || []).filter((p) => p.id !== proxyId);
  if (profile.activeProxyId === proxyId) {
    profile.activeProxyId = profile.proxies.length ? profile.proxies[0].id : null;
  }
  persistState();
  renderProxiesPanel(profile);
}

function setActiveProxy(proxyId) {
  const profile = getActiveProfile();
  if (!profile) return;
  const proxy = (profile.proxies || []).find((p) => p.id === proxyId);
  if (!proxy) return;
  // Any parsed protocol is activatable now (vless/vmess via xray,
  // hy2 via sing-box bridge). Kept intentionally simple — bring back
  // a check + toast when a future transport genuinely can't activate.
  profile.activeProxyId = proxyId;
  persistState();
  renderActiveProxyList(profile);
}

async function fetchSubscriptionViaBackend(url) {
  const res = await fetchWithTimeout("/api/routing.cgi?kind=subscription-fetch", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ url })
  });
  const data = await res.json();
  if (!data.ok) throw new Error(data.error || `fetch failed (${res.status})`);
  // data.raw is base64 of the HTTP body. Body itself is typically base64 of URIs.
  const httpBody = atob(data.raw);
  let text;
  try {
    let inner = httpBody.replace(/-/g, "+").replace(/_/g, "/").trim();
    while (inner.length % 4) inner += "=";
    text = atob(inner);
  } catch {
    text = httpBody;
  }
  return parseSubscriptionText(text);
}

async function saveSubscription() {
  const profile = getActiveProfile();
  if (!profile) return;
  const name = els.newSubscriptionName.value.trim();
  const url = els.newSubscriptionUrl.value.trim();
  if (!url) {
    setSubscriptionFormStatus("error", T.subUrlEmpty);
    return;
  }
  if (!url.toLowerCase().startsWith("https://")) {
    setSubscriptionFormStatus("error", T.subUrlNeedHttps);
    return;
  }
  setSubscriptionFormStatus("info", T.subLoading || "Loading…");
  els.saveSubscriptionBtn.disabled = true;
  try {
    const result = await fetchSubscriptionViaBackend(url);
    // The fetch may take seconds. If the user switched the active profile
    // during that window, mutating the stale `profile` reference would
    // stash this subscription into the wrong profile — silently — because
    // persistState() writes the whole state and the current UI panel
    // belongs to a different profile. Bail cleanly.
    if (getActiveProfile() !== profile) {
      setSubscriptionFormStatus("info", T.subCancelled || "cancelled — profile switched");
      return;
    }
    if (result.configs.length === 0) {
      setSubscriptionFormStatus("error", T.subNoConfigs || "Subscription has no recognisable keys");
      return;
    }
    const subId = `sub-${newId()}`;
    const sub = {
      id: subId,
      name: name || (new URL(url).host),
      url,
      lastFetched: Date.now(),
      lastError: null
    };
    profile.subscriptions = profile.subscriptions || [];
    profile.subscriptions.push(sub);
    profile.proxies = profile.proxies || [];
    for (const cfg of result.configs) {
      profile.proxies.push({
        id: `proxy-${newId()}`,
        name: cfg.name,
        source: subId,
        config: cfg
      });
    }
    if (!profile.activeProxyId && profile.proxies.length) {
      // .find could return undefined if all cfgs failed normalisation
      // — guard so .id doesn't crash the save.
      const first = profile.proxies.find((p) => p.source === subId);
      if (first) profile.activeProxyId = first.id;
    }
    closeSubscriptionForm();
    persistState();
    renderProxiesPanel(profile);
    const errPart = result.errors.length
      ? formatMessage(T.subLoadedErrPart || ", errors: {n}", { n: result.errors.length })
      : "";
    const msg = formatMessage(T.subLoadedFmt || "Loaded {n} key(s){errPart}", { n: result.configs.length, errPart });
    setProbeStatus("success", msg);
  } catch (err) {
    setSubscriptionFormStatus("error", String(err.message || err).slice(0, 200));
  } finally {
    els.saveSubscriptionBtn.disabled = false;
  }
}

async function refreshSubscription(subId) {
  const profile = getActiveProfile();
  if (!profile) return;
  const sub = (profile.subscriptions || []).find((s) => s.id === subId);
  if (!sub) return;
  if (refreshingSubs.has(subId)) return; // already running

  refreshingSubs.add(subId);
  renderSubscriptionsList(profile); // show spinner state
  const toast = showToast(formatMessage(T.subRefreshingFmt, { name: sub.name }), { kind: "progress" });

  // Remember if the active proxy was from this sub — if the refresh removes
  // it we report that in the toast instead of silently falling back.
  const activeProxyBefore = profile.activeProxyId;
  const activeFromThisSub = (profile.proxies || []).find(
    (p) => p.id === activeProxyBefore && p.source === subId
  );
  const activeKeyBefore = activeFromThisSub
    ? activeFromThisSub.config.address + ":" + activeFromThisSub.config.port + "/" + activeFromThisSub.config.uuid
    : null;

  try {
    const result = await fetchSubscriptionViaBackend(sub.url);
    // If the sub was deleted OR the user switched profiles while we were
    // fetching, drop the result on the floor — otherwise we mutate an
    // orphan `sub` and, worse, add new proxies with `source: subId` that
    // point at a subscription that no longer exists. Those proxies can't
    // be deleted through the sub-delete flow ever again.
    const stillActive = getActiveProfile() === profile
      && (profile.subscriptions || []).some((s) => s.id === subId);
    if (!stillActive) {
      toast.update(`«${sub.name}»: ${T.subCancelled}`, "info");
      return;
    }
    if (result.configs.length === 0) {
      sub.lastError = T.subEmpty;
      persistState();
      renderProxiesPanel(profile);
      toast.update(`«${sub.name}»: ${T.subEmpty}`, "error");
      return;
    }

    // Diff by (protocol:address:port/uuid|password). Include protocol and
    // secret so two hy2 keys sharing address:port aren't collapsed into
    // "kept" — that would silently drop the second key on every refresh.
    const keyOf = (c) => `${c.protocol || "vless"}:${c.address}:${c.port}/${c.uuid || c.password || ""}`;
    const oldProxies = (profile.proxies || []).filter((p) => p.source === subId);
    const oldByKey = new Map(oldProxies.map((p) => [keyOf(p.config), p]));
    const newProxies = [];
    const addedNames = [];
    let kept = 0;
    for (const cfg of result.configs) {
      const key = keyOf(cfg);
      const existing = oldByKey.get(key);
      if (existing) {
        existing.config = cfg;
        existing.name = cfg.name;
        newProxies.push(existing);
        oldByKey.delete(key);
        kept++;
      } else {
        newProxies.push({
          id: `proxy-${newId()}`,
          name: cfg.name,
          source: subId,
          config: cfg
        });
        addedNames.push(cfg.name);
      }
    }
    const removedNames = Array.from(oldByKey.values()).map((p) => p.name);
    profile.proxies = [
      ...(profile.proxies || []).filter((p) => p.source !== subId),
      ...newProxies
    ];

    // If the active proxy was removed by this refresh, fall back and tell the
    // user via the toast so the change isn't invisible.
    let activeLostMessage = "";
    if (profile.activeProxyId && !profile.proxies.some((p) => p.id === profile.activeProxyId)) {
      profile.activeProxyId = newProxies[0]?.id || profile.proxies[0]?.id || null;
      const fallbackName = profile.proxies.find((p) => p.id === profile.activeProxyId)?.name;
      activeLostMessage = activeKeyBefore && fallbackName
        ? formatMessage(T.subActiveResetToFmt || " · active reset to {name}", { name: fallbackName })
        : (T.subActiveResetPlain || " · active reset");
    }

    sub.lastFetched = Date.now();
    sub.lastError = null;
    persistState();
    renderProxiesPanel(profile);

    const parts = [];
    if (addedNames.length) parts.push(formatMessage(T.subRefreshAddedFmt || "+{n} new", { n: addedNames.length }));
    if (kept) parts.push(formatMessage(T.subRefreshKeptFmt || "~{n} unchanged", { n: kept }));
    if (removedNames.length) parts.push(formatMessage(T.subRefreshRemovedFmt || "−{n} removed", { n: removedNames.length }));
    const summary = parts.length ? parts.join(", ") : (T.subRefreshNoChanges || "no changes");
    toast.update(`«${sub.name}»: ${summary}${activeLostMessage}`, "success");
  } catch (err) {
    sub.lastError = String(err.message || err).slice(0, 200);
    persistState();
    // The user may have switched profiles while our fetch was in flight.
    // If they did, the profile panel currently on screen belongs to a
    // different profile — rendering profile A's subs into it would visibly
    // corrupt profile B's UI until the next re-render. Toast still fires
    // because the user asked for this action and should see the outcome.
    if (getActiveProfile() === profile) renderProxiesPanel(profile);
    toast.update(`«${sub.name}»: ${sub.lastError}`, "error");
  } finally {
    refreshingSubs.delete(subId);
    if (getActiveProfile() === profile) renderSubscriptionsList(profile);
  }
}

function deleteSubscription(subId) {
  const profile = getActiveProfile();
  if (!profile) return;
  const sub = (profile.subscriptions || []).find((s) => s.id === subId);
  if (!sub) return;
  if (!confirm(formatMessage(T.confirmDeleteSubFmt, { name: sub.name }))) return;
  profile.subscriptions = profile.subscriptions.filter((s) => s.id !== subId);
  profile.proxies = (profile.proxies || []).filter((p) => p.source !== subId);
  if (profile.activeProxyId && !profile.proxies.some((p) => p.id === profile.activeProxyId)) {
    profile.activeProxyId = profile.proxies.length ? profile.proxies[0].id : null;
  }
  revealedSubs.delete(subId);
  const revealTimer = revealedTimers.get(subId);
  if (revealTimer) { clearTimeout(revealTimer); revealedTimers.delete(subId); }
  persistState();
  renderProxiesPanel(profile);
}

// Localhost port where sing-box exposes a mixed (SOCKS5) inbound for xray to
// forward TCP traffic into when the active proxy is hysteria2. xray treats
// the relay as a normal SOCKS5 upstream; sing-box does the real tunneling.
const SINGBOX_XRAY_RELAY_PORT = 61225;

function buildOutboundsDocument(profile) {
  const config = getActiveProxyConfig(profile);
  const mux = buildMuxObject(profile.muxConfig);
  const protocol = (config.protocol || "vless").toLowerCase();

  // Hysteria2 is not xray-native. We keep the "vless-reality" tag (routing
  // rules reference it everywhere) but route the outbound through sing-box
  // via SOCKS5. sing-box owns the real hysteria2 outbound.
  if (protocol === "hysteria2") {
    return {
      outbounds: [
        {
          tag: "vless-reality",
          protocol: "socks",
          settings: {
            servers: [
              { address: "127.0.0.1", port: SINGBOX_XRAY_RELAY_PORT }
            ]
          }
        },
        { protocol: "freedom", tag: "direct" }
      ]
    };
  }

  // user block differs by protocol; xray keeps the outbound tag "vless-reality"
  // for compatibility with existing routing.json rules even when we ship vmess.
  const userBlock = protocol === "vmess"
    ? { id: config.uuid, alterId: Number(config.alterId) || 0, security: "auto", level: 0 }
    : { id: config.uuid, encryption: "none", flow: config.flow || "", level: 0 };

  return {
    outbounds: [
      {
        tag: "vless-reality",
        protocol,
        settings: {
          vnext: [
            {
              address: config.address,
              port: Number(config.port),
              users: [userBlock]
            }
          ]
        },
        streamSettings: buildStreamSettings(config),
        mux
      },
      {
        protocol: "freedom",
        tag: "direct"
      }
    ]
  };
}

// Build the sing-box config that matches the currently selected proxy.
// - For vless/vmess (xray-native): keeps the existing shape (UDP TPROXY ->
//   shadowsocks-relay -> xray). xray does the real tunneling.
// - For hysteria2: adds a mixed inbound on 127.0.0.1:SINGBOX_XRAY_RELAY_PORT
//   (so xray can SOCKS into us) and a hysteria2 outbound to the server.
//   All routes terminate at hysteria2.
function buildSingboxDocument(profile) {
  const config = getActiveProxyConfig(profile);
  const protocol = (config.protocol || "vless").toLowerCase();

  const base = {
    log: { level: "warn", timestamp: true },
    inbounds: [
      {
        type: "tproxy",
        tag: "xkeen-udp-tproxy",
        listen: "0.0.0.0",
        listen_port: 61221,
        network: "udp"
      }
    ],
    outbounds: [],
    route: {
      rules: [{ ip_is_private: true, outbound: "direct" }],
      final: "proxy"
    }
  };

  if (protocol === "hysteria2") {
    base.inbounds.push({
      type: "mixed",
      tag: "xray-relay",
      listen: "127.0.0.1",
      listen_port: SINGBOX_XRAY_RELAY_PORT
    });
    const hy2 = {
      type: "hysteria2",
      tag: "proxy",
      server: config.address,
      server_port: Number(config.port),
      password: config.password || "",
      tls: {
        enabled: true,
        server_name: config.serverName || config.address,
        insecure: !!config.insecure
      }
    };
    if (Array.isArray(config.alpn) && config.alpn.length) {
      hy2.tls.alpn = config.alpn.slice();
    }
    if (config.obfs) {
      hy2.obfs = { type: config.obfs, password: config.obfsPassword || "" };
    }
    if (config.pinSHA256) {
      hy2.tls.certificate_pin_sha256 = [config.pinSHA256];
    }
    base.outbounds.push(hy2);
  } else {
    // Default: relay UDP into xray's shadowsocks listener so it can tunnel
    // via the active VLESS/VMess outbound (same path that worked for months).
    base.outbounds.push({
      type: "shadowsocks",
      tag: "proxy",
      server: "127.0.0.1",
      server_port: 62640,
      method: "none",
      password: "none"
    });
  }

  base.outbounds.push({ type: "direct", tag: "direct" });
  return base;
}

function extractProxyConfig(doc) {
  const outbound = (doc?.outbounds || []).find((item) => item.tag === "vless-reality");
  if (!outbound) return null;
  const vnext = outbound?.settings?.vnext?.[0] || {};
  const user = vnext?.users?.[0] || {};
  const reality = outbound?.streamSettings?.realitySettings || {};
  return normalizeProxyConfig({
    address: vnext.address,
    port: vnext.port,
    uuid: user.id,
    flow: user.flow,
    publicKey: reality.publicKey,
    serverName: reality.serverName,
    shortId: reality.shortId,
    fingerprint: reality.fingerprint
  });
}

function extractMuxConfig(doc) {
  const outbound = (doc?.outbounds || []).find((item) => item.tag === "vless-reality");
  if (!outbound) return null;
  return normalizeMuxConfig(outbound.mux || {});
}

function createDefaultProxyConfig() {
  return {
    protocol: "vless",
    address: "",
    port: "",
    uuid: "",
    flow: "xtls-rprx-vision",
    network: "tcp",
    security: "reality",
    serverName: "",
    fingerprint: "random",
    publicKey: "",
    shortId: "",
    spiderX: "/",
    alpn: [],
    path: "",
    host: "",
    alterId: 0,
    // gRPC-specific
    serviceName: "",
    mode: "",       // gRPC: "multi"|"gun"|"guna"  /  XHTTP: "auto"|"packet-up"|"stream-up"|"stream-one"
    authority: "",  // gRPC :authority pseudo-header
    // XHTTP-specific. xhttpExtra carries the full provider-supplied JSON
    // (scMaxEachPostBytes, scMaxConcurrentPosts, scMinPostsIntervalMs,
    // xPaddingBytes, noGRPCHeader, etc). xPaddingBytes stays as a top-level
    // shortcut so older keys still work, but the full extra wins when set.
    xPaddingBytes: "",
    xhttpExtra: null,
    // Hysteria2-specific (UDP/QUIC protocol, NOT xray-native)
    password: "",         // auth secret (vless/vmess use uuid, hy2 uses password)
    obfs: "",             // "salamander" or empty
    obfsPassword: "",
    insecure: false,      // skip TLS cert verify
    pinSHA256: ""         // pinned cert fingerprint
  };
}

function createDefaultMuxConfig() {
  return {
    mode: "off",
    tcpConcurrency: 8,
    xudpConcurrency: 8,
    xudpProxyUDP443: "reject"
  };
}

// True if muxConfig matches the shipped default — safe to overwrite from
// remote apply. Used by hydrateProxyConfigFromRemote to avoid clobbering
// user-tuned Mux/XUDP choices.
function isMuxConfigEmpty(config) {
  if (!config || typeof config !== "object") return true;
  const d = createDefaultMuxConfig();
  return (config.mode || "off") === d.mode
    && (config.tcpConcurrency == null || config.tcpConcurrency === d.tcpConcurrency)
    && (config.xudpConcurrency == null || config.xudpConcurrency === d.xudpConcurrency)
    && (config.xudpProxyUDP443 || d.xudpProxyUDP443) === d.xudpProxyUDP443;
}

function normalizeProxyConfig(config) {
  return {
    ...createDefaultProxyConfig(),
    ...(config || {})
  };
}

// Parse a single vless:// URI per the standard URL shape
// vless://UUID@HOST:PORT?param=value&...#friendly-name
// Returns { ok: true, config } or { ok: false, error }
function parseVlessUri(uri) {
  if (typeof uri !== "string") return { ok: false, error: "not a string" };
  const trimmed = uri.trim();
  if (!/^vless:\/\//i.test(trimmed)) return { ok: false, error: "not vless://" };

  let body = trimmed.slice("vless://".length);
  let name = "";
  const hashIdx = body.indexOf("#");
  if (hashIdx >= 0) {
    try { name = decodeURIComponent(body.slice(hashIdx + 1)); }
    catch { name = body.slice(hashIdx + 1); }
    body = body.slice(0, hashIdx);
  }

  let queryStr = "";
  const queryIdx = body.indexOf("?");
  if (queryIdx >= 0) {
    queryStr = body.slice(queryIdx + 1);
    body = body.slice(0, queryIdx);
  }

  const atIdx = body.indexOf("@");
  if (atIdx < 0) return { ok: false, error: "missing @ in vless URI" };
  let uuid = body.slice(0, atIdx);
  // Some providers URL-encode `%` and other special chars in the user-info
  // portion. Symmetric with the hy2 parser below, which already decodes.
  try { uuid = decodeURIComponent(uuid); } catch { /* leave raw */ }
  const hostPort = body.slice(atIdx + 1);
  if (!uuid || !hostPort) return { ok: false, error: "empty uuid or host" };

  // rightmost colon — handles IPv6 in brackets
  const colonIdx = hostPort.lastIndexOf(":");
  if (colonIdx < 0) return { ok: false, error: "missing port" };
  const host = hostPort.slice(0, colonIdx).replace(/^\[|\]$/g, "");
  const port = parseInt(hostPort.slice(colonIdx + 1), 10);
  if (!host || !Number.isFinite(port) || port < 1 || port > 65535) {
    return { ok: false, error: "invalid host or port" };
  }

  const params = {};
  for (const pair of queryStr.split("&")) {
    if (!pair) continue;
    const eqIdx = pair.indexOf("=");
    const key = eqIdx < 0 ? pair : pair.slice(0, eqIdx);
    const val = eqIdx < 0 ? "" : pair.slice(eqIdx + 1);
    // application/x-www-form-urlencoded: `+` decodes to a space.
    // decodeURIComponent keeps `+` literal, so subscription providers that
    // pack JSON into extra=... (which has spaces) end up with invalid JSON.
    const decoded = val.replace(/\+/g, " ");
    try { params[key] = decodeURIComponent(decoded); }
    catch { params[key] = decoded; }
  }

  const security = (params.security || "").toLowerCase() || "none";
  const network = (params.type || "tcp").toLowerCase();
  const alpn = params.alpn
    ? params.alpn.split(",").map(s => s.trim()).filter(Boolean)
    : [];

  return {
    ok: true,
    config: {
      protocol: "vless",
      name: name || `${host}:${port}`,
      address: host,
      port,
      uuid,
      flow: params.flow || "",
      network,
      security,
      serverName: params.sni || params.serverName || "",
      fingerprint: params.fp || "",
      publicKey: params.pbk || "",
      shortId: params.sid || "",
      spiderX: params.spx || "/",
      alpn,
      path: params.path || "",
      host: params.host || "",
      alterId: 0,
      // gRPC: prefer explicit serviceName=, fall back to path= which some
      // providers reuse for the gRPC service name.
      serviceName: params.serviceName || params.path || "",
      mode: params.mode || "",
      authority: params.authority || "",
      // XHTTP padding shortcut. Providers expose either
      //   1) `xPaddingBytes=100-1000` directly, or
      //   2) `extra={"xPaddingBytes":"100-1000",...}` JSON-encoded.
      xPaddingBytes: params.xPaddingBytes || (() => {
        if (!params.extra) return "";
        try { return JSON.parse(params.extra).xPaddingBytes || ""; }
        catch { return ""; }
      })(),
      // Full XHTTP extra blob — pass-through so all scMax* / noGRPCHeader /
      // future fields reach xray verbatim. Server-side configs are picky:
      // missing scMaxEachPostBytes etc. silently breaks stream-up handshake.
      xhttpExtra: (() => {
        if (!params.extra) return null;
        try { return JSON.parse(params.extra); }
        catch { return null; }
      })()
    }
  };
}

// Parse vmess:// — payload is base64-encoded JSON
function parseVmessUri(uri) {
  if (typeof uri !== "string") return { ok: false, error: "not a string" };
  const trimmed = uri.trim();
  if (!/^vmess:\/\//i.test(trimmed)) return { ok: false, error: "not vmess://" };

  const payload = trimmed.slice("vmess://".length);
  let json;
  try {
    let b64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    while (b64.length % 4) b64 += "=";
    const decoded = atob(b64);
    json = JSON.parse(decoded);
  } catch (err) {
    return { ok: false, error: `vmess decode failed: ${err.message}` };
  }

  const port = parseInt(json.port, 10);
  if (!json.add || !Number.isFinite(port) || port < 1 || port > 65535) {
    return { ok: false, error: "vmess missing add or port out of range" };
  }

  // vmess "tls" field: "tls" | "reality" | "" | "none"
  const tlsRaw = String(json.tls || "").toLowerCase();
  const security = tlsRaw === "tls" ? "tls" : tlsRaw === "reality" ? "reality" : "none";
  const network = String(json.net || "tcp").toLowerCase();
  const alpn = json.alpn
    ? String(json.alpn).split(",").map(s => s.trim()).filter(Boolean)
    : [];

  return {
    ok: true,
    config: {
      protocol: "vmess",
      name: json.ps || `${json.add}:${port}`,
      address: json.add,
      port,
      uuid: json.id || "",
      flow: "",
      network,
      security,
      serverName: json.sni || "",
      fingerprint: json.fp || "",
      publicKey: "",
      shortId: "",
      spiderX: "/",
      alpn,
      path: json.path || "",
      host: json.host || "",
      alterId: parseInt(json.aid, 10) || 0,
      // gRPC: vmess legacy reuses `path` as the gRPC service name.
      // `type` carries the mode for grpc (multi/gun).
      serviceName: network === "grpc" ? (json.path || "") : "",
      mode: network === "grpc" ? (json.type || "") : "",
      authority: ""
    }
  };
}

// Parse a hysteria2:// or hy2:// URI.
// Format: hysteria2://password@host:port?sni=...&obfs=salamander&obfs-password=...
//                                          &insecure=0|1&pinSHA256=...&alpn=h3#name
// Hysteria2 is UDP/QUIC, not xray-native — applying it requires sing-box.
// Phase A only parses + displays; activation is gated separately.
function parseHysteria2Uri(uri) {
  if (typeof uri !== "string") return { ok: false, error: "not a string" };
  const trimmed = uri.trim();
  if (!/^(hysteria2|hy2):\/\//i.test(trimmed)) return { ok: false, error: "not hysteria2://" };

  let body = trimmed.replace(/^(hysteria2|hy2):\/\//i, "");
  let name = "";
  const hashIdx = body.indexOf("#");
  if (hashIdx >= 0) {
    try { name = decodeURIComponent(body.slice(hashIdx + 1)); }
    catch { name = body.slice(hashIdx + 1); }
    body = body.slice(0, hashIdx);
  }

  let queryStr = "";
  const queryIdx = body.indexOf("?");
  if (queryIdx >= 0) {
    queryStr = body.slice(queryIdx + 1);
    body = body.slice(0, queryIdx);
  }

  const atIdx = body.indexOf("@");
  if (atIdx < 0) return { ok: false, error: "missing @ in hysteria2 URI" };
  let password = body.slice(0, atIdx);
  try { password = decodeURIComponent(password); } catch { /* keep raw */ }
  const hostPort = body.slice(atIdx + 1);
  if (!password || !hostPort) return { ok: false, error: "empty password or host" };

  const colonIdx = hostPort.lastIndexOf(":");
  if (colonIdx < 0) return { ok: false, error: "missing port" };
  const host = hostPort.slice(0, colonIdx).replace(/^\[|\]$/g, "");
  const port = parseInt(hostPort.slice(colonIdx + 1), 10);
  if (!host || !Number.isFinite(port) || port < 1 || port > 65535) {
    return { ok: false, error: "invalid host or port" };
  }

  const params = {};
  for (const pair of queryStr.split("&")) {
    if (!pair) continue;
    const eqIdx = pair.indexOf("=");
    const key = eqIdx < 0 ? pair : pair.slice(0, eqIdx);
    const val = eqIdx < 0 ? "" : pair.slice(eqIdx + 1);
    try { params[key] = decodeURIComponent(val); }
    catch { params[key] = val; }
  }

  const alpn = params.alpn
    ? params.alpn.split(",").map((s) => s.trim()).filter(Boolean)
    : [];

  return {
    ok: true,
    config: {
      protocol: "hysteria2",
      name: name || `${host}:${port}`,
      address: host,
      port,
      uuid: "",                   // hy2 uses password, not uuid
      password,
      flow: "",
      network: "udp",             // QUIC over UDP
      security: "tls",            // always TLS
      serverName: params.sni || params.serverName || host,
      fingerprint: params.fp || "",
      publicKey: "",
      shortId: "",
      spiderX: "/",
      alpn: alpn.length ? alpn : ["h3"],
      path: "",
      host: "",
      alterId: 0,
      serviceName: "",
      mode: "",
      authority: "",
      xPaddingBytes: "",
      // Hysteria2-specific
      obfs: params.obfs || "",
      obfsPassword: params["obfs-password"] || params.obfsPassword || "",
      insecure: params.insecure === "1" || params.insecure === "true",
      pinSHA256: params.pinSHA256 || params["pin-sha256"] || ""
    }
  };
}

// Parse a subscription body (already base64-decoded by caller).
// Each non-empty line is a URI; unknown schemes are skipped silently.
function parseSubscriptionText(rawText) {
  const lines = String(rawText || "").split(/\r?\n/);
  const configs = [];
  const errors = [];
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("//") || trimmed.startsWith("#")) continue;
    let result = null;
    if (/^vless:\/\//i.test(trimmed)) result = parseVlessUri(trimmed);
    else if (/^vmess:\/\//i.test(trimmed)) result = parseVmessUri(trimmed);
    else if (/^(hysteria2|hy2):\/\//i.test(trimmed)) result = parseHysteria2Uri(trimmed);
    else continue;
    if (result.ok) configs.push(result.config);
    else errors.push({ line: trimmed.slice(0, 80), error: result.error });
  }
  return { configs, errors };
}

// Build xray outbound `streamSettings` from a normalized proxy config.
// Branches on `security` (reality | tls | none) and `network` (tcp | ws).
// Returns the streamSettings object for the outbound.
function buildStreamSettings(cfg) {
  const network = (cfg.network || "tcp").toLowerCase();
  const security = (cfg.security || "none").toLowerCase();

  const ss = {
    network,
    security: security === "none" ? "none" : security
  };

  if (security === "reality") {
    ss.realitySettings = {
      publicKey: cfg.publicKey || "",
      fingerprint: cfg.fingerprint || "random",
      serverName: cfg.serverName || "",
      shortId: cfg.shortId || "",
      spiderX: cfg.spiderX || "/"
    };
  } else if (security === "tls") {
    ss.tlsSettings = {
      serverName: cfg.serverName || cfg.address || "",
      fingerprint: cfg.fingerprint || "chrome",
      allowInsecure: false
    };
    if (Array.isArray(cfg.alpn) && cfg.alpn.length) {
      ss.tlsSettings.alpn = cfg.alpn.slice();
    }
  }

  if (network === "ws") {
    ss.wsSettings = {
      path: cfg.path || "/",
      headers: cfg.host ? { Host: cfg.host } : {}
    };
  } else if (network === "grpc") {
    ss.grpcSettings = {
      // Prefer explicit serviceName; fall back to path (vmess-legacy).
      serviceName: cfg.serviceName || cfg.path || "",
      // multi/gun modes — multiMode flips to true for "multi", everything
      // else (default "gun") stays false. xray will use single-stream when
      // multiMode is false.
      multiMode: String(cfg.mode || "").toLowerCase() === "multi"
    };
    if (cfg.authority) ss.grpcSettings.authority = cfg.authority;
  } else if (network === "xhttp") {
    // XHTTP — xray's modern transport: HTTP/2 or HTTP/3 frames that look
    // like normal browser traffic. Best paired with Reality for DPI evasion.
    // mode determines upload framing: "auto" lets xray pick, "stream-one"
    // is the stealthiest single-stream variant.
    const mode = (cfg.mode || "auto").toLowerCase();
    ss.xhttpSettings = {
      mode,
      path: cfg.path || "/",
      host: cfg.host || ""
    };
    // `extra` carries the stream-up tuning that servers really care about
    // (scMaxEachPostBytes, scMaxConcurrentPosts, scMinPostsIntervalMs,
    // xPaddingBytes, noGRPCHeader). Prefer the full provider-supplied blob;
    // fall back to the xPaddingBytes shortcut so older keys still work.
    if (cfg.xhttpExtra && typeof cfg.xhttpExtra === "object") {
      ss.xhttpSettings.extra = cfg.xhttpExtra;
    } else if (cfg.xPaddingBytes) {
      ss.xhttpSettings.extra = { xPaddingBytes: cfg.xPaddingBytes };
    }
  }

  return ss;
}

function normalizeMuxConfig(config) {
  const source = config || {};
  let mode = source.mode;
  if (!mode) {
    if (source.enabled === true) {
      const tcpConcurrency = Number(source.concurrency);
      const xudpConcurrency = Number(source.xudpConcurrency);
      mode = tcpConcurrency < 0 && xudpConcurrency > 0 ? "xudp" : "off";
    } else {
      mode = "off";
    }
  }
  if (!MUX_MODES.has(mode)) {
    mode = Number(source.xudpConcurrency) > 0 ? "xudp" : "off";
  }

  const xudpProxyUDP443 = MUX_UDP443_MODES.has(source.xudpProxyUDP443)
    ? source.xudpProxyUDP443
    : "reject";

  return {
    mode,
    tcpConcurrency: 8,
    xudpConcurrency: clampInt(source.xudpConcurrency, 8, 1, 1024),
    xudpProxyUDP443
  };
}

function buildMuxObject(config) {
  const mux = normalizeMuxConfig(config);
  if (mux.mode === "off") {
    return { enabled: false };
  }
  if (mux.mode === "xudp") {
    return {
      enabled: true,
      concurrency: -1,
      xudpConcurrency: mux.xudpConcurrency,
      xudpProxyUDP443: mux.xudpProxyUDP443
    };
  }
  return { enabled: false };
}

function clampInt(value, fallback, min, max) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, parsed));
}

function isProxyConfigEmpty(config) {
  return !config.address && !config.port && !config.uuid && !config.password
    && !config.publicKey && !config.serverName && !config.shortId;
}

function normalizeState(input) {
  // Guard against null / arrays / primitives. Both loadState (localStorage)
  // and remote fetch can return JSON literals other than a plain object;
  // reading `.profiles` on null throws and crashes bootstrap.
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    input = {};
  }
  if (Array.isArray(input.profiles)) {
    const profiles = input.profiles.map(normalizeProfile).filter(Boolean);
    const safeProfiles = profiles.length ? profiles : cloneFallback().profiles;
    const activeProfileId = safeProfiles.some((profile) => profile.id === input.activeProfileId)
      ? input.activeProfileId
      : safeProfiles[0].id;

    return {
      activeProfileId,
      profiles: safeProfiles
    };
  }

  return {
    activeProfileId: "profile-main",
    profiles: [
      normalizeProfile({
        id: "profile-main",
        name: input.profileName || T.profileName,
        domainStrategy: input.domainStrategy || "IPIfNonMatch",
        fallbackOutbound: input.fallbackOutbound || "direct",
        proxyConfig: input.proxyConfig,
        muxConfig: input.muxConfig,
        groups: input.groups
      })
    ]
  };
}

function createEmptyGroup() {
  return {
    id: newId(),
    name: T.newGroup,
    note: "",
    enabled: true,
    outboundTag: "vless-reality",
    domains: [],
    cidrs: []
  };
}

function cloneFallback() {
  return JSON.parse(JSON.stringify(fallbackState));
}

function createEmptyProfile(name = T.defaultProfileName) {
  return {
    id: newId(),
    name,
    domainStrategy: "IPIfNonMatch",
    fallbackOutbound: "direct",
    proxyConfig: createDefaultProxyConfig(),
    muxConfig: createDefaultMuxConfig(),
    proxies: [],
    subscriptions: [],
    activeProxyId: null,
    groups: [createEmptyGroup()]
  };
}

function cloneProfile(profile) {
  return JSON.parse(JSON.stringify(profile));
}

// Only allow characters that are safe as HTML attribute values without
// escaping, and are stable across state.json round-trips. Rejects things
// like `x"><script>` that would break out of `value="${id}"` templates
// on import of a malicious state.json.
function sanitizeId(raw, fallbackPrefix) {
  const s = String(raw == null ? "" : raw).replace(/[^A-Za-z0-9_-]/g, "");
  if (s && s.length <= 128) return s;
  return `${fallbackPrefix}-${newId()}`;
}

// Coerce a proxy port to a valid integer 1..65535. Anything else (empty,
// non-numeric, `<img onerror>`, out-of-range) collapses to empty string so
// the UI can't render attacker-controlled markup around it.
function sanitizeProxyPort(raw) {
  if (raw === "" || raw == null) return "";
  const n = Number(raw);
  if (!Number.isFinite(n)) return "";
  const i = Math.trunc(n);
  if (i < 1 || i > 65535) return "";
  return i;
}

function normalizeProxyEntry(entry) {
  if (!entry || typeof entry !== "object") return null;
  const config = normalizeProxyConfig(entry.config);
  config.port = sanitizeProxyPort(config.port);
  // vless/vmess authenticate by uuid; hysteria2 by password. Accept either.
  const hasAuth = config.uuid || config.password;
  if (!config.address || !hasAuth || !config.port) return null;
  return {
    id: sanitizeId(entry.id, "proxy"),
    name: String(entry.name || config.address || "Unnamed"),
    source: entry.source || "manual",
    config
  };
}

function normalizeSubscriptionEntry(entry) {
  if (!entry || typeof entry !== "object") return null;
  const url = String(entry.url || "").trim();
  if (!url) return null;
  return {
    id: sanitizeId(entry.id, "sub"),
    name: String(entry.name || url.replace(/^https?:\/\//, "").slice(0, 32)),
    url,
    lastFetched: Number.isFinite(entry.lastFetched) ? entry.lastFetched : null,
    lastError: entry.lastError ? String(entry.lastError).slice(0, 200) : null
  };
}

function normalizeProfile(profile) {
  const groups = (Array.isArray(profile.groups) ? profile.groups : []).map((group) => ({
    id: group.id || newId(),
    name: group.name || T.newGroup,
    note: group.note || "",
    enabled: group.enabled !== false,
    outboundTag: (group.outboundTag === "direct" ? "bypass" : (group.outboundTag || "vless-reality")),
    domains: uniq(Array.isArray(group.domains) ? group.domains : []),
    cidrs: uniq(Array.isArray(group.cidrs) ? group.cidrs : [])
  }));

  // New multi-key fields with shape normalization
  const proxies = (Array.isArray(profile.proxies) ? profile.proxies : [])
    .map(normalizeProxyEntry)
    .filter(Boolean);
  const subscriptions = (Array.isArray(profile.subscriptions) ? profile.subscriptions : [])
    .map(normalizeSubscriptionEntry)
    .filter(Boolean);

  const legacy = normalizeProxyConfig(profile.proxyConfig);

  // Migration: if proxies[] is empty but legacy proxyConfig has real fields,
  // create proxies[0] from legacy. Idempotent — running again no-ops since
  // the migrated proxy is already present.
  if (proxies.length === 0 && legacy.address && legacy.uuid) {
    proxies.push({
      id: `proxy-${newId()}`,
      name: legacy.address || "Legacy",
      source: "manual",
      config: legacy
    });
  }

  // Validate activeProxyId: must reference an existing proxy.
  let activeProxyId = profile.activeProxyId || null;
  if (activeProxyId && !proxies.some((p) => p.id === activeProxyId)) {
    activeProxyId = null;
  }
  if (!activeProxyId && proxies.length) {
    activeProxyId = proxies[0].id;
  }

  return {
    id: profile.id || newId(),
    name: profile.name || T.defaultProfileName,
    domainStrategy: profile.domainStrategy || "IPIfNonMatch",
    fallbackOutbound: profile.fallbackOutbound || "direct",
    proxyConfig: legacy,
    muxConfig: normalizeMuxConfig(profile.muxConfig),
    proxies,
    subscriptions,
    activeProxyId,
    groups: groups.length ? groups : [createEmptyGroup()]
  };
}

// Return the proxy config that should drive the xray outbound. Prefers the
// active entry in profile.proxies[]; falls back to legacy profile.proxyConfig
// when nothing is selected (e.g. fresh install before user picks a key).
function getActiveProxyConfig(profile) {
  if (!profile) return createDefaultProxyConfig();
  const proxies = Array.isArray(profile.proxies) ? profile.proxies : [];
  if (proxies.length && profile.activeProxyId) {
    const active = proxies.find((p) => p.id === profile.activeProxyId);
    if (active && active.config) return normalizeProxyConfig(active.config);
  }
  if (proxies.length && proxies[0].config) return normalizeProxyConfig(proxies[0].config);
  return normalizeProxyConfig(profile.proxyConfig);
}

function getActiveProfile() {
  const profiles = state?.profiles || [];
  return profiles.find((profile) => profile.id === state.activeProfileId) || profiles[0] || null;
}

function newId() {
  if (typeof crypto !== "undefined" && crypto && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }

  return `id-${Date.now()}-${Math.random().toString(16).slice(2, 10)}`;
}

function encodeBase64Unicode(value) {
  const bytes = new TextEncoder().encode(String(value || ""));
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function splitLinesOrCsv(text) {
  return uniq(
    text
      .split(/\r?\n|,/g)
      .map((item) => item.trim())
      .filter(Boolean)
  );
}

function uniq(items) {
  return [...new Set((items || []).map((item) => String(item).trim()).filter(Boolean))];
}

function statPill(text) {
  return `<span class="stat-pill">${escapeHtml(text)}</span>`;
}

function slugify(text) {
  return text.toLowerCase().replace(/[^a-z0-9_-]+/gi, "-").replace(/^-+|-+$/g, "");
}

function downloadJson(fileName, data) {
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = fileName;
  link.click();
  URL.revokeObjectURL(url);
}

// True if string looks like a valid domain (one or more labels, dots,
// no IP-like all-numeric labels, no slashes, no spaces).
const DOMAIN_RE = /^(?=.{1,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/;
function looksLikeDomain(str) {
  const s = String(str || "").trim().toLowerCase();
  if (!s) return false;
  if (/^\d+\.\d+\.\d+\.\d+(\/\d+)?$/.test(s)) return false;
  return DOMAIN_RE.test(s);
}
// True if string is a valid IP or IP/mask CIDR.
function looksLikeIpOrCidr(str) {
  return parseCidrEntry(str) !== null;
}

// Split a list into {valid, invalid} based on a predicate.
function partitionList(list, isValid) {
  const valid = [];
  const invalid = [];
  for (const entry of (list || [])) {
    const trimmed = String(entry || "").trim();
    if (!trimmed) continue;
    if (isValid(trimmed)) valid.push(trimmed);
    else invalid.push(trimmed);
  }
  return { valid, invalid };
}

// Dedupe domains: drop subdomains already covered by a parent domain
// in the same list. Match xray's default "domain" rule semantics — a
// rule for foo.com matches foo.com itself plus any *.foo.com.
function dedupeDomainsList(list) {
  const cleaned = [...new Set((list || [])
    .map((d) => String(d || "").trim().toLowerCase())
    .filter(Boolean))];
  if (cleaned.length <= 1) return cleaned;

  const reversed = cleaned.map((d) => ({
    original: d,
    key: d.split(".").reverse().join(".")
  }));
  reversed.sort((a, b) => (a.key < b.key ? -1 : (a.key > b.key ? 1 : 0)));

  const kept = [];
  for (const item of reversed) {
    const covered = kept.some((parent) =>
      item.key === parent.key || item.key.startsWith(parent.key + ".")
    );
    if (!covered) kept.push(item);
  }
  return kept.map((item) => item.original);
}

// Parse "1.2.3.4" or "1.2.3.0/24" into {network, mask}. Returns null
// for anything that isn't a valid IPv4 address or CIDR.
function parseCidrEntry(str) {
  const trimmed = String(str || "").trim();
  if (!trimmed) return null;
  let ip;
  let mask;
  const slashIdx = trimmed.indexOf("/");
  if (slashIdx >= 0) {
    ip = trimmed.slice(0, slashIdx);
    mask = parseInt(trimmed.slice(slashIdx + 1), 10);
    if (!Number.isFinite(mask) || mask < 0 || mask > 32) return null;
  } else {
    ip = trimmed;
    mask = 32;
  }
  const octets = ip.split(".");
  if (octets.length !== 4) return null;
  let intIp = 0;
  for (const o of octets) {
    if (!/^\d+$/.test(o)) return null;
    const n = Number(o);
    if (n < 0 || n > 255) return null;
    intIp = (intIp * 256) + n;
  }
  const maskBits = mask === 0 ? 0 : (0xFFFFFFFF << (32 - mask)) >>> 0;
  const network = (intIp & maskBits) >>> 0;
  return { original: trimmed, network, mask };
}

// Dedupe CIDR/IP list: drop entries fully contained in a wider entry.
// Invalid entries pass through untouched (so users see their typos).
function dedupeCidrsList(list) {
  const seen = new Set();
  const valid = [];
  const invalid = [];
  for (const entry of (list || [])) {
    const trimmed = String(entry || "").trim();
    if (!trimmed) continue;
    const key = trimmed.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    const parsed = parseCidrEntry(trimmed);
    if (parsed) valid.push(parsed);
    else invalid.push(trimmed);
  }
  valid.sort((a, b) => a.mask - b.mask);
  const kept = [];
  for (const item of valid) {
    const covered = kept.some((parent) => {
      if (parent.mask > item.mask) return false;
      const parentBits = parent.mask === 0 ? 0 : (0xFFFFFFFF << (32 - parent.mask)) >>> 0;
      return ((item.network & parentBits) >>> 0) === parent.network;
    });
    if (!covered) kept.push(item);
  }
  return [...kept.map((k) => k.original), ...invalid];
}

function showFieldFlash(el, text) {
  const host = el.parentElement;
  if (!host) return;
  if (getComputedStyle(host).position === "static") {
    host.style.position = "relative";
  }
  let note = host.querySelector(".field-flash");
  if (!note) {
    note = document.createElement("div");
    note.className = "field-flash";
    host.appendChild(note);
  }
  note.textContent = text;
  note.classList.remove("field-flash-show");
  void note.offsetWidth;
  note.classList.add("field-flash-show");
}

function pushDebug(message) {
  const stamp = new Date().toLocaleTimeString("ru-RU");
  debugState.messages.push(`[${stamp}] ${message}`);
  debugState.messages = debugState.messages.slice(-8);
  console.log(message);
}

function formatMessage(template, values = {}) {
  return String(template || "").replace(/\{(\w+)\}/g, (_, key) => values[key] ?? "");
}

// Locale-aware pluralization. `formsKey` names a LOCALES entry like
// `keysPluralForms` (an object keyed by Intl.PluralRules categories:
// one/few/many/other for ru, one/other for en). Returns "{n} {form}".
function pluralize(n, formsKey) {
  const forms = (T && T[formsKey]) || {};
  let category = "other";
  try {
    category = new Intl.PluralRules(currentLang === "en" ? "en" : "ru").select(n);
  } catch (_) { /* older engines: keep "other" */ }
  const form = forms[category] || forms.other || "";
  return `${n} ${form}`;
}

function applyTranslations() {
  document.documentElement.lang = currentLang;
  document.title = T.documentTitle;
  AUTH_REQUIRED_MESSAGE = T.authRequiredMessage;
  AUTH_LOGIN_HINT = T.authLoginHint;

  if (els.langSelect) els.langSelect.value = currentLang;

  if (els.authTitle) els.authTitle.textContent = T.authTitle;
  if (els.authLead) els.authLead.textContent = T.authLead;
  if (els.authLoginLabel) els.authLoginLabel.textContent = T.authLoginLabel;
  if (els.authPasswordLabel) els.authPasswordLabel.textContent = T.authPasswordLabel;
  if (els.authSubmitBtn) els.authSubmitBtn.textContent = T.authSubmit;
  if (els.langLabel) els.langLabel.textContent = T.langLabel;
  if (els.heroTitle) els.heroTitle.textContent = T.heroTitle;
  if (els.heroLead) els.heroLead.textContent = T.heroLead;
  if (els.profileKicker) els.profileKicker.textContent = T.profileKicker;
  if (els.profileTitle) els.profileTitle.textContent = T.profileTitle;
  if (els.activeProfileLabel) els.activeProfileLabel.textContent = T.activeProfileLabel;
  if (els.profileNameLabel) els.profileNameLabel.textContent = T.profileNameLabel;
  if (els.domainStrategyLabel) els.domainStrategyLabel.textContent = T.domainStrategyLabel;
  if (els.fallbackLabel) els.fallbackLabel.textContent = T.fallbackLabel;
  if (els.proxyTitle) els.proxyTitle.textContent = T.proxyPanelTitle || T.proxyTitle;
  if (els.subsHeading) els.subsHeading.textContent = T.subsHeading;
  if (els.manualKeysHeading) els.manualKeysHeading.textContent = T.manualKeysHeading;
  if (els.activeKeyHeading) els.activeKeyHeading.textContent = T.activeKeyHeading;
  if (els.addManualKeyBtn) els.addManualKeyBtn.textContent = T.addManualKeyBtn;
  if (els.addSubscriptionBtn) els.addSubscriptionBtn.textContent = T.addSubscriptionBtn;
  if (els.probeProxyBtn) els.probeProxyBtn.textContent = T.probeActiveBtn || T.probeProxyBtn;
  if (els.keyNameLabelSpan) els.keyNameLabelSpan.textContent = T.keyNameLabel;
  if (els.manualKeyName) els.manualKeyName.placeholder = T.keyNamePlaceholder || "My VPN";
  if (els.advancedFieldsSummary) els.advancedFieldsSummary.textContent = T.advancedFieldsSummary;
  if (els.saveManualKeyBtn) els.saveManualKeyBtn.textContent = T.saveBtn;
  if (els.cancelManualKeyBtn) els.cancelManualKeyBtn.textContent = T.cancelBtn;
  if (els.newSubTitle) els.newSubTitle.textContent = T.newSubTitle;
  if (els.subNameLabelSpan) els.subNameLabelSpan.textContent = T.subNameLabel;
  if (els.newSubscriptionName) els.newSubscriptionName.placeholder = T.subNamePlaceholder;
  if (els.subUrlLabelSpan) els.subUrlLabelSpan.textContent = T.subUrlLabel;
  if (els.saveSubscriptionBtn) els.saveSubscriptionBtn.textContent = T.saveSubscriptionBtn;
  if (els.cancelSubscriptionBtn) els.cancelSubscriptionBtn.textContent = T.cancelBtn;
  if (els.importProxyBtn) els.importProxyBtn.textContent = T.parseUriBtn || T.importProxyBtn;
  if (els.proxyUrlLabel) els.proxyUrlLabel.textContent = T.proxyUrlLabel;
  if (els.proxyAddressLabel) els.proxyAddressLabel.textContent = T.proxyAddressLabel;
  if (els.proxyPortLabel) els.proxyPortLabel.textContent = T.proxyPortLabel;
  if (els.muxKicker) els.muxKicker.textContent = T.muxKicker;
  if (els.muxTitle) els.muxTitle.textContent = T.muxTitle;
  if (els.muxModeLabel) els.muxModeLabel.textContent = T.muxModeLabel;
  if (els.muxUdp443Label) els.muxUdp443Label.textContent = T.muxUdp443Label;
  if (els.muxXudpConcurrencyLabel) els.muxXudpConcurrencyLabel.textContent = T.muxXudpConcurrencyLabel;
  if (els.muxMode) {
    const optionLabels = {
      off: T.muxModeOff,
      xudp: T.muxModeXudp
    };
    for (const option of els.muxMode.options) {
      option.textContent = optionLabels[option.value] || option.value;
    }
  }
  if (els.previewKicker) els.previewKicker.textContent = T.previewKicker;
  if (els.previewTitle) els.previewTitle.textContent = T.previewTitle;
  if (els.groupsKicker) els.groupsKicker.textContent = T.groupsKicker;
  if (els.groupsTitle) els.groupsTitle.textContent = T.groupsTitle;

  if (els.importStateBtn) els.importStateBtn.textContent = T.importBtn;
  if (els.exportStateBtn) els.exportStateBtn.textContent = T.exportBtn;
  if (els.repairRuntimeBtn) els.repairRuntimeBtn.textContent = T.repairBtn;
  if (els.saveApplyBtn) els.saveApplyBtn.textContent = T.saveApplyBtn;
  if (els.logoutBtn) els.logoutBtn.textContent = T.logoutBtn;
  if (els.addProfileBtn) els.addProfileBtn.textContent = T.addProfileBtn;
  if (els.duplicateProfileBtn) els.duplicateProfileBtn.textContent = T.duplicateProfileBtn;
  if (els.removeProfileBtn) els.removeProfileBtn.textContent = T.removeProfileBtn;
  if (els.saveStateBtn) els.saveStateBtn.textContent = T.saveStateBtn;
  if (els.addGroupBtn) els.addGroupBtn.textContent = T.addGroupBtn;

  if (els.importStateBtn) els.importStateBtn.title = T.importStateTitle;
  if (els.exportStateBtn) els.exportStateBtn.title = T.exportStateTitle;
  if (els.saveStateBtn) els.saveStateBtn.title = T.saveStateTitle;
  if (els.saveApplyBtn) els.saveApplyBtn.title = T.saveApplyTitle;
  if (els.repairRuntimeBtn) els.repairRuntimeBtn.title = T.repairTitle;
  if (els.importProxyBtn) els.importProxyBtn.title = T.importProxyTitle;
  if (els.probeProxyBtn) els.probeProxyBtn.title = T.probeProxyTitle;
  if (els.logoutBtn) els.logoutBtn.title = T.logoutTitle || "";

  if (els.profileName) els.profileName.placeholder = T.profileName;

  if (els.healthKicker) els.healthKicker.textContent = T.healthKicker;
  if (els.healthTitle) els.healthTitle.textContent = T.healthTitle;
  if (els.refreshHealthBtn) els.refreshHealthBtn.textContent = T.healthRefreshBtn;
  if (els.restartXrayBtn) els.restartXrayBtn.textContent = T.restartXrayBtn;
  if (els.restartSingboxBtn) els.restartSingboxBtn.textContent = T.restartSingboxBtn;
  if (els.restartSelfhealBtn) els.restartSelfhealBtn.textContent = T.restartSelfhealBtn;
  if (els.logsSelectLabel) els.logsSelectLabel.textContent = T.logsSelectLabel;
  if (els.logsLinesLabel) els.logsLinesLabel.textContent = T.logsLinesLabel;
  if (els.loadLogsBtn) els.loadLogsBtn.textContent = T.loadLogsBtn;
  if (els.logsCopyBtn && !els.logsCopyBtn.classList.contains("copied")) {
    els.logsCopyBtn.textContent = T.logsCopyBtn;
  }
}
