# Runtime modes

| Call | Does |
|---|---|
| `runtime.compile(agent)` | Compile; returns `workflowDef` and `requiredWorkers`. |
| `runtime.deploy(agent)` | Compile and register on the server. |
| `runtime.serve(agent)` | Deploy, run tool workers, block until INT/TERM. |
| `runtime.call_sync(agent, prompt)` | Start, run workers, return the answer. |
| `runtime.call_async(agent, prompt)` | Same, but return an `Execution` immediately. |
| `Execution.find(id)` | Reattach to an existing execution. |

`runtime` is `Conductor::Agents.runtime` (built from ENV) or your own
`AgentRuntime.new(configuration: ...)`.

Local development: `call_sync`. CI/CD: `compile` to inspect, `deploy` to
release. Production: `serve` in a long-lived worker process, then start runs
from anywhere with the [client](../reference/client.md).

Tools must be defined in the process that calls `serve` or `call_*`. Call
`shutdown` before a short-lived process exits.
