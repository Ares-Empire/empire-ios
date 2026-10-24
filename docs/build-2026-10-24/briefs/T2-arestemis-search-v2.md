# T2: Arestemis server, search version 2

Read `COMMON.md` (same folder) first; its rules hold (only your worktree, commit but never push/merge, no SSH, no
secrets). Worktree: `~/wt/Arestemis-search` (branch `search-v2`). Make a venv there with
`/opt/homebrew/bin/python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'`; tests: `.venv/bin/python -m pytest -q`.

## Why

Patrik found the search too fiddly: three kind buttons (own flat / room in a WG / empty 2-person WG), rent tiers,
separate furnished and size fields. He wants: WG or not or both (optional), how many people move in, max flatmates,
m² min and max, city, cold and warm rent ranges, dates, portals, extras. **Every filter is optional on its own**
(it only changes how many listings pass); only places and portals are required.

## The contract is written

`docs/API.md` on your branch (commit `fd57c9b`) is **version 2**; read `Search`, the kind labels under the push
format, and the version-2 note at the end. The samples in `docs/samples/` are already updated. Do not change the
contract; if something in it is unworkable, stop and say so in your final message.

Read also: `CLAUDE.md` (repo rules), `docs/ARCHITECTURE.md`, `src/arestemis/matching.py` (module docstring = the
rules), `llm/provider.py` (prompts and schemas), `describe.py`, `db.py` (migrations), `sources/*.py` (how the
wanted kinds pick portal categories).

## Build

1. **models.py:** `Kind = Literal["flat", "wg"]`; `Search` and `SearchDraft` (`Partial<Search>`) as in the
   contract. Validation: `people` 1–6 (default 1), numbers > 0 (`flatmates_max` ≥ 0), each range `min <= max`
   (the error's `field` is the max, e.g. `search.rent_warm_max`), the move-in window as now. Drop `RentTier`.
   `Overview.version` 2. `KIND_LABELS = {"flat": "Flat", "wg": "WG room"}`.
2. **matching.py** (stage 1; unknown values still pass, update the docstring):
   - kinds: a flat offer needs `flat`, a WG offer needs `wg`.
   - people: a WG offer whose WG size (people the flat is for, `ListingExtra.wg_size`) is known and smaller than
     `people` is out. Everything else about people is the AI's job.
   - rent: each known rent against its range (`rent_warm` vs warm range, `rent_cold` vs cold range); plus, since
     warm ≥ cold: only the cold rent known and over `rent_warm_max` → out; only the warm rent known and under
     `rent_cold_min` → out. Reasons name the numbers ("€1,240 warm is over €1,000").
   - size: a flat offer's `sqm` against `sqm_min`/`sqm_max`; a WG offer's `sqm` (the room) against
     `room_sqm_min`/`room_sqm_max`.
   - `rooms_min` flat offers only; `flatmates_max` WG offers only; move-in window and sublet as now; furnished gone.
3. **Portal queries:** the wanted kinds pick the categories as before, with `wg` where `wg_room`/`wg_empty` were
   (WG-Gesucht: `wg` → WG rooms, `flat` → 1-room flats and flats; Kleinanzeigen and Immowelt only for `flat`).
   Listing kinds from the portals become `flat`/`wg`.
4. **AI** (`llm/provider.py`, `describe.py`):
   - Verify: `describe_search` writes the v2 search; the numbers stay HARD LIMITS (keep that wording). `people`:
     "N people move in together: the offer must suit N people (a flat: not a single flat or 'nur 1 Person'; a WG:
     enough free rooms, or a room for a couple if the text allows couples)"; for 1 person say nothing special.
     Explain that each rent range is for the offer as listed, and which size applies to which kind. The verdict
     schema's kind enum becomes `flat`, `wg`, `other`.
   - Parse ("describe it"): schema and prompt for the v2 fields ("WG oder Wohnung" → both kinds; "zu zweit" →
     people 2; "bis 900 warm" → `rent_warm_max`; "kalt" → the cold range; "möbliert" → `extra`). `describe.py`
     validates each field on its own as now; a min above its max drops the max with an `unclear` note.
   - Applications: when `people` > 1, the AI application text says that N people move in together (the
     `about_me` stays the source for who they are). Check `application_messages`.
5. **notify.py:** subtitle with the new labels.
6. **db.py migration** (the next `MIGRATIONS` entry, SQL with SQLite's JSON functions is fine): stored searches
   become v2 (`wg_room` → `wg`; `wg_empty` → `wg` plus `people: 2`; duplicates removed; `rent_max_warm` →
   `rent_warm_max`; `rent_tiers` and `furnished` removed; missing new fields read as their defaults), and every
   stored listing/match/rejected `kind` `wg_room`/`wg_empty` → `wg`. The live database has one hunt; the migration
   must still be general and tested on a version-1 file with both old kinds.
7. **Tests:** update the suite; add table tests for every new rule (each range end, unknown values pass, the two
   warm/cold cross rules, people vs WG size, sizes per kind, rooms only for flats, flatmates only for WGs), model
   validation (min > max → 400 with the max's `field`, people bounds), the migration, the parse mapping
   (`to_draft`), the verify prompt text for people 1 and 2, `tests/test_models.py` with the new samples.
8. **Docs:** `CLAUDE.md`, `README.md`, `docs/ARCHITECTURE.md` where they describe the old search.

## Live check (allowed)

With the Groq key from the Keychain (`security find-generic-password -s groq-api-key -w` into the env var the config
reads, for that one command; see `config.py`), call the parse step once or twice on sentences like "WG oder Wohnung
in München zu zweit, warm bis 1.400 €, ab Dezember, möbliert" and check the draft. No portal scraping in loops; one
end-to-end run of the existing real-adapter test is fine if it exists and is cheap.

## Done when

- `.venv/bin/python -m pytest -q` passes (say how many tests).
- The migration is tested and its SQL is in `db.py`.
- Committed on `search-v2`. Final message as in COMMON.md, plus: anything in the contract you found doubtful.
