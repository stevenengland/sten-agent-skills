# Sources

The registry of tracked skills and their upstream sources now lives in [sources.yaml](sources.yaml).

It is consumed by the [`sync-upstream-skills`](skills/sync-upstream-skills/SKILL.md) skill, which walks each tracked entry, compares it against its upstream, and interviews the user about changes worth importing.

