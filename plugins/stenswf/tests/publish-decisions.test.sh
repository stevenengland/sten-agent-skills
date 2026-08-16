#!/usr/bin/env bash
# Behavior tests for publishing decision anchors to PR / issue surfaces.
#
# Three things here fail silently in production:
#
#   1. Inherited stubs carry no rationale — inherit-decisions.sh writes
#      `Source: #<PRD>/D<n>` expecting the reader to open a local file. Ship
#      that verbatim to a PR and every reviewer gets a dangling pointer, with
#      nothing to notice: the block still renders.
#   2. The upsert is idempotent or it is not. A non-idempotent one appends a
#      second `## Decisions` block on every apply-loop pass, and nothing
#      errors — the PR body just grows.
#   3. Superseded entries leak. `### ~~D3~~` must never publish, because a
#      published contradiction of the shipped code is worse than no record.
#
# Run: bash plugins/stenswf/tests/publish-decisions.test.sh
set -uo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$HERE/../scripts/publish-decisions.sh"

PASS=0
FAIL=0
fail() { printf 'not ok - %s\n' "$1"; FAIL=$((FAIL + 1)); }
ok()   { printf 'ok - %s\n'     "$1"; PASS=$((PASS + 1)); }
assert_eq()      { [ "$2" = "$3" ] && ok "$1" || { fail "$1"; printf '    expected: %s\n    actual:   %s\n' "$3" "$2"; }; }
assert_match()   { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || { fail "$1"; printf '    missing %q in: %s\n' "$3" "$2"; }; }
assert_nomatch() { printf '%s' "$2" | grep -qF -- "$3" && { fail "$1"; printf '    unexpected %q in: %s\n' "$3" "$2"; } || ok "$1"; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- Fixtures --------------------------------------------------------------
# 900 = PRD with the full rationales. 901 = slice with mixed entry kinds.
# 902 = slice whose stubs point at a PRD that only exists archived.
# 903 = slice whose stubs point at a PRD with no anchor anywhere.
mkdir -p "$WORK/.stenswf/900" "$WORK/.stenswf/901" "$WORK/.stenswf/902" \
         "$WORK/.stenswf/903" "$WORK/.stenswf/904" \
         "$WORK/.stenswf/.archive/905-2026-01-01"

cat > "$WORK/.stenswf/900/decisions.md" <<'EOF'
# Decisions — #900

### D1 — Use a queue, not a cron poll

- **Category:** arch
- **Source:** prd-from-grill-me
- **Rationale:** Polling costs a round trip per tick and cannot express ordering; the queue already exists for billing.
- **Refs:** src/queue.py, src/worker.py

### D2 — Name the state column `phase`

- **Category:** decision
- **Source:** prd-from-grill-me
- **Rationale:** `status` collides with the HTTP field already on the model.
- **Refs:** src/models.py
EOF

cat > "$WORK/.stenswf/901/decisions.md" <<'EOF'
# Decisions — #901

### D1 — Use a queue, not a cron poll (inherited from #900)

- **Category:** inherited
- **Source:** #900/D1
- **Refs:** src/queue.py, src/worker.py

### ~~D2~~ — Retry three times

- **Category:** decision
- **Source:** ship-light
- **Rationale:** Matches the analog in src/mailer.py.
- **Refs:** src/worker.py

### D3 — Retry with exponential backoff

- **Category:** decision
- **Source:** apply
- **Rationale:** Three flat retries stampede a cold dependency; the reviewer hit it on staging.
- **Refs:** src/worker.py
- **Supersedes:** D2 — flat retries stampede

### D4 — Interpret AC3 as per-tenant, not global

- **Category:** decision
- **Source:** ship-light
- **Rationale:** The AC says "the limit" with a tenant-scoped subject everywhere else in the slice.
- **Refs:** AC#3

### D5 — Pick the serialization format

- **Category:** decision
- **Source:** plan-light
- **Rationale:** Unattended when reached.
- **Refs:** src/wire.py
- **Status:** parked

### D6 — Keep the legacy importer

- **Category:** decision
- **Source:** ship-light
- **Rationale:** Two customers parked on the old format and have not migrated.
- **Refs:** src/importer.py
EOF

cat > "$WORK/.stenswf/902/decisions.md" <<'EOF'
# Decisions — #902

### D1 — Use a queue, not a cron poll (inherited from #905)

- **Category:** inherited
- **Source:** #905/D1
- **Refs:** src/queue.py
EOF

cat > "$WORK/.stenswf/.archive/905-2026-01-01/decisions.md" <<'EOF'
# Decisions — #905

### D1 — Use a queue, not a cron poll

- **Category:** arch
- **Source:** prd-from-grill-me
- **Rationale:** Archived but still the authority for this stub.
- **Refs:** src/queue.py
EOF

cat > "$WORK/.stenswf/903/decisions.md" <<'EOF'
# Decisions — #903

### D1 — Something decided upstream (inherited from #906)

- **Category:** inherited
- **Source:** #906/D1
- **Refs:** src/x.py
EOF

# 904: every entry superseded — the render must come back empty.
cat > "$WORK/.stenswf/904/decisions.md" <<'EOF'
# Decisions — #904

### ~~D1~~ — Abandoned approach

- **Category:** arch
- **Source:** plan
- **Rationale:** Replaced during review.
- **Refs:** src/old.py
EOF

render() { ( cd "$WORK" && bash "$SCRIPT" render "$@" ); }

# --- 1. Active-entry selection --------------------------------------------

OUT=$(render 901)
assert_eq "renders exactly the active entries" \
  "$(printf '%s\n' "$OUT" | grep -c '^### ')" "5"
assert_nomatch "a superseded entry never publishes" "$OUT" "Retry three times"
assert_nomatch "a superseded id never publishes" "$OUT" "~~D2~~"
assert_match "the superseding entry publishes" "$OUT" "### D3 — Retry with exponential backoff"
assert_match "the Supersedes field is carried through" "$OUT" "**Supersedes:** D2 — flat retries stampede"

# Default mode is deliberately unfiltered: an AC interpretation has no
# file-path Ref and would be dropped by the docs/ filter, but it is exactly
# what a PR reviewer needs.
assert_match "an entry with no file-path Ref still publishes by default" \
  "$OUT" "### D4 — Interpret AC3 as per-tenant, not global"

# --- 2. Inherited-stub resolution ------------------------------------------

assert_match "an inherited stub gets its rationale filled in from the PRD" \
  "$OUT" "Polling costs a round trip per tick"
assert_match "an inherited stub reports the PRD's real category" \
  "$OUT" "**Category:** arch"
assert_match "an inherited stub's source becomes a linkable issue ref" \
  "$OUT" "**Source:** #900"
assert_nomatch "an inherited stub never publishes a local-file pointer" \
  "$OUT" "#900/D1"
assert_nomatch "no rendered entry leaks a .stenswf path as a pointer" \
  "$OUT" ".stenswf/"

OUT902=$(render 902)
assert_match "a stub resolves against an archived PRD anchor" \
  "$OUT902" "Archived but still the authority for this stub."

OUT903=$(render 903)
assert_match "an unresolvable stub degrades to an issue reference" \
  "$OUT903" "see #906 — entry D1"
assert_nomatch "an unresolvable stub still publishes no local pointer" \
  "$OUT903" "#906/D1"

# --- 3. Parked entries -----------------------------------------------------

assert_match "a parked entry is flagged in the header" "$OUT" "### ⚠ D5 —"
assert_match "a parked entry states that it blocks" "$OUT" "**Status:** parked — blocking"

# The flag is set by a Status FIELD, not by the word appearing anywhere in the
# entry. D6's rationale contains "parked on the old format" and is resolved.
assert_nomatch "the word 'parked' in a rationale does not flag the entry" \
  "$OUT" "### ⚠ D6 —"
assert_match "the non-parked entry still renders normally" "$OUT" "### D6 — Keep the legacy importer"

# Legacy bare-paragraph form: no longer written, still parsed, so old anchors
# keep their warning instead of silently publishing as resolved.
mkdir -p "$WORK/.stenswf/907"
cat > "$WORK/.stenswf/907/decisions.md" <<'EOF'
# Decisions — #907

### D1 — Await the schema owner

- **Category:** decision
- **Source:** ship-light
- **Rationale:** Needs the data team's call on the column type.
- **Refs:** src/schema.py

status: parked
EOF
assert_match "the legacy bare 'status: parked' paragraph still flags" \
  "$(render 907)" "### ⚠ D1 —"

# --- 4. Curated mode (the docs/ excerpt filter) ----------------------------

CUR=$(render --excerpt 901)
assert_match "excerpt keeps a decision entry with a file-path Ref" "$CUR" "### D3 —"
assert_nomatch "excerpt drops an entry whose only Ref is an AC" "$CUR" "### D4 —"
# A stub is dropped on its raw `inherited` category, before resolution — the
# PRD's own anchor is curated in its own right, so keeping the stub would
# duplicate the entry in the committed excerpt.
assert_nomatch "excerpt drops an inherited stub" "$CUR" "### D1 —"

CUR900=$(render --excerpt 900)
assert_match "excerpt keeps an arch entry with a file-path Ref" "$CUR900" "### D1 —"
assert_match "excerpt keeps a decision entry with a file-path Ref" "$CUR900" "### D2 —"

# The committed excerpt supplies its own `# Decisions — PRD #N` heading, so
# the block chrome must stay out. Without this, markers and a duplicate
# heading land in docs/stenswf/decisions/ permanently and nothing complains.
assert_nomatch "excerpt emits no start marker" "$CUR900" "stenswf:decisions:start"
assert_nomatch "excerpt emits no end marker" "$CUR900" "stenswf:decisions:end"
assert_nomatch "excerpt emits no ## Decisions heading" "$CUR900" "## Decisions"
assert_nomatch "excerpt emits no rendered-by preamble" "$CUR900" "Rendered from the local decision anchor"
assert_match "excerpt still emits the entries themselves" "$CUR900" "**Rationale:** Polling costs a round trip"

# Equivalence net for the awk lifted out of apply/decisions-excerpt.md. The
# original is reproduced here verbatim; if the shared renderer ever stops
# agreeing with it, the committed excerpt silently changes shape.
curate_anchor_v0() {
  awk '
    function flush() {
      if (have && (category=="arch" || category=="decision") && hasref) print block
      block=""; category=""; hasref=0; have=0
    }
    /^### / {
      flush()
      if ($0 ~ /^### D[0-9]+ /) { block=$0 "\n"; have=1 }
      next
    }
    have {
      block = block $0 "\n"
      if ($0 ~ /^- \*\*Category:\*\* (arch|decision)/) {
        category=$0; sub(/.*Category:\*\* */,"",category)
      }
      if ($0 ~ /^- \*\*Refs:\*\*.*\//) hasref=1
    }
    END { flush() }
  ' "$1"
}
# Compare the selected entry ids, not byte-for-byte layout: the renderer
# normalises field order and spacing by design. Selection is the contract.
ids_of() { printf '%s\n' "$1" | grep -oE '^### (⚠ )?D[0-9]+' | sed 's/⚠ //' | sort -u; }
for N in 900 901; do
  assert_eq "excerpt selects the same entries as the original curate_anchor (#$N)" \
    "$(ids_of "$(render --excerpt "$N")")" \
    "$(ids_of "$(curate_anchor_v0 "$WORK/.stenswf/$N/decisions.md")")"
done

# --- 5. Empty and absent anchors -------------------------------------------

assert_eq "an all-superseded anchor renders nothing" "$(render 904)" ""
assert_eq "an all-superseded anchor still exits 0" "$( render 904 >/dev/null 2>&1; echo $? )" "0"
assert_eq "a missing anchor renders nothing" "$(render 8888)" ""
assert_eq "a missing anchor exits 0, not an error" "$( render 8888 >/dev/null 2>&1; echo $? )" "0"

# --- 6. PR upsert ----------------------------------------------------------
# Fake gh backed by a file, so a second upsert reads back the first's write.

BODY="$WORK/pr-body"
cat > "$BODY" <<'EOF'
Closes #901

## Summary
- Adds the worker.

## Notable assumptions
- The queue is already provisioned.
EOF

CBODY="$WORK/comment-body"   # the one decisions comment, when it exists
CMETA="$WORK/comment-meta"   # holds its id once created

cat > "$WORK/gh" <<GHEOF
#!/usr/bin/env bash
# Minimal fake gh. PR body and issue comment both round-trip through files,
# so a second upsert reads back what the first wrote — the property the
# idempotence claim actually rests on.
BODY="$BODY"; CBODY="$CBODY"; CMETA="$CMETA"
args="\$*"
flagval() { local want="\$1" prev=""; shift; for a in "\$@"; do [ "\$prev" = "\$want" ] && { printf '%s' "\$a"; return; }; prev="\$a"; done; }

case "\$1 \$2" in
  "pr view") cat "\$BODY" ;;
  "pr edit")
    f=\$(flagval --body-file "\$@")
    [ -n "\$f" ] || { echo "fake gh: pr edit without --body-file" >&2; exit 3; }
    cp "\$f" "\$BODY" ;;
  "issue comment")
    f=\$(flagval --body-file "\$@")
    [ "\$f" = "-" ] && cat > "\$CBODY" || cp "\$f" "\$CBODY"
    echo 4242 > "\$CMETA" ;;
  "api user") echo "octocat" ;;
  *)
    case "\$args" in
      # List comments: emit the one comment, if it exists, as the --jq
      # filter would have selected it (marker present, authored by us).
      *"/comments"*" --paginate"*)
        # Fail ONLY the listing call, to model a rate limit or transient 5xx
        # while every other endpoint keeps working.
        [ -e "$WORK/list-fails" ] && { echo "fake gh: API rate limit exceeded" >&2; exit 1; }
        [ -s "\$CMETA" ] || exit 0
        grep -qF '<!-- stenswf:decisions:start -->' "\$CBODY" || exit 0
        cat "\$CMETA" ;;
      *"--method PATCH"*"issues/comments/"*)
        f=\$(flagval -F "\$@"); f="\${f#body=@}"
        cp "\$f" "\$CBODY" ;;
      *"issues/comments/"*) cat "\$CBODY" ;;
      *) echo "fake gh: unhandled: \$args" >&2; exit 3 ;;
    esac ;;
