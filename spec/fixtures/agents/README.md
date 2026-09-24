# Agent contract fixtures

Python-generated expectations for the Ruby `ConfigSerializer`. Nothing here is produced by Ruby.

- `agent-schema.json`: the server's agent config schema, vendored from Conductor.
- `configs/`: golden `agentConfig` outputs from the Python SDK's contract suite.
  `103_plan_and_compile.json` adds the planner/fallback config from Python's `plan_execute`.
- `examples/`: one file per ported Python example, from
  `conductor-oss/python-sdk@c99e2cf9871c21f7a64d823126ee1b77989b00ad` (checked against
  `main` on 2026-09-17). Each file is an array of configs in execution order; an agent run
  more than once appears once. All `model` fields are normalized to `openai/gpt-4o-mini`.

`spec/conductor/agents/examples_spec.rb` builds each Ruby example and compares its full
config with `examples/`. `contract_spec.rb` validates `configs/` against the schema.

To refresh `examples/`: import the Python example, serialize each agent it passes to
`runtime.run` or `start` with `AgentConfigSerializer.serialize`, normalize models
recursively, and write sorted, indented JSON. Review the source revision and the fixture
diff together.

LLM recordings for playback live in `llm-recordings/` in conductor-oss/conductor, not here.
