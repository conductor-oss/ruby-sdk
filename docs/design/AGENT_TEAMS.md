# Teams

```ruby
require 'conductor/agents'
include Conductor::Agents

tool def create_issue(title: String, body: '')
  Github.create_issue(title, body, token: secret('GH_TOKEN'))
end

triage = Agent.new(
  name: 'triage',
  model: 'openai/gpt-4o-mini',
  instructions: 'Read the bug report. Say ACTIONABLE if it should be filed.'
)

filer = Agent.new(
  name: 'filer',
  model: 'anthropic/claude-sonnet-4-5',
  instructions: 'File the bug as a GitHub issue.'
)
filer.add_tool :create_issue

triage.hands_off_to filer, on: 'ACTIONABLE'

team = Agent.new(name: 'bug_desk')
team.add_agent triage
team.add_agent filer

puts team.call_sync(File.read('report.md'))
```

Make the agent. Then give it things.

| Line | Does |
|---|---|
| `filer.add_tool :create_issue` | Give filer a tool. |
| `triage.hands_off_to filer, on: 'ACTIONABLE'` | When triage's answer contains ACTIONABLE, filer takes over. |
| `team.add_agent triage` | Give the team a member. First one added starts. `team.add_agents a, b` for several. |
| `secret('GH_TOKEN')` | Reads the secret — and declares it: the SDK sees the literal at `tool def` and tells the server this tool needs GH_TOKEN. Store it once with `conductor secrets put GH_TOKEN ghp_...`. Never in your code or env. |

`tools:` and `agents:` still work as keyword args in `Agent.new` if you already have the list.
Same object either way.

## If you need them

```ruby
filer.redact %w[password api_key]       # scrub these from output before anyone sees it
filer.stop_when 'ISSUE_FILED'           # stop on this text
filer.stop_after messages: 12           # or after this many messages

team.strategy = :sequential             # one after another (default is handoff)
team.strategy = :parallel               # all at once, merged
```

## Underneath

Same Python objects, same `agentConfig`. Sugar only.

| Sugar | Python-parity object |
|---|---|
| `a.add_tool :x` | appends to `Agent#tools`, same array `tools:` fills |
| `team.add_agent a` | appends to `Agent#agents`, same as `agents:` |
| `a.hands_off_to b, on: 'X'` | `handoffs: [Handoff::OnTextMention.new(target: 'b', text: 'X')]` |
| `a.redact %w[...]` | `guardrails: [RegexGuardrail.new(..., position: :output, on_fail: :fix)]` |
| `a.stop_when 'X'` / `a.stop_after messages: n` | `termination: TextMention \| MaxMessage` |
| `secret('X')` | at `tool def`: AST scan adds `X` to `ToolDef#credentials` → `TaskDef.runtimeMetadata` / `tool.config.credentials`. At run: reads `Task.runtimeMetadata['X']` (fiber-local). Same wire contract as Python `credentials=[...]` + `get_secret` |
| `Agent.new(name: 'bug_desk')` + `add_agent` | `strategy: :handoff` default |
