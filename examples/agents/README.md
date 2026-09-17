# Agent examples

These are standalone Ruby ports of the [Python agent examples](https://github.com/conductor-oss/python-sdk/tree/c99e2cf9871c21f7a64d823126ee1b77989b00ad/examples/agents).
Each file contains its own tools, agents, and prompts. Run or copy that file; no test harness is required.

```bash
bundle install
export CONDUCTOR_SERVER_URL=http://localhost:8080/api
export CONDUCTOR_AGENT_LLM_MODEL=openai/gpt-4o-mini
bundle exec ruby -Ilib examples/agents/01_basic_agent.rb
```

Configure the selected LLM integration on the server. The SDK uses the usual
`CONDUCTOR_AUTH_KEY` / `CONDUCTOR_AUTH_SECRET` settings when authentication is required.

| File | Demonstrates |
|---|---|
| [01_basic_agent.rb](01_basic_agent.rb) | Basic question and answer |
| [02a_simple_tools.rb](02a_simple_tools.rb) | Local Ruby tools |
| [02c_tool_retry_config.rb](02c_tool_retry_config.rb) | Task retry policies |
| [04_http_and_mcp_tools.rb](04_http_and_mcp_tools.rb) | HTTP and discovered MCP tools |
| [05_handoffs.rb](05_handoffs.rb) | Agent handoffs |
| [06_sequential_pipeline.rb](06_sequential_pipeline.rb) | Sequential team |
| [07_parallel_agents.rb](07_parallel_agents.rb) | Parallel team |
| [09_human_in_the_loop.rb](09_human_in_the_loop.rb) | Interactive approval and feedback |
| [09c_hitl_streaming.rb](09c_hitl_streaming.rb) | Streaming events and interactive approval |
| [103_plan_and_compile.rb](103_plan_and_compile.rb) | Planner, compiled workflow, and recovery agent |
| [10_guardrails.rb](10_guardrails.rb) | Ruby guardrail functions |
| [13_hierarchical_agents.rb](13_hierarchical_agents.rb) | Nested agent teams |
| [17_swarm_orchestration.rb](17_swarm_orchestration.rb) | Swarm routing |
| [21_regex_guardrails.rb](21_regex_guardrails.rb) | Regex redaction and validation |
| [22_llm_guardrails.rb](22_llm_guardrails.rb) | LLM validation and expected rejection |
| [64_swarm_with_tools.rb](64_swarm_with_tools.rb) | Swarm members with worker tools |
| [66_handoff_to_parallel.rb](66_handoff_to_parallel.rb) | Handoff into a parallel team |
| [33_external_workers.rb](33_external_workers.rb) | External services and one local formatting tool |
| [16e_credentials_http_tool.rb](16e_credentials_http_tool.rb) | Server-side HTTP credential substitution |

For `04`, run `mcp-testkit==1.0.4 --transport http --auth ...` on port 3001 and
configure `MCP_TEST_API_KEY` and `HTTP_TEST_API_KEY` in the server secret store.
For `16e`, configure `GITHUB_TOKEN` in the server secret store. `GITHUB_REPOS_URL`
can override the GitHub URL when using a local test dependency.
For `33`, start `bundle exec ruby -Ilib examples/agents/external_workers.rb` in another
terminal. Its three worker services run independently of the example runtime.
The two approval examples read their response fields from stdin. Example `22` deliberately
uses strict guardrails: its recorded outcome is a verified content-safety rejection.

## Playback integration suite

[The integration wrapper](../../spec/integration/agents/examples_spec.rb) requires these
files through the filename-only [catalog](catalog.rb) and calls their `run` methods.
It never redefines agents, tools, or prompts. It supplies approval input, checks final states,
and inspects persisted tasks for mock LLM execution, approvals, guards, compiled factorial
tasks, and external workers.

[CI](../../.github/workflows/agents-playback.yml) builds Conductor from
`feature/llm_mock_impl`, uses that branch's unchanged shared recordings,
and invokes its `check-playback` composite action from the same branch. Local verification
used branch head `acb7d27750e5dacc6a6334ed0bcabe3ade030533`. The test server uses a fresh SQLite database.
HTTP/MCP services are real local dependencies; the HTTP fixture returns the recorded GitHub
response and validates the substituted dummy bearer credential. No provider keys are needed.

To reproduce with Java 21, Ruby 3.3, Python, and `mcp-testkit==1.0.4` installed:

```bash
# In a separate Conductor checkout at the feature branch revision:
./gradlew --no-daemon :conductor-server:bootJar -x test

# Back in ruby-sdk; use a new work directory for every run:
export CONDUCTOR_PLAYBACK_WORK_DIR="$PWD/tmp/agent-playback"
export CONDUCTOR_SERVER_URL=http://localhost:18080/api
export CONDUCTOR_AGENT_LLM_MODEL=mock/mockLLM
export CONDUCTOR_AGENTS_PLAYBACK=true
export GITHUB_REPOS_URL='http://localhost:3002/users/Conductor/repos?per_page=5&sort=updated'
bash .github/scripts/start-agent-playback.sh /path/to/conductor
bundle exec ruby -Ilib examples/agents/external_workers.rb > "$CONDUCTOR_PLAYBACK_WORK_DIR/workers.log" 2>&1 &
echo $! > "$CONDUCTOR_PLAYBACK_WORK_DIR/workers.pid"
bundle exec rspec spec/integration/agents/ --format documentation
sh /path/to/conductor/.github/actions/check-playback/check-playback.sh "$CONDUCTOR_SERVER_URL"

# Stop only the services started for this run:
for file in "$CONDUCTOR_PLAYBACK_WORK_DIR"/*.pid; do
  kill "$(cat "$file")" 2>/dev/null || true
done
```

The shared check requires all 93 recordings to be consumed and zero unmatched LLM requests.
The GitHub action has been configured; its verifier was also run locally after all 19 tests passed.
WireMock replay remains a separate transport test; it is not a substitute for this suite.
