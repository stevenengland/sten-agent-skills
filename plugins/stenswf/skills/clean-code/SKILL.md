---
name: clean-code
description: Apply clean code principles for readability, simplicity, and ease of change when writing, reviewing, or refactoring code.
disable-model-invocation: true
---

# Clean Code Skill

Use this skill to turn "code that works" into "code that is easy to read, change,
and extend" by any competent developer.

## When to Use

Use this skill whenever you:

- Write new production code.
- Refactor existing code.
- Review pull requests or staged changes.
- Apply review or improvement plans.

## Goals

When this skill is active, optimize for:

- Clarity over cleverness.
- Simple, direct solutions over over-engineered designs.
- Code that is easy to understand and modify by someone who did not write it.

## 1. Names

- Use intention-revealing names for variables, functions, classes, and modules.
- Avoid misleading names and unnecessary abbreviations.
- Prefer names that are easy to pronounce, search, and grep.

## 2. Functions and Methods

- Keep functions small; they should do one thing and do it well.
- Keep each function at a single level of abstraction.
- Prefer fewer parameters; avoid long parameter lists and flag parameters.
- Avoid hidden side effects and surprising global state changes.

## 3. Comments

- Prefer self-explanatory code over comments.
- Use comments sparingly to explain *why* something is done, not *what* it does.
- Remove outdated, redundant, or noisy comments.

## 4. Structure and Formatting

- Organize code so that high-level ideas appear first, details later.
- Keep related lines close together; avoid unnecessary vertical distance.
- Use consistent indentation and spacing to make structure obvious.

## 5. Objects, Data, and Dependencies

- Hide implementation details behind clear interfaces or APIs.
- Avoid “train-wreck” access like `a.getB().getC().doSomething()`.
- Keep data structures and behavior cohesive and focused.

## 6. Error Handling

- Prefer clear exception or error handling over scattered return codes.
- Keep error-handling paths readable and separate from happy-path logic.
- Avoid silently swallowing errors.

## 7. Tests

- Ensure new or changed behavior is covered by automated tests.
- Keep tests simple, readable, and independent.
- Use tests as a safety net for refactoring.

## 8. Smells and Heuristics

Watch for and reduce:

- Duplication of logic or structure.
- Overly complex or deeply nested code.
- Classes or functions that have too many responsibilities.
- Code that is hard to explain in a few sentences.

## Application Checklist

When you invoke this skill on a piece of code, ask:

- [ ] Are names clear and intention-revealing?
- [ ] Are functions small and focused on one purpose?
- [ ] Is the structure simple and easy to follow top-to-bottom?
- [ ] Is duplication minimized?
- [ ] Is error handling clear and non-intrusive?
- [ ] Are relevant tests in place and readable?