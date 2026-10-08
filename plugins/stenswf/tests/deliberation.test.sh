#!/usr/bin/env bash
# Behavior tests for the peer deliberation protocol (scripts/deliberation.sh).
#
# What a shell assertion can reach is the state machine, not the quality
# of the argument — that is forward-tested by running real agents. Pinned
# here: moves are immutable and ordered, whose move it is, every way a
# deliberation ends, the bounds, the waits, the contradiction gate's
# search, and the skills' wiring to all of it.
#
# Run:  bash plugins/stenswf/tests/deliberation.test.sh
set -uo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPTS="$HERE/../scripts"
SKILLS="$HERE/../skills"
REFS="$HERE/../references"

# shellcheck source=../scripts/deliberation.sh
source "$SCRIPTS/deliberation.sh"

PASS=0; FAIL=0
fail() { printf 'not ok - %s\n' "$1"; FAIL=$((FAIL + 1)); }
ok()   { printf 'ok - %s\n'     "$1"; PASS=$((PASS + 1)); }
assert_eq()      { [ "$2" = "$3" ] && ok "$1" || { fail "$1"; printf '    expected: %s\n    actual:   %s\n' "$3" "$2"; }; }
assert_match()   { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || { fail "$1"; printf '    missing %q in: %s\n' "$3" "$2"; }; }
assert_nomatch() { printf '%s' "$2" | grep -qF -- "$3" && { fail "$1"; printf '    unexpected %q\n' "$3"; } || ok "$1"; }
refused()        { "${@:2}" >/dev/null 2>&1 && fail "$1" || ok "$1"; }
allowed()        { "${@:2}" >/dev/null 2>&1 && ok "$1" || fail "$1"; }

WORK=$(mktemp -d); ORIG=$PWD
trap 'cd "$ORIG"; rm -rf "$WORK"' EXIT
cd "$WORK" && git init -q . && git config user.email t@t && git config user.name t

printf '# Tension\n\n- **Host seam:** ship\n' > "$WORK/tension.md"
printf '# Tension\n\n- **Host seam:** apply-loop\n' > "$WORK/tension-pr.md"
printf '# Turn\n\n## Read\nsrc/x.ts\n' > "$WORK/t.md"
printf '# Rejection\n\nclause 2 double-counts the backoff\n' > "$WORK/rej.md"
printf '# Closing\n\nno convergence\n' > "$WORK/close.md"
printf '# Result\n' > "$WORK/res.md"
prop() { printf '# Proposal\n\n## Solution\n%s\n\n## Refs\nsrc/adapter.ts\n\n## Scope impact\nnone\n' "$1" > "$WORK/p.md"; }
move() { delib_move "$@" >/dev/null 2>&1; }

# --- 1. Opening: an exact, fresh, id'd directory -------------------------
D=$(delib_new 42 "$WORK/tension.md")
assert_match "a deliberation gets its own id'd directory" "$D" ".stenswf/42/deliberations/"
assert_eq "the tension is move 00" "$(_delib_last_file "$D")" "00-A-tension.md"
assert_eq "B answers the tension" "$(delib_status "$D")" "open B"
D2=$(delib_new 42 "$WORK/tension.md")
[ "$D" != "$D2" ] && ok "a second wall on one issue does not collide with the first" \
                  || fail "a second wall on one issue does not collide with the first"
# A forced id collision must never reuse a directory — the old `mkdir -p`
# silently wrote the second wall's tension into the first.
_delib_id() { printf 'c011de'; }
C1=$(delib_new 50 "$WORK/tension.md"); C2=$(delib_new 50 "$WORK/tension.md" 2>/dev/null)
assert_eq "a colliding id is refused, not reused" "$C2" ""
assert_eq "the first wall is untouched by the collision" "$(ls "$C1" | tr '\n' ' ')" "00-A-tension.md "
unset -f _delib_id; source "$SCRIPTS/deliberation.sh"
refused "a second tension is refused" delib_move "$D" A tension "$WORK/tension.md"

