---
name: tdd
description: Test-driven development with a red-green-refactor loop for features, bug fixes, or integration tests.
---

# Test-Driven Development

## Philosophy

**Core principle**: Tests should verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't.

**Good tests** are integration-style: they exercise real code paths through public APIs. They describe _what_ the system does, not _how_ it does it. A good test reads like a specification - "user can checkout with valid cart" tells you exactly what capability exists. These tests survive refactors because they don't care about internal structure.

**Bad tests** are coupled to implementation. They mock internal collaborators, test private methods, or verify through external means (like querying a database directly instead of using the interface). The warning sign: your test breaks when you refactor, but behavior hasn't changed. If you rename an internal function and tests fail, those tests were testing implementation, not behavior.

See [tests.md](tests.md) for examples and [mocking.md](mocking.md) for mocking guidelines.

## Anti-Pattern: Horizontal Slices

**DO NOT write all tests first, then all implementation.** This is "horizontal slicing" - treating RED as "write all tests" and GREEN as "write all code."

This produces **crap tests**:

- Tests written in bulk test _imagined_ behavior, not _actual_ behavior
- You end up testing the _shape_ of things (data structures, function signatures) rather than user-facing behavior
- Tests become insensitive to real changes - they pass when behavior breaks, fail when behavior is fine
- You outrun your headlights, committing to test structure before understanding the implementation

**Correct approach**: Vertical slices via tracer bullets. One test → one implementation → repeat. Each test responds to what you learned from the previous cycle. Because you just wrote the code, you know exactly what behavior matters and how to verify it.

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  RED→GREEN: test3→impl3
  ...
```

## Workflow

### 1. Before the first test (interface-design lens)

Before writing the failing test for a `(behavior)` AC, name the public
interface in your own working memory — do NOT ask the user, do NOT
write a planning document. This is a thinking step, not a ceremony.

Apply [interface-design.md](interface-design.md) and
[deep-modules.md](deep-modules.md):

- Function/method signature: inputs as parameters (accept dependencies,
  don't construct them), output as return value (return results, don't
  mutate hidden state).
- Smallest surface that satisfies the AC. Prefer one deep function over
  many shallow ones.
- The signature you name here is the signature the failing test calls —
  it is the single action in the test's `When` block (see [tests.md](tests.md)).

If two materially different signatures both satisfy the AC and the
codebase offers no tiebreaker, this is an architectural ambiguity —
escalate per the caller's ambiguity rules (e.g. `ship-light` emits
`ROUTE_HEAVY`). Do not silently pick.

For `(structural)` ACs, skip this step — there is no new behavior to
design an interface for.

### 2. Tracer Bullet

Write ONE test that confirms ONE thing about the system, in Given/When/Then
shape (see [tests.md](tests.md)):

```
RED:   Write test for first behavior → test fails
GREEN: Write minimal code to pass → test passes
```

This is your tracer bullet - proves the path works end-to-end.

### 3. Incremental Loop

For each remaining behavior:

```
RED:   Write next test → fails
GREEN: Minimal code to pass → passes
```

Rules:

- One test at a time
- Only enough code to pass current test
- Don't anticipate future tests
- Keep tests focused on observable behavior

### 4. Refactor

After all tests pass, look for [refactor candidates](refactoring.md):

- [ ] Extract duplication
- [ ] Deepen modules (move complexity behind simple interfaces)
- [ ] Apply SOLID principles where natural
- [ ] Consider what new code reveals about existing code
- [ ] Run tests after each refactor step

**Never refactor while RED.** Get to GREEN first.

## Checklist Per Cycle

```
[ ] Test describes behavior, not implementation
[ ] Test shaped Given/When/Then — one action (When), one logical outcome (Then)
[ ] Test uses public interface only
[ ] Test would survive internal refactor
[ ] Code is minimal for this test
[ ] No speculative features added
```
