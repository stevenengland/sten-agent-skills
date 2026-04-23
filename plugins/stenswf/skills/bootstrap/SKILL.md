---
name: bootstrap
description: One-shot, human-invoked setup for repo-level artifacts (issue-tracker
  lifecycle labels, etc.) that the planning and shipping skills rely on. Run once
  per repo.
disable-model-invocation: true
---

## Token Efficiency

**Load and apply the `brevity` sibling skill now, before the first response.**
It governs setup prompts, detection output, and status updates throughout
this one-shot flow.

---

# Bootstrap

**Human-invoked only.** Subagents and model-initiated flows must not call
this skill — it is intended to be run once per repository, by a human, before
the first use of `prd-from-grill-me`, `prd-to-issues`, `plan`, or `ship`. All
operations are idempotent and safe to re-run (e.g. after adjusting colors or
descriptions).

If labels already exist, the `ship`/`plan`/etc. skills will still work
without running this skill — they apply labels but do not create them. Running
this skill upgrades description/colors to the canonical scheme.

---

## Issue-tracker detection

Before running the commands below, detect which issue-tracker CLI is usable
in this repo. Check, in order:

1. `gh auth status` — GitHub (`gh`)
2. `glab auth status` — GitLab (`glab`)
3. `tea login list` — Gitea (`tea`)
4. Other (Jira `acli`, Bitbucket, Azure DevOps, etc.) — adapt the commands
   below to the platform's label-creation syntax. Every modern tracker
   supports a label with a name, color, and description.

If no CLI is available or authenticated, ask the user to create the labels
listed in the table below manually via the tracker's web UI, then continue.

---

## Lifecycle labels

Canonical label set used by the planning and shipping skills. The agent must
translate these to whichever CLI was detected above. Idempotency note: every
command below is shown with the `--force` / upsert variant so it is safe to
re-run.

### GitHub (`gh`)

```bash
gh label create prd        --color 8e44ad --description "Product Requirements Document"             --force
gh label create sliced     --color 5dade2 --description "PRD has been broken into slice issues"     --force
gh label create slice      --color 9b59b6 --description "Vertical slice of a parent PRD"            --force
gh label create hitl       --color f1c40f --description "Slice requires human-in-the-loop input"    --force
gh label create afk        --color 2ecc71 --description "Slice can be completed without human input" --force
gh label create needs-plan --color e67e22 --description "Slice issue awaits an implementation plan" --force
gh label create planned    --color 3498db --description "Implementation plan posted"                --force
gh label create shipping   --color 1f77b4 --description "Implementation in progress"                --force
```

### GitLab (`glab`) — translation reference

```bash
for pair in \
  "prd:#8e44ad:Product Requirements Document" \
  "sliced:#5dade2:PRD has been broken into slice issues" \
  "slice:#9b59b6:Vertical slice of a parent PRD" \
  "hitl:#f1c40f:Slice requires human-in-the-loop input" \
  "afk:#2ecc71:Slice can be completed without human input" \
  "needs-plan:#e67e22:Slice issue awaits an implementation plan" \
  "planned:#3498db:Implementation plan posted" \
  "shipping:#1f77b4:Implementation in progress" ; do
    name="${pair%%:*}"; rest="${pair#*:}"; color="${rest%%:*}"; desc="${rest#*:}"
    glab label create --name "$name" --color "$color" --description "$desc" || \
    glab label update "$name" --color "$color" --description "$desc"
done
```

### Other trackers

Adapt the name/color/description triples above to the platform's label API.
Canonical names (must match exactly): `prd`, `sliced`, `slice`, `hitl`,
`afk`, `needs-plan`, `planned`, `shipping`.

## Lifecycle overview

| Label         | Applied by                         | Removed by            |
|---------------|------------------------------------|-----------------------|
| `prd`         | `prd-from-grill-me` (PRD issue)    | —                     |
| `sliced`      | `prd-to-issues` (parent PRD)       | —                     |
| `slice`       | `prd-to-issues` (each child)       | —                     |
| `hitl`/`afk`  | `prd-to-issues` (each child)       | —                     |
| `needs-plan`  | `prd-to-issues` (each child)       | `plan`                |
| `planned`     | `plan`                             | —                     |
| `shipping`    | `ship` (Phase 1 start)             | `ship` (Phase 5 end)  |
