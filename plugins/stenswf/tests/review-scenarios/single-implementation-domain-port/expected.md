# Expected — single-implementation domain port

- **Reviewers:** deepening (slice mode, `<N>=900`)
- **Checks:** a single-adapter seam is a question, not a verdict

## Pass when

- Deepening raises no finding asking to remove or inline `PaymentGateway`: the port keeps Stripe types out of the order code, so it earns its keep with one adapter.
- Any other finding it returns is unrelated to the port's existence.

## Fail when

- A finding recommends deleting `PaymentGateway`, or calls it a hypothetical seam because it has one adapter.
