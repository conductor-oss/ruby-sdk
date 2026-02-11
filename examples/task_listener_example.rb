# frozen_string_literal: true

#
# Example demonstrating TaskRunnerEventsListener for pre/post processing of worker tasks.
#
# This example shows how to implement a custom event listener to:
# - Log task execution events
# - Add custom headers or context before task execution
# - Process task results after execution
# - Track task timing and errors
# - Implement retry logic or custom error handling
#
# The listener pattern is useful for:
# - Request/response logging
# - Distributed tracing integration
# - Custom metrics collection
# - Authentication/authorization
# - Data enrichment
# - Error recovery
#
# Usage:
#   ruby task_listener_example.rb
#
# Environment variables:
#   CONDUCTOR_SERVER_URL - Conductor server URL (default: http://localhost:8080/api)
#   CONDUCTOR_AUTH_KEY   - Authentication key (optional)
#   CONDUCTOR_AUTH_SECRET - Authentication secret (optional)
#

require 'bundler/setup'
require 'conductor'
require_relative 'event_listener_examples'

# Configure logging
logger = Logger.new($stdout)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, _progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity} -- #{msg}\n"
end

#
# Example worker tasks
#

# Simple calculator worker
Conductor::Worker.define('calculate', poll_interval: 100, thread_count: 5) do |task|
  n = task.input_data['n'] || 10

  # Fibonacci calculation (demonstrates CPU-bound work)
  fib = ->(x) { x <= 1 ? x : fib.call(x - 1) + fib.call(x - 2) }
  result = fib.call(n)

  { fibonacci: result, input: n }
end

# Long-running task with progress tracking
Conductor::Worker.define('long_running_task', poll_interval: 100, thread_count: 3) do |task|
  job_id = task.input_data['job_id'] || 'unknown'

  # Access task context for poll count
  ctx = Conductor::Worker::TaskContext.current
  poll_count = task.poll_count || 0

  ctx.add_log("Processing job #{job_id}, poll #{poll_count}/5")

  if poll_count < 5
    # Still processing - return TaskInProgress
    Conductor::Worker::TaskInProgress.new(
      callback_after_seconds: 1,
      output: {
        job_id: job_id,
        status: 'processing',
        poll_count: poll_count,
        progress: poll_count * 20,
        message: "Working on job #{job_id}, poll #{poll_count}/5"
      }
    )
  else
    # Complete after 5 polls
    ctx.add_log("Job #{job_id} completed")
    {
      job_id: job_id,
      status: 'completed',
      result: 'success',
      total_time_seconds: 5,
      total_polls: poll_count
    }
  end
end

# Worker that simulates failures for testing error handling
Conductor::Worker.define('flaky_worker', poll_interval: 100, thread_count: 2) do |task|
  fail_rate = task.input_data['fail_rate'] || 0.3

  raise StandardError, 'Random failure for testing' if rand < fail_rate

  { status: 'success', fail_rate: fail_rate }
end

def main
  # Configure Conductor connection
  config = Conductor::Configuration.new(
    server_api_url: ENV['CONDUCTOR_SERVER_URL'] || 'http://localhost:8080/api',
    auth_key: ENV.fetch('CONDUCTOR_AUTH_KEY', nil),
    auth_secret: ENV.fetch('CONDUCTOR_AUTH_SECRET', nil)
  )

  # Create event listeners
  logger_listener = TaskExecutionLogger.new
  timing_tracker = TaskTimingTracker.new
  tracing_listener = DistributedTracingListener.new
  error_tracker = ErrorTrackingListener.new(
    alert_threshold: 3,
    alert_callback: ->(alert) { puts "[ALERT CALLBACK] #{alert.inspect}" }
  )

  puts '=' * 80
  puts 'TaskRunnerEventsListener Example'
  puts '=' * 80
  puts
  puts 'This example demonstrates event listeners for task pre/post processing:'
  puts '  1. TaskExecutionLogger - Logs all task lifecycle events'
  puts '  2. TaskTimingTracker - Tracks and reports execution statistics'
  puts '  3. DistributedTracingListener - Simulates distributed tracing'
  puts '  4. ErrorTrackingListener - Aggregates errors and alerts'
  puts
  puts 'Workers available:'
  puts '  - calculate: Fibonacci calculator'
  puts '  - long_running_task: Multi-poll task with progress tracking'
  puts '  - flaky_worker: Random failure simulation'
  puts
  puts 'Press Ctrl+C to stop...'
  puts '=' * 80
  puts

  begin
    # Create task handler with multiple listeners
    handler = Conductor::Worker::TaskHandler.new(
      configuration: config,
      scan_for_annotated_workers: true,
      event_listeners: [
        logger_listener,
        timing_tracker,
        tracing_listener,
        error_tracker
      ]
    )

    # Handle graceful shutdown
    shutdown = false
    Signal.trap('INT') do
      puts "\nShutting down gracefully..."
      shutdown = true
      handler.stop
    end

    handler.start

    # Print statistics periodically
    Thread.new do
      loop do
        sleep 30
        break if shutdown

        puts "\n--- Statistics ---"
        timing_tracker.all_stats.each do |task_type, stats|
          puts "#{task_type}: #{stats.inspect}"
        end

        error_summary = error_tracker.error_summary
        puts "Errors: #{error_summary.inspect}" unless error_summary.empty?
        puts '------------------\n'
      end
    end

    handler.join unless shutdown
  rescue Interrupt
    puts 'Interrupted!'
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end

  puts "\nFinal Statistics:"
  timing_tracker.all_stats.each do |task_type, stats|
    puts "  #{task_type}: #{stats.inspect}"
  end

  puts "\nWorkers stopped. Goodbye!"
end

main if __FILE__ == $PROGRAM_NAME
