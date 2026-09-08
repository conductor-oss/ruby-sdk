# Tools

```ruby
require 'conductor/agents'
include Conductor::Agents

tool def get_weather(city: String, units: 'metric')
  { temp_c: 21.0, summary: "Sunny in #{city}" }
end

agent.add_tool :get_weather
```

`tool` receives the Symbol that `def` returns (the same trick as `private def`) and builds a
`ToolDef`: the tool's name is the method name, its description is the humanized name
(`get_weather` -> "Get weather"), its JSON schema comes from the keyword defaults, and its
secrets from `secret('...')` literals in the body. The method stays a normal method, so
`get_weather(city: 'Lisbon')` works in tests.

## Types

The default is the type:

| You write | JSON schema |
|---|---|
| `city: String` | required string |
| `amount: Float` | required number |
| `count: Integer` | required integer |
| `flags: Hash` | required object |
| `tags: [String]` | required array of strings |
| `units: 'metric'` | optional string, default `"metric"` |
| `limit: 10` | optional integer, default `10` |
| `verbose: false` | optional boolean, default `false` |
| `units: %w[metric imperial]` | optional string, one of these, default `"metric"` |
| `extra: nil` | optional, any type |
| `city:` (no default) | required, any type |

Positional parameters raise at `tool def`. Types are read from the method's AST
(`RubyVM::AbstractSyntaxTree.of`), which works on MRI whenever the source file is on disk. For
methods typed into irb (Ruby 3.2+: set `RubyVM.keep_script_lines = true`) or on other Rubies,
every keyword becomes an untyped property and only keywords without defaults are required.

Because `city: String` uses the class as the Ruby default, the runtime never calls a tool with a
required argument missing: the task fails with a clear reason instead.

## Description, approval, options

```ruby
describe :get_weather, 'Get the current weather for a city.'
requires_approval :issue_refund            # a human approves before it runs
tool_credentials :create_issue, 'GH_TOKEN' # when the secret name is not a literal
Weather[:forecast].timeout_seconds = 60    # any ToolDef attribute
tool :ping, description: 'Health check', retry_count: 0   # options on registration
```

## Modules

```ruby
module Weather
  extend Conductor::Agents::Tools

  tool def current(city: String) ... end
  tool def forecast(city: String, days: 3) ... end
end

agent.add_tools Weather              # both
agent.add_tool  Weather[:current]    # one
```

Inside a class body (an `RSpec.describe` block, for example) `tool def` also works; the method
is bound to a bare instance of the class.

## RubyLLM tools

```ruby
class Weather < RubyLLM::Tool
  description 'Gets current weather for a location'
  param :latitude, type: :number
  param :longitude, type: :number

  def execute(latitude:, longitude:) ... end
end

agent.add_tool Weather   # a RubyLLM::Tool class, as-is
```

The adapter reads `name`, `description` and `parameters`, and runs `Weather.new.execute(**args)`
as the worker body. RubyLLM is optional and only used when it is loaded. It is not the engine:
Conductor runs the LLM loop server-side with the provider key held as an integration.

## Server-side tools

These need no worker in your process:

```ruby
ToolDef.http('lookup', 'https://api.example.com/orders/${id}', method: 'GET',
             headers: { 'Authorization' => 'Bearer ${API_KEY}' }, credentials: ['API_KEY'])
ToolDef.mcp('http://localhost:3001/mcp', tool_names: %w[search fetch])
ToolDef.human('ask_user', description: 'Ask the user a question and wait for the answer.')
ToolDef.agent(researcher)                 # another agent as a tool
ToolDef.image('draw', description: '...', llm_provider: 'openai', model: 'dall-e-3')
```

`${NAME}` placeholders in headers must be listed in `credentials:`. MCP discovery happens on
the server (`LIST_MCP_TOOLS` before the loop); nothing runs client-side.

## What the server sends your tool

The LLM's arguments arrive as top-level task input keys, plus `method`, `_agent_state` and
`_agent_tool_name` which the SDK strips. Strings are coerced to the schema type (`"5"` -> `5`,
`"true"` -> `true`, JSON text -> arrays/objects). A Hash result is returned as-is; anything else
is wrapped as `{ "result" => value }`. A `_state_updates` key in the result is merged into the
agent's durable state by the server. Exceptions fail the task (retried per the tool's
`retry_count`, default 2); missing arguments, missing secrets and unserializable results fail it
terminally.
