# Teams

```ruby
tool def create_issue(title: String, body: '')
  Github.create_issue(title, body, token: secret('GH_TOKEN'))
end

triage = Agent.new(name: 'triage', model: 'openai/gpt-4o-mini',
                   instructions: 'Read the bug report. Say ACTIONABLE if it should be filed.')

filer = Agent.new(name: 'filer', model: 'anthropic/claude-sonnet-4-5',
                  instructions: 'File the bug as a GitHub issue.')
filer.add_tool :create_issue

triage.hands_off_to filer, on: 'ACTIONABLE'

team = Agent.new(name: 'bug_desk')
team.add_agent triage
team.add_agent filer

puts team.call_sync(File.read('report.md'))
```

| Line | Does |
|---|---|
| `filer.add_tool :create_issue` | Give filer a tool. |
| `triage.hands_off_to filer, on: 'ACTIONABLE'` | When triage's answer contains ACTIONABLE, filer takes over. Pass a block/proc as `on:` for a custom condition. |
| `team.add_agent triage` | Give the team a member. First one added starts. `team.add_agents a, b` for several. |
| `Agent.new(name: 'bug_desk')` | No model needed: a team inherits the first member's model (the server requires one on every agent). |

`tools:` and `agents:` still work as keyword arguments in `Agent.new`.

## Strategies

```ruby
team.strategy = :sequential   # one after another
team.strategy = :parallel     # all at once, merged
team.strategy = :swarm        # members transfer to each other via handoffs
team.strategy = :router       # router: agent picks the member
# also :round_robin, :random, :manual (default :handoff)

pipeline = researcher >> writer >> editor   # sequential, named researcher_writer_editor
```

When members declare `hands_off_to` and the team has no explicit strategy, the serializer
makes the team a `swarm` and lists the members' handoffs on the team, which is where the
server reads them. Set a strategy explicitly to keep it.

## Guardrails and stopping

```ruby
filer.redact %w[password api_key]        # scrub these from output before anyone sees it
filer.stop_when 'ISSUE_FILED'            # stop on this text
filer.stop_after messages: 12            # or after this many messages
filer.add_guardrail RegexGuardrail.new('\b\d{3}-\d{2}-\d{4}\b', name: 'no_ssn', on_fail: :raise)
filer.add_guardrail LlmGuardrail.new('openai/gpt-4o-mini', 'No medical advice', on_fail: :retry)
filer.add_guardrail Guardrail.new(name: 'no_pii', on_fail: :retry) { |text| !text.include?('SSN') }
```

`stop_when` / `stop_after` build `Termination::TextMention` / `Termination::MaxMessage` and
combine with `|`; any `Termination::*` condition (also `StopMessage`, `TokenUsage`, `&`, `|`)
can be set directly with `termination:`. The server evaluates them through a
`<agent>_termination` worker this process runs. Custom guardrails with a block also run here;
regex and LLM guardrails run on the server.

## Callbacks

```ruby
class Timing < Conductor::Agents::CallbackHandler
  def on_model_start(messages: nil, **) = (@t0 = Time.now; nil)
  def on_model_end(llm_result: nil, **) = (puts Time.now - @t0; nil)
end
agent.add_callback Timing.new
agent.callback(:before_tool) { |**kw| log kw; nil }
```

Positions: `before_agent after_agent before_model after_model before_tool after_tool`. Each
becomes a `<agent>_<position>` task the server schedules and this process serves. Return a
non-empty Hash to override; nil to continue.

## Underneath

Same Python objects, same `agentConfig`. Sugar only.

| Sugar | Python-parity object |
|---|---|
| `a.add_tool :x` | appends to `Agent#tools`, same array `tools:` fills |
| `team.add_agent a` | appends to `Agent#agents`, same as `agents:` |
| `a.hands_off_to b, on: 'X'` | `Handoff::OnTextMention.new(target: 'b', text: 'X')` |
| `a.redact %w[...]` | `RegexGuardrail.new(..., position: :output, on_fail: :fix)` |
| `a.stop_when 'X'` / `a.stop_after messages: n` | `Termination::TextMention \| Termination::MaxMessage` |
| `a >> b` | `Agent.new(strategy: :sequential, agents: [a, b])` |
