# Agent contract fixtures

`agent-schema.json` and the original `configs/` files are the vendored server schema and
Python golden contracts. `configs/103_plan_and_compile.json` adds the named planner/fallback
configuration from Python's `plan_execute` helper.

`examples/*.json` contains the configurations of the actual 19 requested Python examples at
`conductor-oss/python-sdk@c99e2cf9871c21f7a64d823126ee1b77989b00ad`, checked against their
GitHub `main` source on 2026-09-17. Each file is an array in example execution order; repeated
runs of the same agent use one configuration. `21_regex_guardrails` has two configurations.
All `model` fields (including LLM guards) are normalized to `openai/gpt-4o-mini`.

Generation used Python's `AgentConfigSerializer.serialize` on the imported example agents.
The second regex agent is constructed from its assignment in the example's main block;
`103` uses the example's factorial/write_summary/check_summary tools and planner instructions
with `plan_execute`, its fallback instructions, and fallback_max_turns=4. No Ruby serializer
output is used to produce these fixtures. To refresh, import the corresponding Python example,
serialize each agent passed to `runtime.run`/`start`, normalize models recursively, and write
sorted, indented JSON. Review the source revision and fixture changes together.

`spec/conductor/agents/examples_spec.rb` builds the actual Ruby examples, compares full configs
with these fixtures, and validates them against the schema. These are contract expectations,
not separate implementations of the examples. Runtime recordings live exclusively in the
Conductor feature-branch checkout's `llm-recordings`; see the playback workflow.
