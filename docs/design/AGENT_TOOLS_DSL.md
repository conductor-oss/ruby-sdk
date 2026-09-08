# Tools

## Whole thing, one file

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

Run it: `ruby weather.rb`. That's the whole thing.

## What each line does

| Line | Does |
|---|---|
| `tool def get_weather(...)` | Makes the method a tool. `tool` sees the name `:get_weather` because `def` returns it (same as `private def`). |
| `city: String` | Required string. |
| `units: 'metric'` | Optional string, default `metric`. |
| `agent.add_tool :get_weather` | Give the agent the tool by name. |
| `agent.call_sync('prompt')` | Run it, wait, return the answer. Server URL / auth come from `CONDUCTOR_*` env vars. |

The description the LLM sees is the method name: `get_weather` → "Get weather".

## Types

Whatever you put as the default is the type:

| You write | Meaning |
|---|---|
| `city: String` | required string |
| `amount: Float` | required number |
| `count: Integer` | required integer |
| `tags: [String]` | required list of strings |
| `units: 'metric'` | optional, default `"metric"` |
| `limit: 10` | optional, default `10` |
| `verbose: false` | optional, default `false` |
| `units: %w[metric imperial]` | optional, one of these |

## More than a few tools? Put them in a module

```ruby
module Weather
  extend Conductor::Agents::Tools

  tool def current(city: String) ... end
  tool def forecast(city: String, days: 3) ... end
end

agent.add_tools Weather              # both
agent.add_tool  Weather[:current]    # one
```

## Options

Approval and secrets are one line each, after the tool:

```ruby
tool def issue_refund(order_id: String, amount: Float)
  Stripe.refund(order_id, amount, key: secret('STRIPE_KEY'))
end
requires_approval :issue_refund
```

- `requires_approval :name` — a human approves before it runs. See `AGENT_STREAMING.md`.
- `secret('KEY')` — reads a secret. Writing it in the body is also the declaration: the SDK
  finds it at `tool def` and tells the server this tool needs `STRIPE_KEY`. See `AGENT_SECRETS.md`.
- `describe :name, '...'` — override the description if the method name isn't enough.

## Rules

- Keyword args only (`city:`). Positional args raise at load.
- It's still a normal method: `get_weather(city: 'Lisbon')` works in tests.

## Already have RubyLLM tools?

They work as-is:

```ruby
class Weather < RubyLLM::Tool
  desc "Gets current weather for a location"
  def execute(latitude:, longitude:) ... end
end

agent.add_tool Weather               # a RubyLLM::Tool class, as-is
```

RubyLLM already builds the JSON schema from `execute`'s keyword args and exposes `name` and
`description`; we read those into a `ToolDef` and run `Weather.new.execute(**args)` as the
worker body. Optional dependency — only loaded if `RubyLLM` is defined.

RubyLLM is not the engine underneath. It runs the LLM loop client-side with your provider key;
Conductor runs it server-side with the key held as an integration. Only the tool class and the
`call_sync` / `call_async` API shape are shared.