# --- 2. Moves are immutable and taken in order ----------------------------
refused "A cannot answer its own tension" delib_move "$D" A turn "$WORK/t.md"
allowed "B takes its move" delib_move "$D" B turn "$WORK/t.md"
assert_eq "control passes to the other side" "$(delib_status "$D")" "open A"
refused "B cannot move twice in a row" delib_move "$D" B turn "$WORK/t.md"
assert_eq "a refused move writes nothing" "$(_delib_last_file "$D")" "01-B-turn.md"
printf 'REWRITTEN\n' > "$WORK/bad.md"
mkdir "$D/.seq-02"   # another writer reserved move 02 first
refused "a move number taken concurrently is refused" delib_move "$D" A turn "$WORK/bad.md"
rmdir "$D/.seq-02"
assert_nomatch "no .tmp residue is left behind" "$(ls -A "$D")" ".tmp"
refused "B cannot propose" delib_move "$D" B proposal "$WORK/t.md"
refused "an unknown kind is refused" delib_move "$D" A verdict "$WORK/t.md"

# --- 3. Proposal, verdicts, and the stale acceptance ----------------------
prop "Retry at the adapter."
allowed "A proposes on its move" delib_move "$D" A proposal "$WORK/p.md"
assert_eq "an unjudged proposal is B's move" "$(delib_status "$D")" "open B"
refused "B owes a verdict, not a turn" delib_move "$D" B turn "$WORK/t.md"
allowed "B accepts" delib_move "$D" B accept
assert_eq "acceptance verifies" "$(proposal_verify "$D")" "accepted"
assert_match "the acceptance names the proposal it covers" "$(cat "$D/03-B-accept.md")" "02-A-proposal.md"
sed -i 's/Retry at the adapter\./Retry at the caller./' "$D/02-A-proposal.md"
assert_eq "editing an accepted proposal makes it stale" "$(proposal_verify "$D")" "stale"
refused "a stale acceptance cannot be agreed" delib_move "$D" A agreed "$WORK/res.md"
sed -i 's/Retry at the caller\./Retry at the adapter.  /' "$D/02-A-proposal.md"
assert_eq "trailing whitespace does not invalidate acceptance" "$(proposal_verify "$D")" "accepted"

R=$(delib_new 43 "$WORK/tension.md")
move "$R" B turn "$WORK/t.md"; prop "Use A."; move "$R" A proposal "$WORK/p.md"
refused "A cannot judge its own proposal" delib_move "$R" A accept
allowed "B rejects with the failing clauses" delib_move "$R" B reject "$WORK/rej.md"
assert_eq "a rejection hands control to A" "$(delib_status "$R")" "open A"
refused "a rejected proposal cannot then be accepted" delib_move "$R" B accept
# After a rejection A may discuss instead of revising — and B gets its say.
allowed "A may answer a rejection with a turn" delib_move "$R" A turn "$WORK/t.md"
assert_eq "a turn after a rejection hands control to B" "$(delib_status "$R")" "open B"
allowed "B answers the turn" delib_move "$R" B turn "$WORK/t.md"
prop "Use C."; allowed "A revises" delib_move "$R" A proposal "$WORK/p.md"
assert_match "the rejected version stays readable" "$(cat "$R/02-A-proposal.md")" "Use A."
move "$R" B accept
refused "B cannot agree on A's behalf" delib_move "$R" B agreed "$WORK/res.md"

# --- 4. Every way a deliberation ends -------------------------------------
assert_eq "an accepted proposal does not close it" "$(delib_open_for_issue 43)" "$R"
allowed "A agrees over the accepted latest proposal" delib_move "$R" A agreed "$WORK/res.md"
assert_eq "agreement ends it" "$(delib_status "$R")" "ended agreed"
assert_eq "an ended deliberation is no longer open" "$(delib_open_for_issue 43)" ""
refused "nothing follows an end" delib_move "$R" A turn "$WORK/t.md"
refused "a second end is refused" delib_move "$R" A parked "$WORK/close.md"

