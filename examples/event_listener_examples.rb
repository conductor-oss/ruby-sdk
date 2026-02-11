# frozen_string_literal: true

#
# Reusable event listener examples for TaskRunnerEventsListener.
#
# This module provides example event listener implementations that can be used
# in any application to monitor and track task execution.
#
# Available Listeners:
#   - TaskExecutionLogger: Simple logging of all task lifecycle events
#   - TaskTimingTracker: Statistical tracking of task execution times
#   - DistributedTracingListener: Simulated distributed tracing integration
#   - ErrorTrackingListener: Error aggregation and alerting
#
# Usage:
#   require_relative 'event_listener_examples'
#
#   handler = Conductor::Worker::TaskHandler.new(
#     configuration: config,
#     event_listeners: [
#       TaskExecutionLogger.new,
#       TaskTimingTracker.new
#     ]
#   )
#   handler.start
#   handler.join
#

require 'logger'
require 'conductor'

# Simple listener that logs all task execution events.
#
# Demonstrates basic pre/post processing:
# - on_task_execution_started: Pre-processing before task executes
# - on_task_execution_completed: Post-processing after successful execution
# - on_task_execution_failure: Error handling after failed execution
#
class TaskExecutionLogger
  def initialize(logger: nil)
    @logger = logger || Logger.new($stdout)
    @logger.formatter = proc do |severity, datetime, _progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity} -- #{msg}\n"
    end
  end

  # Called before task execution begins (pre-processing).
  #
  # Use this for:
  # - Setting up context (tracing, logging context)
  # - Validating preconditions
  # - Starting timers
  # - Recording audit events
  #
  def on_task_execution_started(event)
    @logger.info("[PRE] Starting task '#{event.task_type}' " \
                 "(task_id=#{event.task_id}, worker=#{event.worker_id})")
  end

  # Called after task execution completes successfully (post-processing).
  #
  # Use this for:
  # - Logging results
  # - Sending notifications
  # - Updating external systems
  # - Recording metrics
  #
  def on_task_execution_completed(event)
    @logger.info("[POST] Completed task '#{event.task_type}' " \
                 "(task_id=#{event.task_id}, duration=#{event.duration_ms.round(2)}ms, " \
                 "output_size=#{event.output_size_bytes || 0} bytes)")
  end

  # Called when task execution fails (error handling).
  #
  # Use this for:
  # - Error logging
  # - Alerting
  # - Retry logic
  # - Cleanup operations
  #
  def on_task_execution_failure(event)
    @logger.error("[ERROR] Failed task '#{event.task_type}' " \
                  "(task_id=#{event.task_id}, duration=#{event.duration_ms.round(2)}ms, " \
                  "error=#{event.cause.class}: #{event.cause.message})")
  end

  # Called when polling for tasks begins.
  def on_poll_started(event)
    @logger.debug("Polling for '#{event.task_type}' tasks (poll_count=#{event.poll_count})")
  end

  # Called when polling completes successfully.
  def on_poll_completed(event)
    return unless event.tasks_received.positive?

    @logger.debug("Received #{event.tasks_received} '#{event.task_type}' tasks " \
                  "in #{event.duration_ms.round(2)}ms")
  end

  # Called when polling fails.
  def on_poll_failure(event)
    @logger.warn("Poll failed for '#{event.task_type}': #{event.cause.message}")
  end

  # Called when task update fails after all retries (CRITICAL).
  def on_task_update_failure(event)
    @logger.fatal("[CRITICAL] Task result LOST for '#{event.task_type}' " \
                  "(task_id=#{event.task_id}, retries=#{event.retry_count})")
  end
end

