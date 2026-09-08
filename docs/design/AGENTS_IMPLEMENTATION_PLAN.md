# Ruby Agents Parity: Implementation Plan

Status: implemented on `feature/conductor_agents`, 2026-09-08. Owner: Ruby SDK.

## Status

| Slice | State | Notes |
|---|---|---|
| Phase 0 (toolchain, token cache, runtimeMetadata, transport) | done | plus `update-v2` in the runner and `lease_extend_enabled` (2.18) |
| Phase 1 (definition layer, serializer, contract tests) | done | 19/19 goldens identical to Python, schema-valid |
| Phase 2 (runtime, SSE, dispatch, secrets, system workers) | done | Net::HTTP SSE; polling fallback over `/agent/{id}/status` |
| Phase 3.1 (WireMock replay of `tool_happy_path`) | done | zero unmatched requests; CI job `agents-replay` |
| Phase 3.2 (record approval / secrets / team scenarios) | open | needs a server with AI enabled and provider keys |
| Phase 3.3 (mockLLM functional suite) | open | blocked on the server-side `MockLLM` provider |
| Phase 4 (examples, docs, changelog) | done | Confluence page refresh left to the owner (see 4.1) |

Decisions taken during implementation that extend section 2: 2.18 (update-v2), 2.19 (swarm
hoisting for `hands_off_to`), 2.20 (run domain applies to every worker).

