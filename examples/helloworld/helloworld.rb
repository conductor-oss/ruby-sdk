#!/usr/bin/env ruby
# frozen_string_literal: true

# Hello World Example
# ===================
#
# The simplest complete example demonstrating:
# 1. Define a workflow
# 2. Register the workflow
# 3. Start workers
# 4. Execute the workflow
# 5. Get the result
#
# Usage:
#   cd examples/helloworld
#   bundle exec ruby helloworld.rb
#
# Prerequisites:
#   - Conductor server running (set CONDUCTOR_SERVER_URL env var)
#   - For Orkes: Set CONDUCTOR_AUTH_KEY and CONDUCTOR_AUTH_SECRET

require_relative 'greetings_worker'

# Include workflow DSL for shorter class names
include Conductor::Workflow

def greetings_workflow(workflow_executor, workflow_client)
  workflow = ConductorWorkflow.new(
    workflow_client,
    'greetings',
    version: 1,
    executor: workflow_executor
  )

  # Create greet task that uses workflow input
  greet = SimpleTask.new('greet', 'greet_ref')
                    .input('name', workflow.input('name'))

  # Add task to workflow
  workflow >> greet

  # Set output to be the result from greet task
  workflow.output_parameter('result', greet.output('result'))

  workflow
end

def register_workflow(workflow_executor, workflow_client)
  workflow = greetings_workflow(workflow_executor, workflow_client)
  workflow_executor.register_workflow(workflow, overwrite: true)
  workflow
end

def main
  # Configuration - reads from environment variables by default:
  # CONDUCTOR_SERVER_URL: Conductor server URL (default: http://localhost:8080/api)
  # CONDUCTOR_AUTH_KEY: API Authentication Key (optional for OSS)
  # CONDUCTOR_AUTH_SECRET: API Auth Secret (optional for OSS)
  config = Conductor::Configuration.new

  puts '=' * 60
  puts 'Conductor Ruby SDK - Hello World'
  puts '=' * 60
  puts
  puts "Server: #{config.server_url}"
  puts

  # Create clients
  clients = Conductor::Orkes::OrkesClients.new(config)
  workflow_executor = clients.get_workflow_executor
  workflow_client = clients.get_workflow_client

  # Register workflow (only needs to be done once)
  puts 'Registering workflow...'
  workflow = register_workflow(workflow_executor, workflow_client)
  puts "Registered workflow: #{workflow.name} v#{workflow.version}"
  puts

  # Start workers
  puts 'Starting workers...'
  task_handler = Conductor::Worker::TaskRunner.new(config)
  task_handler.register_worker(GreetingsWorker.new)
  task_handler.start
  puts 'Workers started!'
  puts

  # Execute workflow
  puts 'Executing workflow with input: { name: "World" }'
  workflow_run = workflow_executor.execute(
    workflow.name,
    input: { 'name' => 'World' },
    wait_for_seconds: 30
  )

  puts
  puts '-' * 60
  puts "Workflow result: #{workflow_run.output['result']}"
  puts '-' * 60
  puts
  puts "See the workflow execution at: #{config.ui_host}/execution/#{workflow_run.workflow_id}"

  # Stop workers
  task_handler.stop
  puts
  puts 'Done!'
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
