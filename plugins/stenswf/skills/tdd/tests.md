# Good and Bad Tests

## Good Tests

**Integration-style**: Test through real interfaces, not mocks of internal parts.

```typescript
// GOOD: behavioral shape — Given/When/Then, one action, one outcome
test("checkout with a valid cart confirms the order", async () => {
  // Given a cart with one product
  const cart = createCart();
  cart.add(product);

  // When the customer checks out
  const result = await checkout(cart, paymentMethod);

  // Then the order is confirmed
  expect(result.status).toBe("confirmed");
});
```

Characteristics:

- Tests behavior users/callers care about
- Uses public API only
- Survives internal refactors
- Describes WHAT, not HOW
- One logical assertion per test

## Behavioral shape (Given/When/Then)

Every `(behavior)` test MUST be written in Given/When/Then shape. This is how
"describes WHAT, not HOW" becomes the visible structure of the test — see the
GOOD example above.

Rules:

- **Name** states the capability as a spec sentence: state + outcome
  ("checkout with a valid cart confirms the order"). No `should` filler. Use
  `describe`/`it` nesting where the framework supports it (Jest, RSpec); in
  xUnit-style frameworks (pytest, Go, JUnit) the sentence becomes the test's
  identifier name (`test_checkout_with_a_valid_cart_confirms_the_order`) or its
  docstring. The semantic — condition + outcome — is what matters, so this
  stays language-agnostic.
- **Body** uses `Given`/`When`/`Then` blocks labelled with the language's
  comment syntax (`//`, `#`, …); `Given` is optional when there is no
  precondition (a When/Then test is fine). Label the **business condition, not
  the code**: `// Given a cart with one product`, never `// Given create a cart`.
- **One `When`.** Multiple `Given` steps are fine (arrange); there is exactly
  one action under test. A second `When` means the test does too much — split it.
- **One logical `Then`.** The outcome may take several assertions, but they must
  verify the *same* outcome. "One logical assertion," not "one `assert`/`expect`
  statement."
- **No `given`/`when`/`then` helper functions.** Inline the setup so the test
  reads top-to-bottom (DAMP, not DRY); helpers force the reader to chase
  indirection.
- Parameterized/table-driven tests keep the shape: the case table is the
  `Given`, the single `When` runs per case.

The same shape in Python (pytest) — the function name carries the spec
sentence, `#` labels the blocks, `assert` is the `Then`:

```python
def test_checkout_with_a_valid_cart_confirms_the_order():
    # Given a cart with one product
    cart = create_cart()
    cart.add(product)

    # When the customer checks out
    result = checkout(cart, payment_method)

    # Then the order is confirmed
    assert result.status == "confirmed"
```

## Bad Tests

**Implementation-detail tests**: Coupled to internal structure.

```typescript
// BAD: Tests implementation details
test("checkout calls paymentService.process", async () => {
  const mockPayment = jest.mock(paymentService);
  await checkout(cart, payment);
  expect(mockPayment.process).toHaveBeenCalledWith(cart.total);
});
```

Red flags:

- Mocking internal collaborators
- Testing private methods
- Asserting on call counts/order
- Test breaks when refactoring without behavior change
- Test name describes HOW not WHAT
- Verifying through external means instead of interface
- No single observable When→Then — asserts on a collaborator call or external
  state instead of the outcome

```typescript
// BAD: Bypasses interface to verify
test("createUser saves to database", async () => {
  await createUser({ name: "Alice" });
  const row = await db.query("SELECT * FROM users WHERE name = ?", ["Alice"]);
  expect(row).toBeDefined();
});

// GOOD: Verifies through interface (no Given needed — When/Then is enough)
test("createUser makes user retrievable", async () => {
  // When a user is created
  const user = await createUser({ name: "Alice" });

  // Then the user can be fetched back by id
  const retrieved = await getUser(user.id);
  expect(retrieved.name).toBe("Alice");
});
```
