#!/usr/bin/env bash
# Publish a slice's decision anchor to durable, non-local surfaces.
#
# `.stenswf/` is gitignored, so `.stenswf/<N>/decisions.md` dies with the
# working copy. This script renders the anchor's ACTIVE entries into a
# marker-delimited markdown block for the PR body and the wrap-up issue
# comment. Contract: plugins/stenswf/README.md#decision-anchor-contract.
#
# Usage:
#   publish-decisions.sh render [--excerpt] <issue>      # block on stdout
#   publish-decisions.sh pr <issue> <pr>              # upsert into PR body
#   publish-decisions.sh issue <issue>                # upsert the decisions comment
#
# render            all active entries, regardless of category or Refs.
# render --excerpt  the committed docs/ tier: active ∩ {arch, decision} ∩ has
#                   a file-path Ref, and no markers or heading.
# pr / issue        idempotent: replace an existing block, preserve
#                   everything outside the markers, remove the block when
#                   the render is empty. `issue` owns ONE comment per issue
#                   and every publisher targets it, so the issue never
#                   accumulates contradicting blocks.
#
# A missing anchor is a silent no-op (exit 0), matching the read contract:
# absence is a context note, not an error.
set -eu

MARK_START='<!-- stenswf:decisions:start -->'
MARK_END='<!-- stenswf:decisions:end -->'
US=$(printf '\037')

# Live anchor, else the newest archived one. Owner of the live-or-archived
# fallback that review/prd.md and apply/decisions-excerpt.md both need.
anchor_path() {
  _p=".stenswf/$1/decisions.md"
  if [ -s "$_p" ]; then
    printf '%s\n' "$_p"
    return 0
  fi
  _p=$(ls -1d .stenswf/.archive/"$1"-*/decisions.md 2>/dev/null | sort | tail -1)
  if [ -n "$_p" ] && [ -s "$_p" ]; then
    printf '%s\n' "$_p"
    return 0
  fi
  return 1
}