U=$(delib_new 45 "$WORK/tension.md"); prop "Unjudged."; move "$U" B turn "$WORK/t.md"; move "$U" A proposal "$WORK/p.md"
refused "an unaccepted proposal cannot be agreed" delib_move "$U" A agreed "$WORK/res.md"
# Parking must actually close it. It used to be impossible: only an agreed
# result ended a deliberation, so a parked one stayed open forever and the
# reviewer, forbidden to stop while one was open, never stopped.
allowed "A parks while B owes a verdict" delib_move "$U" A parked "$WORK/close.md"
assert_eq "parking ends it" "$(delib_status "$U")" "ended parked"
assert_eq "a parked deliberation is no longer open" "$(delib_open_for_issue 45)" ""
refused "B cannot judge after the park" delib_move "$U" B accept

X=$(delib_new 47 "$WORK/tension.md")
refused "B cannot escalate" delib_move "$X" B escalated "$WORK/close.md"
allowed "B may cancel on A's absence, whoever's move it is" delib_move "$X" B cancelled "$WORK/close.md"
assert_eq "cancelling ends it" "$(delib_status "$X")" "ended cancelled"
X=$(delib_new 48 "$WORK/tension.md")
allowed "A escalates to a human" delib_move "$X" A escalated "$WORK/close.md"
assert_eq "escalating ends it" "$(delib_status "$X")" "ended escalated"

# --- 5. The round cap counts every move -----------------------------------
# Proposals and verdicts used to slip past a cap that counted turn files
# only: ten propose/reject exchanges passed a cap of six.
K=$(delib_new 49 "$WORK/tension.md"); move "$K" B turn "$WORK/t.md"
code=0; i=0
while [ "$i" -lt 10 ]; do
  prop "Variant $i."
  DELIB_MAX_ROUNDS=3 delib_move "$K" A proposal "$WORK/p.md" >/dev/null 2>&1 || { code=$?; break; }
  DELIB_MAX_ROUNDS=3 delib_move "$K" B reject "$WORK/rej.md" >/dev/null 2>&1 || { code=$?; break; }
  i=$((i + 1))
done
assert_eq "propose/reject exchanges hit the cap with exit 3" "$code" "3"
# Six moves after the tension, plus the verdict the sixth was owed.
assert_eq "the cap stops them once three rounds are spent" "$(_delib_last_file "$K")" "07-B-reject.md"
assert_eq "the status says capped" "$(DELIB_MAX_ROUNDS=3 delib_status "$K")" "capped"
assert_eq "A is woken by the cap" "$(DELIB_MAX_ROUNDS=3 delib_wait "$K" A 0 1)" "capped 07-B-reject.md"
assert_eq "B is not — it waits for A to close" "$(DELIB_MAX_ROUNDS=3 delib_wait "$K" B 0 1)" "timeout"
DELIB_MAX_ROUNDS=3 allowed "A can still close a capped deliberation" delib_move "$K" A parked "$WORK/close.md"
# A verdict owed at the cap is still given, and its acceptance can still close.
V=$(delib_new 51 "$WORK/tension.md"); move "$V" B turn "$WORK/t.md"; prop "Last."
DELIB_MAX_ROUNDS=1 delib_move "$V" A proposal "$WORK/p.md" >/dev/null 2>&1
DELIB_MAX_ROUNDS=1 allowed "a verdict owed at the cap is still allowed" delib_move "$V" B accept
DELIB_MAX_ROUNDS=1 allowed "and its acceptance can still be agreed" delib_move "$V" A agreed "$WORK/res.md"

