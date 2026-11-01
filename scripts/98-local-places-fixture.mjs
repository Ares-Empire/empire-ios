// Uses aresium's existing packer and tsx loader. No network, private inputs or changes to the source repository.
// node --import /Users/pab/aresium/node_modules/tsx/dist/loader.mjs scripts/98-local-places-fixture.mjs [aresium]
import { writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { gzipSync } from 'node:zlib';
const source = resolve(process.argv[2] ?? `${process.env.HOME}/aresium`);
const { packLocalPlaces } = await import(pathToFileURL(`${source}/scripts/local-places-pack.ts`));
const bytes = packLocalPlaces({
  version: 1, attribution: 'Fictional fixture; no OpenStreetMap data', source: 'Fictional test data',
  dataDate: '2026-11-01', categories: ['groceries'], towns: ['quarzstadt'],
  rows: [['quarzfunken', 0, [0, 0]]],
});
await writeFile(new URL('../Aresium/AresiumTests/Engine/local-places-fixture.places.bin.gz', import.meta.url), gzipSync(bytes));
