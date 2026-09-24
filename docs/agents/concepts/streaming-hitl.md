# Streaming and approval

```ruby
execution = agent.call_async('Transfer $500', on_event: ->(e) { puts e['event'] })
execution.result(timeout: 120)
```

Events (`message`, `tool_call`, `tool_result`, `waiting`, `done`, `error`)
arrive over SSE; the runtime falls back to polling when SSE is unavailable.
`execution.partial_text` holds the text so far; nothing is final until
`execution.done?`.

Tools with `approval_required: true` pause the execution:

```ruby
agent.on_approval do |request|
  puts request.tool_name, request.arguments
  request.approve            # or request.reject('no'), request.respond(hash)
end
```

`Tool.human` asks a person a question; `Tool.wait_for_message` waits for
`execution.signal(message)`. Without a handler, use `execution.approve`,
`reject`, `signal`, or the [client](../reference/client.md). Approval calls are
safe to repeat.

Call `Conductor::Agents.shutdown` when a short-lived program is done.
