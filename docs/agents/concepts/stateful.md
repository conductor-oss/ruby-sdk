# Stateful agents

```ruby
agent = Agent.new(name: 'chat', model: 'openai/gpt-4o-mini', stateful: true,
                  memory: ConversationMemory.new(max_messages: 50))
agent.call_sync('Hi, I am Ana.', session_id: 'user-42')
agent.call_sync('What is my name?', session_id: 'user-42')
```

`stateful: true` keeps conversation state on the server per `session_id:` and
pins the run's tool workers to its own task domain. After a process restart,
`Execution.find(execution_id)` reattaches.

Bound context with `max_messages:` rather than growing the prompt.
