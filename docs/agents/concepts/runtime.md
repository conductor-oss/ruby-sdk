# Runtime and deployment

`Agent#call_sync` / `#call_async` use `Conductor::Agents.runtime`, an `AgentRuntime` built
from the environment (`CONDUCTOR_SERVER_URL`, `CONDUCTOR_AUTH_KEY`, `CONDUCTOR_AUTH_SECRET`).

```ruby
Conductor::Agents.configure(
  configuration: Conductor::Configuration.new(server_api_url: 'https://play.orkes.io/api'),
  agent_config: Conductor::Agents::AgentConfig.new(worker_thread_count: 4)
)

runtime = Conductor::Agents::AgentRuntime.new(configuration: config)   # or your own instance
runtime.call_sync(agent, 'hi')
runtime.compile(agent)     # { "workflowDef", "requiredWorkers" } without registering
runtime.deploy(a, b)       # register on the server; returns names
runtime.serve(a, b)        # deploy + run the tool workers until Ctrl-C
runtime.shutdown           # stop workers and streams
Conductor::Agents.shutdown # same for the default runtime
```

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `CONDUCTOR_AGENT_WORKER_POLL_INTERVAL` | `100` | tool worker poll interval (ms) |
| `CONDUCTOR_AGENT_WORKER_THREADS` | `1` | concurrent tasks per tool worker |
| `CONDUCTOR_AGENT_STREAMING_ENABLED` | `true` | use SSE; `false` polls `/agent/{id}/status` |
| `CONDUCTOR_AGENT_INTEGRATIONS_AUTO_REGISTER` | `false` | reserved (Python parity), not used yet |

Booleans accept `true/1/yes/on` and `false/0/no/off`.

## What runs where

| Piece | Where |
|---|---|
| LLM loop, tool routing, guardrail chain, approval pause, MCP discovery | server |
| `tool def` tools, RubyLLM tools | this process (Conductor workers, one per tool name) |
| `<agent>_termination` (`stop_when`, `stop_after`, `termination:`) | this process |
| custom guardrails (with a block), callbacks, `on_condition` handoffs | this process |
| regex / LLM guardrails, http / mcp / human / agent tools | server |

Every worker registers its TaskDef with the Python SDK's defaults: `retryCount 2`,
`retryDelaySeconds 2`, `retryLogic LINEAR_BACKOFF`, `timeoutSeconds 0`,
`responseTimeoutSeconds 10`, `timeoutPolicy RETRY`, `runtimeMetadata` = declared secret names.
Task results go to `POST /api/tasks/update-v2` (with a one-time fallback to `POST /api/tasks`).
While a tool or system worker runs, the SDK renews its lease at 80% of the task's
`responseTimeoutSeconds` (every 8 seconds for the default timeout). Renewals use
`POST /api/tasks` with `extendLease: true` and stop before the final result is sent.
Tasks with no positive response timeout do not need renewal. Agent workers enable
`lease_extend_enabled` by default; other workers can opt in with that option.

An agent execution is a Conductor workflow: `execution_id` is the workflow id, and the
workflow, task and prompt data are visible in the Conductor UI like any other run.

## Stateful runs

`Agent.new(..., stateful: true)` (or a stateful tool) sends a `runId` with the start request.
The server maps every required worker to that task domain and the SDK polls with it, so each
run's tasks reach the process that started it.

## Testing

Contract tests (`spec/conductor/agents/contract_spec.rb`) need no server: every serialized
config must equal the Python SDK's golden file and validate against `agent-schema.json`.

Runtime tests (`spec/agents/`) replay scenarios recorded from a real server with WireMock
(`conductor-oss/conductor-mocks`):

```bash
docker run -d -p 8080:8080 -v $PWD/../conductor-mocks/mocks/agent/tool_happy_path:/home/wiremock wiremock/wiremock:3x
CONDUCTOR_AGENTS_REPLAY_URL=http://localhost:8080 bundle exec rspec spec/agents
```

A request the recorded server never saw fails the run.
