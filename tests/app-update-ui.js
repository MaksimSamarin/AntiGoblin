const assert = require("assert");
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync("ui/xkeen-manager/app.js", "utf8").replace(/\r\n/g, "\n");
const extract = (name) => {
  const start = source.search(new RegExp(`(?:async )?function ${name}\\(`));
  assert(start >= 0, name);
  return source.slice(start, source.indexOf("\n}\n", start) + 2);
};
const button = {}, version = {}, layout = {};
const controls = { saveApplyBtn: {}, repairRuntimeBtn: {}, importStateBtn: {} };
let responses = [], requests = [], toasts = [], timers = [], confirmed = false, reloads = 0;
const ctx = { currentLang: "ru", currentApplyStep: "", appUpdateActive: false, appUpdateTimer: null,
  appUpdatePollingSince: 0, Date, AUTH_LOGIN_HINT: "login", els: controls,
  document: { getElementById: (id) => id === "updateAppBtn" ? button : version, querySelector: () => layout },
  window: { confirm: () => confirmed }, location: { reload: () => reloads++ },
  fetchWithTimeout: async (url, options) => { requests.push({ url, options }); const value = responses.shift(); if (value instanceof Error) throw value; return value; },
  parseResponseOrThrow: async (value) => value, isAuthError: () => false,
  showAuthOverlay: () => {}, showToast: (text, options) => toasts.push({ text, options }),
  setTimeout: (fn, delay) => { timers.push({ fn, delay }); return timers.length; } };
vm.createContext(ctx);
for (const name of ["interfaceText", "appUpdateRequest", "showAppUpdateState", "pollAppUpdate", "updateApplication"]) vm.runInContext(extract(name), ctx);
const idle = { currentVersion: "1.3.2", latestVersion: "1.3.2", running: false, updateAvailable: false, phase: "idle" };
(async () => {
  responses = [idle]; await ctx.updateApplication();
  assert.equal(requests.length, 1); assert.equal(button.disabled, false);
  responses = [{ ...idle, latestVersion: "1.3.3", updateAvailable: true }]; await ctx.updateApplication();
  assert.equal(requests.length, 2, "cancelling confirmation must not start an update");
  confirmed = true;
  responses = [{ ...idle, latestVersion: "1.3.3", updateAvailable: true }, { ...idle, running: true, phase: "installing" }];
  await ctx.updateApplication();
  assert(JSON.parse(requests.at(-1).options.body).confirm);
  assert(button.disabled && controls.saveApplyBtn.disabled && layout.inert);
  responses = [new Error("connection reset during uhttpd restart")]; await ctx.pollAppUpdate();
  assert.equal(timers.at(-1).delay, 3000); assert.equal(reloads, 0);
  responses = [{ ...idle, phase: "failed", message: "previous configuration restored" }]; await ctx.pollAppUpdate();
  assert.equal(layout.inert, false); assert.equal(button.disabled, false);
  assert.equal(toasts.at(-1).options.kind, "error"); assert.equal(reloads, 0);
  ctx.appUpdatePollingSince = Date.now();
  responses = [{ ...idle, currentVersion: "1.3.3", phase: "succeeded" }]; await ctx.pollAppUpdate();
  assert.equal(toasts.at(-1).options.kind, "success"); timers.at(-1).fn(); assert.equal(reloads, 1);
  assert.equal(version.textContent, "v1.3.3");
  console.log("PASS: updater confirmation, edit lock, reconnect retry, failure and successful reload");
})().catch((error) => { console.error(error); process.exitCode = 1; });