esac
GHEOF
chmod +x "$WORK/gh"
cp "$WORK/gh" "$WORK/gh.real"   # restore point: one test deliberately breaks gh
export PATH="$WORK:$PATH"

( cd "$WORK" && bash "$SCRIPT" pr 901 77 ) >/dev/null
AFTER1=$(cat "$BODY")
assert_match "upsert appends the block to a PR body that had none" \
  "$AFTER1" "<!-- stenswf:decisions:start -->"
assert_match "upsert carries the decisions through" "$AFTER1" "### D3 — Retry with exponential backoff"
assert_match "upsert preserves the pre-existing summary" "$AFTER1" "- Adds the worker."
assert_match "upsert preserves the assumptions section it sits beside" \
  "$AFTER1" "- The queue is already provisioned."
assert_eq "one block after the first upsert" \
  "$(printf '%s\n' "$AFTER1" | grep -cF '<!-- stenswf:decisions:start -->')" "1"

# Second pass: what apply / apply-loop do on every convergence.
( cd "$WORK" && bash "$SCRIPT" pr 901 77 ) >/dev/null
AFTER2=$(cat "$BODY")
assert_eq "re-upsert leaves exactly one start marker" \
  "$(printf '%s\n' "$AFTER2" | grep -cF '<!-- stenswf:decisions:start -->')" "1"
