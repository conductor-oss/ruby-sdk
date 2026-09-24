# Tools

`tool def` turns a method into a tool. Keyword defaults give the schema
(`city: String`, `units: 'metric'`). Each call is a retryable Conductor task.

```ruby
require 'conductor/agents'
include Conductor::Agents

tool def create_issue(title: String)
  Github.create_issue(title, token: secret('GITHUB_TOKEN'))
  "created: #{title}"
end
describe :create_issue, 'Create a GitHub issue.'
requires_approval :create_issue
```

`secret('NAME')` inside the body both declares the credential and reads it at
run time. The server resolves it from its secret store into the task; nothing goes
through ENV or workflow input. Use `credentials:` for names built dynamically.

Server-side tools need no worker:

| Tool | Factory |
|---|---|
| HTTP endpoint | `Tool.http(name, url, ...)` |
| OpenAPI / Postman | `Tool.api(url)` |
| MCP server | `Tool.mcp(url)` |
| Human answer | `Tool.human(name, description:)` |
| Wait for a message | `Tool.wait_for_message(name, description:)` |
| Media, PDF, vectors | `Tool.image`, `.audio`, `.video`, `.pdf`, `.index`, `.search` |
| Another agent | `Tool.agent(child)` or `agent.add_tool(child)` |

Options on `tool`: `name:` (when the tool name differs from the method name),
`description:`, `guardrails:`, `credentials:`, `external:`, `stateful:`,
`retry_count:`, `retry_delay_seconds:`, `timeout_seconds:`, `max_calls:`,
`approval_required:`, `input_schema:`, `output_schema:`. The factories take the
subset that applies to them. `tool.with_guardrails(g)` returns a guarded copy of
any tool.

A tool stuck in `SCHEDULED` has no worker polling. `CredentialNotFoundError`
means the secret is missing on the server.
