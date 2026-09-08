# Calling an agent: sync, async, approval

One idea per step. Each step is a complete program.

## 1. Sync — call and wait

```ruby
agent = Agent.new(
  name: 'support',
  model: 'anthropic/claude-sonnet-4-5',
  instructions: 'Help with orders.'
)

answer = agent.call_sync('What is your return policy?')
puts answer
```

`call_sync` blocks until the agent is finished and returns the answer as a String.

## 2. Async — call and get told when it's done

```ruby
agent.call_async('What is your return policy?') do |answer|
  Mailer.send(customer, answer)
end
```

Returns immediately. Your block runs with the answer when the agent finishes.

## 3. Async — call and check on it yourself

```ruby
execution = agent.call_async('What is your return policy?')

execution.done?          # false until finished
execution.partial_text   # what has streamed in so far
execution.result         # blocks until done, returns the answer
execution.cancel         # stop it
```

Same `call_async`, no block. You get an `Execution` and poll it.

## 4. Give it a tool

```ruby
tool def issue_refund(order_id: String, amount: Float)
  Billing.refund(order_id, amount)
end

agent = Agent.new(
  name: 'support',
  model: 'anthropic/claude-sonnet-4-5',
  instructions: 'Help with orders.'
)
agent.add_tool :issue_refund

puts agent.call_sync('Refund order A-1029, it arrived broken')
```

The model calls `issue_refund`, the refund happens, the answer comes back.

## 5. Make the tool wait for a human

```ruby
requires_approval :issue_refund
```

One line, after the tool. Now the agent stops before running `issue_refund` and waits.

## 6. Decide

```ruby
agent.on_approval do |request|
  if request.amount < 100
    request.approve
  else
    request.reject('Needs a manager')
  end
end
```

`request` has the tool's arguments as methods (`request.amount`, `request.order_id`), plus
`approve` and `reject(reason)`. Works the same with `call_sync` (block runs while you wait)
and `call_async` (block runs on the background thread).

No `on_approval` registered? The agent waits until something else approves it — a web UI,
another process, `execution.pending.approve`.

## 7. What happened?

```ruby
execution = agent.call_async('Refund order A-1029, it arrived broken')
execution.result

execution.finish_reason   # :stop, or :rejected if you rejected the tool
execution.tool_calls      # [#<ToolCall issue_refund order_id: "A-1029" amount: 49.0>]
execution.execution_id    # look it up later: Execution.find(id)
```

## All together

```ruby
require 'conductor/agents'
include Conductor::Agents

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

agent.call_async('Refund order A-1029, it arrived broken') do |answer|
  Mailer.send(customer, answer)
end
```

## Optional

```ruby
agent.call_sync(question, session_id: 'cust-77')   # same conversation across calls

agent.before_tool_call  { |call| log call.name }    # hooks
agent.after_tool_result { |result| log result }
```

## Fire and forget

`call_async` with no block, keep the `execution_id`, walk away. One catch: if the agent has
`tool def` tools, they run in *your* process, so it has to stay up. Fire-and-forget only works
when tools are all server-side (http / mcp / human) or you've `deploy`ed the agent and have
workers running elsewhere. Same rule as Python.

## Under the hood

`call_async(prompt, &on_done)`:

1. POST `/agent/start`, register the tool workers the server asks for
2. return an `Execution`; open SSE `/agent/stream/{id}` on a background thread
3. text events append to `execution.partial_text`
4. waiting events build an `ApprovalRequest` and call your `on_approval` block
5. done event sets `done?`, `finish_reason`, `tool_calls`; calls `on_done(answer)`

`call_sync` = `call_async(prompt).result`.
