const STORAGE_KEY = "xkeen-manager-state-v7";
const LANGUAGE_KEY = "xkeen-manager-lang-v1";
const STATE_URL = "./api/routing.cgi?kind=state";
const OUTBOUNDS_URL = "./api/routing.cgi?kind=outbounds";
const PROBE_URL = "./api/routing.cgi?kind=probe";
const REPAIR_URL = "./api/routing.cgi?kind=repair-runtime";
const LOGIN_URL = "./api/routing.cgi?kind=login";
const LOGOUT_URL = "./api/routing.cgi?kind=logout";
const LIVE_ROUTING_URL = "./api/routing.cgi";
const HEALTH_URL = "./api/routing.cgi?kind=health";
const LOGS_URL = "./api/routing.cgi?kind=logs";
const RESTART_SVC_URL = "./api/routing.cgi?kind=restart-svc";

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
    healthFetchFailed: "Не удалось загрузить статус",
    restartXrayBtn: "Перезапустить xray",
    restartSingboxBtn: "Перезапустить sing-box",
    restartSelfhealBtn: "Перезапустить self-heal",
    restartSvcDone: "Перезапуск выполнен",
    restartSvcFailed: "Ошибка перезапуска",
    logsSelectLabel: "Лог",
    logsLinesLabel: "Строк",
    loadLogsBtn: "Загрузить",
    logsLoadFailed: "Не удалось загрузить лог",
    logsEmpty: "(лог пуст)",
    logsCopyBtn: "Скопировать",
    logsCopiedDone: "Скопировано",
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
    healthFetchFailed: "Failed to load health status",
    restartXrayBtn: "Restart xray",
    restartSingboxBtn: "Restart sing-box",
    restartSelfhealBtn: "Restart self-heal",
    restartSvcDone: "Restart done",
    restartSvcFailed: "Restart failed",
    logsSelectLabel: "Log",
    logsLinesLabel: "Lines",
    loadLogsBtn: "Load",
    logsLoadFailed: "Failed to load log",
    logsEmpty: "(log file is empty)",
    logsCopyBtn: "Copy",
    logsCopiedDone: "Copied",
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
  proxyImportUrl: document.getElementById("proxyImportUrl"),
  importProxyBtn: document.getElementById("importProxyBtn"),
  probeProxyBtn: document.getElementById("probeProxyBtn"),
  proxyProbeStatus: document.getElementById("proxyProbeStatus"),
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
  healthChecks: document.getElementById("healthChecks"),
  restartXrayBtn: document.getElementById("restartXrayBtn"),
  restartSingboxBtn: document.getElementById("restartSingboxBtn"),
  restartSelfhealBtn: document.getElementById("restartSelfhealBtn"),
  logsSelectLabel: document.getElementById("logsSelectLabel"),
  logsSelect: document.getElementById("logsSelect"),
  logsLinesLabel: document.getElementById("logsLinesLabel"),
  logsLinesSelect: document.getElementById("logsLinesSelect"),
  loadLogsBtn: document.getElementById("loadLogsBtn"),
  logsPreview: document.getElementById("logsPreview"),
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
    const titleSide = header.firstElementChild || header;
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "panel-collapse-toggle";
    btn.setAttribute("aria-expanded", "true");
    titleSide.insertBefore(btn, titleSide.firstChild);
    const saved = localStorage.getItem(`panel-collapsed-${id}`);
    btn.setAttribute("aria-label", "Свернуть/развернуть");
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
    });
  }

  els.authSubmitBtn.addEventListener("click", async () => {
    const previous = els.authSubmitBtn.textContent;
    els.authSubmitBtn.disabled = true;
    els.authSubmitBtn.textContent = T.authSubmitting;
    els.authSubmitBtn.textContent = "Вход...";
    els.authSubmitBtn.textContent = T.authSubmitting;
    setAuthStatus("info", "");
    try {
      await loginToRouter(els.authLogin.value, els.authPassword.value);
      els.authPassword.value = "";
      await bootstrap();
    } catch (error) {
      showAuthOverlay(error.message || T.invalidLogin);
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
  bindProxyField(els.proxyPort, "port", (value) => {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : "";
  });
  bindProxyField(els.proxyUuid, "uuid");
  bindProxyField(els.proxyFlow, "flow");
  bindProxyField(els.proxyPublicKey, "publicKey");
  bindProxyField(els.proxyServerName, "serverName");
  bindProxyField(els.proxyShortId, "shortId");
  bindProxyField(els.proxyFingerprint, "fingerprint");

  els.importProxyBtn.addEventListener("click", () => {
    try {
      const parsed = parseVlessUrl(els.proxyImportUrl.value);
      const profile = getActiveProfile();
      if (!profile) return;
      profile.proxyConfig = {
        ...normalizeProxyConfig(profile.proxyConfig),
        ...parsed
      };
      persistState();
      renderProxyConfig(profile);
      queueMicrotask(() => setProbeStatus("success", T.loginImported));
      setProbeStatus("success", "VLESS URL импортирован");
    } catch (error) {
      setProbeStatus("error", `Ошибка импорта: ${error.message}`);
    }
  });

  els.probeProxyBtn.addEventListener("click", async () => {
    const profile = getActiveProfile();
    if (!profile) return;
    const config = normalizeProxyConfig(profile.proxyConfig);
    try {
      const probe = await probeProxy(config);
      if (probe.ok) {
        const ipPart = probe.resolvedIp ? `, IP ${probe.resolvedIp}` : "";
        queueMicrotask(() => setProbeStatus("success", formatMessage(T.probeAvailable, { address: probe.address, port: probe.port, ipPart })));
        setProbeStatus("success", `TCP ${probe.address}:${probe.port} доступен${ipPart}`);
      } else {
        setProbeStatus("error", probe.error || "Проверка не прошла");
      }
    } catch (error) {
      setProbeStatus("error", `Ошибка проверки: ${error.message}`);
    }
  });

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
    els.refreshHealthBtn.addEventListener("click", () => { renderHealth().catch(() => {}); });
  }
  for (const [btn, svc] of [
    [els.restartXrayBtn, "xray"],
    [els.restartSingboxBtn, "singbox"],
    [els.restartSelfhealBtn, "selfheal"]
  ]) {
    if (!btn) continue;
    btn.addEventListener("click", async () => {
      const previous = btn.textContent;
      btn.disabled = true;
      btn.textContent = `${previous}...`;
      try {
        await restartService(svc);
        btn.textContent = T.restartSvcDone;
        await renderHealth().catch(() => {});
      } catch (error) {
        btn.textContent = T.restartSvcFailed;
        alert(`${T.restartSvcFailed}: ${error.message}`);
      } finally {
        setTimeout(() => {
          btn.textContent = previous;
          btn.disabled = false;
        }, 1500);
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
      } catch (error) {
        els.logsPreview.textContent = `${T.logsLoadFailed}: ${error.message}`;
      } finally {
        els.loadLogsBtn.textContent = previous;
        els.loadLogsBtn.disabled = false;
      }
    });
  }

  els.repairRuntimeBtn.addEventListener("click", async () => {
    const previous = els.repairRuntimeBtn.textContent;
    els.repairRuntimeBtn.disabled = true;
    els.repairRuntimeBtn.textContent = `${T.repairBtn}...`;
    try {
      await repairRemoteRuntime();
      els.repairRuntimeBtn.textContent = T.repairDone;
      setTimeout(() => {
        els.repairRuntimeBtn.textContent = previous;
      }, 1600);
    } catch (error) {
      if (isAuthError(error)) {
        showAuthOverlay(AUTH_LOGIN_HINT);
      }
      alert(`${T.repairFailed}: ${error.message}`);
      els.repairRuntimeBtn.textContent = previous;
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
    const previous = els.saveStateBtn.textContent;
    els.saveStateBtn.disabled = true;
    els.saveStateBtn.textContent = `${T.saveStateBtn}...`;
    try {
      await saveRemoteState();
      persistState();
      els.saveStateBtn.textContent = T.saveStateDone;
      setTimeout(() => {
        els.saveStateBtn.textContent = previous;
      }, 1400);
    } catch (error) {
      if (isAuthError(error)) {
        showAuthOverlay(AUTH_LOGIN_HINT);
      }
      alert(`${T.saveStateFailed}: ${error.message}`);
      els.saveStateBtn.textContent = previous;
    } finally {
      els.saveStateBtn.disabled = false;
    }
  });

  els.saveApplyBtn.addEventListener("click", async () => {
    const previous = els.saveApplyBtn.textContent;
    els.saveApplyBtn.disabled = true;
    els.saveApplyBtn.textContent = `${T.saveApplyBtn}...`;
    try {
      await saveRemoteState();
      await saveRemoteOutbounds();

      const routingResponse = await fetch(LIVE_ROUTING_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json; charset=utf-8"
        },
        body: JSON.stringify(buildRoutingDocument(getActiveProfile()))
      });
      const routingPayload = await routingResponse.json();
      if (!routingResponse.ok || routingPayload.ok === false) {
        throw new Error(routingResponse.status === 401 ? AUTH_REQUIRED_MESSAGE : (routingPayload.error || `HTTP ${routingResponse.status}`));
      }
      localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
      els.saveApplyBtn.textContent = T.saveApplyDone;
      setTimeout(() => {
        els.saveApplyBtn.textContent = previous;
      }, 1400);
    } catch (error) {
      if (isAuthError(error)) {
        showAuthOverlay(AUTH_LOGIN_HINT);
      }
      alert(`${T.saveApplyFailed}: ${error.message}`);
      els.saveApplyBtn.textContent = previous;
    } finally {
      els.saveApplyBtn.disabled = false;
    }
  });
}