Source of truth for *what* we build is the Confluence page
[Ruby Agents Parity Plan](https://orkes.atlassian.net/wiki/spaces/ENG/pages/53739522/Ruby+Agents+Parity+Plan)
and its local mirror `docs/design/AGENTS_PARITY_ONEPAGER.md`, plus the sub-specs
`AGENT_TOOLS_DSL.md`, `AGENT_STREAMING.md`, `AGENT_TEAMS.md`, `AGENT_SECRETS.md`,
`AGENT_TESTING.md`, `SDK_AGENT_TESTING_STRATEGY_V2.md`. This document is *how* and *in what
order*, reconciled against two things the design docs were written before we had verified:

- the Python SDK agents package (`python-sdk/src/conductor/ai/agents`), the parity source; and
- the server implementation (`conductor/agentspan`, branch `feature/llm_mock_impl`), the wire contract.

Section 2 lists every place the verified contract changes the design. Everything after that is
the work, split into PR-sized slices with acceptance criteria.

---

## 1. Goal and scope

Ship `Conductor::Agents` in `conductor_ruby`: define an agent in Ruby, serialize it to the same
`agentConfig` Python sends, start it on the server, run the tool workers locally, stream the
result. The three examples in the one-pager (tools, streaming + approval, team + secret) must run
unchanged against a Conductor server that has `conductor.integrations.ai.enabled=true`.

### In scope (parity surface)

| Area | Ruby API (from design docs) | Python source |
|---|---|---|
| Definition | `Agent`, `ToolDef`, `ToolType`, `Tools` DSL (`tool def`, `describe`, `requires_approval`, `[]`), `Guardrail`/`RegexGuardrail`/`LlmGuardrail`, `Termination::*`, `Handoff::*`, `CallbackHandler`, `ConversationMemory`, `PromptTemplate` | `agent.py`, `tool.py`, `guardrail.py`, `termination.py`, `handoff.py`, `callback.py`, `memory.py` |
| Serialization | `ConfigSerializer.serialize(agent)` | `config_serializer.py` |
| Transport | `AgentResourceApi`, `AgentClient`, `OrkesClients#get_agent_client`, `SseClient` | `orkes_agent_client.py` |
| Runtime | `AgentRuntime` (`call_sync`, `call_async`, `deploy`, `serve`, `shutdown`), `AgentConfig.from_env`, `Execution`, `ApprovalRequest`, `ToolRegistry`, `Dispatch`, `Secrets` | `runtime/runtime.py`, `_dispatch.py`, `tool_registry.py`, `config.py`, `result.py` |
| Sugar | `add_tool`/`add_agent`/`hands_off_to`/`redact`/`stop_when`/`stop_after`/`on_approval`, `secret()`/`secrets_env()` auto-declaration | Ruby-only |
| Tests | contract tests (schema + 19 golden configs), runtime tests (replay), CI job | `tests/unit/ai`, `examples/agents/_configs` |
| Docs | README section, `docs/agents/`, three runnable examples, CHANGELOG | `docs/agents/` |

### Out of scope for this plan (Python has them; deliberately deferred)

Framework agents (`framework`/`rawConfig`: OpenAI Agents, LangGraph, ADK, Claude Agent SDK),
skills, `claude-code` pseudo-provider, `plan_execute` strategy (planner/fallback/plannerContext),
local code execution and CLI tools, OCG retrieval agent, schedules, semantic memory,
`openai_compat.Runner`, OpenTelemetry tracing, liveness monitor / worker restarter,
`scatter_gather`, `a >> b` sequential operator, `@agent`-on-methods (`Agent.from_instance`),
`prefill_tools`, `output_type` (structured output via schema), `router` strategy with a worker
router function, `gate`, `allowed_transitions`, `masked_fields`, `introduction`,
`include_contents`, `thinking_config`, `reasoning_effort`, `context_window_budget`.

The serializer will be written so any of these can be added as one field + one test later; none
of them changes the architecture. The Confluence page already marks the frameworks row N/A.

---

## 2. Verified contract vs. design docs: what changes

Each item below is a decision. Where the design docs and the verified contract disagree, the
contract wins and the design docs get a one-line update in Phase 4.

### 2.1 `agentConfig` wire format (from Python `config_serializer.py`, server `AgentConfig.java`)

- Keys are camelCase. Every `nil` is dropped. Leaf agents omit `strategy`; it is emitted only
  when the agent has sub-agents. `external` and `maxTurns` and `timeoutSeconds` are always
  emitted. `approvalRequired`, `stateful`, `enablePlanning` are emitted only when `true`.
- **Credentials asymmetry**: agent-level credentials are top-level `"credentials": [...]`;
  tool-level credentials are nested `"config": { "credentials": [...] }`. The server reads
  `tool.config.credentials` and falls back to the agent list.
- `strategy` values on the wire are lowercase snake_case: `handoff sequential parallel router
  round_robin random swarm manual plan_execute`. Default `handoff`.
- Termination: `{"type": "text_mention"|"stop_message"|"max_message"|"token_usage"|"and"|"or", ...}`.
  Handoffs: `{"target", "type": "on_tool_result"|"on_text_mention"|"on_condition", ...}`.
  Guardrails: `{"name","position","onFail","maxRetries","guardrailType": "regex"|"llm"|"custom"|"external", ...}`.
  Callbacks: `[{"position": "before_model", "taskName": "<agent>_before_model"}]`.
  Memory: `{"messages": [...], "maxMessages": n}`. Prompt template instructions:
  `{"type": "prompt_template", "name", "variables", "version"}`.
- Agent name regex `^[a-zA-Z_][a-zA-Z0-9_-]*$`, `maxTurns >= 1`, duplicate sub-agent names rejected.
- There is **no server-side JSON schema** for `agentConfig`. Python's
  `docs/agents/reference/agent-schema.json` (Draft 2020-12, `additionalProperties: false` at the
  root) is the contract artifact. We vendor it and the 19 golden configs from
  `python-sdk/examples/agents/_configs/`.

### 2.2 Server requires `model` on every agent, including team parents

`ModelParser.parse` runs unconditionally on every compile path and raises on a missing or
slash-less model. The one-pager's `team = Agent.new(name: 'bug_desk')` would be rejected.
Python only auto-inherits for `parallel`.

**Decision D1**: `ConfigSerializer` fills a missing parent `model` from the first sub-agent that
has one, for every multi-agent strategy. A leaf agent with no model raises
`Conductor::Agents::ConfigurationError` at serialize time (unless `external: true`). The
examples stay as written.

### 2.3 Approval is a `waiting` event plus a `respond` call; `ApprovalRequest` is Ruby-only

Python has no `ApprovalRequest` and no `on_approval`. On the server, `approvalRequired: true`
on any tool inserts a `HUMAN` task (`<agent>_approval_human`, status `IN_PROGRESS`). The SDK
sees SSE `waiting` with `pendingTool = {taskRefName, toolCalls: [{name, args}], response_schema,
...}`. One HUMAN task gates the whole batch of tool calls, so `tool_name`/`parameters` in
`pendingTool` are `null` and `toolCalls` is populated. The reply is
`POST /api/agent/{executionId}/respond` with `{"approved": true}` or
`{"approved": false, "reason": "..."}`. A rejection ends the execution **COMPLETED** with
`output.finishReason == "rejected"` and `output.rejectionReason` set.

**Decision D2**: `ApprovalRequest` wraps one `waiting` event. It exposes `execution_id`,
`task_ref_name`, `tool_calls` (array of `ToolCall(name:, arguments:)`), and, as sugar, `tool_name`
and argument accessors (`request.amount`) taken from the first tool call. `approve` and
`reject(reason)` post to `respond`. If no `on_approval` block is registered the request is
parked on `execution.pending` and nothing is sent. `finish_reason` becomes `:rejected` from
`output.finishReason`.

### 2.4 Tool task input carries server-injected keys at the top level

`inputData` for a worker tool is the LLM's arguments flattened at the top level **plus**
`method` (tool name, always), `_agent_state`, `_agent_tool_name`, and `_allowed_commands` for
`cli` tools. Verified in `conductor-mocks/mocks/agent/tool_happy_path/mappings/04_*.json`.

**Decision D7**: `Dispatch#coerce_args` strips those four keys before binding keyword arguments,
rejects missing required arguments with `FAILED_WITH_TERMINAL_ERROR` (not a Ruby
`ArgumentError` mid-call; see 2.9 on `city: String` defaults), coerces `String -> Integer/Float/
Boolean` and `String <-> JSON` for array/object params, returns a Hash as-is and wraps any other
result as `{"result" => value}`. A `_state_updates` key in the result passes through (server
merges it into `_agent_state`). Non-JSON-serializable results fail the task with a clear reason.

### 2.5 `requiredWorkers` and system workers

`POST /agent/start` returns `{executionId, agentName, requiredWorkers: [String]}`. The list is
flat task names: every `toolType: worker` tool **by its own name, no prefix**, plus
compiler-generated SIMPLE tasks the SDK must serve: `<agent>_termination` whenever
`termination` is set, custom guardrail `taskName`s, callback `<agent>_<position>` tasks,
`on_condition` handoff `taskName`s, `stopWhen.taskName`. `<team>_handoff_check`,
`<agent>_check_transfer` and `<team>_transfer_to_<agent>` are compiled INLINE on this server and
are **not** in the list (Python still registers them for older servers; we do not).

**Decision**: `ToolRegistry#register_system_workers(required_workers)` serves exactly the
compiler-generated names it recognises by suffix, with Ruby ports of Python's
`TerminationEntry` (`{should_continue, reason}`), `GuardrailEntry` (`{passed, message, on_fail,
fixed_output, guardrail_name, should_continue}`), `CallbackEntry`, and the `on_condition`
handoff worker. An unrecognised name logs a warning listing it, because a task with no worker
sits SCHEDULED forever. Since `stop_when`/`stop_after` serialize to `termination`, the
termination worker is needed for the team example and is Phase 2, not later.

### 2.6 SSE framing and reconnect (server `AgentStreamRegistry`)

`GET /api/agent/stream/{executionId}`, `Accept: text/event-stream`. Server writes `:connected`
first, then `id:<n>\nevent:<type>\ndata:<json>\n\n`, ids start at 1 per execution, a
`:heartbeat` comment every 15 s, emitter never times out, stream is closed after `done` or
`error`. Replay buffer of 200 events for 5 minutes after completion. `Last-Event-ID` is an HTTP
request header bound to a Java `Long`: send a bare integer; when absent the server replays from
0, so connecting after start loses nothing. Child sub-workflow events are aliased onto the
parent stream. Event types: `thinking tool_call tool_result handoff waiting guardrail_pass
guardrail_fail error done` plus `context_condensed subagent_start subagent_stop`. `done.output`
is the workflow output `{result, finishReason, context, rejectionReason}`.

**Decision D3**: `SseClient` reconnects with `Last-Event-ID` after any drop with a fixed 1 s
backoff, raises `SseUnavailableError` if the first connect fails, and the runtime falls back to
polling `GET /agent/{id}/status` (fields `isComplete`, `isWaiting`, `output`, `pendingTool`,
`reasonForIncompletion`) every 0.5 s. This is simpler than Python's task-graph synthesis and
loses only `partial_text` in fallback mode. `partial_text` is the concatenation of `thinking` and
`message` `content` fields; there is no separate delta event.

### 2.7 SSE cannot go through the existing `RestClient`

`RestClient` has a 120 s total timeout, retry middleware, and buffers bodies. `SseClient` opens
its own long-lived connection: plain `Net::HTTP` with `read_body` streaming (no adapter
uncertainty, no new gem), read timeout disabled, headers from `ApiClient#get_authentication_headers`
so token refresh stays in one place. Faraday `on_data` through `faraday-net_http_persistent 2.3.1`
is the alternative; spike both in Phase 2 slice 1 and keep whichever streams the recorded
scenario end to end.

### 2.8 Secrets ride on `runtimeMetadata`; both Ruby models lack the field

`TaskDef.runtimeMetadata` is `List<String>` (names). `Task.runtimeMetadata` is
`Map<String,String>` (values), filled at poll time by `RuntimeMetadataResolver` (secret store,
then server env with `CONDUCTOR_SECRET_` / `CONDUCTOR_ENV_` prefixes), silently omitted on miss,
never persisted. Needs conductor-oss with PR #1255 (3.32.0-rc.8+). Neither field exists in
`lib/conductor/http/models/task.rb` or `task_def.rb` today.

**Decision D5**: add both fields. `Secrets.secret(name)` reads
`TaskContext.current.task.runtime_metadata[name]`, then `ENV[name]`, then raises
`CredentialNotFoundError`. `TaskContext` is stored in `Thread.current[]`, which is fiber-local in
Ruby, so this already satisfies the "fiber-local, never writes ENV" rule with no new binding
mechanism. `secrets_env(*names)` returns a Hash for `system`/`spawn`/`Open3`.

### 2.9 `tool def` type inference needs the AST, and so does secret scanning

`Method#parameters` returns kinds and names only, never default values, so `city: String` vs
`units: 'metric'` is indistinguishable by reflection. Both type inference and `secret('...')`
scanning therefore use `RubyVM::AbstractSyntaxTree.of(method)` (MRI 2.6+, works when the source
file is on disk; in irb/`eval` needs `RubyVM.keep_script_lines = true`, Ruby 3.2+). Prism ships
only with Ruby 3.3, and the gem targets Ruby >= 3.0, so no parser dependency.

**Decision D9**: `Tools#get_json_schema_def` maps `String/Integer/Float/Hash` class defaults to
required typed properties, literal defaults to optional properties with `default`, `[String]` to
`array` with `items`, `%w[a b]` to `enum` (optional, default first), `true/false` to boolean.
When the AST is unavailable the fallback is Python's behaviour: every keyword param gets `{}`
and `:keyreq` params are required; secret declaration then needs the explicit
`add_tool ..., credentials:`. Positional parameters raise at `tool def`. A one-line spike
proving `AbstractSyntaxTree.of` works for a top-level `def` and for a method in a module is the
first task of Phase 1.

Runtime consequence: because `city: String` has the class as its Ruby default, the worker must
never call the method with a required argument missing (it would receive the `String` class).
That is why D7 validates required arguments before the call.

### 2.10 Tool task definitions

Python registers each tool with `retryCount 2, retryDelaySeconds 2, retryLogic LINEAR_BACKOFF,
timeoutSeconds 0, responseTimeoutSeconds 10, timeoutPolicy RETRY, runtimeMetadata [names]`,
`overwrite_task_def: true`, `worker_id "agent-sdk"`. The server also registers a TaskDef for
every required worker (with `responseTimeoutSeconds 3600`); ours overwrites it, exactly as the
recorded scenario shows (`02_put_api_metadata_taskdefs.json`).

**Decision D6**: same defaults, via `Worker.define(name, register_task_def: true,
overwrite_task_def: true, task_def_template: TaskDef.new(...))`. `TaskDefinitionRegistrar#
build_task_definition` already honours `task_def_template`; it must stop overriding
`timeout_seconds`/`response_timeout_seconds` when the template sets them (it currently uses
`||=`, which is fine for non-nil values but `timeout_seconds: 0` is truthy in Ruby, so no change
needed; add a test).

### 2.11 MCP discovery is server-side; drop `McpDiscovery`

The compiler emits `LIST_MCP_TOOLS` and an LLM filter chain before the agent loop for every
`toolType: mcp` tool, and dispatches `CALL_MCP_TOOL` at runtime. Python's `mcp_discovery.py`
served its now-legacy local-compile path. **Decision D4**: no `McpDiscovery` class; `ToolDef.mcp`
serializes `{server_url, headers, tool_names, max_tools}` and nothing else happens client-side.
The one-pager's runtime diagram loses one box.

### 2.12 Stateful runs, domains, sessions

`AgentStartRequest.runId` makes the server map every required worker to that task domain. Python
sends `runId = uuid4().hex` only when the agent or any tool is `stateful`, then polls with
`domain == run_id`. `sessionId` is passed straight through. **Decision**: same. `Agent#stateful`
and `ToolDef#stateful` exist from Phase 1; domain wiring is a Phase 2 task with one test.

### 2.13 Finish reasons and statuses

Server `finishReason` is uppercase (`STOP TOOL_CALLS MAX_TOKENS CONTENT_FILTER LENGTH`) except
the literal `"rejected"`. Execution status is the Conductor workflow status (`RUNNING COMPLETED
FAILED TIMED_OUT TERMINATED PAUSED`); `executionId == workflowId`. **Decision D8**:
`Execution#finish_reason` is `:stop | :tool_calls | :length | :content_filter | :rejected |
:error | :cancelled | :timeout`, derived the way Python's `_derive_finish_reason` does.

### 2.14 `redact` needs verification

`redact` is specified as `RegexGuardrail(position: :output, on_fail: :fix)`. Whether
`GuardrailCompiler` rewrites matched text for a regex guardrail with `onFail: fix` was not
confirmed. Phase 1 serializes it as specified; Phase 3's replay scenario for the team example
verifies behaviour, and if the server does not rewrite, `redact` switches to `on_fail: :retry`
and the doc is updated.

### 2.15 Testing infrastructure reality

`SDK_AGENT_TESTING_STRATEGY_V2.md` (in-server `mockLLM` provider, record mode) is **not
implemented on the server yet**: only fixture primitives exist on `feature/llm_mock_impl`
(`ai/.../testing/LlmFixture*.java`, `llm-fixture.schema.json`); no `MockLLM` provider, no
`conductor.ai.mock-llm.record` property, no test-server task. What exists today is
`conductor-mocks` with one normalized WireMock scenario, `agent/tool_happy_path`, recorded
against a real server for this SDK.

**Decision**: contract tests need no server and land first. Runtime tests use WireMock replay of
`tool_happy_path` now (it is the only recording, and it covers start, TaskDef PUT, poll with
`runtimeMetadata: []`, update-v2, SSE). Approval, secrets and team scenarios are recorded into
`conductor-mocks` as they become runnable. The mockLLM functional suite is a Phase 3 follow-up
gated on the server; the spec helper is written so `mocks:` (WireMock) and `model:
'mockLLM/<scenario>'` (real server) coexist.

### 2.16 Prerequisite already called out in the design: instance-level token cache

`Configuration` keeps `auth_token`/`token_update_time` as class-level state. Two runtimes with
different credentials in one process (tests, multi-tenant workers) would share one token. Only
`ApiClient` reads it. Move to instance level; keep the class accessors as deprecated shims for
one release.

### 2.17 Local toolchain

Ruby is not installed on this machine (`ruby: command not found`; no rbenv/rvm/mise). Docker and
podman are. Either install Ruby 3.3 or run the suite in `ruby:3.3-alpine` (the repo's
`Dockerfile` base). This is the first checklist item in Phase 0.

### 2.18 Task result updates go to update-v2 (added during implementation)

The recorded scenario shows the tool result posted to `POST /api/tasks/update-v2` with
`extendLease: false`; the Ruby runner posted to `POST /api/tasks`. The Python runner uses
update-v2 by default and falls back to `/tasks` once on 404/405. **Decision**: same in
`TaskRunner#send_task_update`; `Worker` gains `lease_extend_enabled` (tool workers set it, like
Python) so lease extension can follow later.

### 2.19 `hands_off_to` on a member makes the team a swarm (added during implementation)

The design puts handoffs on the member (`triage.hands_off_to filer`), but the server reads
`handoffs` on the coordinator and only acts on them under `strategy: swarm`; a member's
handoffs under the default `handoff` strategy would be ignored. **Decision D10**: when members
declare handoffs and the team has no explicit strategy, `ConfigSerializer` emits
`strategy: swarm` and hoists the members' handoffs onto the team. An explicit strategy is
never overridden. Python-style teams (handoffs on the parent, `strategy: :swarm`) serialize
unchanged; goldens 13 and 17 prove it.

### 2.20 The run domain applies to every worker (added during implementation)

When a start request carries `runId`, the server maps every name in `requiredWorkers` to that
task domain, not just stateful tools. **Decision**: `ToolRegistry` gives all workers of a
stateful run the run domain; the plan's per-tool rule was wrong.

---

## 3. Target layout

```
lib/conductor/agents.rb                      # require 'conductor/agents'; requires everything below
lib/conductor/agents/
  version.rb?                                # no: reuse Conductor::VERSION
  errors.rb                                  # ConfigurationError, CredentialNotFoundError, AgentApiError,
                                             # AgentNotFoundError, SseUnavailableError, ToolSerializationError
  agent.rb                                   # Agent (definition + sugar + call_sync/call_async delegating to runtime)
  tool_def.rb                                # ToolDef, ToolType, PrefillToolCall (minimal), factories http/mcp/human/agent
  tools.rb                                   # Tools module: tool, describe, requires_approval, [], schema + secret scan
  tools/schema_builder.rb                    # AST -> JSON schema (D9)
  tools/secret_scanner.rb                    # AST -> literal secret()/secrets_env() names
  tools/ruby_llm_adapter.rb                  # RubyLLM::Tool class -> ToolDef (only if defined?(RubyLLM))
  guardrail.rb                               # Guardrail, RegexGuardrail, LlmGuardrail, GuardrailResult
  termination.rb                             # Termination::Condition, TextMention, StopMessage, MaxMessage, TokenUsage, And, Or
  handoff.rb                                 # Handoff::Condition, OnToolResult, OnTextMention, OnCondition
  callback_handler.rb                        # CallbackHandler + POSITION_TO_METHOD
  memory.rb                                  # ConversationMemory
  prompt_template.rb                         # PromptTemplate
  config_serializer.rb                       # ConfigSerializer.serialize(agent) -> Hash (camelCase)
  runtime/agent_config.rb                    # AgentConfig.from_env
  runtime/agent_runtime.rb                   # AgentRuntime: call_sync/call_async/deploy/serve/shutdown
  runtime/execution.rb                       # Execution, ToolCall, TokenUsage
  runtime/approval_request.rb                # ApprovalRequest
  runtime/sse_client.rb                      # SseClient: each_event(execution_id, last_event_id:), reconnect
  runtime/status_poller.rb                   # polling fallback over /agent/{id}/status
  runtime/tool_registry.rb                   # ToolRegistry: register_tool_workers, register_system_workers
  runtime/dispatch.rb                        # Dispatch.run_tool_task, coerce_args
  runtime/system_workers.rb                  # termination / guardrail / callback / handoff worker bodies
  runtime/secrets.rb                         # Secrets.secret, secrets_env
lib/conductor/http/api/agent_resource_api.rb # AgentResourceApi
lib/conductor/client/agent_client.rb         # AgentClient (Hash in / Hash out, like Python)
lib/conductor/orkes/orkes_clients.rb         # + get_agent_client
lib/conductor/http/models/task.rb            # + runtime_metadata (Hash<String,String>)
lib/conductor/http/models/task_def.rb        # + runtime_metadata (Array<String>)
spec/conductor/agents/**                     # unit + contract specs (no server)
spec/agents/**                               # runtime specs (WireMock replay / real server), tagged
spec/fixtures/agents/agent-schema.json       # vendored from python-sdk docs/agents/reference
spec/fixtures/agents/configs/*.json          # 19 golden configs vendored from python-sdk examples/agents/_configs
examples/agents/{weather,support_approval,bug_desk}.rb
examples/agents/dump_agent_configs.rb        # regenerates goldens from Ruby for cross-SDK diff
docs/agents/README.md + concepts/*.md
```

Namespacing: definition classes live directly under `Conductor::Agents` so `include
Conductor::Agents` gives `Agent`, `RegexGuardrail`, `Termination`, `Handoff`, and the `tool`,
`describe`, `requires_approval`, `secret`, `secrets_env` methods. `Tools` is included into
`Conductor::Agents` so top-level `include Conductor::Agents` works; `extend
Conductor::Agents::Tools` on a module works because `tool` resolves `method(name)` first and
falls back to `instance_method(name)` + `module_function name`.

---

## 4. Work breakdown

Each slice is one reviewable PR. Every PR: `bundle exec rubocop`, `bundle exec rspec
spec/conductor/`, coverage not lower than before, `bundle exec ruby -Ilib -e "require
'conductor/agents'"` loads. Sizes: S < 1 day, M 1-3 days, L 3-5 days.

### Phase 0: prerequisites (no agent code yet)

**PR 0.1 Toolchain + hygiene (S)**
- Install Ruby 3.3 locally or document `docker run --rm -v $PWD:/app -w /app ruby:3.3 bundle exec rspec`.
- Remove unused `vcr` dev dependency (called out in `AGENT_TESTING.md`); keep `webmock`.
- Add `json_schemer` as a development dependency for contract tests.
- Acceptance: `bundle exec rspec spec/conductor/` green locally.

**PR 0.2 Instance-level auth token cache (S)** (2.16)
- `Configuration`: `@auth_token`, `@token_update_time` per instance; `update_token`,
  `auth_token`, `token_update_time` read instance state. Class-level accessors remain, emit a
  deprecation warning once, and read/write a process-wide fallback only when the instance has none.
- `ApiClient` unchanged in behaviour; add a spec that two configurations hold two tokens.
- Acceptance: all existing specs pass; new spec proves isolation.

**PR 0.3 `runtimeMetadata` on models + registrar (S)** (2.8, 2.10)
- `Task`: `runtime_metadata: 'Hash<String, String>'` / `:runtimeMetadata`, default `{}`.
- `TaskDef`: `runtime_metadata: 'Array<String>'` / `:runtimeMetadata`, default `[]`.
- `TaskDefinitionRegistrar`: test that `task_def_template` with `timeout_seconds: 0`,
  `response_timeout_seconds: 10`, `runtime_metadata: ['GH_TOKEN']` survives `build_task_definition`.
- Acceptance: model round-trip specs; recorded `04_*` poll body deserializes `runtimeMetadata`.

**PR 0.4 Agent transport (M)** (server §2 of the API report)
- `Http::Api::AgentResourceApi` over `ApiClient#call_api`, `return_type: 'Hash<String, Object>'`:
  - `start(body)` POST `/agent/start`; `deploy(body)` POST `/agent/deploy`; `compile(body)` POST `/agent/compile`
  - `status(id)` GET `/agent/{executionId}/status`; `execution(id)` GET `/agent/execution/{executionId}`
  - `executions(params)` GET `/agent/executions` (`start,size,sort,freeText,status,agentName,sessionId`)
  - `respond(id, body)` POST `/agent/{executionId}/respond`; `stop(id)`; `signal(id, message)`
  - `pause(id)` PUT `/agent/{executionId}/pause`; `resume(id)` PUT; `cancel(id, reason:)` DELETE `/agent/{executionId}/cancel`
  - `list` GET `/agent/list`; `get(name, version:)` GET `/agent/{name}`; `delete(name, version:)`
- `Client::AgentClient` wrapping it with Python's method names (`start_agent`, `deploy_agent`,
  `compile_agent`, `get_status`, `get_execution`, `list_executions`, `respond`, `approve`,
  `reject`, `send_message`, `stop`, `signal`, `pause`, `resume`, `cancel`). Map 404 to
  `AgentNotFoundError`, other `ApiError` to `AgentApiError` carrying the `{error, status}` body.
