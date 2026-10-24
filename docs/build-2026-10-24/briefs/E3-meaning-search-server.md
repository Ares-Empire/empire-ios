# E3: meaning search on the Arestoteles server

Read `E-COMMON.md` first (the iOS parts don't apply to you), then `E-search-contract.md` (final), then in your
worktree `CLAUDE.md`, `README.md`, `docs/API.md`, `deploy/README.md`, `src/arestoteles/` (`reader.py`, `index.py`,
`service.py`, `api.py`, `models.py`) and `tests/`. Worktree: `~/wt/Arestoteles-search` (branch `meaning-search`, from
`~/Arestoteles` main). No iOS work.

## Why

Patrik asked for search "kinda like Google": find the passage that answers a question even when it uses other words,
or when the question is German and the note English (his notes are English with German terms). **No generated
answers** (the lead's call: for a figure or a source the exact passage is the answer, and a small model could get a
figure wrong); every result is a passage as it stands.

## How it works

- **Passages:** every paragraph, list item, quote, callout and position of the notes people read (see the contract),
  with note id, block index, item, heading. Built from the same parsed vault that `/vault` serves (one source of
  truth), rebuilt whenever the vault is rebuilt (after a pull or an edit).
- **Words:** BM25 over the passages with case and accent folding like the app's (`"Handelsstadte"` finds
  `"Handelsstädte"`). A small own implementation is fine.
- **Meaning:** a multilingual sentence-embedding model on the CPU through ONNX (`fastembed`, or `onnxruntime` +
  `tokenizers` directly; no torch). Limits: at most about 600 MB more memory on the server (4 cores, x86_64, 8 GB,
  about 4 GB free, Python 3.13), model files at most about 500 MB, a query answered in at most about 300 ms. The files
  live outside git in `ARESTOTELES_MODELS` (default `/var/lib/arestoteles/models`), fetched by a documented deploy
  command, never during a request.
- **Cache:** the passages' embeddings are kept on disk by text hash (default under `/var/lib/arestoteles/`, a setting
  like the others in `config.py`), so a pull re-embeds only the passages that changed. Embedding runs in the
  background: the API answers at once and, until it is ready, gives word matches with `"meaning": false`.
- **Ranking:** fuse the two lists (reciprocal rank fusion or similar; passages holding all the query's words rank
  higher); `match` says which side found it; `sentence` is the passage's best sentence for the query.
- The model sits behind a small interface; **tests use a fake embedder** (deterministic, no download) and all run
  without the model. One optional test with the real model, skipped when its files are missing.

## Choosing the model

Write about 20 queries for the sample vault (`tests/fixtures`, the vault behind `docs/samples/`): English and German,
questions in other words than the note, a figure, a source, a term. Each with the passage it should find. Compare two
or three multilingual candidates (for example `intfloat/multilingual-e5-small`,
`sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2`, and one more you think fits) by hits@1 / hits@3, memory
and query time, and keep the script and queries in the repo (`scripts/` or `tests/`). You may also run the same script
read-only against Patrik's real vault (`~/Documents/Patrik Breeck/Weltbild`) with queries you invent; report only the
numbers, never its text. If the local Python 3.14 has no wheels for the runtime, say so, keep the fake-embedder tests
green, and write the exact commands for the lead to run the comparison on the server.

## Done when

- `pytest` passes (old and new tests); the route matches the contract; `docs/API.md` documents it (and the
  `meaning` flag), `docs/samples/search.json` is the real answer for one query on the sample vault (generate it the
  way the other samples are made, see `docs/API.md` → Samples), `deploy/README.md` has the install, the model download
  and the memory note, README/CLAUDE.md are current.
- Your final message has the model comparison table and the exact deploy steps.
