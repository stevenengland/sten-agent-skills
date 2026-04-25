# Out-of-scope memory

Persistent rejection memory consumed by `/stenswf:triage-issue` Phase 1
(dedup). Pattern adapted from Matt Pocock's `github-triage`
(`frameworks/mattpocock-skills/github-triage/OUT-OF-SCOPE.md`):
GitHub search alone misses the "we discussed this six months ago and
rejected it" case because the original closed issue ranks low and gets
re-filed under a different title.

## Location

```
.stenswf/.out-of-scope/<original-issue-N>.md
```

Created by `/stenswf:bootstrap`. Per-clone (excluded via
`.git/info/exclude`). Not committed — each developer carries their own
copy.

## File schema

One short markdown file per rejected issue:

```markdown
title: <verbatim title of the rejected issue>
reason: <≤2 sentences — why it was rejected>
decided-at: 2026-04-25
decided-by: <github-username>
related: 42 87 113
```

- `title:` — verbatim from the GitHub issue.
- `reason:` — why it was rejected. Stays terse; longer rationale lives
  in the issue close-comment.
- `decided-at:` — ISO 8601 date (no time).
- `decided-by:` — GitHub username of the human who confirmed REJECT.
- `related:` — optional space-separated issue numbers (other rejects
  this references).

## Triage Phase 1 dedup query

`triage-issue` runs both checks:

### GitHub search (open + closed)

```bash
# Extract top-3 nouns from the title (drop common stopwords).
TITLE=$(gh issue view "$ARGUMENTS" --json title -q .title)
NOUNS=$(printf '%s' "$TITLE" \
  | tr '[:upper:]' '[:lower:]' \
  | tr -c 'a-z0-9' ' ' \
  | tr ' ' '\n' \
  | grep -Ev '^(a|an|the|in|on|at|to|of|for|with|when|while|is|are|was|fails|fail|error|errors|bug|bugs|broken|cannot|cant|doesnt|does|not)$' \
  | grep -E '.{3,}' \
  | head -3 \
  | tr '\n' ' ')

# Search open + closed, cap at 10 results.
gh issue list --state all --search "$NOUNS is:issue" --limit 10 \
  --json number,title,state,closedAt
```

### Out-of-scope memory grep

```bash
if [ -d .stenswf/.out-of-scope ]; then
  for n in $NOUNS; do
    grep -i -l -E "^(title|reason):.*$n" .stenswf/.out-of-scope/*.md \
      2>/dev/null
  done | sort -u
fi
```

A match in either source surfaces to Phase 4 as a candidate REJECT.
The user always confirms (see `triage-issue` Q10a).

## When triage-issue writes here

Only on REJECT outcomes that the human confirms:

| Sub-type | Writes file? |
|---|---|
| `duplicate` (open issue dup) | no — GitHub already records it |
| `out-of-scope` (matches existing memory) | optional — may add `related:` cross-reference |
| `out-of-scope` (novel rejection) | **yes** — new file, full schema |
| `needs-info` | no — not a durable rejection |

`wontfix`-style rejections that the agent cannot decide alone bubble up
to the user as a question. If the user says "reject as out-of-scope,"
triage-issue writes the file.

## Schema validation

`triage-issue` Phase 1 tolerates malformed files (missing fields are
treated as empty). Do not block the workflow on a hand-edited memory
file. Log `missing_artifact` if a file lacks both `title:` and
`reason:`.
