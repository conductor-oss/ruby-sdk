# Agents

Durable AI agents on Conductor, written in Ruby. Tools run as Conductor worker
tasks, approvals and schedules wait server-side, and an execution survives a
process restart.

Requires Ruby 3.0+ and a Conductor server with an LLM provider configured.

- [Getting started](getting-started.md)
- Concepts: [agents](concepts/agents.md), [tools](concepts/tools.md), [multi-agent](concepts/multi-agent.md),
  [guardrails](concepts/guardrails.md), [termination](concepts/termination.md), [callbacks](concepts/callbacks.md),
  [stateful](concepts/stateful.md), [streaming and approval](concepts/streaming-hitl.md),
  [structured output](concepts/structured-output.md), [runtime modes](concepts/deploy-serve-run.md),
  [scheduling](concepts/scheduling.md)
- Reference: [API map](reference/api.md), [runtime](reference/runtime.md), [client](reference/client.md),
  [agent fields](reference/agent-definition.md), [wire contract](reference/agent-schema.md)
- [Examples](../../examples/agents/)
