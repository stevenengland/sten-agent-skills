---
name: security-bug-hunting
description: Hunt for security defects worth fixing during a refactor — injection vectors, unsafe deserialisation, broken auth/authz, secret leakage, unsafe dependency surface. Language-agnostic counterpart to the security-scanning portion of python-refactor. Use when scoping a refactor and you want security fixes folded into the plan rather than deferred.
disable-model-invocation: true
---

**Status:** placeholder — not yet implemented.

Intended purpose: surface security defects (injection, deserialisation,
auth, secrets, dependency risk) worth fixing during an upcoming
refactor. Pairs with `improve-codebase-architecture` (structural
opportunities) and `functional-bug-hunting` (behavioural defects) to
form the "discover" phase of `stenswr`.

Do not invoke this skill yet — it has no implementation body.
