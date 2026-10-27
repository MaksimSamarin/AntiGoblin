(function (root) {
  "use strict";
  // Confirmed voice and stream destinations as of 2026-10-12. Keep exact
  // host routes: the surrounding Cloudflare ranges serve other applications.
  const discordMediaCidrs = Object.freeze([
    "66.22.192.0/18",
    "104.29.149.49/32",
    "104.29.155.176/32",
    "104.29.155.181/32",
    "104.29.155.185/32",
    "104.29.155.187/32",
    "104.29.155.196/32",
    "104.29.155.201/32",
    "104.29.155.204/32",
    "104.29.158.3/32"
  ]);
  const rows = [
    ["chatgpt", "ChatGPT", "ai", "openai", true],
    ["claude", "Claude", "ai", "anthropic", true],
    ["copilot", "GitHub Copilot", "ai", "github-copilot"],
    ["gemini", "Gemini", "ai", "google-gemini"],
    ["perplexity", "Perplexity", "ai", "perplexity"],
    ["deepseek", "DeepSeek", "ai", "deepseek"],
    ["discord", "Discord", "social", "discord", true],
    ["telegram", "Telegram", "social", "telegram", true, "telegram"],
    ["whatsapp", "WhatsApp", "social", "whatsapp", true],
    ["instagram", "Instagram", "social", "instagram", true],
    ["facebook", "Facebook", "social", "facebook"],
    ["twitter", "X / Twitter", "social", "twitter"],
    ["reddit", "Reddit", "social", "reddit"],
    ["tiktok", "TikTok", "social", "tiktok", true],
    ["linkedin", "LinkedIn", "social", "linkedin"],
    ["youtube", "YouTube", "media", "youtube", true],
    ["twitch", "Twitch", "media", "twitch", true],
    ["netflix", "Netflix", "media", "netflix", true, "netflix"],
    ["spotify", "Spotify", "media", "spotify", true],
    ["steam", "Steam", "games", "steam", true],
    ["epicgames", "Epic Games", "games", "epicgames"],
    ["blizzard", "Blizzard / WoW", "games", "blizzard"],
    ["xbox", "Xbox", "games", "xbox"],
    ["playstation", "PlayStation", "games", "playstation"],
    ["github", "GitHub", "work", "github"],
    ["zoom", "Zoom", "work", "zoom"],
    ["notion", "Notion", "work", "notion"],
    ["figma", "Figma", "work", "figma"],
    ["google", "Google", "ecosystems", "google", false, "google"],
    ["microsoft", "Microsoft", "ecosystems", "microsoft"],
    ["apple", "Apple", "ecosystems", "apple"]
  ];
  // BluOS has no GeoSite category. Keep its own domains explicit rather
  // than sending unrelated AWS/CloudFront customers through this preset.
  const nadBluos = Object.freeze({
    id: "nad-bluos", name: "NAD / BluOS", category: "media", popular: false,
    domains: Object.freeze([
      "bluos.net",
      "bluos.io",
      "bluesound.com",
      "nadelectronics.com",
      // C700 V2 stage2 diagnostics, verified 2026-10-27.
      "d27y2nb09d21cl.cloudfront.net"
    ]),
    cidrs: Object.freeze([])
  });
  const catalog = Object.freeze(rows.map(([id, name, category, code, popular, geoip]) => Object.freeze({
    id, name, category, popular: !!popular,
    domains: Object.freeze([`geosite:${code}`]),
    cidrs: Object.freeze(geoip ? [`geoip:${geoip}`] : id === "discord" ? discordMediaCidrs : [])
  })).concat(nadBluos));
  const get = (id) => catalog.find((s) => s.id === id);
  const unique = (items) => [...new Set((Array.isArray(items) ? items : []).filter((v) => typeof v === "string" && v.trim()).map((v) => v.trim()))];
  function isIPv4Cidr(value) {
    const match = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?:\/(\d{1,2}))?$/.exec(value);
    return !!match && match.slice(1, 5).every((n) => Number(n) <= 255) && (match[5] === undefined || Number(match[5]) <= 32);
  }
  function localVoiceCidrs(profile) {
    return unique((profile?.groups || []).flatMap((g) => g.id === "discord-voice-observed"
      ? (g.cidrs || []) : (g.serviceVoiceCidrs || []))).filter(isVoiceDestination).slice(0, 256);
  }
  function isVoiceDestination(value) {
    return isIPv4Cidr(value) && (!value.includes("/") || value.endsWith("/32"));
  }
  function normalizeGroup(group) {
    if (!Array.isArray(group.serviceIds)) return group;
    const ids = unique(group.serviceIds).filter((id) => /^[a-z0-9_-]{1,64}$/.test(id));
    let manualDomains = unique(Array.isArray(group.serviceManualDomains) ? group.serviceManualDomains : group.domains);
    let manualCidrs = unique(Array.isArray(group.serviceManualCidrs) ? group.serviceManualCidrs : group.cidrs);
    // A newer catalog may introduce IDs this client does not know. Retain
    // their materialized routes as manual rules rather than dropping traffic.
    if (ids.some((id) => !get(id))) {
      manualDomains = unique([...manualDomains, ...(group.domains || [])]);
      manualCidrs = unique([...manualCidrs, ...(group.cidrs || [])]);
    }
    const voice = group.serviceVoiceEnabled !== false;
    const local = unique(group.serviceVoiceCidrs).filter(isVoiceDestination).slice(0, 256);
    const selected = ids.map(get).filter(Boolean);
    const domains = unique([...manualDomains, ...selected.flatMap((s) => s.domains)]);
    const cidrs = unique([...manualCidrs, ...selected.flatMap((s) => s.id === "discord" && !voice ? [] : s.cidrs),
      ...(ids.includes("discord") && voice ? local : [])]);
    return { ...group, serviceIds: ids, serviceManualDomains: manualDomains, serviceManualCidrs: manualCidrs,
      serviceVoiceEnabled: voice, serviceVoiceCidrs: local, domains, cidrs,
      // An empty enabled VPN group means a full tunnel to the runtime. Never
      // turn removing the last preset into an accidental UDP catch-all.
      enabled: domains.length || cidrs.length ? group.enabled !== false : false };
  }
  function selectServices(group, ids, options = {}) {
    const prior = Array.isArray(group.serviceIds);
    return normalizeGroup({ ...group, serviceIds: unique(ids),
      serviceManualDomains: prior ? group.serviceManualDomains : unique(group.domains),
      serviceManualCidrs: prior ? group.serviceManualCidrs : unique(group.cidrs),
      serviceVoiceEnabled: options.voiceEnabled === undefined ? group.serviceVoiceEnabled !== false : options.voiceEnabled !== false,
      serviceVoiceCidrs: unique([...(group.serviceVoiceCidrs || []), ...(options.voiceCidrs || [])]) });
  }
  function scope(service, lang) {
    const ru = lang !== "en";
    if (service.id === "nad-bluos") return ru ? "BluOS · обновления" : "BluOS · updates";
    if (service.id === "discord") return ru ? "Чаты · голос и стримы" : "Chats · voice and streams";
    if (service.id === "whatsapp" || service.id === "zoom") return ru ? "Сайты · звонки отдельно" : "Websites · calls need IP rules";
    if (service.category === "games") return ru ? "Магазин · игры отдельно" : "Store · games need IP rules";
    if (service.category === "ecosystems") return ru ? "Вся экосистема" : "Entire ecosystem";
    return service.cidrs.length ? (ru ? "Сайты и сети" : "Websites and networks") : (ru ? "Сайты" : "Websites");
  }
  const labels = {
    ru: { all: "Все", ai: "AI", social: "Общение", media: "Видео и музыка", games: "Игры", work: "Работа", ecosystems: "Экосистемы",
      title: "Популярные сервисы", search: "Поиск сервиса", add: "Добавить сервисы", edit: "Изменить сервисы", cancel: "Отмена",
      name: "Название группы", route: "Направление", vpn: "Через VPN", bypass: "Мимо VPN", selected: "Выбрано", extra: "Свои дополнительные правила",
      voice: "Голос и стримы Discord", voiceHint: "Добавляет известные медиа-адреса. Discord может менять IP; свои дополнительные правила сохраняются.",
      rules: "Правила выбранных сервисов", quick: "Популярные сервисы", more: "Показать весь каталог", empty: "Сервис не найден",
      group: "Мои сервисы", remove: "Убрать", geoMissing: "Сначала установите базу сервисов кнопкой обновления Geo-баз.",
      geoFailed: "Не удалось проверить базу сервисов.", checking: "Проверяем базу сервисов…", geoReady: "База сервисов установлена", apply: "Добавить в группу" },
    en: { all: "All", ai: "AI", social: "Social", media: "Video and music", games: "Games", work: "Work", ecosystems: "Ecosystems",
      title: "Popular services", search: "Search services", add: "Add services", edit: "Edit services", cancel: "Cancel",
      name: "Group name", route: "Direction", vpn: "Via VPN", bypass: "Bypass VPN", selected: "Selected", extra: "Additional custom rules",
      voice: "Discord voice and streams", voiceHint: "Includes known media destinations. Discord IPs may change; your additional custom rules are retained.",
      rules: "Selected service rules", quick: "Popular services", more: "Show all services", empty: "Service not found",
      group: "My services", remove: "Remove", geoMissing: "Install service databases with the Geo database update button first.",
      geoFailed: "Cannot check service databases.", checking: "Checking service databases…", geoReady: "Service databases installed", apply: "Add to group" }
  };
  const api = { catalog, get, unique, localVoiceCidrs, normalizeGroup, selectServices, scope, labels };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.AntiGoblinServices = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
