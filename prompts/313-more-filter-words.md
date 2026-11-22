# 313: Arestemis app: up to 60 filter words

Status: merged 2026-11-19 (fresh Claude reviewer SAFE). Builder: Codex `gpt-6-luna`, reasoning medium. Why: one limit in one model, its message and a test.
Branch: `codex/313-more-filter-words` · Worktree: `../empire-ios-313-filter-words`

The Arestemis server now accepts 60 excluded words per search instead of 20 (server brief 313). Each word stays at most
40 characters. The owner agreed to more filter words on 2026-11-13.

Change only this:

1. `Arestemis/Arestemis/Model/ItemSearchDraft.swift`: a named constant `maxExcludeWords = 60` next to `maxWishLength`,
   used by the `problems` check.
2. The message "Up to 20 words, each at most 40 characters." becomes "Up to 60 words, each at most 40 characters." in
   that file and in `Arestemis/Arestemis/Localizable.xcstrings`, with its German translation updated and the old key
   removed. Keep the catalog's formatting.
3. `Arestemis/ArestemisTests/ItemSearchDraftTests.swift`: 60 words are valid, 61 are a problem.

No layout or design changes, no other files. Never commit or push. `xcodebuild` is blocked in your sandbox, so Claude
runs the tests. Final message: files changed and anything doubtful.