- `OrkesClients#get_agent_client`.
- Specs mirror `spec/conductor/client/prompt_client_spec.rb` (instance doubles) plus WebMock
  specs asserting exact paths and bodies for start/respond/status.
- Acceptance: every endpoint in the table has a spec asserting method + path + body keys.

### Phase 1: definition layer and serializer (no server)

**PR 1.1 Spike: AST availability (S, half day, can be a scratch script)** (2.9)
- Prove `RubyVM::AbstractSyntaxTree.of(method)` returns `KW_ARG` defaults and `secret('X')`
  call nodes for: a top-level `tool def` in a file, a method in a module with `extend Tools`, a
  method defined in irb with `keep_script_lines`. Record the matrix in `tools/schema_builder.rb`
  comments. If the top-level-in-file case fails on any supported Ruby (3.0-3.3), the fallback in
  D9 becomes the primary path and the DSL doc changes before any more code is written.

**PR 1.2 ToolDef, ToolType, factories (M)**
- `ToolType` constants: `worker http api mcp human agent_tool generate_image generate_audio
  generate_video generate_pdf rag_index rag_search pull_workflow_messages cli`.
- `ToolDef` fields and defaults exactly as Python: `name, description '', input_schema {},
  output_schema {}, func nil, approval_required false, timeout_seconds nil, tool_type 'worker',
  config {}, guardrails [], credentials [], stateful false, max_calls nil, retry_count 2,
  retry_delay_seconds 2, retry_policy 'linear_backoff'`.
