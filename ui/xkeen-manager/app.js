const STORAGE_KEY = "xkeen-manager-state-v1";

const sampleState = {
  profileName: "Домашний XKeen",
  domainStrategy: "IPIfNonMatch",
  inboundTags: ["redirect", "tproxy"],
  directDomains: ["stalcraft.net", "exbo.net", "cdn77.org"],
  fallbackOutbound: "direct",
  groups: [
    {
      id: "sample-ai",
      name: "AI",
      note: "ChatGPT / OpenAI / Anthropic",
      enabled: true,
      outboundTag: "vless-reality",
      domains: ["chatgpt.com", "openai.com", "oaistatic.com", "anthropic.com", "claude.ai", "claude.com"],
      cidrs: []
    },
    {
      id: "sample-telegram",
      name: "Telegram",
      note: "Пример группы с доменами и CIDR",
      enabled: true,
      outboundTag: "vless-reality",
      domains: ["t.me", "telegram.org", "telegram.me", "tdesktop.com"],
      cidrs: ["149.154.160.0/20", "91.108.4.0/22", "91.108.8.0/22"]
    }
  ]
};

let state = loadState();

const els = {
  profileName: document.getElementById("profileName"),
  domainStrategy: document.getElementById("domainStrategy"),
  inboundTags: document.getElementById("inboundTags"),
  directDomains: document.getElementById("directDomains"),
  fallbackOutbound: document.getElementById("fallbackOutbound"),
  groups: document.getElementById("groups"),
  stats: document.getElementById("stats"),
  preview: document.getElementById("routingPreview"),
  addGroupBtn: document.getElementById("addGroupBtn"),
  loadSampleBtn: document.getElementById("loadSampleBtn"),
  exportStateBtn: document.getElementById("exportStateBtn"),
  exportRoutingBtn: document.getElementById("exportRoutingBtn"),
  importStateBtn: document.getElementById("importStateBtn"),
  importRoutingBtn: document.getElementById("importRoutingBtn"),
  importStateInput: document.getElementById("importStateInput"),
  importRoutingInput: document.getElementById("importRoutingInput"),
  copyRoutingBtn: document.getElementById("copyRoutingBtn"),
  copyApplyCmdBtn: document.getElementById("copyApplyCmdBtn"),
  applyCommand: document.getElementById("applyCommand"),
  groupTemplate: document.getElementById("groupTemplate")
};

bindTopLevel();
render();

function bindTopLevel() {
  els.profileName.addEventListener("input", () => { state.profileName = els.profileName.value; persistAndRender(); });
  els.domainStrategy.addEventListener("change", () => { state.domainStrategy = els.domainStrategy.value; persistAndRender(); });
  els.inboundTags.addEventListener("input", () => { state.inboundTags = splitLinesOrCsv(els.inboundTags.value); persistAndRender(); });
  els.directDomains.addEventListener("input", () => { state.directDomains = splitLinesOrCsv(els.directDomains.value); persistAndRender(); });
  els.fallbackOutbound.addEventListener("change", () => { state.fallbackOutbound = els.fallbackOutbound.value; persistAndRender(); });

  els.addGroupBtn.addEventListener("click", () => {
    state.groups.push(createEmptyGroup());
    persistAndRender();
  });

  els.loadSampleBtn.addEventListener("click", () => {
    state = structuredClone(sampleState);
    persistAndRender();
  });

  els.exportStateBtn.addEventListener("click", () => downloadJson(`${slugify(state.profileName || "xkeen")}-state.json`, state));
  els.exportRoutingBtn.addEventListener("click", () => downloadJson("05_routing.generated.json", buildRoutingDocument(state)));
  els.importStateBtn.addEventListener("click", () => els.importStateInput.click());
  els.importRoutingBtn.addEventListener("click", () => els.importRoutingInput.click());

  els.importStateInput.addEventListener("change", async (event) => {
    const file = event.target.files?.[0];
    if (!file) return;
    state = normalizeState(JSON.parse(await file.text()));
    persistAndRender();
    event.target.value = "";
  });

  els.importRoutingInput.addEventListener("change", async (event) => {
    const file = event.target.files?.[0];
    if (!file) return;
    state = importFromRouting(JSON.parse(await file.text()));
    persistAndRender();
    event.target.value = "";
  });

  els.copyRoutingBtn.addEventListener("click", async () => {
    await navigator.clipboard.writeText(JSON.stringify(buildRoutingDocument(state), null, 2));
    els.copyRoutingBtn.textContent = "Скопировано";
    setTimeout(() => { els.copyRoutingBtn.textContent = "Копировать JSON"; }, 1200);
  });

  els.copyApplyCmdBtn.addEventListener("click", async () => {
    await navigator.clipboard.writeText(els.applyCommand.textContent);
    els.copyApplyCmdBtn.textContent = "Скопировано";
    setTimeout(() => { els.copyApplyCmdBtn.textContent = "Копировать apply-команду"; }, 1200);
  });
}

