const fs = require("fs");
const vm = require("vm");

const source = fs.readFileSync("ui/xkeen-manager/app.js", "utf8").replace(/\r\n/g, "\n");
const start = source.indexOf("function vpnSeverity(");
const end = source.indexOf("\n}\n", start);
if (start < 0 || end < 0) throw new Error("vpnSeverity not found");

const context = {};
vm.createContext(context);
vm.runInContext(source.slice(start, end + 2), context);

const healthyServices = { singbox: { running: true, listenUdp: true } };
const stoppedServices = { singbox: { running: false, listenUdp: false } };

if (context.vpnSeverity({ transport: "udp", host: "hy2.example", total: 0 }, healthyServices) !== "ok") {
  throw new Error("idle HY2 was incorrectly reported as unhealthy");
}
if (context.vpnSeverity({ transport: "udp", host: "hy2.example", total: 0 }, stoppedServices) !== "critical") {
  throw new Error("stopped sing-box was not reported as critical");
}
if (context.vpnSeverity({ transport: "tcp", established: 0 }, healthyServices) !== "warn") {
  throw new Error("legacy TCP idle warning changed");
}
console.log("PASS: HY2 health uses sing-box UDP readiness; TCP behavior is preserved");
