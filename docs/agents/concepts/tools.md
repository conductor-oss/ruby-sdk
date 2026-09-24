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
| HTTP endpoint | `ToolDef.http(name, url, ...)` |
| OpenAPI / Postman | `ToolDef.api(url)` |
| MCP server | `ToolDef.mcp(url)` |
| Human answer | `ToolDef.human(name, description:)` |
| Wait for a message | `ToolDef.wait_for_message(name, description:)` |
| Media, PDF, vectors | `ToolDef.image`, `.audio`, `.video`, `.pdf`, `.index`, `.search` |
| Another agent | `ToolDef.agent(child)` or `agent.add_tool(child)` |

Options on `tool` and the factories: `retry_count:`, `retry_delay_seconds:`,
`timeout_seconds:`, `max_calls:`, `approval_required:`, `output_schema:`.

A tool stuck in `SCHEDULED` has no worker polling. `CredentialNotFoundError`
means the secret is missing on the server.
