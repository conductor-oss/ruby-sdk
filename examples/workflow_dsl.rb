#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Using the Conductor Ruby SDK Workflow DSL
#
# This example demonstrates how to define workflows programmatically using
# the new Ruby-idiomatic DSL, which provides a clean and expressive way to build workflows.
#
# Key Features:
# - Method-per-type: simple(), http(), wait(), terminate(), etc.
# - Auto-generated reference names
# - Hash-style [] for output references: task[:field]
# - wf[:param] for workflow inputs
# - Block-based control flow: parallel, decide, loop_times
#
# Run with: bundle exec ruby examples/workflow_dsl.rb

require_relative '../lib/conductor'

puts '=' * 70
puts 'Conductor Ruby SDK - New DSL Examples'
puts '=' * 70
puts

# ============================================================================
# Example 1: Simple Sequential Workflow
# ============================================================================
puts '=== Example 1: Simple Sequential Workflow ==='

simple_workflow = Conductor.workflow :ruby_simple_workflow, version: 1 do
  description 'A simple sequential workflow created with the new Ruby DSL'
  timeout 3600
  owner_email 'developer@example.com'

  # Tasks are created with simple method calls
  # wf[:userName] returns "${workflow.input.userName}"
  greet = simple :greet_user, name: wf[:userName]

  # Reference previous task outputs with task[:field]
  # greet[:message] returns "${greet_user_ref.output.message}"
  process = simple :process_greeting, greeting: greet[:message]

  # Set workflow output
  output result: process[:result]
end

puts "Workflow: #{simple_workflow.name}"
puts "Tasks: #{simple_workflow.builder.tasks.size}"
puts

# ============================================================================
# Example 2: Parallel Execution
# ============================================================================
puts '=== Example 2: Parallel Execution ==='

parallel_workflow = Conductor.workflow :ruby_parallel_workflow, version: 1 do
  description 'Workflow with parallel task execution'
  timeout 300

  # Initial task
  fetch = simple :fetch_data, source: wf[:dataSource]

  # Parallel block - tasks execute concurrently
  parallel do
    simple :process_type_a, data: fetch[:data]
    simple :process_type_b, data: fetch[:data]
  end

  # Aggregation after parallel tasks complete
  # Note: Access parallel outputs via the specific task ref names
  aggregate = simple :aggregate_results,
                     result_a: '${process_type_a_ref.output.result}',
                     result_b: '${process_type_b_ref.output.result}'

  output combined: aggregate[:result]
end

puts "Workflow: #{parallel_workflow.name}"
puts "Task count: #{parallel_workflow.builder.tasks.size} (includes fork/join)"
puts

# ============================================================================
# Example 3: Conditional Branching with Switch
# ============================================================================
puts '=== Example 3: Conditional Branching with Switch ==='

conditional_workflow = Conductor.workflow :ruby_conditional_workflow, version: 1 do
  description 'Workflow with conditional branching'

  # Classification task
  classify = simple :classify_request, request: wf[:request]

  # Switch based on the classification output
  decide classify[:requestType] do
    on 'TYPE_A' do
      simple :handle_type_a, data: classify[:data]
    end

    on 'TYPE_B' do
      simple :handle_type_b, data: classify[:data]
    end

    otherwise do
      simple :handle_default, data: classify[:data]
    end
  end

  output status: 'completed'
end

puts "Workflow: #{conditional_workflow.name}"
puts 'Switch cases: TYPE_A, TYPE_B, default'
puts

# ============================================================================
# Example 4: HTTP Task
# ============================================================================
puts '=== Example 4: HTTP Task ==='

http_workflow = Conductor.workflow :ruby_http_workflow, version: 1 do
  description 'Workflow with HTTP calls'

  # HTTP task with dynamic URL from workflow input
  api_call = http :call_api,
                  url: 'https://api.example.com/users/${workflow.input.userId}',
                  method: :get,
                  headers: { 'Authorization' => 'Bearer ${workflow.input.token}' }

  # Process the response
  process = simple :process_response,
                   status_code: api_call[:statusCode],
                   body: api_call[:body]

  output result: process[:result]
end

puts "Workflow: #{http_workflow.name}"
puts 'HTTP endpoint: api.example.com/users'
puts

# ============================================================================
# Example 5: Sub-Workflow Task
# ============================================================================
puts '=== Example 5: Sub-Workflow Task ==='

parent_workflow = Conductor.workflow :ruby_parent_workflow, version: 1 do
  description 'Parent workflow that calls a sub-workflow'

  prepare = simple :prepare_data, input: wf[:data]

  # Call an existing workflow as a sub-workflow
  child_result = sub_workflow :call_child,
                              workflow: 'child_workflow_name',
                              version: 1,
                              data: prepare[:preparedData]

  process = simple :process_child_result, child_output: child_result[:output]

  output final_result: process[:result]