function render() {
  els.profileName.value = state.profileName;
  els.domainStrategy.value = state.domainStrategy;
  els.inboundTags.value = state.inboundTags.join(", ");
  els.directDomains.value = state.directDomains.join("\n");
  els.fallbackOutbound.value = state.fallbackOutbound;
  renderGroups();
  renderPreview();
}

function renderGroups() {
  els.groups.innerHTML = "";
  state.groups.forEach((group) => {
    const node = els.groupTemplate.content.firstElementChild.cloneNode(true);
    const nameEl = node.querySelector(".group-name");
    const noteEl = node.querySelector(".group-note");
    const enabledEl = node.querySelector(".group-enabled");
    const outboundEl = node.querySelector(".group-outbound");
    const domainsEl = node.querySelector(".group-domains");
    const cidrsEl = node.querySelector(".group-cidrs");
    const removeBtn = node.querySelector(".remove-group");

    nameEl.value = group.name;
    noteEl.value = group.note || "";
    enabledEl.checked = group.enabled;
    outboundEl.value = group.outboundTag;
    domainsEl.value = group.domains.join("\n");
    cidrsEl.value = group.cidrs.join("\n");

    nameEl.addEventListener("input", () => updateGroup(group.id, { name: nameEl.value }));
    noteEl.addEventListener("input", () => updateGroup(group.id, { note: noteEl.value }));
    enabledEl.addEventListener("change", () => updateGroup(group.id, { enabled: enabledEl.checked }));
    outboundEl.addEventListener("change", () => updateGroup(group.id, { outboundTag: outboundEl.value }));
    domainsEl.addEventListener("input", () => updateGroup(group.id, { domains: splitLinesOrCsv(domainsEl.value) }));
    cidrsEl.addEventListener("input", () => updateGroup(group.id, { cidrs: splitLinesOrCsv(cidrsEl.value) }));
    removeBtn.addEventListener("click", () => {
      state.groups = state.groups.filter((item) => item.id !== group.id);
      persistAndRender();
    });

    els.groups.appendChild(node);
  });
}

function renderPreview() {
  const routing = buildRoutingDocument(state);
  els.preview.textContent = JSON.stringify(routing, null, 2);
  els.applyCommand.textContent = ".\\scripts\\xkeen\\apply_xkeen_routing_file.ps1 -RoutingFile .\\05_routing.generated.json";

  const activeGroups = state.groups.filter((group) => group.enabled);
  const domainCount = uniq(activeGroups.flatMap((group) => group.domains)).length;
  const cidrCount = uniq(activeGroups.flatMap((group) => group.cidrs)).length;

  els.stats.innerHTML = [
    statPill(`Групп: ${state.groups.length}`),
    statPill(`Активных: ${activeGroups.length}`),
    statPill(`Direct-доменов: ${uniq(state.directDomains).length}`),
    statPill(`VPN-доменов: ${domainCount}`),
    statPill(`CIDR: ${cidrCount}`)
  ].join("");
}

function buildRoutingDocument(inputState) {
  const inboundTags = uniq(inputState.inboundTags.length ? inputState.inboundTags : ["redirect", "tproxy"]);
  const rules = [];
  const directDomains = uniq(inputState.directDomains);

  if (directDomains.length) {
    rules.push({ type: "field", inboundTag: inboundTags, domain: directDomains, outboundTag: "direct" });
  }

  for (const group of inputState.groups.filter((item) => item.enabled)) {
    const domains = uniq(group.domains);
    const cidrs = uniq(group.cidrs);
    if (domains.length) rules.push({ type: "field", inboundTag: inboundTags, domain: domains, outboundTag: group.outboundTag });
    if (cidrs.length) rules.push({ type: "field", inboundTag: inboundTags, ip: cidrs, outboundTag: group.outboundTag });
  }

  rules.push({ type: "field", inboundTag: inboundTags, outboundTag: inputState.fallbackOutbound || "direct" });
  return { routing: { domainStrategy: inputState.domainStrategy || "IPIfNonMatch", rules } };
}