- Factories from the one-pager: `ToolDef.http(name, url, method: 'GET', description:, headers:,
  input_schema:, credentials:)`, `ToolDef.mcp(server_url, name: 'mcp_tools', headers:,
  tool_names:, max_tools: 64, credentials:)`, `ToolDef.human(name, description:, input_schema:)`,
  `ToolDef.agent(agent, name:, description:, retry_count:, retry_delay_seconds:, optional:)`.
  `${NAME}` header placeholders must appear in `credentials` or raise. Media/RAG/api factories
  are one method each and can ride along if cheap; not required by the examples.
- Specs: config keys per type match Python's `_serialize_tool` (`url method headers accept
  contentType`; `server_url headers tool_names max_tools`; `agent` replaced by `agentConfig`).

**PR 1.3 Tools DSL: `tool def`, `describe`, `requires_approval`, `[]`, schema, secret scan (L)**
- `tool(name)`: resolves the method, builds `ToolDef(name:, description: humanize(name),
  input_schema: SchemaBuilder.for(method), credentials: SecretScanner.scan(method), func: ->(**kw) {...})`,
  registers it in a per-`self` registry (`Tools#[]`), returns the ToolDef. Positional params raise.
- `describe(name, text)`, `requires_approval(name)` mutate the registered ToolDef.
- `SchemaBuilder` implements the D9 table; `required` only when non-empty; no `$schema` key
  (Python emits a bare `{"type":"object","properties":{...},"required":[...]}`).