end

puts "Workflow: #{parent_workflow.name}"
puts 'Calls sub-workflow: child_workflow_name'
puts

# ============================================================================
# Example 6: Loop with Times
# ============================================================================
puts '=== Example 6: Loop with Times ==='

loop_workflow = Conductor.workflow :ruby_loop_workflow, version: 1 do
  description 'Workflow with loop iteration'

  init = simple :initialize, count: 0

  # Loop 3 times
  loop_times 3 do
    simple :process_batch, iteration: '${do_while_ref.output.iteration}'
  end

  finalize = simple :finalize, batches_processed: 3

  output result: finalize[:summary]
end

puts "Workflow: #{loop_workflow.name}"
puts 'Loops 3 times'
puts

# ============================================================================
# Example 7: Inline Workflow Definition
# ============================================================================
puts '=== Example 7: Inline Workflow ==='

inline_demo = Conductor.workflow :ruby_inline_workflow, version: 1 do
  description 'Workflow with inline sub-workflow'

  start = simple :start_processing, data: wf[:input_data]

  # Define a sub-workflow inline
  inline_workflow :process_order, version: 1 do
    validate = simple :validate_order
    simple :charge_payment, amount: validate[:total]
    simple :ship_order
  end

  complete = simple :complete_processing

  output status: 'done'
end

puts "Workflow: #{inline_demo.name}"
puts 'Contains inline sub-workflow'
puts

# ============================================================================
# Example 8: Wait and Human Tasks
# ============================================================================
puts '=== Example 8: Wait and Human Tasks ==='

approval_workflow = Conductor.workflow :ruby_approval_workflow, version: 1 do
  description 'Workflow with wait and human tasks'

  submit = simple :submit_request, request: wf[:request]

  # Human task for approval
  approval = human :manager_approval,
                   assignee: wf[:manager_email],
                   display_name: 'Approve Request'

  # Conditional based on approval
  decide approval[:decision] do
    on 'approved' do
      simple :process_approved
    end

    on 'rejected' do
      terminate :failed, 'Request rejected by manager'
    end

    otherwise do
      # Wait for escalation
      wait 86_400 # 24 hours
      simple :escalate_request
    end
  end

  output status: 'completed'
end

puts "Workflow: #{approval_workflow.name}"
puts 'Includes human task and wait'
puts

# ============================================================================
# Example 9: Complete Workflow with All Features
# ============================================================================
puts '=== Example 9: Complete Example Workflow ==='

complete_workflow = Conductor.workflow :ruby_complete_example, version: 1 do
  description 'Complete example workflow demonstrating all features'
  timeout 7200
  owner_email 'team@example.com'

  # Initialize
  init = simple :initialize, user_id: wf[:userId]

  # Validate
  validate = simple :validate_input, data: init[:output]

  # Process
  process = simple :process_action, validated_data: validate[:output]

  # Notify
  notify = simple :notify_user,
                  user_id: wf[:userId],
                  result: process[:result]

  # Set output parameters
  output(
    status: notify[:status],
    completed_at: notify[:timestamp]
  )
end

# Convert to workflow definition (for inspection)
workflow_def = complete_workflow.to_workflow_def
puts "Workflow: #{complete_workflow.name}"
puts "Version: #{workflow_def.version}"
puts "Task count: #{workflow_def.tasks.length}"
puts "Timeout: #{workflow_def.timeout_seconds} seconds"
puts

# ============================================================================
# Summary
# ============================================================================
puts '=' * 70
puts 'Examples completed!'
puts '=' * 70
puts
puts 'New DSL Features Demonstrated:'
puts '  - Conductor.workflow :name do...end - Entry point'
puts '  - simple, http, wait, terminate, sub_workflow, human - Task methods'
puts '  - parallel do...end - Concurrent execution'
puts '  - decide expr do...end - Conditional branching'
puts '  - loop_times N do...end - Loop iteration'
puts '  - inline_workflow :name do...end - Inline sub-workflows'
puts '  - wf[:param] - Workflow input references'
puts '  - task[:field] - Task output references'
puts '  - output key: value - Workflow output'
puts
puts 'To run workflows against a Conductor server:'
puts '  1. Set CONDUCTOR_SERVER_URL environment variable'
puts '  2. Add executor: parameter to Conductor.workflow'
puts '  3. Call workflow.register(overwrite: true)'
puts '  4. Call workflow.execute(input: { ... })'