async function saveRemoteState() {
  const stateResponse = await fetch(STATE_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8"
    },
    body: JSON.stringify(state)
  });
  const statePayload = await stateResponse.json();
  if (!stateResponse.ok || statePayload.ok === false) {
    throw new Error(stateResponse.status === 401 ? AUTH_REQUIRED_MESSAGE : (statePayload.error || `HTTP ${stateResponse.status}`));
  }
}

async function saveRemoteOutbounds() {
  const profile = getActiveProfile();
  if (!profile) throw new Error("active profile missing");
  const outboundsResponse = await fetch(OUTBOUNDS_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8"
    },
    body: JSON.stringify(buildOutboundsDocument(profile))
  });
  const outboundsPayload = await outboundsResponse.json();
  if (!outboundsResponse.ok || outboundsPayload.ok === false) {
    throw new Error(outboundsResponse.status === 401 ? AUTH_REQUIRED_MESSAGE : (outboundsPayload.error || `HTTP ${outboundsResponse.status}`));
  }
}

async function repairRemoteRuntime() {
  const response = await fetch(REPAIR_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8"
    },
    body: "{}"
  });
  const payload = await response.json();
  if (!response.ok || payload.ok === false) {
    throw new Error(response.status === 401 ? AUTH_REQUIRED_MESSAGE : (payload.error || `HTTP ${response.status}`));
  }
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

  const badges = [
    { name: "xray", svc: services.xray, extras: [
      services.xray && services.xray.listenTcp ? "tcp 61219" : null,
      services.xray && services.xray.listenRelayUdp ? "udp 62640" : null
    ] },
    { name: "sing-box", svc: services.singbox, extras: [
      services.singbox && services.singbox.listenUdp ? "udp 61221" : null
    ] },
    { name: "self-heal", svc: services.selfheal, extras: [] }
  ];
  els.healthBadges.innerHTML = badges.map((item) => {
    if (!item.svc) {
      return `<div class="health-badge health-bad"><span class="health-dot" aria-hidden="true"></span><span class="health-text"><span class="health-name">${escapeHtml(item.name)}</span><span class="health-status">?</span></span></div>`;
    }
    const okClass = item.svc.running ? "health-ok" : "health-bad";
    const status = item.svc.running ? T.healthRunning : T.healthStopped;
    const pid = item.svc.pid ? `<span class="health-pid">pid ${escapeHtml(String(item.svc.pid))}</span>` : "";
    const extras = item.extras.filter(Boolean).map((x) => `<span class="health-extra">${escapeHtml(x)}</span>`).join("");
    return `<div class="health-badge ${okClass}">
      <span class="health-dot" aria-hidden="true"></span>
      <span class="health-text">
        <span class="health-name">${escapeHtml(item.name)}</span>
        <span class="health-status">${escapeHtml(status)}</span>
      </span>
      ${pid}
      ${extras ? `<span class="health-extra">${extras}</span>` : ""}
    </div>`;
  }).join("");

  const checkRows = [
    { label: T.healthCheckTproxy, ok: checks.tproxyRuleAtEnd },
    { label: T.healthCheckIpRule, ok: checks.ipRuleMasked },
    { label: T.healthCheckUdpIpset, ok: checks.udpIpsetExists, extra: sizes.udpRoute != null ? `${sizes.udpRoute} ${T.cidrShort}` : null },
    { label: T.healthCheckBypassIpset, ok: checks.bypassIpsetExists, extra: sizes.bypass != null ? `${sizes.bypass} ${T.cidrShort}` : null }
  ];
  els.healthChecks.innerHTML = checkRows.map((row) => {
    const okClass = row.ok ? "check-ok" : "check-bad";
    const okText = row.ok ? T.healthCheckPass : T.healthCheckFail;
    const extra = row.extra ? ` <span class="check-extra">${escapeHtml(row.extra)}</span>` : "";
    return `<div class="check-row ${okClass}"><span class="check-mark">${row.ok ? "✓" : "✗"}</span><span class="check-label">${escapeHtml(row.label)}</span><span class="check-status">${escapeHtml(okText)}</span>${extra}</div>`;
  }).join("");
}

