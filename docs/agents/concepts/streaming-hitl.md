# Calling an agent: sync, async, approval

## Sync

```ruby
answer = agent.call_sync('What is your return policy?')
```

Blocks until the agent is finished and returns the answer as a String. Pass `timeout:` seconds
to give up (`Timeout::Error`). A failed, cancelled or timed-out execution raises
`Conductor::Agents::Error`.

## Async with a callback

```ruby
agent.call_async('What is your return policy?') do |answer, execution|
  Mailer.send(customer, answer)
end
```

Returns immediately. The block runs on the stream thread when the agent finishes (`answer` is
nil when it failed; check `execution.finish_reason`). Exceptions in the block are logged, never
raised into the stream.

## Async, poll it yourself

```ruby
execution = agent.call_async('What is your return policy?')

execution.done?          # false until finished
execution.waiting?       # true while a tool waits for approval
execution.partial_text   # text streamed so far
execution.result         # blocks until done, returns the answer
execution.finish_reason  # :stop | :tool_calls | :length | :content_filter | :rejected | :error | :cancelled | :timeout
execution.tool_calls     # [#<ToolCall get_weather city: "Lisbon">] with .result once known
execution.token_usage    # prompt / completion / total, summed over sub-agents
execution.execution_id   # also the Conductor workflow id; Execution.find(id) later
execution.pause; execution.resume; execution.cancel; execution.stop; execution.signal('hurry up')
```

## Approval

```ruby
tool def issue_refund(order_id: String, amount: Float)
  Billing.refund(order_id, amount)
end
requires_approval :issue_refund

agent.on_approval do |request|
  request.amount < 100 ? request.approve : request.reject('Needs a manager')
end
```

When the model calls an approval-required tool the server pauses on a HUMAN task and the SDK
receives a `waiting` event. `request` is an `ApprovalRequest`: the tool's arguments are
methods (`request.amount`, `request.order_id`), plus `tool_name`, `arguments`, `tool_calls`
(the server gates the whole batch of tool calls in a turn with one approval), `approve`,
`reject(reason)` and `send_message(text)` for human-input tools.

The block runs on the stream thread, for `call_sync` and `call_async` alike. Without an
`on_approval` block the request is parked on `execution.pending`; `execution.approve` /
`execution.reject` answer it, or any other client can call `POST /api/agent/{id}/respond`.

A rejected tool ends the run as COMPLETED with `finish_reason == :rejected`, `result` nil and
the reason on `execution.output['rejectionReason']`.

## Sessions

```ruby
agent.call_sync(question, session_id: 'cust-77')   # same conversation across calls
```

## Fire and forget

`call_async` with no block, keep the `execution_id`, walk away. If the agent has `tool def`
tools they run in *your* process, so it has to stay up. Fire-and-forget only works when every
tool is server-side (http / mcp / human) or you have `deploy`ed the agent and run `serve`
somewhere else.

## Under the hood

`call_async(prompt)`:

1. `POST /api/agent/start` with the serialized `agentConfig`; the reply lists `requiredWorkers`
2. start a worker for every required task this process can serve (your tools, plus
   `<agent>_termination`, custom guardrails, callbacks) with the same TaskDef defaults as Python
3. return an `Execution`; open `GET /api/agent/stream/{id}` (SSE) on a background thread,
   reconnecting with `Last-Event-ID`; fall back to polling `GET /api/agent/{id}/status` if SSE is
   unavailable or `CONDUCTOR_AGENT_STREAMING_ENABLED=false`
4. `tool_call` / `tool_result` events fill `tool_calls`; `waiting` builds an `ApprovalRequest`
5. `done` sets the result and `finish_reason`, fetches token usage, fires the block

`call_sync` is `call_async(prompt).result`.
