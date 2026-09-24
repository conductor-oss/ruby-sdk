# AgentRuntime

One per process. `Conductor::Agents.runtime` is the default, built from ENV;
`AgentRuntime.new(configuration:, agent_config:, logger:)` for anything else.

| Method | Returns |
|---|---|
| `call_sync(agent, prompt, session_id:, timeout:, **opts)` | answer `String` |
| `call_async(agent, prompt, on_event:, **opts, &on_done)` | `Execution` |
| `compile(agent)` | `{ 'workflowDef', 'requiredWorkers' }` |
| `deploy(*agents)` | deployed names |
| `serve(*agents, blocking: true)` | blocks |
| `shutdown(timeout: 5)` | stops workers and streams |

`opts`: `media:`, `context:`, `idempotency_key:`, `timeout_seconds:`.

`AgentConfig.from_env` reads `CONDUCTOR_AGENT_WORKER_POLL_INTERVAL`,
`CONDUCTOR_AGENT_WORKER_THREADS`, `CONDUCTOR_AGENT_INTEGRATIONS_AUTO_REGISTER`,
`CONDUCTOR_AGENT_STREAMING_ENABLED`. Server URL and auth come from
`Configuration` (`CONDUCTOR_*`).

`Execution`: `result(timeout:)`, `output`, `status`, `done?`, `waiting?`,
`partial_text`, `tool_calls`, `token_usage`, `approve`, `reject`, `signal`,
`pause`, `resume`, `stop`, `cancel`. `Execution.find(id)` reattaches.
