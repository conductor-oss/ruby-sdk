# frozen_string_literal: true

# Port of python-sdk/examples/agents/13_hierarchical_agents.py.
# Run: bundle exec ruby -Ilib examples/agents/13_hierarchical_agents.rb
require 'conductor/agents'

module Example13HierarchicalAgents
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    backend_dev = Agent.new(
      name: "backend_dev",
      model: model,
      instructions: "You are a backend developer. You design APIs, databases, and server architecture. Provide technical recommendations with code examples."
    )
    frontend_dev = Agent.new(
      name: "frontend_dev",
      model: model,
      instructions: "You are a frontend developer. You design UI components, user flows, and client-side architecture. Provide recommendations with code examples."
    )
    content_writer = Agent.new(
      name: "content_writer",
      model: model,
      instructions: "You are a content writer. You create blog posts, landing page copy, and marketing materials. Write engaging, clear content."
    )
    seo_specialist = Agent.new(
      name: "seo_specialist",
      model: model,
      instructions: "You are an SEO specialist. You optimize content for search engines, suggest keywords, and improve page rankings."
    )
    engineering_lead = Agent.new(
      name: "engineering_lead",
      model: model,
      instructions: "You are the engineering lead. Route technical questions to the right specialist: backend_dev for APIs/databases/servers, frontend_dev for UI/UX/client-side.",
      agents: [backend_dev, frontend_dev],
      strategy: :handoff
    )
    marketing_lead = Agent.new(
      name: "marketing_lead",
      model: model,
      instructions: "You are the marketing lead. Route marketing questions to the right specialist: content_writer for blog posts/copy, seo_specialist for SEO/keywords/rankings.",
      agents: [content_writer, seo_specialist],
      strategy: :handoff
    )
    ceo = Agent.new(
      name: "ceo",
      model: model,
      instructions: "You are the CEO. Route requests to the right department: engineering_lead for technical/development questions, marketing_lead for marketing/content/SEO questions.",
      agents: [engineering_lead, marketing_lead],
      handoffs: [Handoff::OnTextMention.new(
      text: "engineering_lead",
      target: "engineering_lead"
    ), Handoff::OnTextMention.new(
      text: "marketing_lead",
      target: "marketing_lead"
    )],
      strategy: :swarm
    )
    ceo
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    ceo = build
    executions = []
    execution = runtime.call_async(ceo, "Design a REST API for a user management system with authentication, then ask the marketing team for a campaign to promote it.")
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example13HierarchicalAgents.run
  ensure
    Conductor::Agents.shutdown
  end
end
