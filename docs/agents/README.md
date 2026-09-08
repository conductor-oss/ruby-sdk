# Agents

Define an agent in Ruby, run it on a Conductor server. Same `agentConfig` on the wire as the
Python SDK; the server compiles and runs the loop, this process runs your tools.

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

Run it: `CONDUCTOR_SERVER_URL=http://localhost:8080/api ruby weather.rb`. Server URL and auth
come from the usual `CONDUCTOR_*` variables; nothing else to configure.

| Guide | What it covers |
|---|---|
| [Tools](concepts/tools.md) | `tool def`, types from keyword defaults, `describe`, `requires_approval`, modules, RubyLLM tools, server-side tools |
| [Calling an agent](concepts/streaming-hitl.md) | `call_sync`, `call_async`, `Execution`, approval with `on_approval` |
| [Teams](concepts/teams.md) | `add_agent`, `hands_off_to`, strategies, `redact`, `stop_when`, `stop_after` |
| [Secrets](concepts/secrets.md) | `secret()`, `secrets_env()`, how names reach the server and values reach the tool |
| [Runtime and deployment](concepts/runtime.md) | `AgentRuntime`, `deploy`, `serve`, `CONDUCTOR_AGENT_*` settings, what runs where |

Examples: [`examples/agents/`](../../examples/agents/) (`weather.rb`, `support_approval.rb`,
`bug_desk.rb`). The 19 agents in `examples/agents/golden_agents.rb` serialize identically to
the Python SDK's `examples/agents/_configs`; `dump_agent_configs.rb` regenerates them.

## Requirements

- A Conductor server with the agent runtime enabled (`conductor.integrations.ai.enabled=true`,
  the default) and an LLM integration configured. On Orkes the left side of
  `model: 'openai/gpt-4o'` is the integration name; on OSS it is the provider key whose API key
  the server reads from `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / ...
- Secrets delivered to tools (`secret('GH_TOKEN')`) need conductor-oss 3.32.0-rc.8 or later
  (`runtimeMetadata`). Older servers still work: `secret()` falls back to `ENV`.

## What is not ported

Framework agents (OpenAI Agents SDK, LangGraph, Google ADK, Claude Agent SDK), skills,
`plan_execute`, local code execution and CLI tools, schedules, semantic memory. See
`docs/design/AGENTS_IMPLEMENTATION_PLAN.md` for the full list and the decisions behind the
port.
