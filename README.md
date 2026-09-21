# Conductor Ruby SDK

Ruby clients, workflow definitions, workers, and agents for [Conductor](https://github.com/conductor-oss/conductor).
Requires Ruby 3.0 or newer.

## Install

```ruby
gem 'conductor_ruby'
```

Set `CONDUCTOR_SERVER_URL` to your server's API URL (for example,
`http://localhost:8080/api`). For authenticated servers, also set
`CONDUCTOR_AUTH_KEY` and `CONDUCTOR_AUTH_SECRET`.

## Start a workflow

This starts an existing workflow definition on your server:

```ruby
require 'conductor'

client = Conductor::Client::WorkflowClient.new(Conductor::Configuration.new)
workflow_id = client.start('my_workflow', input: { 'name' => 'Ruby' })
puts workflow_id
```

## Examples

- [Workflow DSL](examples/workflow_dsl.rb)
- [Worker configuration](examples/worker_configuration_example.rb)
- [Task context](examples/task_context_example.rb) and [event listeners](examples/task_listener_example.rb)
- [Agents](examples/agents/): tools, streaming, approvals, guardrails, and teams

To run an agent example from this checkout, configure an LLM integration on your
Conductor server, then run:

```bash
bundle install
CONDUCTOR_AGENT_LLM_MODEL=openai/gpt-4o-mini \
  bundle exec ruby -Ilib examples/agents/01_basic_agent.rb
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for development commands and
[CHANGELOG.md](CHANGELOG.md) for release history. Licensed under [Apache 2.0](LICENSE).
