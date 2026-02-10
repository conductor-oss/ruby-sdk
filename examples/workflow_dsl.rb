#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Using the Conductor Ruby SDK Workflow DSL
#
# This example demonstrates how to define workflows programmatically using
# the Ruby DSL, which provides a clean and expressive way to build workflows.
#
# Run with: bundle exec ruby examples/workflow_dsl.rb

require_relative '../lib/conductor'

# Configuration - uses environment variables or defaults
# The Configuration class automatically reads CONDUCTOR_SERVER_URL from environment
# or you can pass server_api_url directly to the constructor
config = Conductor::Configuration.new(
  server_api_url: ENV.fetch('CONDUCTOR_SERVER_URL', 'http://localhost:7001/api')
)

# Create a workflow client
workflow_client = Conductor::Client::WorkflowClient.new(config)

# ============================================================================
# Example 1: Simple Sequential Workflow
# ============================================================================
puts '=== Example 1: Simple Sequential Workflow ==='

# Include the Workflow module for shorter class names
include Conductor::Workflow

# Create a workflow with basic configuration
simple_workflow = ConductorWorkflow.new(workflow_client, 'ruby_simple_workflow', version: 1)
                                   .description('A simple sequential workflow created with Ruby DSL')
                                   .timeout_seconds(3600)
                                   .owner_email('developer@example.com')

# Define tasks
task1 = SimpleTask.new('greet_user', 'greet_ref')
                  .input('name', '${workflow.input.userName}')

task2 = SimpleTask.new('process_greeting', 'process_ref')
                  .input('greeting', '${greet_ref.output.message}')

# Add tasks to workflow using >> operator
simple_workflow >> task1 >> task2

# Set workflow output
simple_workflow.output_parameter('result', '${process_ref.output.result}')

# Print the workflow definition
puts "Workflow: #{simple_workflow.name}"
puts "Tasks: #{simple_workflow.tasks.map(&:task_reference_name).join(' -> ')}"
puts ''

# ============================================================================
# Example 2: Parallel Execution with Fork-Join
# ============================================================================
puts '=== Example 2: Parallel Execution with Fork-Join ==='

parallel_workflow = ConductorWorkflow.new(workflow_client, 'ruby_parallel_workflow', version: 1)
                                     .description('Workflow with parallel task execution')
                                     .timeout_seconds(300)

# Initial task
fetch_data = SimpleTask.new('fetch_data', 'fetch_ref')
                       .input('source', '${workflow.input.dataSource}')

# Parallel processing tasks (two branches)
process_a = SimpleTask.new('process_type_a', 'process_a_ref')
                      .input('data', '${fetch_ref.output.data}')

process_b = SimpleTask.new('process_type_b', 'process_b_ref')
                      .input('data', '${fetch_ref.output.data}')

# Aggregation task
aggregate = SimpleTask.new('aggregate_results', 'aggregate_ref')
                      .input('resultA', '${process_a_ref.output.result}')
                      .input('resultB', '${process_b_ref.output.result}')

# Build workflow: fetch -> [process_a, process_b] (parallel) -> aggregate
parallel_workflow >> fetch_data
parallel_workflow >> [[process_a], [process_b]] # Fork-join with two branches
parallel_workflow >> aggregate

puts "Workflow: #{parallel_workflow.name}"
puts "Task count: #{parallel_workflow.tasks.length} (includes fork task)"
puts ''

# ============================================================================
# Example 3: Conditional Branching with Switch
# ============================================================================
puts '=== Example 3: Conditional Branching with Switch ==='

conditional_workflow = ConductorWorkflow.new(workflow_client, 'ruby_conditional_workflow', version: 1)
                                        .description('Workflow with conditional branching')

# Determine the type
classify = SimpleTask.new('classify_request', 'classify_ref')
                     .input('request', '${workflow.input.request}')

# Different handlers for each type
handle_type_a = SimpleTask.new('handle_type_a', 'handle_a_ref')
                          .input('data', '${classify_ref.output.data}')

handle_type_b = SimpleTask.new('handle_type_b', 'handle_b_ref')
                          .input('data', '${classify_ref.output.data}')

handle_default = SimpleTask.new('handle_default', 'handle_default_ref')
                           .input('data', '${classify_ref.output.data}')

# Create switch task
switch = SwitchTask.new('route_by_type', '${classify_ref.output.requestType}')
                   .switch_case('TYPE_A', [handle_type_a])
                   .switch_case('TYPE_B', [handle_type_b])
                   .default_case([handle_default])

# Build workflow
conditional_workflow >> classify >> switch

puts "Workflow: #{conditional_workflow.name}"
puts 'Switch cases: TYPE_A, TYPE_B, default'
puts ''

# ============================================================================
# Example 4: HTTP Task
# ============================================================================
puts '=== Example 4: HTTP Task ==='

