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

# 909: fields wrapped across lines. Every doc in this repo hard-wraps at
# ~72 columns, so an agent writing an anchor produces these routinely — and
# a line-oriented parser drops everything after the first line while the
# entry still renders, so the truncation is invisible on every surface.
mkdir -p "$WORK/.stenswf/909"
cat > "$WORK/.stenswf/909/decisions.md" <<'EOF'
# Decisions — #909

### D1 — Use a queue, not a cron poll

- **Category:** arch
- **Source:** plan
- **Rationale:** Polling costs a round trip per tick and cannot express
  ordering; the queue already exists for billing and is cheaper to run.
- **Refs:** src/queue.py,
  src/worker.py

### D2 — Retry with backoff

- **Category:** decision
- **Source:** apply
- **Rationale:** Flat retries stampede a cold dependency.
- **Refs:** src/worker.py
- **Supersedes:** D1 — the D3 experiment showed flat retries fail

A stray paragraph after a blank line belongs to no field.
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

# --- 2b. Wrapped field values ----------------------------------------------
# A regression the equivalence test cannot see: it compares selected ids, not
# byte layout, so a truncated rationale still "matches".

W909=$(render 909)
assert_match "a wrapped rationale keeps its first line" \
  "$W909" "Polling costs a round trip per tick"
assert_match "a wrapped rationale keeps its continuation" \
  "$W909" "the queue already exists for billing and is cheaper to run"
assert_match "the continuation is joined onto one field line" \
  "$W909" "cannot express ordering; the queue"
assert_match "a wrapped Refs list keeps both paths" "$W909" "src/queue.py, src/worker.py"
assert_nomatch "a stray paragraph after a blank line joins no field" \
  "$W909" "belongs to no field"

# A path that only appears on the wrapped continuation must still satisfy the
# curated filter, or the excerpt silently drops the entry.
mkdir -p "$WORK/.stenswf/910"
printf '# Decisions — #910\n\n### D1 — Wrapped ref only\n\n- **Category:** arch\n- **Source:** plan\n- **Rationale:** Short.\n- **Refs:** AC#1,\n  src/late.py\n' \
  > "$WORK/.stenswf/910/decisions.md"
assert_match "a file path found only on a continuation line satisfies --excerpt" \
  "$(render --excerpt 910)" "### D1 —"

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
assert_match "excerpt keeps the PRD's own decision entry" "$CUR900" "### D2 —"

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
  # `trailer` asks for the default branch to scope its git-log scan.
  "repo view") echo "master" ;;
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

# --- 6c. Commit-message trailers -------------------------------------------
# The repo-durable tier. Two properties carry it, and both fail silently:
#
#   1. Re-emission. `trailer` is called at EVERY commit site, so if it does
#      not subtract what the branch already recorded, a ten-commit slice
#      repeats decision D1 ten times and the journal becomes unreadable.
#   2. Under-emission. Anchor ids are local to an issue, so an unqualified
#      `D1` seen on a sibling issue's commit would suppress this issue's D1
#      forever — a decision silently absent from the record, with nothing to
#      notice, because the commit still succeeds.

GWORK="$WORK/git"
mkdir -p "$GWORK"
cp -r "$WORK/.stenswf" "$GWORK/.stenswf"

git init -q -b master "$GWORK"
git -C "$GWORK" config user.email t@example.com
git -C "$GWORK" config user.name test
git -C "$GWORK" commit -q --allow-empty -m "root"

# A real bare remote, so the merge-base path — the one production takes — is
# what gets exercised. Without it only the bounded-scan fallback would run.
git init -q --bare "$WORK/origin.git"
git -C "$GWORK" remote add origin "$WORK/origin.git"
git -C "$GWORK" push -q origin master
git -C "$GWORK" checkout -q -b slice

trailer()   { ( cd "$GWORK" && bash "$SCRIPT" trailer "$@" ); }
gcommit()   { git -C "$GWORK" commit -q --allow-empty -m "$1" -m "$2"; }

T900=$(trailer 900)
assert_match "trailer emits a decision key qualified by issue" "$T900" "Decision: #900/D1"
assert_match "trailer carries the category" "$T900" "[arch] Use a queue, not a cron poll"
assert_match "trailer carries the rationale" "$T900" "Rationale: Polling costs a round trip"
assert_match "trailer maps Refs onto its own token" "$T900" "Touches: src/queue.py, src/worker.py"
assert_nomatch "trailer never spends the Refs token the commit convention owns" \
  "$T900" "Refs: src/queue.py"
assert_eq "trailer emits every unrecorded entry" \
  "$(printf '%s\n' "$T900" | grep -c '^Decision:')" "2"
assert_eq "trailer emits no blank line inside the block (git trailers are one paragraph)" \
  "$(printf '%s\n' "$T900" | grep -c '^$')" "0"

# The property the whole design rests on: record it once, never again.
gcommit "feat: add the queue" "$T900"
assert_eq "an already-recorded decision is never re-emitted" "$(trailer 900)" ""
assert_eq "an exhausted trailer still exits 0" \
  "$( trailer 900 >/dev/null 2>&1; echo $? )" "0"