# Parse an anchor into one US-separated record per ACTIVE entry:
#   id US header US category US source US rationale US refs US supersedes US parked
# Active = header `### D<n> `; strikethrough `### ~~D<n>~~` never matches.
# The header is carried verbatim so the em-dash title survives locales and
# awk variants that mishandle multibyte character classes.
parse_anchor() {
  awk -v CURATED="${2:-0}" '
    function val(s) {
      sub(/^- \*\*[^*]*:\*\*[[:space:]]*/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    function reset() {
      id=""; header=""; cat=""; src=""; rat=""; refs=""; sup=""; parked=0; hasref=0
    }
    function emit() {
      if (id == "") return
      if (CURATED == 1 && cat != "arch" && cat != "decision") { reset(); return }
      if (CURATED == 1 && hasref == 0) { reset(); return }
      printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n",
             id, header, cat, src, rat, refs, sup, parked
      reset()
    }
    BEGIN { reset() }
    /^### / {
      emit()
      if ($0 ~ /^### D[0-9]+ /) {
        header = $0
        sub(/[[:space:]]+$/, "", header)
        match($0, /D[0-9]+/)
        id = substr($0, RSTART, RLENGTH)
      }
      next
    }
    id == "" { next }
    /^- \*\*Category:\*\*/   { cat = val($0); next }
    /^- \*\*Source:\*\*/     { src = val($0); next }
    /^- \*\*Rationale:\*\*/  { rat = val($0); next }
    /^- \*\*Supersedes:\*\*/ { sup = val($0); next }
    /^- \*\*Refs:\*\*/       { refs = val($0); if (refs ~ /\//) hasref = 1; next }
    # Canonical field form, plus the legacy bare paragraph. Both anchored to
    # line start so the word "parked" inside a rationale never sets the flag.
    /^- \*\*Status:\*\*[[:space:]]*parked/ { parked = 1; next }
    /^status:[[:space:]]*parked/           { parked = 1; next }
    END { emit() }
  ' "$1"
}

# One entry of a PRD anchor, as a US-separated record. Used to fill in the
# rationale that inherited stubs deliberately omit (inherit-decisions.sh
# writes `Source: #<PRD>/D<n>` and expects the reader to hop to a local
# file — a dangling pointer once published). Returns the whole record so
# the caller splits it once instead of re-parsing the anchor per field.
lookup_prd_entry() {
  _src=$(anchor_path "$1") || return 1
  parse_anchor "$_src" 0 | awk -F"$US" -v id="$2" '
    $1 == id { print; found = 1; exit }
    END { exit(found ? 0 : 1) }
  '
}

render() {
  # --excerpt = the committed docs/ tier: strict curation filter, and no
  # markers or heading (the excerpt file supplies its own). The two always
  # travelled together, so they are one mode rather than two flags.
  _excerpt=0
  if [ "${1:-}" = "--excerpt" ]; then
    _excerpt=1
    shift
  fi
  _issue="${1:-}"
  [ -n "$_issue" ] || { echo "usage: publish-decisions.sh render [--excerpt] <issue>" >&2; exit 2; }

  _anchor=$(anchor_path "$_issue") || return 0
  _records=$(parse_anchor "$_anchor" "$_excerpt")
  [ -n "$_records" ] || return 0

  if [ "$_excerpt" = "0" ]; then
    printf '%s\n' "$MARK_START"
    printf '## Decisions\n\n'
    printf 'Recorded during the stenswf workflow for #%s. Superseded entries omitted.\n' "$_issue"
    printf 'Rendered from the local decision anchor by `publish-decisions.sh`.\n'
  fi

  printf '%s\n' "$_records" | while IFS="$US" read -r id header cat src rat refs sup parked; do
    # Inherited stubs carry no rationale; resolve it from the PRD anchor.
    if [ "$cat" = "inherited" ]; then
      _prd=$(printf '%s' "$src" | sed -n 's|^#\([0-9][0-9]*\)/.*$|\1|p')
      _stub_id=$(printf '%s' "$src" | sed -n 's|^#[0-9][0-9]*/\(D[0-9][0-9]*\)$|\1|p')
      if [ -n "$_prd" ] && [ -n "$_stub_id" ]; then
        _rec=$(lookup_prd_entry "$_prd" "$_stub_id" 2>/dev/null) || _rec=""
        _rcat=$(printf '%s' "$_rec" | cut -d"$US" -f3)
        _rrat=$(printf '%s' "$_rec" | cut -d"$US" -f5)
        cat="${_rcat:-inherited}"
        # inherit-decisions.sh already suffixes the header; don't repeat it.
        case "$header" in
          *"inherited from #$_prd"*) ;;
          *) cat="$cat (inherited from #$_prd)" ;;
        esac
        rat="${_rrat:-see #$_prd — entry $_stub_id}"
        src="#$_prd"
      fi
    fi

    printf '\n'
    if [ "$parked" = "1" ]; then
      printf '### ⚠ %s\n' "${header#\#\#\# }"
    else
      printf '%s\n' "$header"
    fi
    printf '\n'
    [ -n "$cat" ]  && printf -- '- **Category:** %s\n' "$cat"
    [ -n "$src" ]  && printf -- '- **Source:** %s\n' "$src"
    [ -n "$rat" ]  && printf -- '- **Rationale:** %s\n' "$rat"
    [ -n "$refs" ] && printf -- '- **Refs:** %s\n' "$refs"
    [ -n "$sup" ]  && printf -- '- **Supersedes:** %s\n' "$sup"
    [ "$parked" = "1" ] && printf -- '- **Status:** parked — blocking until resolved\n'
    true
  done

  [ "$_excerpt" = "0" ] && printf '\n%s\n' "$MARK_END"
  return 0
}

# Replace the marked block in a body file, in place, preserving everything
# outside the markers so a human's edits survive every refresh. An empty
# block removes it. Shared by both upsert paths — the PR body and the
# dedicated decisions comment behave identically by construction.
merge_block() {
  _bf="$1"; _blk="$2"
  _mt="$_bf.merge"

  awk -v s="$MARK_START" -v e="$MARK_END" '
    { sub(/\r$/, "") }
    $0 == s { skip = 1; next }
    $0 == e { skip = 0; next }
    skip == 0 { print }
  ' "$_bf" > "$_mt"

  # Trim trailing blank lines left behind by the removed block.
  awk 'BEGIN { n = 0 }
       { lines[NR] = $0; if ($0 ~ /[^[:space:]]/) n = NR }
       END { for (i = 1; i <= n; i++) print lines[i] }' "$_mt" > "$_bf"
  rm -f "$_mt"

  if [ -n "$_blk" ]; then
    [ -s "$_bf" ] && printf '\n' >> "$_bf"
    printf '%s\n' "$_blk" >> "$_bf"
  fi
}

upsert_pr() {
  _issue="${1:-}"; _pr="${2:-}"
  if [ -z "$_issue" ] || [ -z "$_pr" ]; then
    echo "usage: publish-decisions.sh pr <issue> <pr>" >&2
    exit 2
  fi

  _block=$(render "$_issue")

  _tmp=$(mktemp)
  trap 'rm -f "$_tmp" "$_tmp.merge"' EXIT

  gh pr view "$_pr" --json body -q .body > "$_tmp" || {
    echo "publish-decisions: cannot read PR $_pr body" >&2
    return 1
  }

  merge_block "$_tmp" "$_block"
  gh pr edit "$_pr" --body-file "$_tmp"
}

# The issue's single decisions comment. Every lifecycle skill that publishes
# to the issue targets this same comment, so a superseded entry disappears
# from the issue exactly as it does from the PR body. Appending a fresh
# comment per run would leave stale blocks visible forever, contradicted by
# a newer one further down, with no cue which is current.
upsert_issue() {
  _issue="${1:-}"
  [ -n "$_issue" ] || { echo "usage: publish-decisions.sh issue <issue>" >&2; exit 2; }

  _block=$(render "$_issue")

  # Restrict to comments we authored, so a human quoting the block in their
  # own comment is never overwritten. If the login is unavailable, fall back
  # to marker-only matching rather than posting a duplicate.
  _me=$(gh api user --jq .login 2>/dev/null) || _me=""
  _filter='.[] | select(.body | contains("'"$MARK_START"'"))'
  [ -n "$_me" ] && _filter="$_filter | select(.user.login == \"$_me\")"
  _filter="$_filter | .id"

  # Assign before piping: a pipeline's status is `tail`'s, so piping here
  # would make a failed listing indistinguishable from "no comment yet" — and
  # the fallback for that is to POST, which is how a rate limit or transient
  # 5xx turns into a second decisions comment. The older one then lingers
  # with stale content forever, because the next run's `tail -1` targets the
  # newer. Failing loudly is the only safe answer; the `pr` path does the same.
  _list=$(gh api "repos/{owner}/{repo}/issues/$_issue/comments" --paginate \
            --jq "$_filter") || {
    echo "publish-decisions: cannot list comments on issue $_issue" >&2
    return 1
  }
  _cid=$(printf '%s\n' "$_list" | tail -1)

  if [ -z "$_cid" ]; then
    # Nothing published yet. An empty anchor stays silent — most lite slices
    # decide nothing worth recording, and an empty comment is noise.
    [ -n "$_block" ] || return 0
    printf '%s\n' "$_block" | gh issue comment "$_issue" --body-file -
    return
  fi

  _tmp=$(mktemp)
  trap 'rm -f "$_tmp" "$_tmp.merge"' EXIT

  gh api "repos/{owner}/{repo}/issues/comments/$_cid" --jq .body > "$_tmp" || {
    echo "publish-decisions: cannot read comment $_cid on issue $_issue" >&2
    return 1
  }

  merge_block "$_tmp" "$_block"

  # A comment body cannot be empty. If every entry was superseded and the
  # comment carried nothing else, say so rather than leaving the last
  # rendered state standing.
  [ -s "$_tmp" ] || printf '_All recorded decisions were superseded._\n' > "$_tmp"

  gh api --method PATCH "repos/{owner}/{repo}/issues/comments/$_cid" \
    -F body=@"$_tmp" >/dev/null
}

CMD="${1:-}"
shift || true
case "$CMD" in
  render) render "$@" ;;
  pr)     upsert_pr "$@" ;;
  issue)  upsert_issue "$@" ;;
  *)
    echo "usage: publish-decisions.sh render [--excerpt] <issue> | pr <issue> <pr> | issue <issue>" >&2
    exit 2
    ;;
esac