assert_eq "re-upsert leaves exactly one end marker" \
  "$(printf '%s\n' "$AFTER2" | grep -cF '<!-- stenswf:decisions:end -->')" "1"
assert_eq "re-upsert leaves exactly one Decisions heading" \
  "$(printf '%s\n' "$AFTER2" | grep -c '^## Decisions$')" "1"
assert_match "re-upsert still preserves text outside the markers" \
  "$AFTER2" "- Adds the worker."

# A human edits the body around the block; the next refresh must not eat it.
printf '\n## Deploy note\n\nNeeds the feature flag on first.\n' >> "$BODY"
( cd "$WORK" && bash "$SCRIPT" pr 901 77 ) >/dev/null
AFTER3=$(cat "$BODY")
assert_match "refresh preserves a human's later edit" "$AFTER3" "Needs the feature flag on first."
assert_eq "refresh still leaves exactly one block" \
  "$(printf '%s\n' "$AFTER3" | grep -cF '<!-- stenswf:decisions:start -->')" "1"

# An anchor that renders empty must remove a block that is already published.
( cd "$WORK" && bash "$SCRIPT" pr 904 77 ) >/dev/null
AFTER4=$(cat "$BODY")
assert_eq "an empty render removes the published block" \
  "$(printf '%s\n' "$AFTER4" | grep -cF '<!-- stenswf:decisions:start -->')" "0"
