class: refactor

Candidate: deepen the notification senders. Today `src/notify/` has `email.ts`, `sms.ts` and `push.ts`, each re-implementing retry, templating and opt-out checks; callers pick a sender by hand.

Grilled and decided:
- Interface: one `Notifier.send(recipient, message)` module; channel choice moves behind it, driven by the recipient's preferences.
- Behind the seam: the three channel adapters; retry and opt-out checks live once, inside the module.
- Tests: interface tests through `Notifier.send` replace the three per-sender suites once they cover retry, opt-out and templating.
- Invariant kept: an opted-out recipient never receives a message on any channel.
- Rejected: a channel-registry plugin system (no third-party channels planned); keeping the per-channel modules public (callers would keep choosing channels).

Still open:
- Rollout: switch every caller in one change, or migrate caller by caller behind the old functions?
