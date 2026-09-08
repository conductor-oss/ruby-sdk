# Testing strategy

How we test the agents SDK. The mocking layer is shared by every Conductor SDK — agentic and
plain-workflow tests alike; Ruby is the first adopter. WireMock records a real server once;
WireMock replays it in CI. No SDK ships a custom mock server.

## Contract tests — no server

Serializing a Ruby agent must produce exactly what the server (and Python) expect:

```ruby
expect(JSONSchemer.schema(AGENT_SCHEMA).valid?(config)).to be true
expect(ConfigSerializer.serialize(agent)).to eq JSON.parse(fixture('05_handoffs.json'))
```

Fixtures vendored from python-sdk (`agent-schema.json`, the 19 golden `_configs/*.json`),
plus unit specs for schema generation, secret scanning, and serialization. This is also what
makes shared mocks work: replay matches by verb + path + order, so one recording serves every
SDK precisely because the SDKs send equivalent requests.

## Runtime tests — record once, replay everywhere

To create or refresh a recording:

1. Run a Conductor server locally (docker, `localhost:8080`) with real provider keys
   configured as integrations.
2. Run your SDK's test suite as usual, with the two record env vars set. Ruby example:

   ```
   CONDUCTOR_RECORD=1 \
   CONDUCTOR_RECORD_URL=http://localhost:8080 \
   bundle exec rspec spec/agents
   ```

   `CONDUCTOR_RECORD=1` switches the test helper into record mode: it boots WireMock between
   the SDK and your server. `CONDUCTOR_RECORD_URL` says where your server is (shown value is
   the default).
3. The test executes for real — the server calls the actual LLM, your tool methods run.
4. On green, WireMock has saved every response your server sent. A cleanup script swaps
   run-specific values (execution ids, timestamps) for placeholders so the recording replays
   for anyone.
5. The cleaned files are a scenario folder — open a PR to
   [conductor-mocks](https://github.com/conductor-oss/conductor-mocks) with it.

```
mocks/
  agent/tool_happy_path/
  agent/approval_approve/
  agent/approval_reject/
  agent/secrets_runtime_metadata/
  agent/team_handoff/
  agent/mcp_discovery/
  workflow/simple_task/
  workflow/dynamic_fork/
```

Re-recording is manual, and happens when we bump the supported server version — a re-record
is a reviewable diff.

```
record   spec <-> WireMock proxy <-> your conductor-oss <-> REAL model
                   \-> normalized mappings -> conductor-mocks

replay   spec <-> wiremock/wiremock container + scenario mappings
                   no conductor, no LLM, no keys
```

In CI, the replayer is WireMock itself. Scenario states keep responses in recorded order;
`POST /tasks` only matches the stub with the recorded body, so a wrong tool result matches
nothing; any unmatched request fails the run. WireMock buffers SSE — fine, because an agent
stream terminates at `done`, so the captured body is complete. Recorded model text is that
day's output, so tests assert structure (`finish_reason`, tool args), not prose.

### The weather test (Ruby)

```ruby
RSpec.describe 'weather agent', mocks: 'agent/tool_happy_path' do
  tool def get_weather(city: String, units: 'metric')
    { temp_c: 21.0, summary: "Sunny in #{city}" }
  end

  it 'answers with the tool' do
    agent = Agent.new(name: 'weather', model: 'openai/gpt-4o',
                      instructions: 'Answer weather questions.')
    agent.add_tool :get_weather
    expect(agent.call_sync('Weather in Lisbon?')).to include('Lisbon')
  end
end
```

The `mocks:` tag boots WireMock with that scenario and points the SDK at it.

## CI wiring

Each SDK's workflow checks out conductor-mocks and starts the official image — every push,
fork PRs included:

```yaml
- uses: actions/checkout@v4
  with: { repository: conductor-oss/conductor-mocks, path: conductor-mocks }
- run: docker run -d -p 8080:8080
         -v $PWD/conductor-mocks/mocks/agent/tool_happy_path:/home/wiremock
         wiremock/wiremock:3x
- run: CONDUCTOR_SERVER_URL=http://localhost:8080/api bundle exec rspec spec/agents
```

conductor-mocks PRs are reviewed by the conductor-oss team; nothing replay serves was
invented by hand, and no SDK internals are ever stubbed. (Housekeeping: drop the unused
vcr/webmock dev deps from this repo.)
