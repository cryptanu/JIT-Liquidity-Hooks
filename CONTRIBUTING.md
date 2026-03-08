# Contributing

## Requirements
- Foundry (stable)
- Git submodule support

## Setup
```bash
make bootstrap
make build
make test
```

## Development Workflow
1. Create a feature branch.
2. Add/modify contracts in `src/`.
3. Add tests in `test/` (unit + fuzz/invariant if relevant).
4. Run `make test` and `make coverage`.
5. Export ABIs if interfaces changed: `make abi-export`.

## Coding Guidelines
- Deterministic logic over automation assumptions.
- Bounded computation in swap paths.
- Explicit access control and error surfaces.
- Keep launch-phase constraints auditable and documented.

## Pull Requests
Include:
- problem statement
- behavioral delta
- risk assessment
- test evidence (commands + output summary)
