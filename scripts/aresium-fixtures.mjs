// Refreshes the Aresium test fixtures from the aresium repo (run from anywhere):
//   node ~/empire-ios/scripts/aresium-fixtures.mjs [path/to/aresium]
// 1. runs the same sample builder as `npm run sample`, without writing into the service checkout,
// 2. writes the website's own answers for it (web/public/app/data.js), which
//    ServerSampleMatchesWebsiteTests compares the app against.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import vm from "node:vm";
import { execFileSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const aresium = process.argv[2] ?? path.join(os.homedir(), "aresium");
const tests = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "Aresium", "AresiumTests");
// Use the service's existing TypeScript loader and functions; never rebuild or modify its checkout.
const serviceURL = (relative) => pathToFileURL(path.join(aresium, relative)).href;
const generated = JSON.parse(execFileSync(process.execPath, [
  "--import", serviceURL("node_modules/tsx/dist/loader.mjs"), "--input-type=module", "-e",
  `import { buildWebSample } from ${JSON.stringify(serviceURL("src/data/web-sample.ts"))};
   import { buildSampleSource } from ${JSON.stringify(serviceURL("src/data/sample-source.ts"))};
   import { buildDashboard } from ${JSON.stringify(serviceURL("src/data/dashboard.ts"))};
   console.log(JSON.stringify({ web: buildWebSample(), engine: buildDashboard(buildSampleSource()) }));`,
], { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 }));
const sample = generated.web;
fs.writeFileSync(path.join(tests, "server-dashboard.sample.json"), JSON.stringify(sample) + "\n");
// Brief 218 expanded the web demo. The original source remains a separate engine oracle.
fs.writeFileSync(path.join(tests, "Engine/dashboard.sample-expected.json"), JSON.stringify(generated.engine) + "\n");

const window = { AresiumSample: sample };
const context = vm.createContext({ window, location: { protocol: "file:" }, fetch: async () => ({}) });
vm.runInContext(fs.readFileSync(path.join(aresium, "web/public/app/data.js"), "utf8"), context);
const D = window.AresiumData;
const keys = D.months.map((m) => m.key);
const side = (names, monthList, txns) => Object.fromEntries(names.map((n) => [n, {
  months: monthList(n).map((m) => [m.key, m.total]),
  txns: Object.fromEntries(keys.map((k) => [k, txns(n, k).map((t) => [t.id, t.tagged])])),
}]));
const expected = {
  spend: side(sample.categories.map((c) => c.name), D.categoryMonthList, D.categoryMonthTransactions),
  income: side(sample.incomeBuckets.map((c) => c.name), D.incomeBucketMonthList, D.incomeBucketMonthTransactions),
  pick: D.pick,
};
fs.writeFileSync(path.join(tests, "server-dashboard.expected.json"), JSON.stringify(expected));
const count = (s) => Object.values(s).reduce((a, v) => a + v.months.length + Object.values(v.txns).reduce((b, l) => b + l.length, 0), 0);
console.log(`fixtures updated: ${keys.length} months, ${count(expected.spend) + count(expected.income)} list values, pick ${D.pick.spend.length}+${D.pick.income.length}`);
