# AgentClient

`Conductor::Client::AgentClient` wraps `/api/agent/*` with the SDK's normal
transport and auth. Get it with `OrkesClients#get_agent_client`. Use it when the
tools are server-side or already served elsewhere and you only need control.

| | Methods |
|---|---|
| Lifecycle | `compile_agent`, `deploy_agent`, `start_agent` |
| Inspect | `get_status`, `get_execution`, `list_executions`, `list_agents`, `get_agent`, `delete_agent` |
| Control | `approve`, `reject`, `respond`, `send_message`, `signal`, `pause`, `resume`, `stop`, `cancel` |
| Events | `stream_sse(execution_id, last_event_id:) { |event| }` |

`stream_sse` raises `SseUnavailableError` when the server has no stream; poll
`get_status` instead. Control calls change a durable execution, so authorize
callers and make retries idempotent.
