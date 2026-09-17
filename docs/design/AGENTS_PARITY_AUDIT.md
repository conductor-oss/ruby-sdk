# Ruby agents parity audit

Audited 2026-09-17 against version 2 of the live
[Ruby Agents Parity Plan](https://orkes.atlassian.net/wiki/spaces/ENG/pages/53739522/Ruby+Agents+Parity+Plan),
Python SDK `c99e2cf9871c21f7a64d823126ee1b77989b00ad`, and Conductor
`acb7d27750e5dacc6a6334ed0bcabe3ade030533`.

All 19 requested example ports are implemented and their integration wrappers passed on a
fresh Conductor OSS playback server. The supplied shared action's script reported
**93/93 recordings played back; 0 unmatched requests**. Recordings were not changed.
The GitHub workflow is configured but has not yet been run on GitHub.

## Plan coherence

| Plan surface | Implementation and evidence |
|---|---|
| Agent, tools, tool types, schemas, approval metadata | `agent.rb`, `tool_def.rb`, `tools.rb`; serializer and DSL contracts |
| Guardrails, termination, handoffs, callbacks, memory, prompt templates | Definition classes and `runtime/system_workers.rb`; unit contracts, guardrail and team playback |
| Ruby sugar and RubyLLM adapter | `Agent` mutators, `>>`, `Tools`, schema/secret scanner and adapter unit tests |
| Serialization identical to Python | 20 golden contracts plus Python-generated configurations for all 19 runnable ports, validated against the server schema |
| Runtime, deployment, execution and approval | `AgentRuntime`, `Execution`, `ApprovalRequest`; lifecycle unit tests and real-server execution/approval tests |
| Streaming and polling fallback | `SseClient`, `StatusPoller`, `AgentClient#stream_sse`; reconnect/fallback unit tests, playback SSE events and completion |
| Worker dispatch and credentials | `ToolRegistry`, `Dispatch`, `Secrets`; inherited credentials and registration tests, independent external workers and credential-bearing HTTP playback |
| Transport and client factory | `AgentResourceApi`, `AgentClient`, `OrkesClients`; API tests and real-server calls |
| Three original Ruby recipes | `weather.rb`, `support_approval.rb`, `bug_desk.rb` remain available; their features are exercised by the numbered ports |
| Framework adapters marked N/A | Remain outside scope, as specified by the plan |
| Additional requested plan-and-compile example | `Plans#plan_execute`, named planner/fallback slots, inherited model, context, recovery turn limit; golden and real-server compiled-workflow assertions |

The live plan's diagrams are conceptual and contain names/ownership that differ from the
verified Python/server contract. These are documented mappings, not claims of literal
class-diagram identity:

- MCP discovery belongs to the server compiler. Ruby sends `ToolDef.mcp`; there is no SDK
  `McpDiscovery` class or extra discovery workflow. Example `04` verifies actual discovery.
- `ToolRegistry#tool_workers` / `#system_workers` build workers and the runtime registers
  them; these implement the diagram's `register_tool_workers` / `register_system_workers` roles.
- `Dispatch.run_tool_task` runs tool bodies; `SseClient#each_event` reads events while
  `AgentRuntime` owns fallback polling through `StatusPoller`.
- A server `waiting` event can gate a batch of tool calls. `ApprovalRequest` exposes that
  batch and schema-driven `respond`, alongside `approve` / `reject` and argument access.
- Ruby uses `done?` / `waiting?` predicate methods. Model inheritance and implicit swarm
  handoff hoisting follow Python serialization.
- Tool credential declarations use the server's `TaskDef.runtimeMetadata` shape. Provider
  credentials stay on the server; the SDK does not provision LLM integration keys.

These contract decisions are detailed in [the implementation plan](AGENTS_IMPLEMENTATION_PLAN.md),
section 2. The live Confluence page has not been edited; its diagram should adopt these
mappings before describing the implementation as literally identical to the design.

## Tests and examples

[The example guide](../../examples/agents/README.md) maps all 19 requested filenames and
provides standalone and playback commands. Integration tests import the actual files and
provide stdin/output/runtime dependencies; definitions and prompts stay only in examples.
Example `22` is expected to fail its strict guardrail, and the wrapper verifies the persisted
rejection rather than accepting arbitrary failures.

The existing WireMock replay suite remains available. New playback runs the actual server,
MCP service, HTTP dependency and worker processes, then the common action checks the whole
recording set. Unit tests independently cover SSE failures, task retries, credentials,
router errors and worker registration that the successful recordings do not exercise.

## Local verification

- Unit suite: 584 examples, zero failures (baseline: 545).
- Full suite without optional service flags: 741 examples, zero failures, 157 expected
  environment-gated pending examples. The 19 playback cases were separately enabled and passed.
- RuboCop: 211 files, zero offenses. Library load, Ruby syntax, and gem build passed.
- Ruby standard-library line coverage for loaded `lib/` files during the unit suite increased
  from 5,077/6,642 (76.44%) at HEAD to 5,154/6,700 (76.93%). Both were measured with the same
  Ruby 3.3 image and `Coverage.start(lines: true)` before loading RSpec.