http_workflow = ConductorWorkflow.new(workflow_client, 'ruby_http_workflow', version: 1)
                                 .description('Workflow with HTTP calls')

# HTTP task with configuration
api_call = HttpTask.new('call_api', {
                          'uri' => 'https://api.example.com/users/${workflow.input.userId}',
                          'method' => 'GET',
                          'headers' => {
                            'Authorization' => ['Bearer ${workflow.input.token}']
                          }
                        })

# Process the response
process_response = SimpleTask.new('process_response', 'process_api_ref')
                             .input('statusCode', api_call.status_code)
                             .input('body', api_call.body)

http_workflow >> api_call >> process_response

puts "Workflow: #{http_workflow.name}"
puts 'HTTP endpoint: api.example.com/users'
puts ''

# ============================================================================
# Example 5: Sub-Workflow Task
# ============================================================================
puts '=== Example 5: Sub-Workflow Task ==='

# Parent workflow that calls a child workflow
parent_workflow = ConductorWorkflow.new(workflow_client, 'ruby_parent_workflow', version: 1)
                                   .description('Parent workflow that calls a sub-workflow')

prepare_data = SimpleTask.new('prepare_data', 'prepare_ref')
                         .input('input', '${workflow.input.data}')

# Call an existing workflow as a sub-workflow
call_child = SubWorkflowTask.new('call_child', 'child_workflow_name', version: 1)
                            .input('data', '${prepare_ref.output.preparedData}')

process_child_result = SimpleTask.new('process_child_result', 'process_child_ref')
                                 .input('childOutput', '${call_child.output}')

parent_workflow >> prepare_data >> call_child >> process_child_result

puts "Workflow: #{parent_workflow.name}"
puts 'Calls sub-workflow: child_workflow_name'
puts ''

# ============================================================================
# Example 6: Complete Workflow with Registration (commented out)
# ============================================================================
puts '=== Example 6: Complete Workflow Ready for Registration ==='

complete_workflow = ConductorWorkflow.new(workflow_client, 'ruby_complete_example', version: 1)
                                     .description('Complete example workflow demonstrating all features')
                                     .timeout_seconds(7200)
                                     .owner_email('team@example.com')
                                     .input_parameters(%w[userId action])
                                     .variables({ 'processedCount' => 0 })

# Define all tasks
init_task = SimpleTask.new('initialize', 'init_ref')
                      .input('userId', complete_workflow.input('userId'))

validate_task = SimpleTask.new('validate_input', 'validate_ref')
                          .input('data', '${init_ref.output}')

process_task = SimpleTask.new('process_action', 'process_ref')
                         .input('validatedData', '${validate_ref.output}')

notify_task = SimpleTask.new('notify_user', 'notify_ref')
                        .input('userId', complete_workflow.input('userId'))
                        .input('result', '${process_ref.output.result}')

# Build the workflow
complete_workflow >> init_task >> validate_task >> process_task >> notify_task

# Set output parameters
complete_workflow
  .output_parameter('status', '${notify_ref.output.status}')
  .output_parameter('completedAt', '${notify_ref.output.timestamp}')

puts "Workflow: #{complete_workflow.name}"
puts 'Input parameters: userId, action'
puts 'Output parameters: status, completedAt'
puts ''

# Convert to workflow definition (for inspection)
workflow_def = complete_workflow.to_workflow_def
puts 'Workflow Definition:'
puts "  Name: #{workflow_def.name}"
puts "  Version: #{workflow_def.version}"
puts "  Task count: #{workflow_def.tasks.length}"
puts "  Timeout: #{workflow_def.timeout_seconds} seconds"
puts ''

# ============================================================================
# To Register and Run (uncomment when Conductor server is running)
# ============================================================================
# puts '=== Registering and Starting Workflow ==='
#
# begin
#   # Register the workflow definition
#   complete_workflow.register(overwrite: true)
#   puts "Workflow '#{complete_workflow.name}' registered successfully!"
#
#   # Start a workflow instance
#   workflow_id = complete_workflow.start_workflow_with_input(
#     input: {
#       'userId' => 'user123',
#       'action' => 'process'
#     }
#   )
#   puts "Workflow started with ID: #{workflow_id}"
#
#   # Get workflow status
#   status = workflow_client.get_workflow(workflow_id)
#   puts "Workflow status: #{status['status']}"
# rescue Conductor::ApiError => e
#   puts "API Error: #{e.message}"
# end

puts 'Examples completed!'
puts ''
puts 'To run workflows against a Conductor server:'
puts '1. Ensure Conductor is running at http://localhost:7001'
puts '2. Uncomment the registration/start section above'
puts '3. Run: bundle exec ruby examples/workflow_dsl.rb'
