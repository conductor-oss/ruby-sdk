#!/usr/bin/env ruby
# frozen_string_literal: true

# Dynamic Workflow Example
# =========================
#
# Demonstrates creating and executing workflows at runtime without pre-registration.
#
# What it does:
# -------------
# - Creates a workflow programmatically using Ruby code
# - Defines two workers: get_user_email and send_email
# - Chains tasks together using the >> operator
# - Executes the workflow with input data
#
# Use Cases:
# ----------
# - Workflows that cannot be defined statically (structure depends on runtime data)
# - Programmatic workflow generation based on business rules
# - Testing workflows without registering definitions
# - Rapid prototyping and development
#
# Key Concepts:
# -------------
# - ConductorWorkflow: Build workflows in code
# - Task chaining: Use >> operator to define task sequence
# - Dynamic execution: Create and run workflows on-the-fly
# - Worker tasks: Ruby methods/blocks that execute task logic
#
# Usage:
#   bundle exec ruby examples/dynamic_workflow.rb
#
# Prerequisites:
#   - Conductor server running (set CONDUCTOR_SERVER_URL)
#   - For Orkes: Set CONDUCTOR_AUTH_KEY and CONDUCTOR_AUTH_SECRET

require_relative '../lib/conductor'

# Include workflow DSL for shorter class names
include Conductor::Workflow

# ============================================================================
# WORKERS - Define task implementations
# ============================================================================

# Worker 1: Get user email by user ID
class GetUserEmailWorker
  include Conductor::Worker::WorkerModule

  worker_task 'get_user_email'

  def execute(task)
    userid = get_input(task, 'userid', 'unknown')
    email = "#{userid}@example.com"

    puts "[GetUserEmailWorker] Generated email for userid=#{userid}: #{email}"

    # Return the email as output
    { 'result' => email }
  end
end

# Worker 2: Send email
class SendEmailWorker
  include Conductor::Worker::WorkerModule

  worker_task 'send_email'

  def execute(task)
    email = get_input(task, 'email', '')
    subject = get_input(task, 'subject', 'No Subject')
    body = get_input(task, 'body', '')

    puts "[SendEmailWorker] Sending email to #{email}"
    puts "  Subject: #{subject}"
    puts "  Body: #{body}"

    # Simulate sending email
    { 'status' => 'sent', 'to' => email }
  end
end

def main
  # Configuration from environment variables
  # CONDUCTOR_SERVER_URL: Conductor server URL (e.g., https://developer.orkescloud.com/api)
  # CONDUCTOR_AUTH_KEY: API Authentication Key (optional for OSS)
  # CONDUCTOR_AUTH_SECRET: API Auth Secret (optional for OSS)
  config = Conductor::Configuration.new

  puts '=' * 70
  puts 'Conductor Ruby SDK - Dynamic Workflow Example'
  puts '=' * 70
  puts
  puts "Server: #{config.server_url}"
  puts

  # Create clients using OrkesClients factory
  clients = Conductor::Orkes::OrkesClients.new(config)
  workflow_executor = clients.get_workflow_executor

  # Start workers in the background
  task_handler = Conductor::Worker::TaskRunner.new(config)
  task_handler.register_worker(GetUserEmailWorker.new)
  task_handler.register_worker(SendEmailWorker.new)
  task_handler.start

  puts 'Workers started...'
  puts

  # ============================================================================
  # BUILD WORKFLOW DYNAMICALLY
  # ============================================================================

  # Create workflow with executor for dynamic execution
  workflow = ConductorWorkflow.new(
    clients.get_workflow_client,
    'dynamic_workflow_ruby',
    version: 1,
    executor: workflow_executor
  )

  # Define tasks
  # Task 1: Get user email - uses workflow input for userid
  get_email = SimpleTask.new('get_user_email', 'get_user_email_ref')
    .input('userid', workflow.input('userid'))

  # Task 2: Send email - uses output from get_email task
  sendmail = SimpleTask.new('send_email', 'send_email_ref')
    .input('email', get_email.output('result'))
    .input('subject', 'Hello from Conductor Ruby SDK')
    .input('body', 'This is a test email from a dynamic workflow')

  # Chain tasks: workflow >> task1 >> task2
  workflow >> get_email >> sendmail

  # Configure the output of the workflow
  workflow.output_parameter('email', get_email.output('result'))

  # ============================================================================
  # EXECUTE WORKFLOW
  # ============================================================================

  puts 'Executing dynamic workflow...'
  puts

  # Execute workflow synchronously with input
  workflow_run = workflow.execute(
    input: { 'userid' => 'user_a' },
    wait_for_seconds: 30
  )

  puts
  puts 'Workflow completed!'
  puts '-' * 70
  puts "Workflow ID: #{workflow_run.workflow_id}"
  puts "Status: #{workflow_run.status}"
  puts "Output: #{workflow_run.output.inspect}"
  puts
  puts "Check the workflow execution at: #{config.ui_host}/execution/#{workflow_run.workflow_id}"

  # Stop workers
  task_handler.stop
  puts
  puts 'Workers stopped. Goodbye!'
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
