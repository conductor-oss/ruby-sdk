#!/usr/bin/env ruby
# frozen_string_literal: true

# HTTP Poll Task Example
#
# Demonstrates using HTTP_POLL task to poll an external API
# until a condition is met or timeout occurs.
#
# Usage:
#   bundle exec ruby examples/orkes/http_poll.rb

require_relative '../../lib/conductor'

include Conductor::Workflow

def create_http_poll_workflow(workflow_client, workflow_executor)
  workflow = ConductorWorkflow.new(
    workflow_client,
    'http_poll_workflow_ruby',
    version: 1,
    executor: workflow_executor
  )
  workflow.description('Workflow demonstrating HTTP polling')

  # HTTP Poll task - polls until condition is met
  poll_task = HttpPollTask.new('poll_status', {
    'uri' => 'https://httpbin.org/json',
    'method' => 'GET',
    'connectionTimeOut' => 5000,
    'readTimeOut' => 5000
  })
  poll_task.input('terminalCondition', '$.slideshow != null')
  poll_task.input('pollingInterval', 2)
  poll_task.input('pollingStrategy', 'FIXED')

  # Process the result
  process = SimpleTask.new('process_result', 'process_ref')
    .input('data', poll_task.output('response'))

  workflow >> poll_task >> process
  workflow.output_parameter('result', process.output)

  workflow
end

def main
  config = Conductor::Configuration.new

  puts '=' * 70
  puts 'HTTP Poll Task Example'
  puts '=' * 70
  puts "Server: #{config.server_url}"
  puts

  clients = Conductor::Orkes::OrkesClients.new(config)
  workflow_executor = clients.get_workflow_executor
  workflow_client = clients.get_workflow_client

  workflow = create_http_poll_workflow(workflow_client, workflow_executor)
  workflow_executor.register_workflow(workflow, overwrite: true)
  puts "Registered workflow: #{workflow.name}"

  puts "\nExecuting HTTP poll workflow..."
  result = workflow_executor.execute(
    workflow.name,
    input: {},
    wait_for_seconds: 30
  )

  puts "Status: #{result.status}"
  puts "Output: #{result.output.inspect}"
  puts "\nView at: #{config.ui_host}/execution/#{result.workflow_id}"
end

if __FILE__ == $PROGRAM_NAME
  begin
    main
  rescue Conductor::ApiError => e
    puts "API Error: #{e.message}"
  rescue StandardError => e
    puts "Error: #{e.message}"
  end
end
