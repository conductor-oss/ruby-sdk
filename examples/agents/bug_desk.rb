#!/usr/bin/env ruby
# frozen_string_literal: true

# Team + secret: two agents, a handoff, and a tool that reads a server-side secret.
#
#   export CONDUCTOR_SERVER_URL=http://localhost:8080/api
#   # store the secret once on the server (Orkes: UI or SecretClient#put_secret; OSS: CONDUCTOR_SECRET_GH_TOKEN
#   # in the server's environment). Locally the SDK falls back to ENV['GH_TOKEN'].
#   bundle exec ruby examples/agents/bug_desk.rb path/to/report.md
require_relative '../../lib/conductor/agents'
include Conductor::Agents

module Github
  def self.create_issue(title, body, token:)
    "https://github.com/example/repo/issues/42 (#{title.length} chars, token #{token[0, 4]}...)"
  end
end

# secret('GH_TOKEN') is both the read and the declaration: the SDK finds the literal at
# `tool def` and tells the server this tool needs GH_TOKEN (TaskDef.runtimeMetadata).
tool def create_issue(title: String, body: '')
  { url: Github.create_issue(title, body, token: secret('GH_TOKEN')) }
end

model = ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini')

triage = Agent.new(
  name: 'triage',
  model: model,
  instructions: 'Read the bug report. Say ACTIONABLE if it should be filed.'
)

filer = Agent.new(
  name: 'filer',
  model: ENV.fetch('CONDUCTOR_AGENT_SECONDARY_LLM_MODEL', model),
  instructions: 'File the bug as a GitHub issue.'
)
filer.add_tool :create_issue
filer.stop_when 'ISSUE_FILED'
filer.stop_after messages: 12

triage.hands_off_to filer, on: 'ACTIONABLE'

team = Agent.new(name: 'bug_desk')
team.add_agent triage
team.add_agent filer

report = ARGV[0] ? File.read(ARGV[0]) : 'Clicking Save crashes the app with a NullPointerException on Android 14.'
puts team.call_sync(report)
Conductor::Agents.shutdown
