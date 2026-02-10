#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple example demonstrating worker functionality with Conductor Ruby SDK
#
# Prerequisites:
# 1. Conductor server running on localhost:7001 (OSS version)
# 2. A workflow that uses 'simple_task' task type
# 3. Bundle install completed
#
# Usage:
#   bundle exec ruby examples/simple_worker.rb

require_relative '../lib/conductor'

puts '=' * 60
puts 'Conductor Ruby SDK - Simple Worker Example'
puts '=' * 60

# Configure Conductor client
config = Conductor::Configuration.new(
  server_api_url: 'http://localhost:7001/api'
)

puts "\nConnecting to Conductor server at: #{config.server_url}"

# Example 1: Class-based worker
class SimpleWorker
  include Conductor::Worker::WorkerModule

  worker_task 'simple_task', poll_interval: 1

  def execute(task)
    puts "\n[SimpleWorker] Executing task: #{task.task_id}"
    puts "[SimpleWorker] Input: #{task.input_data.inspect}"

    # Get input
    name = get_input(task, 'name', 'World')

    # Do some work
    sleep 0.5
    result_message = "Hello, #{name}!"

    # Create result
    result = Conductor::Http::Models::TaskResult.complete
    result.add_output_data('message', result_message)
    result.add_output_data('processed_at', Time.now.to_s)
    result.log("Processed greeting for #{name}")

    puts "[SimpleWorker] Result: #{result_message}"
    result
  end
end

# Example 2: Block-based worker
math_worker = Conductor::Worker.define('math_task', poll_interval: 1) do |task|
  puts "\n[MathWorker] Executing task: #{task.task_id}"
  puts "[MathWorker] Input: #{task.input_data.inspect}"

  a = task.input_data['a'] || 0
  b = task.input_data['b'] || 0
  operation = task.input_data['operation'] || 'add'

  result = case operation
           when 'add' then a + b
           when 'subtract' then a - b
           when 'multiply' then a * b
           when 'divide' then b.zero? ? 'Error: Division by zero' : a / b
           else 'Unknown operation'
           end

  puts "[MathWorker] Result: #{a} #{operation} #{b} = #{result}"

  # Return hash - will be converted to TaskResult automatically
  { result: result, operation: operation }
end

# Example 3: Worker that can fail
failing_worker = Conductor::Worker.define('failing_task', poll_interval: 1) do |task|
  puts "\n[FailingWorker] Executing task: #{task.task_id}"

  should_fail = task.input_data['should_fail']

  if should_fail
    # Return a failed result
    result = Conductor::Http::Models::TaskResult.failed('Task failed as requested')
    result.log('This task was designed to fail')
    result
  else
    # Return success
    { status: 'success', message: 'Task completed successfully' }
  end
end

# Create and configure task runner
puts "\n[TaskRunner] Creating task runner..."
runner = Conductor::Worker::TaskRunner.new(config)

# Register workers
runner.register_worker(SimpleWorker.new)
runner.register_worker(math_worker)
runner.register_worker(failing_worker)

puts '[TaskRunner] Registered 3 workers:'
puts '  - simple_task (class-based)'
puts '  - math_task (block-based)'
puts '  - failing_task (block-based)'

# Start the runner
puts "\n[TaskRunner] Starting worker threads..."
runner.start(threads: 1)

puts "\nWorkers are now polling for tasks. Press Ctrl+C to stop."
puts '=' * 60

# Keep the main thread alive and handle Ctrl+C gracefully
trap('INT') do
  puts "\n\nReceived interrupt signal..."
  runner.stop
  puts 'Workers stopped. Exiting.'
  exit 0
end

# Keep running
sleep while runner.running?
