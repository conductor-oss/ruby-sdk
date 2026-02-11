#!/usr/bin/env ruby
# frozen_string_literal: true

# Kitchen Sink Example
# ====================
#
# Comprehensive example demonstrating all major workflow task types and patterns
# using the new Ruby-idiomatic DSL.
#
# What it demonstrates:
# ---------------------
# - simple() - Custom worker tasks
# - http() - External API calls
# - javascript() - Inline JavaScript execution
# - jq() - JSON transformation with JQ
# - decide() - Conditional branching (switch)
# - wait() - Pause workflow execution
# - set() - Store workflow variables
# - terminate() - End workflow with specific status
# - sub_workflow() - Call another workflow
# - parallel() - Concurrent task execution
#
# Usage:
#   bundle exec ruby examples/kitchensink.rb

require_relative '../lib/conductor'

# ============================================================================
# WORKER - Custom task implementation
# ============================================================================

class RouteWorker
  include Conductor::Worker::WorkerModule

  worker_task 'route'

  def execute(task)
    country = get_input(task, 'country', 'Unknown')
    message = "routing the packages to #{country}"
    puts "[RouteWorker] #{message}"
    { 'result' => message }
  end
end

def start_workers(config)
  task_handler = Conductor::Worker::TaskRunner.new(config)
  task_handler.register_worker(RouteWorker.new)
  task_handler.start
  task_handler
end

def create_sub_workflow(executor)
  # Create a sub-workflow that will be called from the main workflow
  Conductor.workflow :sub_ruby, version: 1, executor: executor do
    # HTTP call using workflow input for URI
    http :sub_call_api, url: wf[:uri]

    # Wait for 2 seconds
    wait 2
  end
end

def create_kitchensink_workflow(executor)
  # Main kitchen sink workflow using the new DSL
  Conductor.workflow :kitchensink_ruby, version: 1, executor: executor do
    # -------------------------------------------------------------------------
    # 1. JavaScript Task - Execute inline JavaScript
    # -------------------------------------------------------------------------
    say_hello_js = <<~JS
      function greetings() {
          return {
              "text": "hello " + $.name,
              "url": "https://orkes-api-tester.orkesconductor.com/api"
          }
      }
      greetings();
    JS

    js = javascript :hello_script, script: say_hello_js, name: wf[:name]

    # -------------------------------------------------------------------------
    # 2. Parallel Execution - HTTP call and sub-workflow run concurrently
    # -------------------------------------------------------------------------
    parallel do
      # Branch 1: Call sub-workflow with URL from JS task
      sub_workflow :call_sub_workflow, workflow: 'sub_ruby', version: 1, uri: js[:url]

      # Branch 2: HTTP call followed by wait
      http :call_remote_api, url: 'https://orkes-api-tester.orkesconductor.com/api'
      wait 2
    end

    # -------------------------------------------------------------------------
    # 3. JSON JQ Task - Transform JSON data
    # -------------------------------------------------------------------------
    jq :jq_process,
       query: '{ key3: (.key1.value1 + .key2.value2) }',
       key1: { 'value1' => %w[a b] },
       key2: { 'value2' => %w[d e] }

    # -------------------------------------------------------------------------
    # 4. Set Variable Task - Store workflow variables
    # -------------------------------------------------------------------------
    set(
      var1: 'value1',
      var2: 42,
      var3: %w[a b c]
    )

    # -------------------------------------------------------------------------
    # 5. Switch Task - Conditional branching based on country
    # -------------------------------------------------------------------------
    decide wf[:country] do
      on 'US' do
        simple :route, country: wf[:country]
      end

      on 'CA' do
        simple :route, country: wf[:country]
      end

      otherwise do
        terminate :terminated, 'unsupported country'
      end
    end

    # -------------------------------------------------------------------------
    # Set workflow output
    # -------------------------------------------------------------------------
    output greetings: js[:output]
  end
end

def main
  # Configuration from environment variables
  config = Conductor::Configuration.new

  puts '=' * 70
  puts 'Conductor Ruby SDK - Kitchen Sink Example (New DSL)'
  puts '=' * 70
  puts
  puts "Server: #{config.server_url}"
  puts

  # Create clients
  clients = Conductor::Orkes::OrkesClients.new(config)
  workflow_executor = clients.get_workflow_executor

  # Start workers
  task_handler = start_workers(config)
  puts 'Workers started...'
  puts

  # ============================================================================
  # CREATE WORKFLOWS USING NEW DSL
  # ============================================================================

  sub_workflow = create_sub_workflow(workflow_executor)
  main_workflow = create_kitchensink_workflow(workflow_executor)

  # ============================================================================
  # REGISTER SUB-WORKFLOW FIRST
  # ============================================================================

  puts 'Registering sub-workflow...'
  sub_workflow.register(overwrite: true)
  puts "Sub-workflow '#{sub_workflow.name}' registered!"
  puts

  # ============================================================================
  # REGISTER AND EXECUTE MAIN WORKFLOW
  # ============================================================================

  puts 'Registering main workflow...'
  main_workflow.register(overwrite: true)
  puts "Main workflow '#{main_workflow.name}' registered!"
  puts

  puts 'Executing kitchen sink workflow...'
  puts "Input: { name: 'Conductor Ruby', country: 'US' }"
  puts

  result = main_workflow.execute(
    input: { 'name' => 'Conductor Ruby', 'country' => 'US' },
    wait_for_seconds: 60
  )

  puts
  puts 'Workflow completed!'
  puts '-' * 70
  puts "Workflow ID: #{result.workflow_id}"
  puts "Status: #{result.status}"
  puts "Output: #{result.output.inspect}"
  puts
  puts "See the execution at: #{config.ui_host}/execution/#{result.workflow_id}"

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