function importFromRouting(doc) {
  const rules = doc?.routing?.rules || [];
  const inboundTags = uniq(rules.flatMap((rule) => Array.isArray(rule.inboundTag) ? rule.inboundTag : []));
  const directRule = rules.find((rule) => rule.outboundTag === "direct" && Array.isArray(rule.domain));
  const grouped = new Map();

  for (const rule of rules) {
    if (!rule.outboundTag || (rule.outboundTag === "direct" && !rule.domain && !rule.ip)) continue;
    if (rule.outboundTag === "direct" && Array.isArray(rule.domain)) continue;
    const key = rule.outboundTag;
    if (!grouped.has(key)) {
      grouped.set(key, {
        id: crypto.randomUUID(),
        name: key === "vless-reality" ? "VPN" : key,
        note: "Импортировано из routing.json",
        enabled: true,
        outboundTag: key,
        domains: [],
        cidrs: []
      });
    }
    const target = grouped.get(key);
    if (Array.isArray(rule.domain)) target.domains.push(...rule.domain);
    if (Array.isArray(rule.ip)) target.cidrs.push(...rule.ip);
  }

  const imported = {
    profileName: "Импортированный routing",
    domainStrategy: doc?.routing?.domainStrategy || "IPIfNonMatch",
    inboundTags: inboundTags.length ? inboundTags : ["redirect", "tproxy"],
    directDomains: uniq(directRule?.domain || []),
    fallbackOutbound: "direct",
    groups: Array.from(grouped.values()).map((group) => ({
      ...group,
      domains: uniq(group.domains),
      cidrs: uniq(group.cidrs)
    }))
  };

  if (!imported.groups.length) imported.groups = [createEmptyGroup()];
  return normalizeState(imported);
}

function updateGroup(id, patch) {
  state.groups = state.groups.map((group) => group.id === id ? { ...group, ...patch } : group);
  persistAndRender();
}

function persistAndRender() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  render();
}

function loadState() {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) return structuredClone(sampleState);
  try { return normalizeState(JSON.parse(raw)); } catch { return structuredClone(sampleState); }
}

function normalizeState(input) {
  return {
    profileName: input.profileName || "Домашний XKeen",
    domainStrategy: input.domainStrategy || "IPIfNonMatch",
    inboundTags: uniq(Array.isArray(input.inboundTags) ? input.inboundTags : ["redirect", "tproxy"]),
    directDomains: uniq(Array.isArray(input.directDomains) ? input.directDomains : []),
    fallbackOutbound: input.fallbackOutbound || "direct",
    groups: (Array.isArray(input.groups) ? input.groups : []).map((group) => ({
      id: group.id || crypto.randomUUID(),
      name: group.name || "Новая группа",
      note: group.note || "",
      enabled: group.enabled !== false,
      outboundTag: group.outboundTag || "vless-reality",
      domains: uniq(Array.isArray(group.domains) ? group.domains : []),
      cidrs: uniq(Array.isArray(group.cidrs) ? group.cidrs : [])
    }))
  };
}

function createEmptyGroup() {
  return { id: crypto.randomUUID(), name: "Новая группа", note: "", enabled: true, outboundTag: "vless-reality", domains: [], cidrs: [] };
}

function splitLinesOrCsv(text) {
  return uniq(text.split(/\r?\n|,/g).map((item) => item.trim()).filter(Boolean));
}

function uniq(items) {
  return [...new Set((items || []).map((item) => String(item).trim()).filter(Boolean))];
}

function statPill(text) {
  return `<span class=\"stat-pill\">${escapeHtml(text)}</span>`;
}

function slugify(text) {
  return text.toLowerCase().replace(/[^a-zа-я0-9]+/gi, "-").replace(/^-+|-+$/g, "");
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
