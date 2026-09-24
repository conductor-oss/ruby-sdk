# frozen_string_literal: true

# Port of python-sdk/examples/agents/16e_credentials_http_tool.py.
# Run: bundle exec ruby -Ilib examples/agents/16e_credentials_http_tool.rb
require 'conductor/agents'

module Example16eCredentialsHttpTool
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    list_repos = Tool.http(
      "list_github_repos",
      ENV.fetch('GITHUB_REPOS_URL', 'https://api.github.com/users/Conductor/repos?per_page=5&sort=updated'),
      description: "List public GitHub repositories for a user. Returns JSON array with name, url, and stars.",
      headers: { "Authorization" => "Bearer ${GITHUB_TOKEN}", "Accept" => "application/vnd.github.v3+json" },
      credentials: ["GITHUB_TOKEN"]
    )
    agent = Agent.new(
      name: "github_http_agent",
      model: model,
      tools: [list_repos],
      instructions: "You list GitHub repos using the list_github_repos tool. Summarize the results."
    )
    agent
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    agent = build
    executions = []
    execution = runtime.call_async(agent, "List the repos for Conductor")
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example16eCredentialsHttpTool.run
  ensure
    Conductor::Agents.shutdown
  end
end
