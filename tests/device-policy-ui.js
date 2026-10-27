const assert = require("assert");
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync("ui/xkeen-manager/app.js", "utf8").replace(/\r\n/g, "\n");
const extract = (name) => { const start = source.search(new RegExp(`(?:async )?function ${name}\\(`)); assert(start >= 0); return source.slice(start, source.indexOf("\n}\n", start) + 2); };
const elements = Object.fromEntries(["defaultVpnPolicy", "defaultVpnPolicyStatus", "defaultVpnPolicyLabel", "defaultVpnPolicyHelp"].map(id => [id, {}]));
let responses = [], requests = [], toasts = [];
const state = {};
const ctx = { currentLang: "ru", state, appliedStateSnapshot: "{}", currentApplyStep: "", appUpdateActive: false,
  devicePolicyInfo: { enabled: false, ready: true }, devicePolicyBusy: false, devicePolicyDesired: null,
  document: { getElementById: id => elements[id] },
  fetchWithTimeout: async (url, options) => { requests.push({ url, options }); const response = responses.shift(); if (response instanceof Error) throw response; return response; },
  parseResponseOrThrow: async value => value, showToast: (...args) => toasts.push(args), isAuthError: () => false, showAuthOverlay: () => {}, AUTH_LOGIN_HINT: "login", setTimeout: fn => fn() };
vm.createContext(ctx);
for (const name of ["devicePolicyText", "renderDevicePolicy", "devicePolicyRequest", "loadDevicePolicy", "changeDevicePolicy"]) vm.runInContext(extract(name), ctx);
(async () => {
  ctx.renderDevicePolicy();assert.equal(elements.defaultVpnPolicy.checked, false);assert.equal(elements.defaultVpnPolicy.disabled, false);
  ctx.devicePolicyInfo.ready = false;ctx.renderDevicePolicy();assert(elements.defaultVpnPolicy.disabled);
  ctx.devicePolicyInfo.enabled = true;ctx.renderDevicePolicy();assert(!elements.defaultVpnPolicy.disabled, "disabling remains available without a key");
  responses = [{ enabled: false, ready: true }];await ctx.changeDevicePolicy({ target: { checked: false } });
  assert.deepEqual(JSON.parse(requests.at(-1).options.body), { enabled: false });
  assert(!elements.defaultVpnPolicy.checked && !elements.defaultVpnPolicy.disabled);
  responses = [new Error("connection reset during native policy reload"), { enabled: true, ready: true }];
  await ctx.changeDevicePolicy({ target: { checked: true } });
  assert(elements.defaultVpnPolicy.checked);assert.equal(toasts.at(-1)[1].kind, "success");
  const count = requests.length;ctx.appliedStateSnapshot = '{"old":true}';
  await ctx.changeDevicePolicy({ target: { checked: false } });assert.equal(requests.length, count, "unsaved profile edits are not mixed with policy changes");
  ctx.appliedStateSnapshot = "{}";responses = [new Error("apply failed"), { enabled: true, ready: true }, { enabled: true, ready: true }, { enabled: true, ready: true }];
  await ctx.changeDevicePolicy({ target: { checked: false } });
  assert(elements.defaultVpnPolicy.checked);assert.equal(toasts.at(-1)[1].kind, "error");
  console.log("PASS: device checkbox readiness, immediate apply, reconnect recovery, failure state and dirty profile guard");
})().catch(error => { console.error(error); process.exitCode = 1; });
