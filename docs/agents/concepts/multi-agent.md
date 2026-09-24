# Multi-agent

```ruby
team = Agent.new(name: 'support', model: 'openai/gpt-4o-mini',
                 agents: [billing, shipping], strategy: :handoff)
pipeline = researcher >> writer >> editor          # sequential
```

Strategies: `:sequential`, `:parallel`, `:handoff` (default; the model picks a
specialist), `:router` (a `router:` agent picks), `:swarm`, `:round_robin`,
`:random`, `:manual`, `:plan_execute`.

- `a.hands_off_to(b, on: 'billing')` hands off when the text appears; `on:` also
  takes a callable.
- `Tool.agent(child)` calls a child and returns its answer to the parent
  instead of transferring control.
- `plan_execute(name:, tools:, model:, planner_instructions:, fallback_instructions:, fallback_max_turns:)`
  builds a planner that writes a plan executed as a durable sub-workflow.

Every open-ended design needs `max_turns:` and a [termination](termination.md)
condition. Each child appears in the execution history.