async function fetchHealth() {
  const response = await fetch(HEALTH_URL, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(response.status === 401 ? AUTH_REQUIRED_MESSAGE : `HTTP ${response.status}`);
  }
  return response.json();
}

async function fetchLogs(svc, lines) {
  const url = `${LOGS_URL}&svc=${encodeURIComponent(svc)}&n=${encodeURIComponent(lines)}`;
  const response = await fetch(url, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(response.status === 401 ? AUTH_REQUIRED_MESSAGE : `HTTP ${response.status}`);
  }
  return response.text();
}

async function restartService(svc) {
  const response = await fetch(RESTART_SVC_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({ svc })
  });
  const payload = await response.json();
  if (!response.ok || payload.ok === false) {
    throw new Error(response.status === 401 ? AUTH_REQUIRED_MESSAGE : (payload.error || `HTTP ${response.status}`));
  }
  return payload;
}

async function probeProxy(config) {
  const response = await fetch(PROBE_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8"
    },
    body: JSON.stringify({
      address: config.address,
      port: Number(config.port)
    })
  });
  const payload = await response.json();
  if (!response.ok || payload.ok === false) {
    throw new Error(response.status === 401 ? AUTH_REQUIRED_MESSAGE : (payload.error || `HTTP ${response.status}`));
  }
  return payload;
}

