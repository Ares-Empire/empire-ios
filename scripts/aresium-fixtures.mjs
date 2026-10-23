// Refreshes the Aresium test fixtures from the aresium repo (run from anywhere):
//   node ~/empire-ios/scripts/aresium-fixtures.mjs [path/to/aresium]
// 1. copies the server's generated sample (aresium: `npm run sample` writes it),
// 2. writes the website's own answers for it (web/public/app/data.js), which
//    ServerSampleMatchesWebsiteTests compares the app against.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const aresium = process.argv[2] ?? path.join(os.homedir(), "aresium");
const tests = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "Aresium", "AresiumTests");
const samplePath = path.join(aresium, "web/public/app/dashboard.sample.json");
const sample = JSON.parse(fs.readFileSync(samplePath, "utf8"));
fs.copyFileSync(samplePath, path.join(tests, "server-dashboard.sample.json"));

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