# --- 6. Waits are role-aware ----------------------------------------------
W=$(delib_new 44 "$WORK/tension.md")
assert_eq "B wakes on the tension" "$(delib_wait "$W" B 0 1)" "open B 00-A-tension.md"
assert_eq "A does not wake on its own move" "$(delib_wait "$W" A 0 1)" "timeout"
move "$W" B turn "$WORK/t.md"; prop "Use A."; move "$W" A proposal "$WORK/p.md"
assert_eq "A does not wake on its own proposal" "$(delib_wait "$W" A 0 1)" "timeout"
move "$W" B reject "$WORK/rej.md"
# The reviewer's own rejection used to come straight back to it, every pass.
assert_eq "B does not wake on its own rejection" "$(delib_wait "$W" B 0 1)" "timeout"
assert_eq "A wakes on the rejection" "$(delib_wait "$W" A 0 1)" "open A 03-B-reject.md"
move "$W" A cancelled "$WORK/close.md"
assert_eq "both sides wake on the end" "$(delib_wait "$W" B 0 1)" "ended cancelled 04-A-cancelled.md"
refused "waiting on no deliberation is an error" delib_wait "$WORK/nowhere" B 1 1

# --- 7. Open deliberations, by issue and by host seam ---------------------
P1=$(delib_new 60 "$WORK/tension-pr.md"); P2=$(delib_new 60 "$WORK/tension.md")
assert_eq "every open deliberation is listed" "$(delib_open_for_issue 60 | wc -l | tr -d ' ')" "2"
assert_eq "a host seam filters to its own" "$(delib_open_for_issue 60 apply-loop)" "$P1"

