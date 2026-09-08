# Ruby Agents Parity Plan

Port `python-sdk/src/conductor/ai/agents` → `conductor_ruby` as `Conductor::Agents`. Same `agentConfig` on the wire; server compiles, SDK serializes + runs workers.

## Classes

### Definition (serialized to agentConfig)

```mermaid
classDiagram
  direction LR
  class Agent {
    +new(name:, model:, instructions:, tools: [], agents: [], **opts)
    +String name
    +String model  "provider/model"
    +String|PromptTemplate instructions
    +List~ToolDef~ tools
    +List~Agent~ agents
    +Symbol strategy
    +Agent|Proc router
    +Hash output_type
    +List~Guardrail~ guardrails
    +ConversationMemory memory
    +TerminationCondition termination
    +List~HandoffCondition~ handoffs
    +List~CallbackHandler~ callbacks
    +List~String~ credentials
    +Integer max_turns
    +Boolean stateful
    +add_tool(tool, credentials: nil) add_tools(*tools)
    +add_agent(agent) add_agents(*agents)  same as agents:
    +hands_off_to(agent, on:)
    +redact(words) stop_when(text) stop_after(messages:)
    +call_sync(prompt, session_id:) String
    +call_async(prompt, session_id:, &on_done) Execution
    +on_approval() &block
  }
  class ConfigSerializer {
    +serialize(agent) Hash
  }
  class ToolDef {
    +String name
    +String description
    +Hash input_schema
    +Hash output_schema
    +Proc func
    +ToolType tool_type
    +Hash config  per type
    +Boolean approval_required
    +List~String~ credentials
    +Integer retry_count
    +call(**args) PrefillToolCall
    +http(name, url, method) ToolDef$
    +mcp(server_url) ToolDef$
    +human(name) ToolDef$
    +agent(agent) ToolDef$
  }
  class Tools {
    <<module, include or extend>>
    +tool(method_name) ToolDef
    +requires_approval(name)
    +describe(name, text)
    +[](name) ToolDef
    -get_json_schema_def(method) Hash
    -scan_secrets(method) List~String~  literal secret() names
  }
  class ToolType {
    <<enumeration>>
    worker
    http
    api
    mcp
    human
    agent_tool
    generate_image
    generate_audio
    generate_video
    generate_pdf
    rag_index
    rag_search
    pull_workflow_messages
  }
  class Guardrail {
    +String name
    +Symbol position  input|output
    +Symbol on_fail  retry|raise|fix|human
    +Integer max_retries
    +Proc func
  }
  class RegexGuardrail
  class LlmGuardrail
  class TerminationCondition {
    <<abstract>>
    +should_terminate(ctx) TerminationResult
    +&(other) And
    +|(other) Or
  }
  class TextMention
  class StopMessage
  class MaxMessage
  class TokenUsage
  class HandoffCondition {
    +String target
    +should_handoff(ctx) Boolean
  }
  class OnToolResult
  class OnTextMention
  class OnCondition
  class CallbackHandler {
    +on_agent_start() on_agent_end()
    +on_model_start() on_model_end()
    +on_tool_start() on_tool_end()
  }
  class ConversationMemory {
    +List~Hash~ messages
    +Integer max_messages
  }
  class PromptTemplate {
    +String name
    +Hash variables
    +Integer version
  }

  Agent "1" o-- "*" ToolDef : tools, shared by name
  Agent "1" o-- "*" Agent : agents
  Agent "1" o-- "*" CallbackHandler : callbacks
  Agent "1" *-- "*" Guardrail : guardrails
  Agent "1" *-- "0..1" TerminationCondition : termination
  Agent "1" *-- "*" HandoffCondition : handoffs
  Agent "1" *-- "0..1" ConversationMemory : memory
  Agent --> "0..1" PromptTemplate : instructions
  Agent --> "0..1" Agent : router
  ConfigSerializer ..> Agent : reads
  Tools ..> ToolDef : creates
  ToolDef --> "1" ToolType : tool_type, one of these enum values
  ToolDef "1" *-- "*" Guardrail : tool guardrails
  Guardrail <|-- RegexGuardrail
  Guardrail <|-- LlmGuardrail
  TerminationCondition <|-- TextMention
  TerminationCondition <|-- StopMessage
  TerminationCondition <|-- MaxMessage
  TerminationCondition <|-- TokenUsage
  HandoffCondition <|-- OnToolResult
  HandoffCondition <|-- OnTextMention
  HandoffCondition <|-- OnCondition
```

