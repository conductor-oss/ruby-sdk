#!/usr/bin/env ruby
# frozen_string_literal: true

# Workflow Operations Example
# ============================
#
# Demonstrates various workflow lifecycle operations and control mechanisms.
#
# What it does:
# -------------
# - Start workflow: Create and execute a new workflow instance
# - Pause workflow: Temporarily halt workflow execution
# - Resume workflow: Continue paused workflow
# - Terminate workflow: Force stop a running workflow
# - Restart workflow: Restart from a specific task
# - Rerun workflow: Re-execute from beginning with same/different inputs
# - Update task: Manually update task status and output
# - Search workflows: Find workflows by correlation ID or query
#
# Use Cases:
# ----------
# - Workflow lifecycle management (start, pause, resume, terminate)
# - Manual intervention in workflow execution
# - Debugging and testing workflows
# - Implementing human-in-the-loop patterns
# - External event handling via task updates
# - Recovery from failures (restart, rerun)
#
# Key Operations:
# ---------------
# - start_workflow(): Launch new workflow instance
# - pause_workflow(): Halt at current task
# - resume_workflow(): Continue from pause
# - terminate_workflow(): Force stop with reason
# - restart_workflow(): Resume from failed task
# - rerun_workflow(): Start fresh with new/same inputs
# - update_task(): Manually complete tasks
#
# Usage:
#   bundle exec ruby examples/workflow_ops.rb

require 'securerandom'
require_relative '../lib/conductor'

# Include workflow DSL
include Conductor::Workflow

def start_demo_workflow(workflow_executor, workflow_client)
  # Create a workflow with wait tasks for demonstrating operations
  workflow = ConductorWorkflow.new(workflow_client, 'workflow_ops_demo', version: 1, executor: workflow_executor)

  # Wait for 2 seconds
  wait_for_two_sec = WaitTask.new('wait_for_2_sec', wait_for_seconds: 2)

  # Wait for external signal (no timeout - waits indefinitely until updated)
  wait_for_signal = WaitTask.new('wait_for_signal')

  # HTTP call
  http_call = HttpTask.new('call_remote_api', {
                             'uri' => 'https://orkes-api-tester.orkesconductor.com/api'
                           })

  # Build workflow
  workflow >> wait_for_two_sec >> wait_for_signal >> http_call

  # Register the workflow
  workflow_executor.register_workflow(workflow, overwrite: true)

  # Start workflow with a correlation ID
  request = Conductor::Http::Models::StartWorkflowRequest.new(
    name: 'workflow_ops_demo',
    version: 1,
    input: {},
    correlation_id: 'correlation_123'
  )

  workflow_executor.start_workflow(request)
end

