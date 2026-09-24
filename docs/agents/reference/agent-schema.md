# Wire contract

`ConfigSerializer.serialize(agent)` produces the `agentConfig` hash sent to the
server. It is byte-for-byte the Python SDK's output: keys are camelCase, and
`agents`, `router`, `planner`, `fallback` nest recursively.

The server schema is vendored at
[spec/fixtures/agents/agent-schema.json](../../../spec/fixtures/agents/agent-schema.json).
`spec/conductor/agents/contract_spec.rb` validates the golden configs against
it; `examples_spec.rb` compares every example to its Python-generated fixture.

Adding a field means changing the serializer, the schema, and both specs
together. The Python SDK serializer is the parity source.
