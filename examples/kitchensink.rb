#!/usr/bin/env ruby
# frozen_string_literal: true

# Kitchen Sink Example
# ====================
#
# Comprehensive example demonstrating all major workflow task types and patterns.
#
# What it does:
# -------------
# - HTTP Task: Make external API calls
# - JavaScript Task: Execute inline JavaScript code
# - JSON JQ Task: Transform JSON using JQ queries
# - Switch Task: Conditional branching based on values
# - Wait Task: Pause workflow execution
# - Set Variable Task: Store values in workflow variables
# - Terminate Task: End workflow with specific status
# - Sub-Workflow Task: Call another workflow
# - Custom Worker Task: Execute Ruby business logic
#
# Use Cases:
# ----------
# - Learning all available task types
# - Building complex workflows with multiple task patterns
# - Testing different control flow mechanisms (switch, terminate)
# - Understanding how to combine system tasks with custom workers
#
# Key Concepts:
# -------------
# - System Tasks: Built-in tasks (HTTP, JavaScript, JQ, Wait, etc.)
# - Control Flow: Switch for branching, Terminate for early exit
# - Data Transformation: JQ for JSON manipulation
# - Worker Integration: Mix system tasks with custom Ruby workers
# - Variable Management: Set and use workflow variables
#
# This example is a "kitchen sink" showing all major features in one workflow.
#
# Usage:
#   bundle exec ruby examples/kitchensink.rb

require_relative '../lib/conductor'

# Include workflow DSL for shorter class names
include Conductor::Workflow

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

def main
  # Configuration from environment variables
  config = Conductor::Configuration.new

  puts '=' * 70
  puts 'Conductor Ruby SDK - Kitchen Sink Example'
  puts '=' * 70
  puts
  puts "Server: #{config.server_url}"
  puts

  # Create clients
  clients = Conductor::Orkes::OrkesClients.new(config)
  workflow_executor = clients.get_workflow_executor
  workflow_client = clients.get_workflow_client

  # Start workers
  task_handler = start_workers(config)
  puts 'Workers started...'
  puts

  # ============================================================================
  # BUILD KITCHEN SINK WORKFLOW
  # ============================================================================

  wf = ConductorWorkflow.new(workflow_client, 'kitchensink_ruby', version: 1, executor: workflow_executor)

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

  js = JavascriptTask.new('hello_script', say_hello_js)
                     .input('name', wf.input('name'))

  # -------------------------------------------------------------------------
  # 2. HTTP Task - Make external API call
  # -------------------------------------------------------------------------
  http_call = HttpTask.new('call_remote_api', {
                             'uri' => 'https://orkes-api-tester.orkesconductor.com/api'
                           })

  # -------------------------------------------------------------------------
  # 3. Sub-Workflow Task with HTTP and Wait
  # -------------------------------------------------------------------------
  sub_workflow = ConductorWorkflow.new(workflow_client, 'sub_ruby', version: 1, executor: workflow_executor)

  sub_http = HttpTask.new('sub_call_api', {
                            'uri' => sub_workflow.input('uri')
                          })

  sub_wait = WaitTask.new('sub_wait', wait_for_seconds: 2)

  sub_workflow >> sub_http >> sub_wait
  sub_workflow.input_parameters(['uri'])

  # Create sub-workflow task
  sub_workflow_task = SubWorkflowTask.new('call_sub_workflow', 'sub_ruby', version: 1)
                                     .input('uri', js.output('url'))

  # -------------------------------------------------------------------------
  # 4. Wait Task - Pause execution for 2 seconds
  # -------------------------------------------------------------------------
  wait_for_two_sec = WaitTask.new('wait_for_2_sec', wait_for_seconds: 2)

  # -------------------------------------------------------------------------
  # 5. JSON JQ Task - Transform JSON data
  # -------------------------------------------------------------------------
  jq_script = '{ key3: (.key1.value1 + .key2.value2) }'
  jq = JsonJqTask.new('jq_process', jq_script)
                 .input('key1', { 'value1' => %w[a b] })
                 .input('key2', { 'value2' => %w[d e] })

  # -------------------------------------------------------------------------
  # 6. Set Variable Task - Store workflow variables
  # -------------------------------------------------------------------------
  set_wf_var = SetVariableTask.new('set_wf_var_ref')
                              .input('var1', 'value1')
                              .input('var2', 42)
                              .input('var3', %w[a b c])

  # -------------------------------------------------------------------------
  # 7. Switch Task - Conditional branching
  # -------------------------------------------------------------------------
  # Route task for US
  route_us = SimpleTask.new('route', 'us_routing')
                       .input('country', wf.input('country'))

  # Route task for CA
  route_ca = SimpleTask.new('route', 'ca_routing')
                       .input('country', wf.input('country'))

  # Terminate task for unsupported countries
  bad_country = TerminateTask.new(
    'bad_country_ref',
    termination_status: 'TERMINATED',
    termination_reason: 'unsupported country'
  )

  switch = SwitchTask.new('decide', wf.input('country'))
                     .switch_case('US', [route_us])
                     .switch_case('CA', [route_ca])
                     .default_case([bad_country])

  # -------------------------------------------------------------------------
  # BUILD WORKFLOW STRUCTURE
  # -------------------------------------------------------------------------
  # Flow: js -> [sub_workflow | [http_call, wait]] -> jq -> set_var -> switch
  #
  # The parallel fork contains:
  #   Branch 1: sub_workflow_task
  #   Branch 2: http_call -> wait_for_two_sec

  wf >> js
  wf >> [[sub_workflow_task], [http_call, wait_for_two_sec]]
  wf >> jq
  wf >> set_wf_var
  wf >> switch

  # Set workflow output
  wf.output_parameter('greetings', js.output)

  # ============================================================================
  # REGISTER SUB-WORKFLOW FIRST
  # ============================================================================

  puts 'Registering sub-workflow...'
  workflow_executor.register_workflow(sub_workflow, overwrite: true)
  puts 'Sub-workflow registered!'
  puts

  # ============================================================================
  # EXECUTE WORKFLOW
  # ============================================================================

  puts 'Executing kitchen sink workflow...'
  puts "Input: { name: 'Conductor Ruby', country: 'US' }"
  puts

  result = wf.execute(
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
