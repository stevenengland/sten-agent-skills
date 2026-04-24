# plan — task fragment template

Used by `plan` Phase 2 when materialising `.stenswf/$ARGUMENTS/tasks/T<id>.md`.

Tasks are **vertical slices**. Soft cap: >5 test cases or >4 files → split.

IDs are gap-numbered from `T10` stepping by 10. The final task is
always a documentation task (T<last>).

Each file is fully self-contained — a subagent receiving only this
file plus `stable-prefix.md` must execute it correctly. Never write
"similar to Task N"; repeat what the implementer needs.

## Body (full prose — brevity does NOT apply)

```
<task id="T10" name="<slice name>" commit="<type>(<scope>): <subject>">

**Goal:** <one sentence, behavior-level>
**Files:**
- Create: `exact/path/to/new_file.py` — <responsibility>
- Modify: `exact/path/to/existing.py` — <what changes>
- Test:   `tests/exact/path/to/test_file.py`
**Pre-reading (read before editing):**
- `path/to/analogous_code.py::symbol` — existing pattern to mirror
- `tdd` skill — if unsure about test shape
**Done when:** <crisp criterion — must match one AC>

Per test in this slice, repeat steps 1–4:

- [ ] Step 1 — Write failing test `test_<name>` in `<test file>`:
  ```python
  def test_<name>():
      # given
      ...
      # when
      ...
      # then
      assert ...
  ```
- [ ] Step 2 — Run test, confirm it fails:
  Run: `<exact command>`
  Expected: FAIL with `<expected error substring>`
- [ ] Step 3 — Implement minimal code in `<impl file>`.
  Approach: <1–3 sentences; reference analogous symbol by path>.
- [ ] Step 4 — Run test, confirm it passes:
  Run: `<same command>`
  Expected: PASS

After all tests in the slice are green:

- [ ] Refactor within the slice. Tests stay green.
- [ ] Verify: `<exact command>` — all PASS.
      If user-visible, also run: `<manual check>`.
- [ ] Commit using the task's `commit` attribute with a
      `Refs: #$ARGUMENTS T<id>` trailer:
  ```bash
  git add <paths>
  git commit -m "<commit attribute verbatim>" -m "Refs: #$ARGUMENTS T<id>"
  ```

</task>
```

The opening `<task id="..." name="..." commit="...">` tag is required —
extractors may parse it.

## Documentation task (always last)

```
<task id="T<last>" name="Update documentation" commit="docs(<scope>): update docs for issue $ARGUMENTS">

**Goal:** All affected documentation reflects the post-implementation state.
**Files:**
- Modify: `CLAUDE.md` — if new patterns or conventions were introduced
- Modify: `README.md` — if public shape changed
- Modify: `docs/<relevant>.md` — if applicable
**Pre-reading:** Orientation summary from Phase 1.
**Done when:** Every doc file from the orientation summary is either
updated or explicitly noted "no update needed".

- [ ] Review each file from the orientation summary's doc list.
- [ ] Update or note "no update needed" inline.
- [ ] Commit with a `Refs: #$ARGUMENTS T<last>` trailer.

</task>
```

## Prescriptiveness rules

- Test steps: write the full test code. Be prescriptive.
- Implementation steps: describe approach, point at analogous symbols.
  Do not pre-write the full implementation unless no analog exists.
- Exact file paths and commands everywhere.
- Never: `TBD`, `TODO`, `implement later`, `similar to Task N`, test
  steps without code, references to undefined symbols.
