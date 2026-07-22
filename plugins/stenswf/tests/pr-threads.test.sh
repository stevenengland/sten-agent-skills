#!/usr/bin/env bash
# Behavior tests for the reviewer-side PR-thread plumbing.
#
# Exercises scripts/pr-threads.sh through the `gh` seam: a fake `gh` on
# PATH records what each function sends and returns canned responses, so
# the tests observe real behavior without a live GitHub PR. The
# fingerprint test runs fully offline.
#
# Run:  bash plugins/stenswf/tests/pr-threads.test.sh
set -uo pipefail

HERE=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPTS="$HERE/../scripts"

# shellcheck source=../scripts/extractors.sh
source "$SCRIPTS/extractors.sh"
# shellcheck source=../scripts/pr-threads.sh
source "$SCRIPTS/pr-threads.sh"

PASS=0
FAIL=0
fail() { printf 'not ok - %s\n' "$1"; FAIL=$((FAIL + 1)); }
ok()   { printf 'ok - %s\n'     "$1"; PASS=$((PASS + 1)); }
assert_eq()      { [ "$2" = "$3" ]  && ok "$1" || { fail "$1"; printf '    expected: %s\n    actual:   %s\n' "$3" "$2"; }; }
assert_ne()      { [ "$2" != "$3" ] && ok "$1" || { fail "$1"; printf '    both were: %s\n' "$2"; }; }
assert_match()   { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || { fail "$1"; printf '    missing %q in: %s\n' "$3" "$2"; }; }

# --- Fake gh harness -------------------------------------------------------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
STATE="$WORK/review-decision"     # holds the PR reviewDecision
POSTED="$WORK/posted-body"        # captures the body add_thread sends
printf 'REVIEW_REQUIRED' > "$STATE"

cat > "$WORK/gh" <<GHEOF
#!/usr/bin/env bash
# Minimal fake gh. Branches on the sub-command and flags the plumbing uses.
STATE="$STATE"
POSTED="$POSTED"
args="\$*"
case "\$1 \$2" in
  "repo view")
    echo "octo-org octo-repo" ;;                       # owner name (-q)
  "pr view")
    if printf '%s' "\$args" | grep -q 'reviewDecision'; then
      cat "\$STATE"                                    # PR review decision
    elif printf '%s' "\$args" | grep -q '\.id'; then
      echo "PR_node_abc"                               # pull request node id
    else
      echo "77"                                        # current-branch PR number
    fi ;;
  "pr review")
    printf 'APPROVED' > "\$STATE" ;;                   # submit_approval
  "api graphql")
    if printf '%s' "\$args" | grep -q 'addPullRequestReviewThread'; then
      for a in "\$@"; do case "\$a" in body=*) printf '%s' "\${a#body=}" > "\$POSTED";; esac; done
      echo '{"data":{"addPullRequestReviewThread":{"thread":{"id":"RT_new"}}}}'
    else
      # list reviewThreads: one open, one resolved
      cat <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
  {"id":"RT_open","isResolved":false,"comments":{"nodes":[{"author":{"login":"reviewer-bot"},"body":"null deref here\n\n<!-- stenswf-fp:deadbeef0001 -->"}]}},
  {"id":"RT_done","isResolved":true,"comments":{"nodes":[{"author":{"login":"human"},"body":"already fixed"}]}}
]}}}}}
JSON
    fi ;;
  *) echo "fake gh: unhandled: \$args" >&2; exit 3 ;;
esac
GHEOF
chmod +x "$WORK/gh"
PATH="$WORK:$PATH"

# --- fingerprint stability (offline) --------------------------------------
# Same finding located at different diff lines fingerprints identically,
# because line number is never an input; a different finding differs.
fp_line10=$(fingerprint "src/foo.js" "function bar" "unchecked null deref")
fp_line42=$(fingerprint "src/foo.js" "function bar" "unchecked null deref")
assert_eq "fingerprint is stable across a line-shifting diff" "$fp_line10" "$fp_line42"
fp_other=$(fingerprint "src/foo.js" "function baz" "unchecked null deref")
assert_ne "fingerprint discriminates distinct findings" "$fp_line10" "$fp_other"
[ "${#fp_line10}" -ge 8 ] && ok "fingerprint is a non-trivial hash" || fail "fingerprint is a non-trivial hash"

# --- add_thread embeds the fingerprint marker -----------------------------
fp=$(fingerprint "src/foo.js" "function bar" "unchecked null deref")
add_thread 77 "src/foo.js" 10 "$fp" "unchecked null deref" >/dev/null
assert_match "add_thread posts a body carrying the stenswf-fp marker" "$(cat "$POSTED")" "<!-- stenswf-fp:$fp -->"
assert_match "add_thread body keeps the finding text" "$(cat "$POSTED")" "unchecked null deref"

# --- list_open_threads returns node-id + author + body --------------------
listing=$(list_open_threads 77)
assert_match "list_open_threads returns the open thread node-id" "$listing" "RT_open"
assert_match "list_open_threads returns the thread author"       "$listing" "reviewer-bot"
assert_match "list_open_threads surfaces the fingerprint body"   "$listing" "stenswf-fp:deadbeef0001"
printf '%s' "$listing" | grep -q "RT_done" && fail "list_open_threads excludes resolved threads" || ok "list_open_threads excludes resolved threads"

# --- submit_approval / read_review_decision -------------------------------
assert_eq "review decision starts un-approved" "$(read_review_decision 77)" "REVIEW_REQUIRED"
submit_approval 77 "nothing more to say"
assert_eq "submit_approval flips reviewDecision to APPROVED" "$(read_review_decision 77)" "APPROVED"

# --- resolve_pr: explicit arg vs current-branch default -------------------
assert_eq "resolve_pr passes an explicit PR arg through" "$(resolve_pr 55)" "55"
assert_eq "resolve_pr defaults to the current branch's PR" "$(resolve_pr "")" "77"

# --- linked-issue mode drives slice-vs-PRD dispatch -----------------------
prd_body="$WORK/issue-prd.md"
printf '<!-- stenswf:v1\ntype: PRD\n-->\n' > "$prd_body"
TYPE=$(get_fm type "$prd_body"); parse_type; assert_eq "PRD front-matter selects prd mode" "$MODE" "prd"
slice_body="$WORK/issue-slice.md"
printf '<!-- stenswf:v1\ntype: slice — AFK\n-->\n' > "$slice_body"
TYPE=$(get_fm type "$slice_body"); parse_type; assert_eq "slice front-matter selects slice mode" "$MODE" "slice"

# --- summary ---------------------------------------------------------------
printf '\n1..%d\n# pass %d fail %d\n' "$((PASS + FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