cat >> "$GWORK/.stenswf/900/decisions.md" <<'EOF'

### D3 — Drop the nightly reconcile job

- **Category:** arch
- **Source:** ship-light
- **Rationale:** The queue makes it redundant, and it double-writes on retry.
- **Refs:** src/reconcile.py
EOF
T900B=$(trailer 900)
assert_match "a newly appended entry is emitted" "$T900B" "Decision: #900/D3"
assert_nomatch "an appended entry does not drag the recorded ones back" \
  "$T900B" "Decision: #900/D1"

# Ids are local to an issue. #900/D1 is recorded; #901/D1 must still emit.
T901=$(trailer 901)
assert_match "a sibling issue's identical id is not suppressed" "$T901" "Decision: #901/D1"

assert_match "trailer resolves an inherited stub's rationale from the PRD" \
  "$T901" "Rationale: Polling costs a round trip"
assert_nomatch "trailer never writes a local-file pointer into git history" \
  "$T901" ".stenswf/"
assert_nomatch "trailer never leaves a raw stub pointer" "$T901" "#900/D1 —"

assert_match "a superseding entry names what it retires" "$T901" "supersedes #901/D2"
assert_nomatch "a superseded entry is never emitted" "$T901" "Decision: #901/D2"

# Parked = an open question, not a decision. It joins the journal when it
# resolves; until then the ⚠ in the PR body is the surface that carries it.
assert_nomatch "a parked entry is not recorded as a decision" "$T901" "Decision: #901/D5"
assert_match "a non-parked entry beside it still records" "$T901" "Decision: #901/D6"

assert_eq "a missing anchor emits nothing" "$(trailer 999)" ""
assert_eq "a missing anchor exits 0, so \${DEC:+-m} degrades to a plain commit" \
  "$( trailer 999 >/dev/null 2>&1; echo $? )" "0"
assert_eq "an all-superseded anchor emits nothing" "$(trailer 904)" ""

# Folding: a rationale longer than a terminal line must stay ONE trailer
# value, or `git interpret-trailers` reads the overflow as a new trailer.
mkdir -p "$GWORK/.stenswf/908"
cat > "$GWORK/.stenswf/908/decisions.md" <<'EOF'
# Decisions — #908

### D1 — Fold long rationales

- **Category:** decision
- **Source:** ship-light
- **Rationale:** This rationale runs well past any reasonable terminal width so that the folding path is exercised rather than merely declared, and it keeps going for a while yet to force at least two continuation lines.
- **Refs:** src/fold.py
EOF
T908=$(trailer 908)
assert_eq "no folded line exceeds 78 columns" \
  "$(printf '%s\n' "$T908" | awk 'length > 78' | wc -l | tr -d ' ')" "0"
assert_eq "continuation lines are indented, so they stay part of one value" \
  "$(printf '%s\n' "$T908" | sed -n '2,$p' | grep -c '^  ')" \
  "$(printf '%s\n' "$T908" | sed -n '2,$p' | grep -vc '^\(Decision\|Rationale\|Touches\):')"

# The canonical call form puts the block in the SAME paragraph as `Refs:`,
# so both survive `git interpret-trailers`. Two paragraphs would demote
# `Refs:` to body text — conventional-commits.md requires it stay a trailer.
COMBINED=$(printf 'feat(x): thing\n\n%s' "$(printf 'Refs: #908\n%s' "$T908")")
PARSED=$(printf '%s\n' "$COMBINED" | git interpret-trailers --parse)
assert_match "the canonical form keeps Refs a parseable trailer" "$PARSED" "Refs: #908"
assert_match "git unfolds the wrapped rationale back into one value" \
  "$PARSED" "exercised rather than merely declared, and it keeps going"
assert_eq "git sees exactly the trailers we emitted, plus Refs" \
  "$(printf '%s\n' "$PARSED" | wc -l | tr -d ' ')" "4"

# Round trip through git the way an agent would query it later.
gcommit "feat: fold" "$T908"
assert_eq "git log --grep finds the recorded decision" \
  "$(git -C "$GWORK" log --grep='^Decision: #908/D1' --format=%h | wc -l | tr -d ' ')" "1"

# The composed call form, executed rather than described. An empty $DEC must
# leave a bare `Refs:` — conventional-commits.md asserts this in prose, and
# the whole "safe to call at every commit site" claim rests on it.
gcommit "feat: drop the reconcile job" "$(trailer 900)"
EMPTY=$(trailer 900)          # now fully recorded
assert_eq "the exhausted anchor really is empty" "$EMPTY" ""
COMPOSED=$(printf 'Refs: #%s\n%s' 900 "$EMPTY")
assert_eq "an empty emission composes to a bare Refs line" "$COMPOSED" "Refs: #900"
assert_eq "and leaves no trailing blank line to break trailer parsing" \
  "$(printf '%s\n' "$COMPOSED" | wc -l | tr -d ' ')" "1"