# Advanced listener that tracks task execution times and provides statistics.
#
# Demonstrates:
# - Stateful event processing
# - Aggregating data across multiple events
# - Custom business logic in listeners
#
class TaskTimingTracker
  attr_reader :task_times, :task_errors

  def initialize(logger: nil, report_interval: 10)
    @logger = logger || Logger.new($stdout)
    @task_times = Hash.new { |h, k| h[k] = [] }
    @task_errors = Hash.new(0)
    @report_interval = report_interval
    @mutex = Mutex.new
  end

  # Track successful task execution times.
  def on_task_execution_completed(event)
    @mutex.synchronize do
      @task_times[event.task_type] << event.duration_ms

      # Print stats every N completions
      count = @task_times[event.task_type].size
      return unless (count % @report_interval).zero?

      durations = @task_times[event.task_type]
      avg = durations.sum / durations.size
      min_time = durations.min
      max_time = durations.max

      @logger.info("Stats for '#{event.task_type}': " \
                   "count=#{count}, avg=#{avg.round(2)}ms, " \
                   "min=#{min_time.round(2)}ms, max=#{max_time.round(2)}ms")
    end
  end

  # Track task failures.
  def on_task_execution_failure(event)
    @mutex.synchronize do
      @task_errors[event.task_type] += 1
      @logger.warn("Task '#{event.task_type}' has failed #{@task_errors[event.task_type]} times")
    end
  end

  # Get statistics for a task type.
  # @param task_type [String] Task type name
  # @return [Hash] Statistics including count, avg, min, max, error_count
  def stats_for(task_type)
    @mutex.synchronize do
      durations = @task_times[task_type]
      return nil if durations.empty?

      {
        count: durations.size,
        avg_ms: durations.sum / durations.size,
        min_ms: durations.min,
        max_ms: durations.max,
        error_count: @task_errors[task_type]
      }
    end
  end

  # Get all statistics.
  # @return [Hash] Statistics for all task types
  def all_stats
    @mutex.synchronize do
      @task_times.keys.each_with_object({}) do |task_type, result|
        durations = @task_times[task_type]
        result[task_type] = {
          count: durations.size,
          avg_ms: durations.sum / durations.size,
          min_ms: durations.min,
          max_ms: durations.max,
          error_count: @task_errors[task_type]
        }
      end
    end
  end
end

# Example listener for distributed tracing integration.
#
# Demonstrates how to:
# - Generate trace IDs
# - Propagate trace context
# - Create spans for task execution
#
# In production, replace the logging with actual tracing library calls
# (OpenTelemetry, Jaeger, Zipkin, etc.)
#
class DistributedTracingListener
  def initialize(logger: nil)
    @logger = logger || Logger.new($stdout)
    @active_traces = {}
    @mutex = Mutex.new
  end

  # Start a trace span when task execution begins.
  def on_task_execution_started(event)
    trace_id = "trace-#{event.task_id[0..7]}"
    span_id = "span-#{event.task_id[0..7]}"

    @mutex.synchronize do
      @active_traces[event.task_id] = {
        trace_id: trace_id,
        span_id: span_id,
        start_time: Time.now,
        task_type: event.task_type
      }
    end

    @logger.info("[TRACE] Started span: trace_id=#{trace_id}, span_id=#{span_id}, " \
                 "task_type=#{event.task_type}")
  end

  # End the trace span when task execution completes.
  def on_task_execution_completed(event)
    trace_info = @mutex.synchronize { @active_traces.delete(event.task_id) }
    return unless trace_info

    duration = (Time.now - trace_info[:start_time]) * 1000

    @logger.info("[TRACE] Completed span: trace_id=#{trace_info[:trace_id]}, " \
                 "span_id=#{trace_info[:span_id]}, duration=#{duration.round(2)}ms, status=SUCCESS")
  end

  # Mark the trace span as failed.
  def on_task_execution_failure(event)
    trace_info = @mutex.synchronize { @active_traces.delete(event.task_id) }
    return unless trace_info

    duration = (Time.now - trace_info[:start_time]) * 1000

    @logger.info("[TRACE] Failed span: trace_id=#{trace_info[:trace_id]}, " \
                 "span_id=#{trace_info[:span_id]}, duration=#{duration.round(2)}ms, " \
                 "status=ERROR, error=#{event.cause.class}")
  end
end