### Runtime + transport

```mermaid
classDiagram
  direction LR
  class AgentRuntime {
    +call_sync(agent, prompt) String
    +call_async(agent, prompt, &on_done) Execution
    +deploy(*agents) List~String~
    +serve(*agents)
    +shutdown()
  }
  class AgentConfig {
    +Integer worker_poll_interval_ms
    +Integer worker_thread_count
    +Boolean auto_register_integrations
    +Boolean streaming_enabled
    +from_env() AgentConfig$
  }
  class Execution {
    +String execution_id
    +done() Boolean
    +waiting() Boolean
    +result() String  blocks until done
    +String partial_text  so far, non-blocking
    +Symbol finish_reason
    +List~ToolCall~ tool_calls
    +TokenUsage token_usage
    +pause() resume() cancel()
    +find(execution_id) Execution$
  }
  class ApprovalRequest {
    +String execution_id
    +String tool_name
    +Hash arguments
    +approve()
    +reject(reason)
  }
  class ToolRegistry {
    +register_tool_workers(tools, agent_name, domain)
    +register_system_workers(required_workers)
  }
  class Dispatch {
    +run_tool_task(task, tool_def) Hash
    -coerce_args(input_data)
    -bind_secrets(task, tool_def)
  }
  class Secrets {
    <<module, fiber-local>>
    +secret(name) String
    +secrets_env(*names) Hash
  }
  class SseClient {
    +each_event(execution_id) Enumerator
    -fallback_polling()
  }
  class McpDiscovery {
    +expand(mcp_tool) List~ToolDef~
  }
  class AgentClient {
    +start_agent(payload) Hash
    +deploy_agent(payload) Hash
    +compile_agent(payload) Hash
    +get_status(id) Hash
    +get_execution(id) Hash
    +list_executions(params) Hash
    +respond(id, body)
    +stop(id) signal(id, msg)
    +stream_sse(id, last_event_id) Enumerator
  }
  class AgentResourceApi {
    +start(body) POST agent-start
    +deploy(body) POST agent-deploy
    +compile(body) POST agent-compile
    +status(id) GET agent-id-status
    +execution(id) GET agent-execution-id
    +executions(params) GET agent-executions
    +respond(id, body) POST agent-id-respond
    +stop(id) POST agent-id-stop
    +signal(id, msg) POST agent-id-signal
    +stream(id) GET agent-stream-id SSE
  }
  class Agent {
    <<from Definition>>
  }
  class ConfigSerializer {
    <<from Definition>>
  }
  class TaskHandler {
    <<existing>>
  }
  class WorkflowClient {
    <<existing>>
  }
  class ApiClient {
    <<existing>>
  }
  class OrkesClients {
    <<existing>>
    +get_agent_client() AgentClient
  }

  AgentRuntime *-- AgentConfig
  AgentRuntime *-- AgentClient
  AgentRuntime *-- ToolRegistry
  AgentRuntime *-- SseClient
  AgentRuntime ..> ConfigSerializer : agentConfig
  AgentRuntime ..> Agent : reads on_approval
  AgentRuntime ..> McpDiscovery : uses
  AgentRuntime ..> Execution : creates
  Execution --> AgentClient : pause, cancel
  ApprovalRequest --> AgentClient : respond
  SseClient ..> Execution : appends partial_text, fires on_done
  SseClient ..> ApprovalRequest : creates on waiting
  ToolRegistry --> TaskHandler : Worker.define
  ToolRegistry ..> Dispatch : worker body
  Dispatch ..> Secrets : binds per task
  McpDiscovery ..> WorkflowClient : ephemeral LIST_MCP_TOOLS workflow
  AgentClient *-- AgentResourceApi
  AgentResourceApi --> ApiClient
  OrkesClients ..> AgentClient : creates
```