assert_match "removing the block keeps the rest of the body" "$AFTER4" "- Adds the worker."
assert_match "removing the block keeps the human's edit" "$AFTER4" "Needs the feature flag on first."

# A PR that cannot be read must fail loudly. Failing quietly would let a
# caller believe the decisions were published when nothing was written.
cat > "$WORK/gh" <<'GHEOF'
#!/usr/bin/env bash
echo "fake gh: no such PR" >&2; exit 1
GHEOF
chmod +x "$WORK/gh"
ERR=$( cd "$WORK" && bash "$SCRIPT" pr 901 77 2>&1 >/dev/null ); RC=$?
assert_eq "pr exits non-zero when the PR cannot be read" "$RC" "1"
assert_match "pr says which PR it could not read" "$ERR" "cannot read PR 77"
cp "$WORK/gh.real" "$WORK/gh"   # later sections need a working gh again

# --- 6b. Issue comment upsert ----------------------------------------------
# The whole point of a dedicated comment: plan, plan-light, ship, ship-light
# and apply all target it, so a superseded entry disappears from the issue
# instead of standing next to its replacement further up the thread.

rm -f "$CBODY" "$CMETA"
issue_pub() { ( cd "$WORK" && bash "$SCRIPT" issue "$1" ); }

issue_pub 901 >/dev/null
C1=$(cat "$CBODY")
assert_match "first issue publish creates the comment" "$C1" "<!-- stenswf:decisions:start -->"
assert_match "the comment carries the decisions" "$C1" "### D3 — Retry with exponential backoff"
assert_eq "one block after the first issue publish" \
  "$(printf '%s\n' "$C1" | grep -cF '<!-- stenswf:decisions:start -->')" "1"

