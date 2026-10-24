# The Arestoteles search route (contract for E2 and E3, final)

`GET /api/arestoteles/search?q=<query>&limit=<n>`: passages of the vault that answer a query, best first, found by
their words and by their meaning (a German question finds an English passage, a question in other words finds the
passage). No AI writes text: every result is a passage of the vault as it stands.

- **Auth:** as every route (`Authorization: Bearer <Empire token>`; 401 and 403 as in `docs/API.md`).
- **Query:** `q` 1–200 characters after trimming (else 400 `{"error": "…"}`); `limit` 1–30, default 12.
- **Answer 200:**

```json
{
  "commit": "8db2491",
  "meaning": true,
  "results": [
    {
      "note": "Printing press",
      "block": 4,
      "item": 2,
      "position": null,
      "heading": "Spread",
      "text": "Within 50 years **presses** stood in more than 200 towns.",
      "sentence": "Within 50 years presses stood in more than 200 towns.",
      "match": "both"
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `commit` | The vault commit the results come from (the same short hash as in `/vault`'s ETag before the `-`). |
| `meaning` | `false` while the meaning model is not ready (just after a start): the results are then word matches only. |
| `note` | The note's id (as in `/vault`). |
| `block` | Index in that note's `blocks` (as in `/vault`). |
| `item` | For a list: the item's index in the list; else `null`. |
| `position` | For a position: its id (`note`/`block` are then the note and the `positions` block it stands in); else `null`. |
| `heading` | The heading the passage stands under, plain text, or `null`. |
| `text` | The whole passage, inline Markdown as in `/vault`. |
| `sentence` | The passage's one sentence that answers best, plain text (the whole passage if it is one sentence). |
| `match` | `"words"`: holds the query's words; `"meaning"`: found by its meaning only; `"both"`. |

- Passages come from the notes people read: not the `home`, `positions` and `glossary` index pages (the app's
  `VaultSearch` skips the same types). Positions are passages too.
- Sample: `docs/samples/search.json` (the server's real answer for one query on the sample vault).