## Examples

### 1. Tools

```ruby
require 'conductor/agents'
include Conductor::Agents

tool def get_weather(city: String, units: 'metric')
  { temp_c: 21.0, summary: "Sunny in #{city}" }
end

agent = Agent.new(
  name: 'weather',
  model: 'openai/gpt-4o',
  instructions: 'Answer weather questions.'
)
agent.add_tool :get_weather

puts agent.call_sync('Weather in Lisbon?')
```

`tool def` marks a method as a tool. Types come from the keyword defaults: `city: String` = required string, `units: 'metric'` = optional with default. Description = humanized method name (`describe :get_weather, '...'` to override). `RubyLLM::Tool` classes work as-is: `agent.add_tool Weather`. Spec: `docs/design/AGENT_TOOLS_DSL.md`.

```mermaid
sequenceDiagram
  actor You
  participant SDK as Ruby SDK
  participant Server as Conductor Server
  participant LLM as OpenAI

  You->>+SDK: agent.call_sync("Weather in Lisbon?")  (blocks until done)
  SDK->>+Server: POST /agent/start (agentConfig, prompt)
  Server-->>-SDK: executionId, requiredWorkers [get_weather]
  SDK->>SDK: start worker for get_weather
  SDK->>Server: GET /agent/stream (SSE)
  Server->>+LLM: instructions + prompt + tool schema
  LLM-->>-Server: call get_weather(city: "Lisbon")
  Server->>SDK: task get_weather
  SDK->>SDK: get_weather(city: "Lisbon") runs
  SDK-->>Server: result
  Server->>+LLM: tool result
  LLM-->>-Server: "Sunny, 21°C in Lisbon"
  Server-->>SDK: SSE text
  Server-->>SDK: SSE done
  SDK-->>-You: "Sunny, 21°C in Lisbon"
```

### 2. Streaming + approval

```ruby
tool def issue_refund(order_id: String, amount: Float)
  Billing.refund(order_id, amount)
end
requires_approval :issue_refund

agent = Agent.new(
  name: 'support',
  model: 'anthropic/claude-sonnet-4-5',
  instructions: 'Help with orders.'
)
agent.add_tool :issue_refund

agent.on_approval do |request|
  request.amount < 100 ? request.approve : request.reject('Needs a manager')
end

# blocking
answer = agent.call_sync('Refund order A-1029, it arrived broken')

# non-blocking, callback when finished
agent.call_async('Refund order A-1029, it arrived broken') do |answer|
  Mailer.send(customer, answer)
end

# non-blocking, poll it yourself
execution = agent.call_async('Refund order A-1029, it arrived broken')
execution.done?          # false until finished
execution.partial_text   # what has streamed so far
execution.result         # blocks for the answer
execution.finish_reason  # :stop | :rejected
```

`call_sync` blocks and returns the answer. `call_async` returns an `Execution` immediately; SSE runs on a background thread, and the block (if given) runs with the answer when done. Spec: `docs/design/AGENT_STREAMING.md`.