- `SecretScanner` collects string-literal first arguments of `secret(...)` and every
  string-literal argument of `secrets_env(...)`; ignores dynamic names.
- `RubyLlmAdapter`: when `defined?(RubyLLM::Tool)` and `add_tool` receives such a class, build a
  `ToolDef` from `.name`, `.description`, `.parameters`-derived schema, `func: ->(**kw) {
  klass.new.execute(**kw) }`.
- Specs: one per row of the type table; secret scan positive/negative/dynamic; module-extend
  form; RubyLLM adapter behind a stub class.

**PR 1.4 Guardrails, termination, handoffs, callbacks, memory, prompt template (M)**
- Straight ports with Ruby naming. Validation rules from Python: guardrail `position` in
  `input|output`, `on_fail` in `retry|raise|fix|human`, `human` illegal on `input`,
  `max_retries >= 1`; `MaxMessage >= 1`; `TokenUsage` needs at least one limit; `&`/`|`
  flatten same-type children; `RegexGuardrail(patterns, mode: :block|:allow, message:)`;
  `LlmGuardrail(model, policy, max_tokens:)`; `Guardrail.new(name:)` with no block is external.
- `ConversationMemory` with `add_user_message` etc. and `_trim` semantics (keep system messages).
- Specs per class including combinator flattening.