# --- 8. The bootstrap names the installed skill, not this repo's layout ---
BOOT=$(delib_bootstrap "$D")
assert_match "the bootstrap invokes the installed skill" "$BOOT" "/stenswf:deliberate-peer $(cd "$D" && pwd -P)"
assert_nomatch "the bootstrap hardcodes no repository layout" "$BOOT" "Read plugins/stenswf/"
SKILLFILE=$(printf '%s\n' "$BOOT" | sed -n 's/^  Read \(.*\) and follow it\.$/\1/p')
[ -f "$SKILLFILE" ] && case "$SKILLFILE" in /*) true ;; *) false ;; esac \
  && ok "the fallback names an absolute skill file that exists" \
  || fail "the fallback names an absolute skill file that exists ($SKILLFILE)"

# --- 9. The PR-loop pair needs a shared checkout, opted into and seen -----
STENSWF_DELIB_SHARED_CHECKOUT= refused "no opt-in, no PR-loop deliberation" delib_pr_peer_ready 61
STENSWF_DELIB_SHARED_CHECKOUT=1 refused "an opt-in without the reviewer's state here is refused" delib_pr_peer_ready 61
mkdir -p .stenswf/61 && printf '{"cycle":1}\n' > .stenswf/61/loop-state.reviewer.json
STENSWF_DELIB_SHARED_CHECKOUT=1 allowed "opted in, with the reviewer writing here" delib_pr_peer_ready 61

# --- 10. The contradiction gate: entries, literals, nothing dropped -------
C=$(delib_new 80 "$WORK/tension.md"); mkdir -p docs/stenswf/decisions
cat > .stenswf/80/decisions.md <<'EOF'
# Decisions — #80

### D1 — Unrelated call

- **Refs:** src/other.ts

### D2 — Retry at the caller

- **Refs:** src/adapter.ts

### ~~D3~~ — Retired call

- **Refs:** src/adapter.ts
EOF
printf '# Proposal\n\n## Refs\nsrc/adapter.ts, delib#80-abc\n' > "$WORK/g.md"
CAND=$(delib_contradictions 80 "$WORK/g.md")
assert_match "the entry citing the path is named"     "$CAND" "D2"
assert_nomatch "entries citing other paths are not"   "$CAND" "D1"
assert_nomatch "superseded entries are not offered"   "$CAND" "D3"
assert_nomatch "the delib token is not treated as a path" "$CAND" "delib#"

# Paths are literal strings, not patterns: `app/[id]/` is a path.
cat >> .stenswf/80/decisions.md <<'EOF'

### D4 — Render the id route on the server

- **Refs:** app/[id]/page.tsx
EOF
printf '# Curated\n\nRefs: app/[id]/page.tsx\n' > docs/stenswf/decisions/prd-9.md
printf 'x\n' > meta.txt && git add -A >/dev/null 2>&1
git commit -q -m "feat: id route

Touches: app/[id]/page.tsx" >/dev/null 2>&1
printf '# Proposal\n\n## Refs\napp/[id]/page.tsx\n' > "$WORK/g.md"
META=$(delib_contradictions 80 "$WORK/g.md")
assert_match "a bracketed path is found in the anchor tier"    "$META" "D4"
assert_match "a bracketed path is found in the committed tier" "$META" "prd-9.md"
assert_match "a bracketed path is found in the git tier"       "$META" "git"
printf '# Proposal\n\n## Refs\napp/.id./page.tsx\n' > "$WORK/g.md"
assert_nomatch "a regex lookalike does not match a literal path" "$(delib_contradictions 80 "$WORK/g.md")" "D4"

# Root-level names have neither `/` nor `.` — the old filter dropped them,
# and with them every tier, including the house rules.
cat >> .stenswf/80/decisions.md <<'EOF'

### D5 — Pin the base image

- **Refs:** Dockerfile
EOF
printf '# House\n' > AGENTS.md
printf '# Proposal\n\n## Refs\nDockerfile\n' > "$WORK/g.md"
DOCK=$(delib_contradictions 80 "$WORK/g.md")
assert_match "a root-level name reaches the anchor tier" "$DOCK" "D5"
assert_match "the house tier is reported with it"        "$DOCK" "AGENTS.md — read before overruling"
printf '# Proposal\n\n## Refs\n(none)\n' > "$WORK/g.md"
assert_match "the house tier is reported even with no refs" "$(delib_contradictions 80 "$WORK/g.md")" "AGENTS.md"

# Refs as agents actually write them.
printf '# Proposal\n\n## Refs\n- `src/adapter.ts:12`\n- ./app/[id]/page.tsx#L4-L9\n' > "$WORK/g.md"
FORMS=$(delib_contradictions 80 "$WORK/g.md")
assert_match "a backticked ref with a line suffix matches" "$FORMS" "D2"
assert_match "a ./-prefixed ref with a line anchor matches" "$FORMS" "D4"

# No silent truncation: the old `head -3` hid the fourth matching entry.
for n in 6 7 8 9; do printf '\n### D%s — Shared lib call %s\n\n- **Refs:** lib/shared.ts\n' "$n" "$n" >> .stenswf/80/decisions.md; done
printf '# Proposal\n\n## Refs\nlib/shared.ts\n' > "$WORK/g.md"
assert_eq "every matching entry is listed" \
  "$(delib_contradictions 80 "$WORK/g.md" | grep -c '^anchor')" "4"
for n in 1 2 3; do printf '%s\n' "$n" >> meta.txt; git commit -qam "touch lib/shared.ts ($n)"; done
OVER=$(DELIB_GIT_HITS=2 delib_contradictions 80 "$WORK/g.md")
assert_eq "git hits up to the limit are listed" "$(printf '%s\n' "$OVER" | grep -c 'in commit message')" "2"
assert_match "the rest is announced, not dropped" "$OVER" "lib/shared.ts: 1 more not shown"

# --- 11. Wiring -----------------------------------------------------------
for f in "$SKILLS/deliberate/SKILL.md" "$SKILLS/deliberate-peer/SKILL.md"; do
  n=$(basename "$(dirname "$f")")
  assert_match "$n loads the contract"   "$(cat "$f")" "deliberation-loop.md"
  assert_match "$n sources the plumbing" "$(cat "$f")" "scripts/deliberation.sh"
done
A_SKILL=$(cat "$SKILLS/deliberate/SKILL.md"); B_SKILL=$(cat "$SKILLS/deliberate-peer/SKILL.md")
assert_match "A hands over with the bootstrap"  "$A_SKILL" 'delib_bootstrap "$DIR"'
assert_match "A waits by role"                  "$A_SKILL" 'delib_wait "$DIR" A'
assert_match "A always records an anchor"       "$A_SKILL" "**always**"
assert_match "issue-rework skips the human gate" "$A_SKILL" "does not pass through this gate"
assert_match "the peer takes the path as its argument" "$B_SKILL" 'DIR="$ARGUMENTS"'
assert_match "the peer loops on its own wait"   "$B_SKILL" 'delib_wait "$DIR" B'
assert_match "the peer is read-only"            "$B_SKILL" "read-only"
RETIRED=$(grep -lE 'delib_(turn_write|propose|accept|reject|finish|round_guard|next_role|proposal_version|turn)\b' \
  "$SKILLS"/*/SKILL.md "$REFS"/*.md "$HERE/../README.md" 2>/dev/null)
assert_eq "no skill, reference or README uses the retired API" "$RETIRED" ""
AL=$(cat "$SKILLS/apply-loop/SKILL.md"); RL=$(cat "$SKILLS/review-loop/SKILL.md")
assert_match "apply-loop checks the shared checkout first" "$AL" 'delib_pr_peer_ready "$ISSUE"'
assert_match "apply-loop knows the re-raise trigger" "$AL" "list_reraised"
assert_match "apply-loop wakes the reviewer on the thread" "$AL" "stenswf-delib:"
assert_match "review-loop takes only its own deliberations" "$RL" 'delib_open_for_issue "$ISSUE" apply-loop'
assert_nomatch "review-loop takes every open deliberation, not the first" "$RL" "head -1"
assert_match "review-loop will not converge mid-deliberation" "$RL" "Never converge or exit while a deliberation is open"
assert_match "escalation forbids unilateral, not autonomous, decisions" \
  "$(cat "$REFS/decision-escalation.md")" "No *unilateral* heavy decisions"

for f in "$REFS/deliberation-loop.md" "$SKILLS/deliberate/SKILL.md" "$SKILLS/deliberate-peer/SKILL.md"; do
  d=$(dirname "$f")
  while IFS= read -r link; do
    [ -e "$d/$link" ] && ok "link resolves: $(basename "$(dirname "$f")")/$(basename "$f") → $link" \
                      || fail "dangling link in $f: $link"
  done < <(grep -oE '\]\(([^)#]+\.(md|sh))' "$f" | sed 's/^](//' | sort -u)
done

# --- 12. The canonical run, in the skills' own command order --------------
E=$(delib_new 46 "$WORK/tension.md")
assert_eq "e2e: B wakes on the tension" "$(delib_wait "$E" B 0 1)" "open B 00-A-tension.md"
move "$E" B turn "$WORK/t.md"
assert_eq "e2e: A wakes on B's turn" "$(delib_wait "$E" A 0 1)" "open A 01-B-turn.md"
prop "Use A."; move "$E" A proposal "$WORK/p.md"
assert_eq "e2e: B wakes on the proposal" "$(delib_wait "$E" B 0 1)" "open B 02-A-proposal.md"
move "$E" B reject "$WORK/rej.md"
assert_eq "e2e: A wakes on the rejection" "$(delib_wait "$E" A 0 1)" "open A 03-B-reject.md"
prop "Use C."; move "$E" A proposal "$WORK/p.md"; move "$E" B accept
assert_eq "e2e: A wakes on the acceptance" "$(delib_wait "$E" A 0 1)" "open A 05-B-accept.md"
move "$E" A agreed "$WORK/res.md"
assert_eq "e2e: B is told it ended" "$(delib_wait "$E" B 0 1)" "ended agreed 06-A-agreed.md"
assert_eq "e2e: the deliberation closes" "$(delib_open_for_issue 46)" ""

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
