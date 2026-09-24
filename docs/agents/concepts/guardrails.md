# Guardrails

Guardrails check input or output before the next step.

```ruby
no_pii = Guardrail.new(name: 'no_pii', position: :output, on_fail: :retry) do |content|
  GuardrailResult.new(passed: !content.match?(/\d{3}-\d{2}-\d{4}/), message: 'SSN found')
end

agent = Agent.new(name: 'assistant', model: 'openai/gpt-4o-mini', guardrails: [
  RegexGuardrail.new([/\S+@\S+/], mode: :block, position: :output),
  LlmGuardrail.new('openai/gpt-4o-mini', 'No medical advice.'),
  no_pii
])
agent.redact(%w[password token])   # shortcut for a blocking regex guardrail
```

`on_fail:` is `:raise`, `:retry` (up to `max_retries:`), `:fix`, or `:human`.
Retry only when a new model response could plausibly pass.

Use `RegexGuardrail` for format checks, `LlmGuardrail` for policy, and a block
only when the rule needs application state. Put a guardrail on a `ToolDef`
(`guardrails:`) when it protects one side effect. Don't send secrets to an LLM
guardrail. Decisions show up in the execution history.