**PR 1.5 Agent (M)** (2.1, 2.2, 2.12)
- Constructor keywords: `name:, model: nil, instructions: '', tools: [], agents: [], strategy:
  :handoff, router: nil, output_type: nil, guardrails: [], memory: nil, termination: nil,
  handoffs: [], callbacks: [], credentials: [], max_turns: 25, max_tokens: nil,
  timeout_seconds: 0, temperature: nil, stateful: false, metadata: nil, description: nil,
  external: false`.
- Validation: name regex, strategy enum (symbols, serialized lowercase), `max_turns >= 1`,
  duplicate sub-agent names, `router` required for `:router`.
- Sugar: `add_tool(tool, credentials: nil)` accepts `Symbol` (looks up `Tools` registry of the
  caller and of `Conductor::Agents`), `ToolDef`, a `Tools`-extended module (adds all), a
  RubyLLM class; `add_tools(*)`, `add_agent(s)`, `hands_off_to(agent, on:)` ->
  `Handoff::OnTextMention`, `redact(words)` -> `RegexGuardrail(position: :output, on_fail: :fix,
  mode: :block, name: "#{name}_redact")`, `stop_when(text)` -> `Termination::TextMention`,
  `stop_after(messages:)` -> `Termination::MaxMessage` (combined with `|` when both set),
  `on_approval(&block)`, `strategy=`.
- `call_sync(prompt, session_id: nil)` and `call_async(prompt, session_id: nil, &on_done)`
  delegate to `Conductor::Agents.runtime` (Phase 2); until then they raise `NotImplementedError`
  with a pointer.
- Specs: validation matrix; sugar produces the parity objects listed in `AGENT_TEAMS.md`.

**PR 1.6 ConfigSerializer + contract tests (L)** (2.1, 2.2)
- Emission order and conditions per Python's `serialize`, `_serialize_tool`,
  `_serialize_guardrail`, `_serialize_termination`, `_serialize_handoff`, `_serialize_memory`,
  plus D1 (parent model inheritance) and the `ConfigurationError` for model-less leaves.
- Callbacks serialize to `{position, taskName: "#{name}_#{position}"}` for every
  `CallbackHandler` method a handler overrides.
- Vendor `spec/fixtures/agents/agent-schema.json` and the 19 `configs/*.json`. Port
  `dump_agent_configs.py` to `examples/agents/dump_agent_configs.rb` so the Ruby definitions of
  the same 19 agents live in the repo; the spec compares `serialize(agent)` to each golden file
  (`sort_keys`-insensitive Hash equality, model string parametrised by env like Python's dump
  script). Validate every serialized config against the schema; assert an unknown root key fails.
