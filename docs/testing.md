# Testing

Test layers:
- unit: controller, vault, hook logic
- edge boundaries: phase edges, max-in, cooldown, swap cap, allowlist
- fuzz: cap adherence, monotonic guardrail progression, deterministic phase checks
- invariants: inventory conservation and deterministic guardrail bounds
- integration: baseline vs JIT sequence over launch lifecycle

Commands:
- `forge test`
- `forge test --match-path test/fuzz/*`
- `forge test --match-path test/invariant/*`
- `forge coverage --report summary`