async function loginToRouter(login, password) {
  const safeLogin = String(login || "").trim();
  const safePassword = String(password || "");
  if (!safeLogin || !safePassword) {
    throw new Error("Заполни логин и пароль");
  }

  const response = await fetch(LOGIN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8"
    },
    body: JSON.stringify({
      loginB64: encodeBase64Unicode(safeLogin),
      passwordB64: encodeBase64Unicode(safePassword)
    })
  });

  const payload = await response.json();
  if (!response.ok || payload.ok === false) {
    throw new Error(payload.error || `HTTP ${response.status}`);
  }
  return payload;
}

async function logoutFromRouter() {
  const response = await fetch(LOGOUT_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8"
    },
    body: "{}"
  });

  const payload = await response.json();
  if (!response.ok || payload.ok === false) {
    throw new Error(payload.error || `HTTP ${response.status}`);
  }
  return payload;
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
            <textarea class="group-cidrs" rows="9" placeholder="140.82.112.0/20&#10;20.199.39.0/24"></textarea>
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

    let collapsed = true;
    const setCollapsed = (value) => {
      collapsed = value;
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
    removeBtn.addEventListener("click", () => {
      profile.groups = profile.groups.filter((item) => item.id !== group.id);
      persistAndRender();
    });

    setCollapsed(true);

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

  for (const group of inputState.groups.filter((item) => item.enabled && item.outboundTag !== "direct" && item.outboundTag !== "bypass")) {
    const domains = uniq(group.domains);
    const cidrs = uniq(group.cidrs);

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

function importFromRouting(doc) {
  const rules = doc?.routing?.rules || [];
  const inboundTags = uniq(rules.flatMap((rule) => Array.isArray(rule.inboundTag) ? rule.inboundTag : []));
  const grouped = new Map();
  const fallbackRule = rules.find((rule) => rule.outboundTag && !rule.domain && !rule.ip && !rule.network);

  for (const rule of rules) {
    if (!rule.outboundTag || (!rule.domain && !rule.ip)) continue;

    const tag = rule.outboundTag === "direct" ? "bypass" : rule.outboundTag;
    const key = `${tag}`;
    if (!grouped.has(key)) {
      grouped.set(key, {
        id: newId(),
        name: tag === "vless-reality" ? "VPN" : (tag === "bypass" ? T.bypassGroupName : tag),
        note: T.imported,
        enabled: true,
        outboundTag: tag,
        domains: [],
        cidrs: []
      });
    }

    const target = grouped.get(key);
    if (Array.isArray(rule.domain)) target.domains.push(...rule.domain);
    if (Array.isArray(rule.ip)) target.cidrs.push(...rule.ip);
  }

  const imported = {
    profileName: T.currentState,
    domainStrategy: doc?.routing?.domainStrategy || "IPIfNonMatch",
    fallbackOutbound: fallbackRule?.outboundTag || "direct",
    groups: Array.from(grouped.values()).map((group) => ({
      ...group,
      domains: uniq(group.domains),
      cidrs: uniq(group.cidrs)
    }))
  };

  if (!imported.groups.length) {
    imported.groups = [createEmptyGroup()];
  }

  return normalizeState(imported);
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

function persistState() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
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

async function loadRemoteState(force = false) {
  const response = await fetch(STATE_URL, { cache: force ? "reload" : "no-store" });
  if (!response.ok) {
    throw new Error(response.status === 401 ? AUTH_REQUIRED_MESSAGE : `state fetch failed: ${response.status}`);
  }
  return normalizeState(parseJsonText(await response.text()));
}

async function loadRemoteOutbounds(force = false) {
  const response = await fetch(OUTBOUNDS_URL, { cache: force ? "reload" : "no-store" });
  if (!response.ok) {
    throw new Error(response.status === 401 ? AUTH_REQUIRED_MESSAGE : `outbounds fetch failed: ${response.status}`);
  }
  return parseJsonText(await response.text());
}

function isAuthError(error) {
  const message = String(error?.message || "");
  return /\b401\b/.test(message) || message.includes("router ui authorization required") || message.includes(AUTH_REQUIRED_MESSAGE);
}

function announceAuthRequired() {
  els.preview.textContent = AUTH_REQUIRED_MESSAGE;
  els.stats.textContent = AUTH_REQUIRED_MESSAGE;
  setProbeStatus("error", AUTH_REQUIRED_MESSAGE);
}

function showAuthOverlay(message = AUTH_LOGIN_HINT) {
  if (!els.authOverlay) return;
  els.authOverlay.hidden = false;
  els.authLead.textContent = message || AUTH_LOGIN_HINT;
  if (!els.authLogin.value) {
    els.authLogin.value = "admin";
  }
  setAuthStatus("info", "");
  setTimeout(() => els.authLogin.focus(), 0);
}

function hideAuthOverlay() {
  if (!els.authOverlay) return;
  els.authOverlay.hidden = true;
  setAuthStatus("info", "");
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
    if (!remoteConfig) return;
    for (const profile of state.profiles || []) {
      const current = normalizeProxyConfig(profile.proxyConfig);
      if (isProxyConfigEmpty(current)) {
        profile.proxyConfig = { ...remoteConfig };
      }
    }
  } catch (error) {
    pushDebug(`hydrateProxyConfigFromRemote failed: ${error.message}`);
  }
}

function parseJsonText(text) {
  return JSON.parse(String(text).replace(/^\uFEFF/, ""));
}

function parseVlessUrl(input) {
  const value = String(input || "").trim();
  if (!value.startsWith("vless://")) {
    throw new Error("нужна ссылка вида vless://...");
  }

  const url = new URL(value);
  const params = url.searchParams;
  if ((params.get("security") || "").toLowerCase() !== "reality") {
    throw new Error("ожидался security=reality");
  }

  return normalizeProxyConfig({
    address: url.hostname,
    port: Number(url.port || 0) || "",
    uuid: decodeURIComponent(url.username || ""),
    flow: params.get("flow") || "xtls-rprx-vision",
    publicKey: params.get("pbk") || "",
    serverName: params.get("sni") || "",
    shortId: params.get("sid") || "",
    fingerprint: params.get("fp") || "random"
  });
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
}

function setProbeStatus(kind, message) {
  els.proxyProbeStatus.hidden = false;
  els.proxyProbeStatus.className = `probe-status ${kind}`;
  els.proxyProbeStatus.textContent = message;
}

function buildOutboundsDocument(profile) {
  const config = normalizeProxyConfig(profile.proxyConfig);
  return {
    outbounds: [
      {
        tag: "vless-reality",
        protocol: "vless",
        settings: {
          vnext: [
            {
              address: config.address,
              port: Number(config.port),
              users: [
                {
                  id: config.uuid,
                  encryption: "none",
                  flow: config.flow || "xtls-rprx-vision",
                  level: 0
                }
              ]
            }
          ]
        },
        streamSettings: {
          network: "tcp",
          security: "reality",
          realitySettings: {
            publicKey: config.publicKey,
            fingerprint: config.fingerprint || "random",
            serverName: config.serverName,
            shortId: config.shortId,
            spiderX: "/"
          }
        },
        mux: {
          enabled: false
        }
      },
      {
        protocol: "freedom",
        tag: "direct"
      }
    ]
  };
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

function createDefaultProxyConfig() {
  return {
    address: "",
    port: "",
    uuid: "",
    flow: "xtls-rprx-vision",
    publicKey: "",
    serverName: "",
    shortId: "",
    fingerprint: "random"
  };
}

function normalizeProxyConfig(config) {
  return {
    ...createDefaultProxyConfig(),
    ...(config || {})
  };
}

function isProxyConfigEmpty(config) {
  return !config.address && !config.port && !config.uuid && !config.publicKey && !config.serverName && !config.shortId;
}

function normalizeState(input) {
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
    groups: [createEmptyGroup()]
  };
}

function cloneProfile(profile) {
  return JSON.parse(JSON.stringify(profile));
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

  return {
    id: profile.id || newId(),
    name: profile.name || T.defaultProfileName,
    domainStrategy: profile.domainStrategy || "IPIfNonMatch",
    fallbackOutbound: profile.fallbackOutbound || "direct",
    proxyConfig: normalizeProxyConfig(profile.proxyConfig),
    groups: groups.length ? groups : [createEmptyGroup()]
  };
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

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
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
  if (els.proxyTitle) els.proxyTitle.textContent = T.proxyTitle;
  if (els.proxyUrlLabel) els.proxyUrlLabel.textContent = T.proxyUrlLabel;
  if (els.proxyAddressLabel) els.proxyAddressLabel.textContent = T.proxyAddressLabel;
  if (els.proxyPortLabel) els.proxyPortLabel.textContent = T.proxyPortLabel;
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
  if (els.importProxyBtn) els.importProxyBtn.textContent = T.importProxyBtn;
  if (els.probeProxyBtn) els.probeProxyBtn.textContent = T.probeProxyBtn;
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
