---
name: test-file-refactor
description: Lossy test-file refactor — cull tests that no longer pull their weight (duplicative, tautological, over-mocked, testing removed behaviour) and surface coverage gaps worth filling. The lossy counterpart to test-file-compaction (which preserves every test). Use when test suites have accumulated noise and you want honest signal, not just shorter files.
---

**Status:** placeholder — not yet implemented.

Intended purpose: lossy test hygiene. Where `test-file-compaction`
preserves every existing test while shrinking the file, this skill
decides which tests deserve to stay, which should be deleted, and which
coverage gaps are worth filling. Runs in the "test hygiene" phase of
`stenswr` alongside `test-file-compaction`.

Do not invoke this skill yet — it has no implementation body.