- Acceptance: 19/19 golden matches, schema valid, and `examples/agents/dump_agent_configs.rb`
  regenerates byte-identical JSON (sorted keys, 2-space indent) for cross-SDK diffs.

### Phase 2: runtime and transport

**PR 2.1 Spike + SseClient (M)** (2.6, 2.7)
- Implement over `Net::HTTP` streaming first; if `Faraday` `on_data` via the persistent adapter
  streams the recorded `06_get_api_agent_stream_exec_1.json` body (WireMock dribbles it over ~3 s)
  with less code, switch. Parser handles `:` comments (heartbeat), `id:`, `event:`, `data:`
  (multi-line joined by `\n`), blank-line boundaries, JSON parse failure -> `{"content" => raw}`.
- `each_event(execution_id, last_event_id: nil)` is an Enumerator that stops after `done`/`error`,
  reconnects with `Last-Event-ID: <integer>` after a drop, raises `SseUnavailableError` on
  first-connect failure or 15 s of heartbeat-only silence before the first real event.
- Specs with WebMock streaming bodies (WebMock can serve a String body; chunk pacing is not
  needed for parsing tests) covering comments, multi-line data, reconnect id, terminal events.

**PR 2.2 Secrets + Dispatch (M)** (2.4, 2.8)
- `Secrets.secret(name)` / `secrets_env(*names)` per D5; `CredentialNotFoundError` message names
  the tool and the missing key.
- `Dispatch.run_tool_task(task, tool_def)` per D7; returns a `TaskResult`, sets `worker_id
  'agent-sdk'`, `FAILED` with `reason_for_incompletion` on exceptions, `FAILED_WITH_TERMINAL_ERROR`
  on missing required args, missing credentials, or `ToolSerializationError`. Circuit breaker
  (10 consecutive failures per tool) is optional; include only if trivial.
- Specs: strips injected keys (uses the recorded `04_*` input verbatim), coercions, missing
  required arg, Hash vs scalar result, `_state_updates` passthrough, secret from
  `runtime_metadata` vs ENV vs missing, `secrets_env` returns only requested names.

**PR 2.3 ToolRegistry + system workers (M)** (2.5, 2.10)
- `register_tool_workers(tools, agent_name, domain)` builds one `Worker.define` per `worker`/`cli`
  tool with the D6 TaskDef template and `Dispatch` body; server-side tool types are skipped.
- `register_system_workers(required_workers, agent)` matches `<agent>_termination`,
  `<agent>_<position>` callbacks, custom guardrail names, `on_condition` handoff task names;
  bodies in `system_workers.rb` are ports of Python's `TerminationEntry`, `GuardrailEntry`,
  `CallbackEntry`, `HandoffCondition`. Unknown names warn.
- Workers run on a dedicated `TaskHandler` owned by the runtime with `poll_interval` /
  `thread_count` from `AgentConfig`, `register_task_definitions: true`.
- Specs: worker set for the three examples; TaskDef body equals the recorded `02_*` PUT body
  (with `runtimeMetadata: []`); termination worker returns `should_continue: false` on
  `TextMention` match; unknown required worker logs.

**PR 2.4 AgentRuntime, Execution, ApprovalRequest (L)** (2.3, 2.6, 2.12, 2.13)
- `AgentConfig.from_env`: `CONDUCTOR_AGENT_WORKER_POLL_INTERVAL` (100 ms),
  `CONDUCTOR_AGENT_WORKER_THREADS` (1), `CONDUCTOR_AGENT_INTEGRATIONS_AUTO_REGISTER` (false),
  `CONDUCTOR_AGENT_STREAMING_ENABLED` (true); Python boolean parsing (`true/1/yes/on`).
- `AgentRuntime#call_async(agent, prompt, session_id:, &on_done)`: serialize; `run_id =
  SecureRandom.hex` when stateful; `POST /agent/start` with `{agentConfig, prompt, sessionId,
  runId?}`; register tool + system workers from `requiredWorkers` under `domain = run_id`; start
  the handler; create `Execution`; spawn the stream thread (`SseClient`, falling back to
  `StatusPoller` on `SseUnavailableError` or when streaming is disabled); return immediately.
  `call_sync` is `call_async(...).result`.
- Stream thread: `thinking`/`message` append `partial_text`; `tool_call`/`tool_result` pair into
  `execution.tool_calls`; `waiting` with `pendingTool.toolCalls` builds an `ApprovalRequest` and
  invokes `agent.on_approval` (else parks it on `execution.pending`); `done` sets `result =
  output['result']`, `finish_reason` per D8, fetches `tokenUsage` from `GET /agent/execution/{id}`
  (recursing `tasks[].subWorkflowId`), marks done, fires `on_done`; `error` sets `:error`. All
  callbacks are wrapped so a user exception never kills the stream thread.
- `Execution`: `execution_id, done?, waiting?, result (blocks with optional timeout),
  partial_text, finish_reason, tool_calls, token_usage, pending, pause, resume, cancel(reason:),
  stop, signal(text)`; `Execution.find(id)` builds from `get_status` + `get_execution`.
- `deploy(*agents)` -> `POST /agent/deploy` each, returns agent names; `serve(*agents)` deploys,
  registers workers, blocks until `INT`/`TERM`, then `shutdown`; `shutdown` stops the handler and
  stream threads.
- `Conductor::Agents.runtime` memoised default (`Configuration.new` from env),
  `Conductor::Agents.configure(configuration:, agent_config:)`.
- Specs (WebMock, no WireMock): start body equals `serialize(agent)` + prompt; workers
  registered for `requiredWorkers`; approval approve/reject post the exact bodies; rejection ->
  `:rejected`; fallback poller path; `on_done` fires once; user exception in `on_approval` is
  logged not raised.

### Phase 3: end-to-end tests and CI

**PR 3.1 WireMock replay of `agent/tool_happy_path` (M)** (2.15)
- `spec/agents/agents_helper.rb`: `mocks: 'agent/tool_happy_path'` metadata boots
  `wiremock/wiremock:3x` with the scenario dir mounted (Docker via `docker`/`podman` CLI; skip
  with a clear message when neither exists or `CONDUCTOR_MOCKS_DIR` is unset), points
  `CONDUCTOR_SERVER_URL` at it, asserts `GET /__admin/requests/unmatched` is empty in `after`.
