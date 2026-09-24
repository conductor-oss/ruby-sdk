# Termination

```ruby
agent.stop_when('DONE')
agent.stop_after(messages: 20)
agent.termination = Termination::TokenUsage.new(max_total_tokens: 50_000) |
                    Termination::TextMention.new('DONE')
```

Conditions: `Termination::MaxMessage`, `StopMessage`, `TextMention`,
`TokenUsage`. Combine with `&` and `|`. Always set `max_turns:` too.

Stop a running execution with `execution.stop` or `AgentClient#stop`. Stopping
does not undo a tool call that already ran.
