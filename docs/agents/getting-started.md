# Getting started

```shell
gem install conductor_ruby
export CONDUCTOR_SERVER_URL=http://localhost:8080/api
export CONDUCTOR_AGENT_LLM_MODEL=openai/gpt-4o-mini
```

Set `CONDUCTOR_AUTH_KEY` and `CONDUCTOR_AUTH_SECRET` for authenticated servers.
The LLM provider is configured on the server, not in your code.

```ruby
require 'conductor/agents'
include Conductor::Agents

agent = Agent.new(name: 'greeter', model: 'openai/gpt-4o-mini',
                  instructions: 'You are a friendly assistant.')
puts agent.call_sync('Say hello.')
Conductor::Agents.shutdown
```

Or run the checked-in version:

```shell
bundle exec ruby -Ilib examples/agents/01_basic_agent.rb
```

A model error means the provider is not set up on the server. A connection error
means `CONDUCTOR_SERVER_URL` is wrong.
