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
const progressIds = ["appUpdateProgress", "appUpdateProgressTitle", "appUpdateProgressDetail", "appUpdateProgressSteps", ...[0,1,2,3].map(i => `appUpdateStep${i}`)];
const progress = Object.fromEntries(progressIds.map(id => [id, { dataset: {}, attrs: {}, setAttribute(k,v) { this.attrs[k]=v; }, removeAttribute(k) { delete this.attrs[k]; } }]));
const controls = { saveApplyBtn: {}, repairRuntimeBtn: {}, importStateBtn: {} };
let responses = [], requests = [], toasts = [], timers = [], confirmed = false, reloads = 0;
const ctx = { currentLang: "ru", currentApplyStep: "", appUpdateActive: false, appUpdateTimer: null,
  appUpdatePollingSince: 0, appUpdatePhase: "starting", Date, AUTH_LOGIN_HINT: "login", els: controls,
  document: { getElementById: (id) => id === "updateAppBtn" ? button : id === "appVersion" ? version : progress[id], querySelector: () => layout },
  window: { confirm: () => confirmed }, location: { reload: () => reloads++ },
  fetchWithTimeout: async (url, options) => { requests.push({ url, options }); const value = responses.shift(); if (value instanceof Error) throw value; return value; },
  parseResponseOrThrow: async (value) => value, isAuthError: () => false,
  showAuthOverlay: () => {}, showToast: (text, options) => toasts.push({ text, options }),
  setTimeout: (fn, delay) => { timers.push({ fn, delay }); return timers.length; } };
vm.createContext(ctx);
for (const name of ["interfaceText", "appUpdateRequest", "showAppUpdateProgress", "showAppUpdateState", "pollAppUpdate", "updateApplication"]) vm.runInContext(extract(name), ctx);
const idle = { currentVersion: "1.3.2", latestVersion: "1.3.2", running: false, updateAvailable: false, phase: "idle" };
(async () => {
  responses = [idle]; await ctx.updateApplication();
  assert.equal(requests.length, 1); assert.equal(button.disabled, false);
  assert(progress.appUpdateProgress.hidden, "idle checks do not leave a progress panel behind");
  responses = [{ ...idle, latestVersion: "1.3.3", updateAvailable: true }]; await ctx.updateApplication();
  assert.equal(requests.length, 2, "cancelling confirmation must not start an update");
  confirmed = true;
  responses = [{ ...idle, latestVersion: "1.3.3", updateAvailable: true }, { ...idle, running: true, phase: "installing" }];
  await ctx.updateApplication();
  assert(JSON.parse(requests.at(-1).options.body).confirm);
  assert(button.disabled && controls.saveApplyBtn.disabled && layout.inert);
  assert(!progress.appUpdateProgress.hidden);
  assert(progress.appUpdateProgressTitle.textContent.includes("Устанавливаем"));
  assert.equal(progress.appUpdateStep2.attrs["aria-current"], "step");
  ctx.showAppUpdateState({ ...idle, running: true, phase: "downloading" });
  assert(progress.appUpdateProgressTitle.textContent.includes("Скачиваем"));
  responses = [new Error("connection reset during uhttpd restart")]; await ctx.pollAppUpdate();
  assert.equal(timers.at(-1).delay, 3000); assert.equal(reloads, 0);
  assert(progress.appUpdateProgressTitle.textContent.includes("Переподключаемся"));
  assert.equal(progress.appUpdateStep1.attrs["aria-current"], "step", "reconnecting retains the actual last known stage");
  responses = [{ ...idle, running: true, phase: "verifying" }]; await ctx.pollAppUpdate();
  assert(progress.appUpdateProgressTitle.textContent.includes("Проверяем результат"));
  assert.equal(progress.appUpdateStep3.attrs["aria-current"], "step");
  responses = [{ ...idle, phase: "failed", message: "previous configuration restored" }]; await ctx.pollAppUpdate();
  assert.equal(layout.inert, false); assert.equal(button.disabled, false);
  assert.equal(toasts.at(-1).options.kind, "error"); assert.equal(reloads, 0);
  assert(progress.appUpdateProgressSteps.hidden);
  assert.equal(progress.appUpdateProgressDetail.textContent, "previous configuration restored");
  ctx.appUpdatePollingSince = Date.now();
  responses = [{ ...idle, currentVersion: "1.3.3", phase: "succeeded" }]; await ctx.pollAppUpdate();
  assert.equal(toasts.at(-1).options.kind, "success"); timers.at(-1).fn(); assert.equal(reloads, 1);
  assert.equal(version.textContent, "v1.3.3");
  assert(progress.appUpdateProgressTitle.textContent.includes("завершено"));
  ctx.appUpdatePollingSince = Date.now() - 16 * 60 * 1000;
  responses = [{ ...idle, running: true, phase: "verifying" }]; await ctx.pollAppUpdate();
  assert(progress.appUpdateProgressTitle.textContent.includes("больше времени"));
  assert(button.disabled && timers.at(-1).delay === 2000, "long updates remain locked and keep polling rather than freezing silently");
  console.log("PASS: updater confirmation, edit lock, reconnect retry, failure and successful reload");
})().catch((error) => { console.error(error); process.exitCode = 1; });
