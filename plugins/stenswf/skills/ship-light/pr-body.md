# ship-light — PR body template

Verbatim — no brevity compression. `## Notable assumptions` is omitted
entirely if Phase 3 recorded none.

```
Closes #$ARGUMENTS

## Summary
- <bullet 1: what changed>
- <bullet 2: how it was tested>
- <bullet 3: notable trade-off, or "none">

## Tests added (red → green)
- `<test name 1>`
- `<test name 2>`

## Notable assumptions
- <only include if silent assumptions were recorded; else omit section>
```

`## Decisions` is appended below this by
[../../scripts/publish-decisions.sh](../../scripts/publish-decisions.sh)
at Phase 4 — do not hand-write it, and do not edit inside its
`<!-- stenswf:decisions:… -->` markers; later refreshes replace whatever
sits between them.

The two sections sit next to each other and are not the same thing.
`## Notable assumptions` is a transient review surface for silent
"mirror the analog" guesses; `## Decisions` is the durable anchor —
rejected alternatives that pass the grep-blame + surfaces test. An
assumption that turns out to have been a decision belongs in the
anchor, not here.
