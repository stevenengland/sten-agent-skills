# ship-light — PR evidence template

Verbatim — no brevity compression. Write this to
`.stenswf/$ARGUMENTS/pr-evidence.md` at Phase 4. `visual-pr` (body-only
mode) appends it byte for byte below its own **Why the change**, **Special
things to note** and **Change outline** sections, after the closing line
`Closes #$ARGUMENTS`. `## Notable assumptions` is omitted entirely if
Phase 3 recorded none.

```
## Validation
- `<test command>` — <result, e.g. "41 passed">
- `<lint / build command>` — <result>
- <manual check, or what validated a change that needed no new test>

## Tests added (red → green)
- `<test name 1>`
- `<test name 2>`

## Notable assumptions
- <only include if silent assumptions were recorded; else omit section>
```

What the old *Summary* bullets carried now has a home of its own: *what
changed* is visual-pr's **Change outline**, *how it was tested* is
`## Validation` plus `## Tests added (red → green)`, and a notable
trade-off goes under **Special things to note**.

`## Decisions` is appended below the whole body by
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