- The weather spec from `AGENT_TESTING.md` passes end to end: start, TaskDef PUT, poll, tool
  runs in-process, update-v2, SSE `done`, `call_sync` returns the recorded text.
- CI: new `agents-replay` job that checks out `conductor-oss/conductor-mocks` and runs
  `bundle exec rspec spec/agents`. Runs on every PR including forks (no secrets).

**PR 3.2 Record the remaining scenarios (M, blocked on a server with AI enabled and keys)**
- `approval_approve`, `approval_reject`, `secrets_runtime_metadata`, `team_handoff` using the
  three examples, recorded with WireMock's snapshot recorder and `scripts/normalize.py` per the
  `conductor-mocks` README; PRs to `conductor-mocks`; specs here tagged with each scenario.
  `team_handoff` also settles 2.14 (`redact` semantics).

**PR 3.3 mockLLM functional suite (L, blocked on server)**
- When `MockLLM` lands in conductor-oss: `spec/agents/functional/*_spec.rb` for the six-scenario
  catalog in `SDK_AGENT_TESTING_STRATEGY_V2.md`, asserting persisted LLM task input and tool
  tasks via `WorkflowClient#get_workflow`, plus a CI job that builds the pinned server. Not a
  blocker for releasing the feature; replay covers the wire contract until then.

### Phase 4: docs, examples, release

**PR 4.1 Examples + docs (M)**
- `examples/agents/weather.rb`, `support_approval.rb`, `bug_desk.rb` exactly as in the one-pager,
  plus `dump_agent_configs.rb` from Phase 1.
- `docs/agents/README.md` and `concepts/{tools,streaming-hitl,teams,secrets}.md` adapted from the
  four design sub-specs; README gets an "Agents" section after "LLM/AI Tasks"; `AGENTS.md` and
  `DESIGN.md` get the new layer in the architecture diagrams and directory listing.
- Update the design docs for the decisions in section 2 (D1 model inheritance, D2 approval batch
  semantics, D4 no `McpDiscovery`, D9 AST fallback, 2.15 testing reality) and refresh the
  Confluence page from the one-pager (read the live page immediately before writing; it is
  edited concurrently).
- `CHANGELOG.md` Unreleased: Added `Conductor::Agents`, `AgentClient`, `runtimeMetadata`
  fields; Changed instance-level token cache; Removed `vcr`.

**PR 4.2 Release (S)**
- Version bump (minor), gem build, tag. `conductor/agents` stays an explicit require; `require
  'conductor'` does not load it.

---

## 5. Sequencing and parallelism

```
0.1 -> 0.2 -> 0.3 -> 0.4 ----------------------------------.
                 \                                          \
                  1.1 -> 1.2 -> 1.3 -> 1.4 -> 1.5 -> 1.6 -> 2.3 -> 2.4 -> 3.1 -> 4.1 -> 4.2
                                                        2.1 --'      \
                                                        2.2 --'       '-> 3.2 (server + keys)
                                                                       '-> 3.3 (server mockLLM)
```

Phase 0 and Phase 1 are independent after 0.3 and can run in parallel. 2.1 and 2.2 depend only
on Phase 0 and 1.2. The critical path is 1.1 -> 1.3 -> 1.6 -> 2.4 -> 3.1.

Rough total: Phase 0 ~3 days, Phase 1 ~8 days, Phase 2 ~9 days, Phase 3.1 ~2 days, Phase 4 ~3
days. About five weeks for one engineer to a releasable feature with replay-tested wire contract;
3.2 and 3.3 follow as the server pieces land.

---

## 6. Risks and open questions

| # | Risk | Mitigation |
|---|---|---|
| R1 | `RubyVM::AbstractSyntaxTree.of` unavailable or lossy on some supported Ruby (3.0-3.3) or non-MRI | PR 1.1 spike first; D9 fallback (`{}` schema, explicit `credentials:`) is always available; document limits |
| R2 | Server rejects team parent without `model` | D1 inherits from first child at serialize time; contract test |
| R3 | `redact` (`regex` + `fix`) may not rewrite on the server | Verify in 3.2; fall back to `retry` |
| R4 | SSE through WireMock is buffered; without `chunkedDribbleDelay` `done` can arrive before the tool executes | `normalize.py` already paces the body; assert unmatched requests empty |
| R5 | `mockLLM` functional testing not available on the server yet | Replay now, functional later (3.3); spec helper supports both |
| R6 | `runtimeMetadata` needs conductor-oss >= 3.32.0-rc.8 (PR #1255); older servers omit it | `secret()` falls back to `ENV`; document minimum version |
| R7 | OSS vs Orkes model string semantics differ (provider type key vs integration name) | Docs say "left side is the integration name"; on OSS that is the provider key with `*_API_KEY` env; note both |
| R8 | Long-lived SSE thread plus worker threads plus user callbacks: exceptions in user blocks | Wrap every user callback; `execution.error` captures; never let the stream thread die silently |
| R9 | Class-level token cache change alters behaviour for users relying on cross-instance sharing | Deprecated shim for one release; changelog entry |
| R10 | `Last-Event-ID` must be an integer; a stray string 400s the reconnect | Parser stores `id` as Integer; reconnect sends `to_s` of it only |
| R11 | Server auto-registers TaskDefs with `responseTimeoutSeconds 3600`; ours overwrites with 10 | Same as Python; document that lease extension keeps long tools alive (follow-up: `lease_extend_enabled`) |

Open questions for the server team (none block Phases 0-2):

1. Confirm `regex` guardrail with `onFail: fix` rewrites content (2.14).
2. Timeline for `MockLLM` provider and the test-server entry point (2.15).
3. Whether `<agent>_termination` is emitted for `termination` on sub-agents too, so the
   registry can register it per agent in a team.
