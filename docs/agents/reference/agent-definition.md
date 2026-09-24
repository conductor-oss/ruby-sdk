# Agent fields

`Agent.new(name:, model:, instructions:, tools:, agents:, strategy:, router:,
output_type:, guardrails:, memory:, termination:, handoffs:, callbacks:,
credentials:, max_turns: 25, max_tokens:, timeout_seconds:, temperature:,
stateful:, metadata:, description:, planner:, fallback:, fallback_max_turns:)`

`name` must match `^[a-zA-Z_][a-zA-Z0-9_-]*$`. A nil `model` inherits the
parent's. The serializer in `lib/conductor/agents/config_serializer.rb` is the
source of truth for what each field becomes on the wire.
