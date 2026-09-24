#!/usr/bin/env ruby
# frozen_string_literal: true

# Streaming + approval: a tool that waits for a human decision before it runs.
#
#   export CONDUCTOR_SERVER_URL=http://localhost:8080/api
#   bundle exec ruby examples/agents/support_approval.rb
require_relative '../../lib/conductor/agents'
include Conductor::Agents

module Billing
  def self.refund(order_id, amount)
    "Refunded #{amount} for order #{order_id}"
  end
end

tool def issue_refund(order_id: String, amount: Float)
  { message: Billing.refund(order_id, amount) }
end
requires_approval :issue_refund

agent = Agent.new(
  name: 'support',
  model: ENV.fetch('CONDUCTOR_AGENT_LLM_MODEL', 'anthropic/claude-sonnet-4-5'),
  instructions: 'Help with orders.'
)
agent.add_tool :issue_refund

# Decide approval-required tool calls. `request` exposes the tool's arguments as methods.
agent.on_approval do |request|
  puts "approval requested: #{request.tool_name} #{request.arguments}"
  request.amount < 100 ? request.approve : request.reject('Needs a manager')
end

# Blocking
answer = agent.call_sync('Refund order A-1029, it arrived broken. It cost 49 dollars.')
puts answer

# Non-blocking with a callback when finished
agent.call_async('Refund order B-2, it cost 4900 dollars.') do |answer, execution|
  puts "finished (#{execution.finish_reason}): #{answer.inspect}"
end

# Non-blocking, poll it yourself
execution = agent.call_async('Refund order C-3, it cost 12 dollars.')
sleep 0.5 until execution.done?
puts execution.result
puts "finish_reason: #{execution.finish_reason}"       # :stop, or :rejected if the tool was rejected
puts "tool calls: #{execution.tool_calls.inspect}"

Conductor::Agents.shutdown
