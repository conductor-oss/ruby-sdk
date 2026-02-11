#!/usr/bin/env ruby
# frozen_string_literal: true

# Hello World Example
# ===================
#
# The simplest complete example demonstrating:
# 1. Define a workflow using the new Ruby-idiomatic DSL
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

def create_greetings_workflow(executor)
  # Define workflow using the new Ruby-idiomatic DSL
  Conductor.workflow :greetings, version: 1, executor: executor do
    # Create greet task that uses workflow input
    # wf[:name] returns "${workflow.input.name}"
    greet = simple :greet, name: wf[:name]

    # Set output to be the result from greet task
    # greet[:result] returns "${greet_ref.output.result}"
    output result: greet[:result]
  end
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

  # Create workflow with executor (required for register/execute)
  workflow = create_greetings_workflow(workflow_executor)

  # Register workflow (only needs to be done once)
  puts 'Registering workflow...'
  workflow.register(overwrite: true)
  puts "Registered workflow: #{workflow.name} v#{workflow.version}"
  puts

  # Start workers
  puts 'Starting workers...'
  task_handler = Conductor::Worker::TaskRunner.new(config)
  task_handler.register_worker(GreetingsWorker.new)
  task_handler.start
  puts 'Workers started!'
  puts

  # Execute workflow using the new DSL's execute method
  puts 'Executing workflow with input: { name: "World" }'
  workflow_run = workflow.execute(input: { 'name' => 'World' }, wait_for_seconds: 30)

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
