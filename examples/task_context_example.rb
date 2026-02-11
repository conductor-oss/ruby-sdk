# frozen_string_literal: true

#
# Task Context Example
#
# Demonstrates how to use TaskContext to access task information and modify
# task results during execution.
#
# The TaskContext provides:
# - Access to task metadata (task_id, workflow_id, retry_count, etc.)
# - Ability to add logs visible in Conductor UI
# - Ability to set callback delays for polling/retry patterns
# - Access to input parameters
#
# Usage:
#   ruby examples/task_context_example.rb
#
# Environment variables:
#   CONDUCTOR_SERVER_URL  - Conductor server URL (default: http://localhost:8080/api)
#   CONDUCTOR_AUTH_KEY    - Authentication key (optional)
#   CONDUCTOR_AUTH_SECRET - Authentication secret (optional)
#

require 'bundler/setup'
require 'conductor'

#
# Example 1: Basic TaskContext usage - accessing task info
#
Conductor::Worker.define('task_info_example', poll_interval: 100, thread_count: 5) do |task|
  # Get the current task context
  ctx = Conductor::Worker::TaskContext.current

  # Access task information
  task_id = ctx.task_id
  workflow_id = ctx.workflow_instance_id
  retry_count = ctx.retry_count
  poll_count = task.poll_count || 0

  puts "Task ID: #{task_id}"
  puts "Workflow ID: #{workflow_id}"
  puts "Retry Count: #{retry_count}"
  puts "Poll Count: #{poll_count}"

  {
    task_id: task_id,
    workflow_id: workflow_id,
    retry_count: retry_count,
    result: 'processed'
  }
end

#
# Example 2: Adding logs via TaskContext
#
Conductor::Worker.define('logging_example', poll_interval: 100, thread_count: 5) do |task|
  order_id = task.input_data['order_id'] || 'unknown'
  items = task.input_data['items'] || []

  ctx = Conductor::Worker::TaskContext.current

  # Add logs as processing progresses
  ctx.add_log("Starting to process order #{order_id}")
  ctx.add_log("Order has #{items.size} items")

  items.each_with_index do |item, i|
    sleep(0.1) # Simulate processing
    ctx.add_log("Processed item #{i + 1}/#{items.size}: #{item}")
  end

  ctx.add_log('Order processing completed')

  {
    order_id: order_id,
    items_processed: items.size,
    status: 'completed'
  }
end

#
# Example 3: Callback pattern - polling external service
#
Conductor::Worker.define('polling_example', poll_interval: 100, thread_count: 10) do |task|
  job_id = task.input_data['job_id'] || 'unknown'

  ctx = Conductor::Worker::TaskContext.current

  ctx.add_log("Checking status of job #{job_id}")

  # Simulate checking external service
  is_complete = rand > 0.7 # 30% chance of completion

  if is_complete
    ctx.add_log("Job #{job_id} is complete!")
    {
      job_id: job_id,
      status: 'completed',
      result: 'Job finished successfully'
    }
  else
    # Job still running - poll again in 30 seconds
    ctx.add_log("Job #{job_id} still running, will check again in 30s")
    ctx.set_callback_after(30)

    Conductor::Worker::TaskInProgress.new(
      callback_after_seconds: 30,
      output: {
        job_id: job_id,
        status: 'in_progress',
        message: 'Job still running'
      }
    )
  end
end

#
# Example 4: Retry logic with context awareness
#
Conductor::Worker.define('retry_aware_example', poll_interval: 100, thread_count: 5) do |task|
  operation = task.input_data['operation'] || 'default'

  ctx = Conductor::Worker::TaskContext.current

  retry_count = ctx.retry_count

  if retry_count.positive?
    ctx.add_log("This is retry attempt ##{retry_count}")
    # Could implement exponential backoff, different logic, etc.
  end

  ctx.add_log("Executing operation: #{operation}")

  # Simulate operation
  success = rand > 0.3

  if success
    ctx.add_log('Operation succeeded')
    { status: 'success', operation: operation }
  else
    ctx.add_log('Operation failed, will retry')
    raise StandardError, 'Operation failed'
  end
end

#
# Example 5: Accessing input parameters via context
#
Conductor::Worker.define('input_access_example', poll_interval: 100, thread_count: 5) do |_task|
  ctx = Conductor::Worker::TaskContext.current

  # Get all input parameters
  input_data = ctx.input

  ctx.add_log("Received input parameters: #{input_data.keys}")

  # Process based on input
  input_data.each do |key, value|
    ctx.add_log("  #{key} = #{value}")
  end

  {
    processed_keys: input_data.keys,
    input_count: input_data.size
  }
end

#
# Example 6: Long-running task with progress tracking
#
Conductor::Worker.define('progress_tracking_example', poll_interval: 100, thread_count: 5) do |task|
  total_steps = task.input_data['total_steps'] || 5

  ctx = Conductor::Worker::TaskContext.current
  poll_count = task.poll_count || 0

  ctx.add_log("Progress: step #{poll_count + 1}/#{total_steps}")

  if poll_count < total_steps - 1
    # Still processing
    progress = ((poll_count + 1).to_f / total_steps * 100).round

    Conductor::Worker::TaskInProgress.new(
      callback_after_seconds: 1,
      output: {
        current_step: poll_count + 1,
        total_steps: total_steps,
        progress_percent: progress,
        status: 'in_progress'
      }
    )
  else
    # Complete
    ctx.add_log('All steps completed!')
    {
      current_step: total_steps,
      total_steps: total_steps,
      progress_percent: 100,
      status: 'completed'
    }
  end
end

def main
  config = Conductor::Configuration.new(
    server_api_url: ENV.fetch('CONDUCTOR_SERVER_URL', 'http://localhost:8080/api'),
    auth_key: ENV.fetch('CONDUCTOR_AUTH_KEY', nil),
    auth_secret: ENV.fetch('CONDUCTOR_AUTH_SECRET', nil)
  )

  puts '=' * 60
  puts 'Conductor TaskContext Examples'
  puts '=' * 60
  puts
  puts 'Workers demonstrating TaskContext usage:'
  puts '  - task_info_example      - Access task metadata'
  puts '  - logging_example        - Add logs to task'
  puts '  - polling_example        - Use callback_after for polling'
  puts '  - retry_aware_example    - Handle retries intelligently'
  puts '  - input_access_example   - Access task input via context'
  puts '  - progress_tracking_example - Track progress across polls'
  puts
  puts 'Key TaskContext Features:'
  puts '  - Access task metadata (ID, workflow ID, retry count)'
  puts '  - Add logs visible in Conductor UI'
  puts '  - Set callback delays for polling patterns'
  puts '  - Thread-safe via Thread.current'
  puts '=' * 60
  puts
  puts 'Starting workers... Press Ctrl+C to stop'
  puts

  begin
    handler = Conductor::Worker::TaskHandler.new(
      configuration: config,
      scan_for_annotated_workers: true
    )

    shutdown = false
    Signal.trap('INT') do
      puts "\nShutting down gracefully..."
      shutdown = true
      handler.stop
    end

    handler.start
    handler.join unless shutdown
  rescue Interrupt
    puts 'Interrupted!'
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end

  puts "\nWorkers stopped. Goodbye!"
end

main if __FILE__ == $PROGRAM_NAME
