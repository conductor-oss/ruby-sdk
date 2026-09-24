# Structured output

```ruby
agent = Agent.new(name: 'extract', model: 'openai/gpt-4o-mini',
                  instructions: 'Extract the invoice.',
                  output_type: { 'type' => 'object',
                                 'properties' => { 'total' => { 'type' => 'number' } },
                                 'required' => ['total'] })
execution = agent.call_async(text)
execution.result
execution.output   # => { 'total' => 42.0 }
```

`output_type:` is a JSON Schema hash, or any object with `to_json_schema`. The
server validates the final answer; on failure the run errors rather than
returning malformed data. Keep the schema small and ask for the same shape in
the instructions.
