# Working in this repository

- Follow [CONTRIBUTING.md](CONTRIBUTING.md) for setup and validation.
- After changes, run `bundle exec rspec spec/conductor/` and `bundle exec rubocop`.
- Before committing, verify the library loads, check Ruby syntax, and run `bundle exec rspec`.
- Add tests for new behavior and bug fixes; do not reduce coverage.
- Use keyword arguments for options and mutexes for shared worker state.
- Keep documentation brief; prefer runnable examples over separate guides or design reports.

Code: `lib/conductor/client/` (clients), `http/` (transport/models),
`workflow/dsl/` (workflow definitions), `worker/` (execution), `agents/` (agents).
Unit tests mirror these paths under `spec/conductor/`.

For agent wire changes, use the Python SDK serializer as the parity source and
Conductor's `agentspan` module as the server contract. Update Python-derived golden
fixtures and run `bundle exec rspec spec/conductor/agents/contract_spec.rb`.