```mermaid
sequenceDiagram
  actor You
  participant SDK as Ruby SDK
  participant Server as Conductor Server
  participant LLM as Anthropic

  You->>+SDK: agent.call_async("Refund order A-1029") with on_done block
  SDK->>+Server: POST /agent/start
  Server-->>-SDK: executionId, requiredWorkers [issue_refund]
  SDK->>SDK: start worker for issue_refund
  SDK->>Server: GET /agent/stream (SSE, background thread)
  SDK-->>-You: Execution  (returns immediately)

  Note over You,SDK: Everything below runs on background thread

  Server->>+LLM: prompt + tool schema
  LLM-->>-Server: call issue_refund(order_id: "A-1029", amount: 49.0)
  Server->>Server: requires approval → pause

  Server-->>+SDK: SSE waiting (tool, arguments)
  SDK->>+You: on_approval(request)
  You-->>-SDK: request.approve
  SDK->>+Server: POST /agent/id/respond approved
  Server-->>-SDK: ok
  deactivate SDK

  Server->>+SDK: task issue_refund
  SDK->>SDK: issue_refund runs
  SDK-->>-Server: result

  Server->>+LLM: tool result
  LLM-->>-Server: "Refunded $49."

  Server-->>+SDK: SSE text
  SDK->>SDK: execution.partial_text appended
  deactivate SDK

  Server-->>+SDK: SSE done
  SDK->>SDK: execution.done? = true
  SDK->>+You: on_done("Refunded $49.")
  You-->>-SDK: block returns
  deactivate SDK

  You->>+SDK: execution.finish_reason
  SDK-->>-You: :stop
```

Had `on_approval` called `request.reject`, the server skips the tool and finishes with `finish_reason == :rejected`. Same flow with `call_sync`: the first activation bar simply stays open until done and the answer is the return value.

### 3. Team + secret

```ruby
tool def create_issue(title: String, body: '')
  Github.create_issue(title, body, token: secret('GH_TOKEN'))
end

triage = Agent.new(
  name: 'triage',
  model: 'openai/gpt-4o-mini',
  instructions: 'Read the bug report. Say ACTIONABLE if it should be filed.'
)

filer = Agent.new(
  name: 'filer',
  model: 'anthropic/claude-sonnet-4-5',
  instructions: 'File the bug as a GitHub issue.'
)
filer.add_tool :create_issue

triage.hands_off_to filer, on: 'ACTIONABLE'

team = Agent.new(name: 'bug_desk')
team.add_agent triage
team.add_agent filer

puts team.call_sync(File.read('report.md'))
```

Make the agent, then give it things. `secret('GH_TOKEN')` in the tool body both reads the secret and declares it — the SDK scans for it at `tool def` and the server attaches the value to each task. Optional: `filer.redact %w[password api_key]`, `filer.stop_when 'ISSUE_FILED'`, `filer.stop_after messages: 12`, `team.strategy = :sequential`. Every line is sugar over the Python-parity objects (`Handoff::OnTextMention`, `RegexGuardrail`, `Termination::*`). Spec: `docs/design/AGENT_TEAMS.md`.

```mermaid
sequenceDiagram
  actor You
  participant SDK as Ruby SDK
  participant Server as Conductor Server
  participant Triage as triage (gpt-4o-mini)
  participant Filer as filer (claude)

  You->>+SDK: team.call_sync(report)  (blocks until done)
  SDK->>+Server: POST /agent/start (team agentConfig: triage, filer)
  Server-->>-SDK: executionId, requiredWorkers [create_issue]
  SDK->>SDK: start worker for create_issue, TaskDef.runtime_metadata = [GH_TOKEN]
  SDK->>Server: GET /agent/stream (SSE)
  Server->>+Triage: report
  Triage-->>-Server: "... ACTIONABLE"
  Server->>Server: hands_off_to filer matched
  Server->>+Filer: conversation so far + create_issue schema
  Filer-->>-Server: call create_issue(title, body)
  Server->>Server: resolve GH_TOKEN from secret store
  Server->>SDK: task create_issue, runtime_metadata GH_TOKEN=ghp_...
  SDK->>SDK: secret("GH_TOKEN") → Github.create_issue
  SDK-->>Server: issue url
  Server->>+Filer: tool result
  Filer-->>-Server: "Filed: github.com/.../issues/42"
  Server-->>SDK: SSE text
  Server-->>SDK: SSE done
  SDK-->>-You: "Filed: github.com/.../issues/42"
```

## Secrets

