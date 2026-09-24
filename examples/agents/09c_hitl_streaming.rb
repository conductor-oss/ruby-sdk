# frozen_string_literal: true

# Port of python-sdk/examples/agents/09c_hitl_streaming.py.
# Run: bundle exec ruby -Ilib examples/agents/09c_hitl_streaming.rb
require 'conductor/agents'

module Example09cHitlStreaming
  include Conductor::Agents
  extend Conductor::Agents::Tools

  def check_service(service_name: String)
    { service: service_name, status: "unhealthy", uptime: "0m" }
  end
  tool :check_service, description: "Check the health of a service."

  def restart_service(service_name: String)
    { service: service_name, status: "restarted", new_uptime: "0m" }
  end
  tool :restart_service, description: "Restart a service. Safe operation, no approval needed."

  def delete_service_data(service_name: String, data_type: String)
    { service: service_name, data_type: data_type, status: "deleted" }
  end
  tool :delete_service_data, description: "Delete service data. Destructive — requires human approval." , approval_required: true

  def self.build(model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'openai/gpt-4o-mini'))
    agent = Agent.new(
      name: "ops_agent",
      model: model,
      tools: [self[:check_service], self[:restart_service], self[:delete_service_data]],
      instructions: "You are an operations assistant. Work through the request one tool call at a time, in this order:\n1. Check the service with check_service.\n2. If it is unhealthy, restart it with restart_service.\n3. Last, if the user asked you to clear or delete data, call delete_service_data.\nA human approves the deletion, not you — delete_service_data pauses for that approval by itself, so never ask for approval in your own reply."
    )
    agent
  end

  def self.run(runtime: Conductor::Agents.runtime, input: $stdin, output: $stdout)
    agent = build
    agent.on_approval do |request|
      output.puts "Approval requested: #{request.tool_calls}"
      response = {}
      request.response_schema.fetch('properties').each do |field, schema|
        output.print "#{schema['description'] || schema['title'] || field}: "
        answer = input.gets
        raise EOFError, "No response supplied for #{field}" unless answer

        response[field] = schema['type'] == 'boolean' ? %w[y yes].include?(answer.strip.downcase) : answer.strip
      end
      request.respond(response)
    end
    executions = []
    on_event = ->(event) { output.puts "[#{event['event']}] #{event['data']}" }
    execution = runtime.call_async(agent, "The payments service is down. Check it, restart it, and clear its stale cache data.", on_event: on_event)
    output.puts execution.result(timeout: 180)
    executions << execution
    executions
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Example09cHitlStreaming.run
  ensure
    Conductor::Agents.shutdown
  end
end
