# Agents

```ruby
require 'conductor/agents'
include Conductor::Agents

tool def get_weather(city: String)
  "Weather for #{city}"
end

agent = Agent.new(name: 'weather', model: 'openai/gpt-4o-mini',
                  instructions: 'Answer concisely.', tools: [:get_weather])
puts agent.call_sync('Weather in Seattle?')
```

- `name` must match `^[a-zA-Z_][a-zA-Z0-9_-]*$`.
- `model` is `provider/model`; the provider is an integration on the server.
  Omit it only for sub-agents that inherit the parent's model.
- `instructions` is a String, a Proc evaluated at compile time, or a `PromptTemplate`.
- Per-call options: `session_id:`, `media:`, `context:`, `idempotency_key:`,
  `timeout_seconds:`. Don't mutate a shared agent per request.

`call_sync` compiles the agent, starts workers for its tools, and returns the
answer. A tool task stuck in `SCHEDULED` means no process is running its worker.

See [tools](tools.md), [multi-agent](multi-agent.md), [runtime modes](deploy-serve-run.md).