# Second publisher on the same issue (plan-light → ship-light, or ship → apply).
issue_pub 901 >/dev/null
C2=$(cat "$CBODY")
assert_eq "re-publishing updates the same comment, not a new one" \
  "$(printf '%s\n' "$C2" | grep -cF '<!-- stenswf:decisions:start -->')" "1"
assert_eq "re-publishing leaves one Decisions heading" \
  "$(printf '%s\n' "$C2" | grep -c '^## Decisions$')" "1"

# A human replies inside the decisions comment; the next refresh keeps it.
printf '\nAgreed on D3 — see the incident postmortem.\n' >> "$CBODY"
issue_pub 901 >/dev/null
C3=$(cat "$CBODY")
assert_match "refresh preserves a human's note in the comment" \
  "$C3" "Agreed on D3 — see the incident postmortem."
assert_eq "refresh still leaves one block in the comment" \
  "$(printf '%s\n' "$C3" | grep -cF '<!-- stenswf:decisions:start -->')" "1"

# Everything superseded: the comment must not keep asserting stale decisions.
issue_pub 904 >/dev/null
C4=$(cat "$CBODY")
assert_eq "an empty render removes the block from the comment" \
  "$(printf '%s\n' "$C4" | grep -cF '<!-- stenswf:decisions:start -->')" "0"