# Error tracking listener for aggregating and alerting on errors.
#
# Demonstrates:
# - Error aggregation by type
# - Threshold-based alerting
# - Integration with external error tracking services
#
class ErrorTrackingListener
  def initialize(logger: nil, alert_threshold: 5, alert_callback: nil)
    @logger = logger || Logger.new($stdout)
    @alert_threshold = alert_threshold
    @alert_callback = alert_callback
    @errors = Hash.new { |h, k| h[k] = [] }
    @mutex = Mutex.new
  end

  def on_task_execution_failure(event)
    @mutex.synchronize do
      error_key = "#{event.task_type}:#{event.cause.class}"
      @errors[error_key] << {
        task_id: event.task_id,
        workflow_instance_id: event.workflow_instance_id,
        message: event.cause.message,
        is_retryable: event.is_retryable,
        timestamp: event.timestamp
      }

      # Check if threshold exceeded
      recent_errors = @errors[error_key].select do |e|
        e[:timestamp] > Time.now - 300 # Last 5 minutes
      end

      trigger_alert(event.task_type, event.cause.class.to_s, recent_errors.size) if recent_errors.size >= @alert_threshold
    end
  end

  def on_task_update_failure(event)
    @logger.fatal("[ALERT] CRITICAL: Task result lost! task_id=#{event.task_id}, " \
                  "task_type=#{event.task_type}, retries=#{event.retry_count}")

    # Always alert on task update failures
    return unless @alert_callback

    @alert_callback.call(
      type: :task_update_failure,
      severity: :critical,
      task_id: event.task_id,
      task_type: event.task_type,
      retry_count: event.retry_count
    )
  end

  # Get error summary.
  # @return [Hash] Error counts by task_type:error_class
  def error_summary
    @mutex.synchronize do
      @errors.transform_values(&:size)
    end
  end

  private

  def trigger_alert(task_type, error_class, count)
    @logger.warn("[ALERT] High error rate: #{task_type} has #{count} " \
                 "#{error_class} errors in last 5 minutes")

    return unless @alert_callback

    @alert_callback.call(
      type: :high_error_rate,
      severity: :warning,
      task_type: task_type,
      error_class: error_class,
      count: count
    )
  end
end

# SLA monitoring listener that alerts when tasks exceed duration thresholds.
#
# Demonstrates:
# - Configuration-driven thresholds
# - Percentage-based alerting
# - P99 latency tracking
#
class SLAMonitorListener
  def initialize(thresholds: {}, logger: nil, alert_callback: nil)
    @thresholds = thresholds # { 'task_type' => max_duration_ms }
    @logger = logger || Logger.new($stdout)
    @alert_callback = alert_callback
    @violations = Hash.new { |h, k| h[k] = [] }
    @mutex = Mutex.new
  end

  def on_task_execution_completed(event)
    threshold = @thresholds[event.task_type]
    return unless threshold && event.duration_ms > threshold

    @mutex.synchronize do
      @violations[event.task_type] << {
        task_id: event.task_id,
        duration_ms: event.duration_ms,
        threshold_ms: threshold,
        timestamp: event.timestamp
      }
    end

    @logger.warn("[SLA] Violation: '#{event.task_type}' took #{event.duration_ms.round(2)}ms " \
                 "(threshold: #{threshold}ms)")

    return unless @alert_callback

    @alert_callback.call(
      type: :sla_violation,
      task_type: event.task_type,
      task_id: event.task_id,
      duration_ms: event.duration_ms,
      threshold_ms: threshold
    )
  end

  # Get SLA violation summary.
  # @return [Hash] Violation counts by task type
  def violation_summary
    @mutex.synchronize do
      @violations.transform_values(&:size)
    end
  end

  # Get recent violations for a task type.
  # @param task_type [String] Task type name
  # @param limit [Integer] Maximum number of violations to return
  # @return [Array<Hash>] Recent violations
  def recent_violations(task_type, limit: 10)
    @mutex.synchronize do
      @violations[task_type].last(limit)
    end
  end
end

# Example showing how to run with event listeners (for documentation)
if __FILE__ == $PROGRAM_NAME
  puts <<~USAGE
    Event Listener Examples

    This file provides reusable event listener implementations.
    Import them in your application:

      require_relative 'event_listener_examples'

      # Create listeners
      logger_listener = TaskExecutionLogger.new
      timing_tracker = TaskTimingTracker.new
      tracing_listener = DistributedTracingListener.new

      # Use with TaskHandler
      handler = Conductor::Worker::TaskHandler.new(
        configuration: config,
        event_listeners: [
          logger_listener,
          timing_tracker,
          tracing_listener
        ]
      )

      handler.start
      handler.join

    Available Listeners:
      - TaskExecutionLogger: Logs all task lifecycle events
      - TaskTimingTracker: Tracks execution statistics
      - DistributedTracingListener: Simulates distributed tracing
      - ErrorTrackingListener: Aggregates errors and alerts
      - SLAMonitorListener: Monitors SLA violations

  USAGE
end