```mermaid
classDiagram
  direction LR
  class Integration {
    <<server-side>>
    holds LLM provider key
    model "openai/gpt-4o" → integration "openai"
  }
  class Agent {
    +String model  "openai/gpt-4o"
    +List~String~ credentials  inherited by sub-agents and tools
  }
  class Tools {
    -scan_secrets(method)  literal secret() names
  }
  class ToolDef {
    +List~String~ credentials
  }
  class TaskDef {
    +Hash runtime_metadata  names only
  }
  class Task {
    +Hash runtime_metadata  name → plaintext, wire-only
  }
  class Dispatch {
    -bind_secrets(task, tool_def)
  }
  class Secrets {
    <<module, fiber-local>>
    +secret(name) String
    +secrets_env(*names) Hash  for system, spawn, Open3
    falls back to ENV
  }
  class CredentialNotFoundError

  Agent ..> Integration : model prefix names it
  Tools ..> ToolDef : scan_secrets at tool def
  Agent ..> ToolDef : credentials copied down at serialize
  ToolDef ..> TaskDef : credentials copied to runtime_metadata at register
  TaskDef ..> Task : server fills values at poll
  Dispatch ..> Task : reads runtime_metadata
  Dispatch ..> Secrets : binds for this call
  Secrets ..> CredentialNotFoundError : missing everywhere
```

| Secret | Held by | You write |
|---|---|---|
| Conductor auth | your env | `CONDUCTOR_AUTH_KEY`, `CONDUCTOR_AUTH_SECRET` (existing `Configuration`, token cache moves to instance level) |
| LLM provider key | server Integration | `model: 'openai/gpt-4o'` — `openai` is the integration name. SDK never sees the key. |
| Tool credential | server secret store | `secret('GH_TOKEN')` in the tool body — read and declaration in one |

### Flow: tool credential

```mermaid
sequenceDiagram
  participant SDK as Ruby SDK
  participant Server as Conductor Server
  participant Store as Secret Store

  Note over SDK,Server: at startup
  SDK->>+Server: register TaskDef create_issue, runtimeMetadata [GH_TOKEN]
  Server-->>-SDK: ok

  Note over Server: LLM calls create_issue
  Server->>+Store: get GH_TOKEN
  Store-->>-Server: ghp_...
  Server->>+SDK: task create_issue, runtimeMetadata GH_TOKEN=ghp_...
  SDK->>SDK: bind runtimeMetadata for this call (fiber-local)
  SDK->>SDK: create_issue runs, secret("GH_TOKEN") → ghp_...
  SDK-->>-Server: result (runtimeMetadata dropped)
```

### Use a secret in a tool

```ruby
tool def create_issue(title: String, body: '')
  Github.create_issue(title, body, token: secret('GH_TOKEN'))
end
```

That's it. `secret('GH_TOKEN')` is the read *and* the declaration: at `tool def` the SDK parses the method body, collects every literal `secret('...')`, and puts the names in the tool's contract (`TaskDef.runtimeMetadata`, `tool.config.credentials`). Python makes you write the list; Ruby reads it off the code. Same wire contract.

### When the name isn't a literal

```ruby
filer.add_tool :create_issue, credentials: ['GH_TOKEN']     # this tool
filer = Agent.new(..., credentials: ['GH_TOKEN'])           # everything under this agent
```

### Tool that shells out

```ruby
tool def gh_create_issue(title: String)
  system(secrets_env('GH_TOKEN'), 'gh', 'issue', 'create', '--title', title)
end
```

`secrets_env('GH_TOKEN')` is `{ 'GH_TOKEN' => 'ghp_...' }` for this call, and declares the same way. Ruby's `system` / `spawn` / `Open3` take an env hash as the first argument, so only the child process sees it. We never write to `ENV`.

### No secret store on the server?

`secret('GH_TOKEN')` falls back to `ENV['GH_TOKEN']`.

## Frameworks

No official Ruby SDK exists for any of these. Not supported.

| Framework | Ruby |
|---|---|
| OpenAI Agents SDK | N/A |
| Anthropic Claude Agent SDK | N/A |
| LangGraph | N/A |
| Google ADK | N/A |