assert_match "the human's note survives the block's removal" \
  "$C4" "Agreed on D3 — see the incident postmortem."

# Empty anchor with no comment yet must stay silent rather than post noise.
rm -f "$CBODY" "$CMETA"
issue_pub 904 >/dev/null
assert_eq "an empty anchor posts no comment at all" "$( [ -e "$CBODY" ] && echo exists || echo absent )" "absent"

# A failed listing must NOT read as "no comment yet". If it does, the fallback
# is to POST — so a rate limit silently creates a second decisions comment, and
# every later run's `tail -1` targets the newer one while the older lingers
# with stale content. That permanently breaks the one-comment invariant.
rm -f "$CBODY" "$CMETA"
: > "$WORK/list-fails"
ERR=$( issue_pub 901 2>&1 >/dev/null ); RC=$?
rm -f "$WORK/list-fails"
assert_eq "issue exits non-zero when the comment listing fails" "$RC" "1"
assert_match "issue says it could not list the comments" "$ERR" "cannot list comments on issue 901"
assert_eq "a failed listing posts no comment" \
  "$( [ -e "$CBODY" ] && echo exists || echo absent )" "absent"

# --- 7. Wiring -------------------------------------------------------------
# The skills must actually call the script; a correct script wired nowhere
# publishes nothing.

ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
for F in skills/plan/SKILL.md skills/plan-light/SKILL.md \
         skills/ship-light/SKILL.md skills/ship/post-dispatch.md \
         skills/apply/slice.md skills/apply/decisions-excerpt.md \
         skills/apply-loop/SKILL.md; do
  assert_match "$F invokes publish-decisions.sh" \
    "$(cat "$ROOT/$F")" "publish-decisions.sh"
done

# Planners have no PR, so they must reach the issue via the comment
# subcommand — never `gh issue edit`, which would perturb concept_sha256.
for F in skills/plan/SKILL.md skills/plan-light/SKILL.md; do
  assert_match "$F publishes via the issue subcommand" \
    "$(cat "$ROOT/$F")" "publish-decisions.sh issue"
done

assert_nomatch "review-loop never publishes (reviewers do not write anchors)" \
  "$(cat "$ROOT/skills/review-loop/SKILL.md")" "publish-decisions.sh"
assert_nomatch "review never publishes" \
  "$(cat "$ROOT/skills/review/SKILL.md")" "publish-decisions.sh"

# Every skill that supersedes entries must refresh BOTH surfaces, or the
# issue comment keeps asserting a decision the PR body already retired.
for F in skills/apply/slice.md skills/apply-loop/SKILL.md; do
  assert_match "$F refreshes the PR body" \
    "$(cat "$ROOT/$F")" "publish-decisions.sh pr"
  assert_match "$F refreshes the issue comment" \
    "$(cat "$ROOT/$F")" "publish-decisions.sh issue"
done

assert_nomatch "decisions-excerpt no longer carries its own curation awk" \
  "$(cat "$ROOT/skills/apply/decisions-excerpt.md")" "curate_anchor()"

printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