# `git log --grep` must survive a squash merge — the README claims it does,
# because GitHub's COMMIT_MESSAGES default concatenates the branch's messages.
SQUASHED=$(git -C "$GWORK" log --format='* %s%n%b' -2)
assert_match "a concatenated squash message still carries the decision keys" \
  "$SQUASHED" "Decision: #908/D1"
git -C "$GWORK" checkout -q -b squashed master
git -C "$GWORK" commit -q --allow-empty -m "$SQUASHED"
assert_eq "git log --grep finds decisions through a squash" \
  "$(git -C "$GWORK" log --grep='^Decision: #908/D1' --format=%h | wc -l | tr -d ' ')" "1"
git -C "$GWORK" checkout -q slice

# --amend must NOT recompute: the scan runs before the rewrite, so HEAD still
# contains the commit being amended, the call returns empty, and re-passing it
# would drop the trailers the original message carried.
git -C "$GWORK" commit -q --allow-empty -m "feat: amend me" \
  -m "$(printf 'Refs: #%s\n%s' 908 "$(trailer 908)")"
BEFORE=$(git -C "$GWORK" log -1 --format=%B | grep -c '^Decision:' || true)
assert_eq "the pre-amend commit carries its trailers" "$BEFORE" "0"
git -C "$GWORK" commit -q --amend --allow-empty --no-edit -m "feat: amended subject" \
  -m "$(printf 'Refs: #%s' 908)"
assert_eq "recomputing on amend would return empty (hence the --no-edit rule)" \
  "$(trailer 908)" ""
assert_match "the documented amend rule is stated where the form lives" \
  "$(cat "$HERE/../references/conventional-commits.md")" "--amend --no-edit"

# No remote / no merge-base: the bounded-scan fallback must still subtract,
# or a detached or freshly-branched tree re-emits everything it already has.
git init -q -b master "$WORK/noremote"
cp -r "$WORK/.stenswf" "$WORK/noremote/.stenswf"
git -C "$WORK/noremote" config user.email t@example.com
git -C "$WORK/noremote" config user.name test
NR=$( cd "$WORK/noremote" && bash "$SCRIPT" trailer 900 )
assert_match "with no remote, trailer still emits" "$NR" "Decision: #900/D1"
git -C "$WORK/noremote" commit -q --allow-empty -m "seed" -m "$NR"
assert_eq "with no remote, the bounded scan still subtracts what was recorded" \
  "$( cd "$WORK/noremote" && bash "$SCRIPT" trailer 900 )" ""

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

# A commit site that does not call `trailer` drops those decisions from the
# repo silently — the commit still succeeds, and nothing downstream notices.
# These files are read by the skill-loading agent, so the skill-relative path
# resolves for them.
for F in skills/ship-light/SKILL.md skills/ship/post-dispatch.md \
         skills/apply/slice.md skills/apply/prd.md skills/apply-loop/SKILL.md \
         skills/ship/dispatch.md; do
  assert_match "$F records decisions in its commit" \
    "$(cat "$ROOT/$F")" "publish-decisions.sh trailer"
done

# The block must share the paragraph with Refs:, or Refs: stops being a
# trailer — conventional-commits.md states that as a hard rule.
for F in skills/ship-light/SKILL.md skills/apply/slice.md \
         skills/apply/prd.md skills/apply-loop/SKILL.md; do
  assert_match "$F keeps Refs and the block in one paragraph" \
    "$(cat "$ROOT/$F")" "Refs: #%s"
done

assert_match "the commit spec documents the decision trailers" \
  "$(cat "$ROOT/references/conventional-commits.md")" "## Decision trailers"

# Subagent-facing files. A skill-relative script path has nothing to resolve
# against there — the subagent's CWD is the repo root — so the call would
# fail, the commit would still succeed with a bare `Refs:`, and the report
# format is silent on success. Demonstrate the breakage, then assert neither
# file contains one.
REPO_ROOT=$(CDPATH= cd -- "$ROOT/../.." && pwd)
assert_eq "a skill-relative script path does not resolve from the repo root" \
  "$( cd "$REPO_ROOT" && bash ../../scripts/publish-decisions.sh trailer 1 >/dev/null 2>&1; echo $? )" \
  "127"

for F in references/plan-task-template.md; do
  assert_nomatch "$F never calls the script from subagent context" \
    "$(cat "$ROOT/$F")" "bash ../../scripts/publish-decisions.sh"
  assert_match "$F takes its trailers from the prompt instead" \
    "$(cat "$ROOT/$F")" "COMMIT TRAILERS"
done

# dispatch.md is read by the orchestrator but contains the subagent's prompt.
# The computation must sit outside that prompt block, and the prompt must
# carry the result.
assert_match "dispatch.md passes the trailers through the prompt tail" \
  "$(cat "$ROOT/skills/ship/dispatch.md")" "--- COMMIT TRAILERS ---"
assert_nomatch "the subagent's commit step does not call the script itself" \
  "$(sed -n '/FETCH YOUR TASK FRAGMENT/,/REPORT FORMAT/p' "$ROOT/skills/ship/dispatch.md")" \
  "publish-decisions.sh"

printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
