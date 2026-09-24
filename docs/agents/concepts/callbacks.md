# Callbacks

```ruby
agent.callback(:before_tool) { |**event| logger.info(event[:tool_name]) }

class Audit < CallbackHandler
  def on_agent_end(**event) = logger.info(event)
end
agent.add_callback(Audit.new)
```

Positions: `before_agent`, `after_agent`, `before_model`, `after_model`,
`before_tool`, `after_tool`. Handler methods are `on_agent_start`, `on_agent_end`,
`on_model_start`, `on_model_end`, `on_tool_start`, `on_tool_end`.

Callbacks run in your process and don't change the workflow. Keep them fast, and
don't make them the only record of anything: a restart drops them. Durable side
effects belong in a tool.
