#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple example demonstrating basic workflow operations with Conductor Ruby SDK
#
# Prerequisites:
# 1. Conductor server running on localhost:7001 (OSS version)
# 2. Bundle install completed
#
# Usage:
#   bundle exec ruby examples/simple_workflow.rb

require_relative '../lib/conductor'

puts '=' * 60
puts 'Conductor Ruby SDK - Simple Workflow Example'
puts '=' * 60

# Configure Conductor client
config = Conductor::Configuration.new(
  server_api_url: 'http://localhost:7001/api'
)

puts "\nConnecting to Conductor server at: #{config.server_url}"

# Create workflow client
workflow_client = Conductor::Client::WorkflowClient.new(config)

puts 'Workflow client created successfully!'

# Example 1: Start a workflow
puts "\n[Example 1] Starting a workflow..."
begin
  request = Conductor::Http::Models::StartWorkflowRequest.new(
    name: 'my_workflow',
    version: 1,
    input: {
      'param1' => 'value1',
      'param2' => 42
    }
  )

  workflow_id = workflow_client.start_workflow(request)
  puts "  ✓ Workflow started with ID: #{workflow_id}"

  # Get workflow status
  puts "\n[Example 2] Getting workflow status..."
  workflow = workflow_client.get_workflow(workflow_id)
  puts "  ✓ Workflow status: #{begin
    workflow['status']
  rescue StandardError
    'N/A'
  end}"
rescue Conductor::ApiError => e
  puts "  ✗ Error: #{e.message}"
  puts "  Note: Make sure the workflow 'my_workflow' is registered in Conductor"
end

# Example 3: Using convenience method
puts "\n[Example 3] Starting workflow with convenience method..."
begin
  workflow_id = workflow_client.start(
    'my_workflow',
    input: { 'key' => 'value' },
    correlation_id: 'example-123'
  )
  puts "  ✓ Workflow started with ID: #{workflow_id}"
rescue Conductor::ApiError => e
  puts "  ✗ Error: #{e.message}"
end

# Example 4: Task result creation
puts "\n[Example 4] Creating task results..."
result = Conductor::Http::Models::TaskResult.complete
result.add_output_data('result', 'success')
result.log('Task completed successfully')
puts "  ✓ Task result created with status: #{result.status}"
puts "  ✓ Output data: #{result.output_data.inspect}"
puts "  ✓ Logs: #{result.logs.inspect}"

# Example 5: WorkflowStatus constants
puts "\n[Example 5] Workflow status constants..."
puts "  All statuses: #{Conductor::Http::Models::WorkflowStatusConstants::ALL.join(', ')}"
puts "  Running? #{Conductor::Http::Models::WorkflowStatusConstants.running?('RUNNING')}"
puts "  Terminal? #{Conductor::Http::Models::WorkflowStatusConstants.terminal?('COMPLETED')}"

puts "\n#{'=' * 60}"
puts 'Example completed!'
puts '=' * 60