def main
  # Configuration from environment variables
  config = Conductor::Configuration.new

  puts '=' * 70
  puts 'Conductor Ruby SDK - Workflow Operations Example'
  puts '=' * 70
  puts
  puts "Server: #{config.server_url}"
  puts

  # Create clients
  clients = Conductor::Orkes::OrkesClients.new(config)
  workflow_client = clients.get_workflow_client
  task_client = clients.get_task_client
  workflow_executor = clients.get_workflow_executor

  # ============================================================================
  # START WORKFLOW
  # ============================================================================

  workflow_id = start_demo_workflow(workflow_executor, workflow_client)
  puts "Started workflow with ID: #{workflow_id}"
  puts "Monitor at: #{config.ui_host}/execution/#{workflow_id}"
  puts

  # ============================================================================
  # GET WORKFLOW STATUS
  # ============================================================================

  workflow = workflow_client.get_workflow(workflow_id, include_tasks: true)
  last_task = workflow['tasks'].last
  puts "Workflow status: #{workflow['status']}"
  puts "Currently running task: #{last_task['referenceTaskName']}"
  puts

  # ============================================================================
  # WAIT FOR TIMED WAIT TO COMPLETE
  # ============================================================================

  puts 'Waiting 3 seconds for the timed wait task to complete...'
  sleep 3

  workflow = workflow_client.get_workflow(workflow_id, include_tasks: true)
  last_task = workflow['tasks'].last
  puts "Workflow status: #{workflow['status']}"
  puts "Currently running task: #{last_task['referenceTaskName']}"
  puts

  # ============================================================================
  # TERMINATE WORKFLOW
  # ============================================================================

  puts 'Terminating workflow...'
  workflow_client.terminate_workflow(workflow_id, reason: 'testing termination')

  workflow = workflow_client.get_workflow(workflow_id, include_tasks: true)
  last_task = workflow['tasks'].last
  puts "Workflow status: #{workflow['status']}"
  puts "Last task status: #{last_task['status']}"
  puts

  # ============================================================================
  # RETRY WORKFLOW
  # ============================================================================

  puts 'Retrying workflow...'
  workflow_client.retry_workflow(workflow_id)

  workflow = workflow_client.get_workflow(workflow_id, include_tasks: true)
  last_task = workflow['tasks'].last
  puts "Workflow status: #{workflow['status']}"
  puts "Last task: #{last_task['referenceTaskName']} (status: #{last_task['status']})"
  puts

  # ============================================================================
  # MANUALLY COMPLETE WAIT TASK
  # ============================================================================

  puts 'Manually completing the wait_for_signal task...'

  # Create task result to complete the WAIT task
  task_result = Conductor::Http::Models::TaskResult.new(
    workflow_instance_id: workflow_id,
    task_id: last_task['taskId'],
    status: 'COMPLETED',
    output_data: { 'greetings' => 'hello from Conductor Ruby SDK' }
  )
  task_client.update_task(task_result)

  workflow = workflow_client.get_workflow(workflow_id, include_tasks: true)
  last_task = workflow['tasks'].last
  puts "Workflow status: #{workflow['status']}"
  puts "Last task: #{last_task['referenceTaskName']} (status: #{last_task['status']})"

  # Wait for HTTP task to complete
  sleep 2

  # ============================================================================
  # RERUN WORKFLOW
  # ============================================================================

  puts
  puts 'Re-running workflow from the second task...'

  # Get the workflow again to find the second task
  workflow = workflow_client.get_workflow(workflow_id, include_tasks: true)

  if workflow['tasks'].length > 1
    second_task_id = workflow['tasks'][1]['taskId']

    rerun_request = {
      're_run_from_task_id' => second_task_id
    }
    workflow_client.rerun_workflow(workflow_id, rerun_request)

    workflow = workflow_client.get_workflow(workflow_id, include_tasks: true)
    puts "Workflow status after rerun: #{workflow['status']}"
  end

  # ============================================================================
  # RESTART WORKFLOW
  # ============================================================================

  puts
  puts 'Terminating and restarting workflow...'

  workflow_client.terminate_workflow(workflow_id, reason: 'terminating so we can restart')
  workflow_client.restart_workflow(workflow_id)

  workflow = workflow_client.get_workflow(workflow_id, include_tasks: true)
  puts "Workflow status after restart: #{workflow['status']}"

  # ============================================================================
  # PAUSE AND RESUME WORKFLOW
  # ============================================================================

  puts
  puts 'Pausing workflow...'
  workflow_client.pause_workflow(workflow_id)

  workflow = workflow_client.get_workflow(workflow_id, include_tasks: true)
  puts "Workflow status: #{workflow['status']}"

  puts 'Waiting 3 seconds while paused...'
  sleep 3

  workflow = workflow_client.get_workflow(workflow_id, include_tasks: true)
  # While paused, wait task may complete but no new tasks scheduled
  wait_task = workflow['tasks'].first
  puts "Wait task status: #{wait_task['status']}"
  puts "Number of tasks: #{workflow['tasks'].length} (should be limited while paused)"

  puts
  puts 'Resuming workflow...'
  workflow_client.resume_workflow(workflow_id)

  sleep 1
  workflow = workflow_client.get_workflow(workflow_id, include_tasks: true)
  puts "Workflow status after resume: #{workflow['status']}"
  puts "Number of tasks after resume: #{workflow['tasks'].length}"

  # ============================================================================
  # SEARCH WORKFLOWS
  # ============================================================================

  puts
  puts 'Searching for workflows with correlation_id "correlation_123"...'

  search_results = workflow_client.search(
    start: 0,
    size: 100,
    free_text: '*',
    query: 'correlationId = "correlation_123"'
  )

  puts "Found #{search_results['results']&.length || 0} workflow(s) with correlation_id 'correlation_123'"

  # Search for a random correlation ID (should find nothing)
  random_correlation_id = SecureRandom.uuid
  search_results = workflow_client.search(
    start: 0,
    size: 100,
    free_text: '*',
    query: "status IN (RUNNING) AND correlationId = \"#{random_correlation_id}\""
  )

  puts "Found #{search_results['results']&.length || 0} workflow(s) with random correlation_id (expected: 0)"

  # ============================================================================
  # CLEANUP
  # ============================================================================

  puts
  puts 'Terminating workflow for cleanup...'
  workflow_client.terminate_workflow(workflow_id, reason: 'cleanup after demo')

  puts
  puts '-' * 70
  puts 'Workflow Operations Demo Complete!'
  puts '-' * 70
  puts
  puts 'Operations demonstrated:'
  puts '  - Start workflow'
  puts '  - Get workflow status'
  puts '  - Terminate workflow'
  puts '  - Retry workflow'
  puts '  - Update task manually'
  puts '  - Rerun workflow from task'
  puts '  - Restart workflow'
  puts '  - Pause workflow'
  puts '  - Resume workflow'
  puts '  - Search workflows'
end

if __FILE__ == $PROGRAM_NAME
  begin
    main
  rescue Conductor::ApiError => e
    puts "API Error: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end
end
