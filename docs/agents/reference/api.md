# API map

Everything lives under `Conductor::Agents` after `require 'conductor/agents'`.

| Need | Ruby | Guide |
|---|---|---|
| Define an agent | `Agent` | [agents](../concepts/agents.md) |
| Tools | `tool def`, `ToolDef.*` | [tools](../concepts/tools.md) |
| Run | `AgentRuntime`, `Conductor::Agents.runtime` | [runtime](runtime.md) |
| Control a run | `Execution`, `ApprovalRequest`, `Client::AgentClient` | [client](client.md) |
| Safety | `Guardrail`, `RegexGuardrail`, `LlmGuardrail`, `Termination::*` | [guardrails](../concepts/guardrails.md) |
| Compose | `strategy:`, `>>`, `hands_off_to`, `plan_execute` | [multi-agent](../concepts/multi-agent.md) |
| Wire format | `ConfigSerializer` | [contract](agent-schema.md) |

Signatures are documented in YARD comments under `lib/conductor/agents/`.
