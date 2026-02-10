# frozen_string_literal: true

require 'concurrent'
require 'logger'
require_relative '../client/task_client'
require_relative '../http/models/task'
require_relative '../http/models/task_result'
require_relative '../http/models/task_result_status'
require_relative '../exceptions'
require_relative 'task_context'
require_relative 'task_in_progress'
require_relative 'worker_config'
require_relative 'events/task_runner_events'
require_relative 'events/sync_event_dispatcher'
require_relative 'events/listener_registry'

module Conductor
  module Worker
    # TaskRunner - The core polling loop that runs in a dedicated thread
    # Implements batch polling, adaptive backoff, capacity management, and event publishing
    class TaskRunner
      # Retry backoffs for task update (in seconds)
      RETRY_BACKOFFS = [0, 10, 20, 30].freeze

      # Maximum exponent for adaptive backoff to prevent overflow
      MAX_BACKOFF_EXPONENT = 10

      # Maximum auth failure backoff in seconds
      MAX_AUTH_BACKOFF_SECONDS = 60

      attr_reader :worker, :running

      # Initialize TaskRunner for a specific worker
      # @param worker [Worker] The worker instance
      # @param configuration [Configuration] Conductor configuration
      # @param event_dispatcher [SyncEventDispatcher] Shared event dispatcher
      # @param logger [Logger] Logger instance
      def initialize(worker, configuration:, event_dispatcher: nil, logger: nil)
        @worker = worker
        @configuration = configuration || Configuration.new
        @event_dispatcher = event_dispatcher || Events::SyncEventDispatcher.new
        @logger = logger || create_default_logger

        # Create task client for API communication
        @task_client = Client::TaskClient.new(@configuration)

        # Resolve worker configuration
        resolved_config = WorkerConfig.resolve(
          worker.task_definition_name,
          extract_worker_options(worker)
        )
        apply_resolved_config(resolved_config)

        # Create thread pool executor for task execution
        @executor = Concurrent::ThreadPoolExecutor.new(
          min_threads: 1,
          max_threads: @max_workers,
          max_queue: @max_workers * 2,
          fallback_policy: :caller_runs
        )

        # State tracking
        @running_tasks = Concurrent::Set.new
        @consecutive_empty_polls = Concurrent::AtomicFixnum.new(0)
        @auth_failures = Concurrent::AtomicFixnum.new(0)
        @last_auth_failure_time = nil
        @last_poll_time = nil
        @poll_count = Concurrent::AtomicFixnum.new(0)
        @shutdown = Concurrent::AtomicBoolean.new(false)
        @mutex = Mutex.new
      end

      # Main polling loop (runs until shutdown)
      def run
        @logger.info("Starting TaskRunner for '#{@worker.task_definition_name}' " \
                     "(thread_count=#{@max_workers}, poll_interval=#{@poll_interval}ms)")

        # Register task definition if configured
        register_task_definition if @worker.register_task_def

        until @shutdown.true?
          begin
            run_once
          rescue StandardError => e
            @logger.error("Error in polling loop: #{e.message}")
            @logger.debug(e.backtrace.join("\n")) if e.backtrace
            sleep(1) # Brief pause before retrying
          end
        end

        cleanup
        @logger.info("TaskRunner for '#{@worker.task_definition_name}' stopped")
      end

      # Single iteration of the polling loop
      def run_once
        # 1. Cleanup completed tasks
        cleanup_completed_tasks

        # 2. Check capacity
        current_capacity = @running_tasks.size
        if current_capacity >= @max_workers
          sleep(0.001) # 1ms sleep to prevent busy-waiting
          return
        end

        available_slots = @max_workers - current_capacity

        # 3. Adaptive backoff for empty polls
        if @consecutive_empty_polls.value > 0
          backoff_ms = calculate_adaptive_backoff
          elapsed_ms = @last_poll_time ? (Time.now - @last_poll_time) * 1000 : backoff_ms

          if elapsed_ms < backoff_ms
            sleep_time = (backoff_ms - elapsed_ms) / 1000.0
            sleep([sleep_time, 0.001].max)
            return
          end
        end

        # 4. Batch poll for tasks
        @last_poll_time = Time.now
        tasks = batch_poll(available_slots)

        # 5. Submit tasks for execution
        if tasks.empty?
          @consecutive_empty_polls.increment
        else
          @consecutive_empty_polls.value = 0
          tasks.each do |task|
            submit_task(task)
          end
        end
      end

      # Signal the runner to stop
      def shutdown
        @shutdown.make_true
      end

      # Check if runner is running
      # @return [Boolean]
      def running?
        !@shutdown.true?
      end

      private

      # Create default logger
      # @return [Logger]
      def create_default_logger
        logger = Logger.new($stdout)
        logger.level = Logger::INFO
        logger.formatter = proc do |severity, datetime, _progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity} -- #{msg}\n"
        end
        logger
      end

      # Extract worker options as a hash
      # @param worker [Worker] Worker instance
      # @return [Hash]
      def extract_worker_options(worker)
        options = {}
        Worker::DEFAULTS.keys.each do |key|
          options[key] = worker.send(key) if worker.respond_to?(key)
        end
        options
      end

      # Apply resolved configuration
      # @param config [Hash] Resolved configuration
      def apply_resolved_config(config)
        @poll_interval = config[:poll_interval]
        @max_workers = config[:thread_count]
        @worker_id = config[:worker_id]
        @domain = config[:domain]
        @poll_timeout = config[:poll_timeout]
      end

      # Cleanup completed task futures
      def cleanup_completed_tasks
        @running_tasks.each do |future|
          @running_tasks.delete(future) if future.fulfilled? || future.rejected?
        end
      end

      # Calculate adaptive backoff for empty polls
      # @return [Float] Backoff in milliseconds
      def calculate_adaptive_backoff
        exponent = [@consecutive_empty_polls.value, MAX_BACKOFF_EXPONENT].min
        [1.0 * (2**exponent), @poll_interval].min
      end

      # Batch poll for tasks with auth failure backoff
      # @param count [Integer] Number of tasks to poll for
      # @return [Array<Hash>] Array of task hashes
      def batch_poll(count)
        # Skip if worker is paused
        return [] if @worker.paused

        # Auth failure exponential backoff
        if @auth_failures.value > 0 && @last_auth_failure_time
          backoff_seconds = [2**@auth_failures.value, MAX_AUTH_BACKOFF_SECONDS].min
          elapsed = Time.now - @last_auth_failure_time
          return [] if elapsed < backoff_seconds
        end

        # Publish PollStarted event
        @event_dispatcher.publish(Events::PollStarted.new(
          task_type: @worker.task_definition_name,
          worker_id: @worker_id,
          poll_count: @poll_count.value
        ))

        start_time = Time.now

        begin
          # HTTP batch poll - use domain only if it's a non-empty string
          domain_param = @domain.to_s.empty? ? nil : @domain

          tasks = @task_client.batch_poll_tasks(
            @worker.task_definition_name,
            count: count,
            timeout: @poll_timeout,
            worker_id: @worker_id,
            domain: domain_param
          )

          tasks ||= []
          duration_ms = (Time.now - start_time) * 1000
          @poll_count.increment

          # Publish PollCompleted event
          @event_dispatcher.publish(Events::PollCompleted.new(
            task_type: @worker.task_definition_name,
            duration_ms: duration_ms,
            tasks_received: tasks.size
          ))

          # Reset auth failures on success
          @auth_failures.value = 0

          tasks
        rescue AuthorizationError => e
          handle_auth_failure(e, start_time)
          []
        rescue StandardError => e
          handle_poll_failure(e, start_time)
          []
        end
      end

      # Handle authorization failure
      # @param error [AuthorizationError] The error
      # @param start_time [Time] When the poll started
      def handle_auth_failure(error, start_time)
        @auth_failures.increment
        @last_auth_failure_time = Time.now
        duration_ms = (Time.now - start_time) * 1000

        @event_dispatcher.publish(Events::PollFailure.new(
          task_type: @worker.task_definition_name,
          duration_ms: duration_ms,
          cause: error
        ))

        backoff = [2**@auth_failures.value, MAX_AUTH_BACKOFF_SECONDS].min
        @logger.warn("Auth failure ##{@auth_failures.value} for '#{@worker.task_definition_name}', " \
                     "backing off #{backoff}s: #{error.message}")
      end

      # Handle general poll failure
      # @param error [StandardError] The error
      # @param start_time [Time] When the poll started
      def handle_poll_failure(error, start_time)
        duration_ms = (Time.now - start_time) * 1000

        @event_dispatcher.publish(Events::PollFailure.new(
          task_type: @worker.task_definition_name,
          duration_ms: duration_ms,
          cause: error
        ))

        @logger.error("Poll failed for '#{@worker.task_definition_name}': #{error.message}")
      end

      # Submit a task for execution
      # @param task [Hash] Task data from API
      def submit_task(task)
        future = Concurrent::Future.execute(executor: @executor) do
          execute_and_update(task)
        end
        @running_tasks << future
      end

      # Execute a task and update the result
      # @param task [Hash] Task data from API
      def execute_and_update(task)
        task_result = execute_task(task)

        # Skip update for TaskInProgress (task stays in IN_PROGRESS state)
        return if task_result.nil?

        # Don't update if result is IN_PROGRESS (will be polled again)
        return if task_result.status == Http::Models::TaskResultStatus::IN_PROGRESS &&
                  task_result.callback_after_seconds&.positive?

        update_task_with_retry(task_result)
      end

      # Execute a task
      # @param task [Task] Task object from API (already deserialized)
      # @return [TaskResult, nil]
      def execute_task(task)
        # Ensure we have a Task object (may be Hash if deserialization was skipped)
        task_obj = task.is_a?(Http::Models::Task) ? task : Http::Models::Task.from_hash(task)

        # Create initial TaskResult for context
        initial_result = Http::Models::TaskResult.new
        initial_result.task_id = task_obj.task_id
        initial_result.workflow_instance_id = task_obj.workflow_instance_id
        initial_result.worker_id = @worker_id

        # Set task context (thread-local)
        TaskContext.current = TaskContext.new(task_obj, initial_result)

        start_time = Time.now

        # Publish TaskExecutionStarted
        @event_dispatcher.publish(Events::TaskExecutionStarted.new(
          task_type: @worker.task_definition_name,
          task_id: task_obj.task_id,
          worker_id: @worker_id,
          workflow_instance_id: task_obj.workflow_instance_id
        ))

        begin
          # Execute worker
          task_result = @worker.execute(task_obj)

          duration_ms = (Time.now - start_time) * 1000

          # Merge logs from context
          ctx = TaskContext.current
          if ctx&.task_result&.logs && !ctx.task_result.logs.empty?
            task_result.logs ||= []
            task_result.logs.concat(ctx.task_result.logs)
          end

          # Merge callback_after from context
          task_result.callback_after_seconds ||= ctx&.callback_after_seconds

          output_size = calculate_output_size(task_result)

          # Publish TaskExecutionCompleted
          @event_dispatcher.publish(Events::TaskExecutionCompleted.new(
            task_type: @worker.task_definition_name,
            task_id: task_obj.task_id,
            worker_id: @worker_id,
            workflow_instance_id: task_obj.workflow_instance_id,
            duration_ms: duration_ms,
            output_size_bytes: output_size
          ))

          task_result

        rescue NonRetryableError => e
          handle_non_retryable_error(task_obj, e, start_time)

        rescue StandardError => e
          handle_retryable_error(task_obj, e, start_time)

        ensure
          TaskContext.clear
        end
      end

      # Calculate output size in bytes
      # @param task_result [TaskResult]
      # @return [Integer]
      def calculate_output_size(task_result)
        return 0 unless task_result.output_data

        task_result.output_data.to_json.bytesize
      rescue StandardError
        0
      end

      # Handle non-retryable error
      # @param task [Task] Task object
      # @param error [NonRetryableError] The error
      # @param start_time [Time] When execution started
      # @return [TaskResult]
      def handle_non_retryable_error(task, error, start_time)
        duration_ms = (Time.now - start_time) * 1000

        task_result = Http::Models::TaskResult.failed_with_terminal_error(error.message)
        task_result.task_id = task.task_id
        task_result.workflow_instance_id = task.workflow_instance_id
        task_result.worker_id = @worker_id
        task_result.log("NonRetryableError: #{error.class}: #{error.message}")

        @event_dispatcher.publish(Events::TaskExecutionFailure.new(
          task_type: @worker.task_definition_name,
          task_id: task.task_id,
          worker_id: @worker_id,
          workflow_instance_id: task.workflow_instance_id,
          duration_ms: duration_ms,
          cause: error,
          is_retryable: false
        ))

        @logger.warn("Task #{task.task_id} failed with terminal error: #{error.message}")
        task_result
      end

      # Handle retryable error
      # @param task [Task] Task object
      # @param error [StandardError] The error
      # @param start_time [Time] When execution started
      # @return [TaskResult]
      def handle_retryable_error(task, error, start_time)
        duration_ms = (Time.now - start_time) * 1000

        task_result = Http::Models::TaskResult.failed(error.message)
        task_result.task_id = task.task_id
        task_result.workflow_instance_id = task.workflow_instance_id
        task_result.worker_id = @worker_id

        backtrace = error.backtrace&.first(5)&.join("\n") || ''
        task_result.log("Error: #{error.class}: #{error.message}\n#{backtrace}")

        @event_dispatcher.publish(Events::TaskExecutionFailure.new(
          task_type: @worker.task_definition_name,
          task_id: task.task_id,
          worker_id: @worker_id,
          workflow_instance_id: task.workflow_instance_id,
          duration_ms: duration_ms,
          cause: error,
          is_retryable: true
        ))

        @logger.error("Task #{task.task_id} failed: #{error.message}")
        task_result
      end

      # Update task with retry logic
      # @param task_result [TaskResult] The result to send
      def update_task_with_retry(task_result)
        RETRY_BACKOFFS.each_with_index do |backoff, attempt|
          sleep(backoff) if backoff.positive?

          begin
            @task_client.update_task(task_result)
            return # Success
          rescue StandardError => e
            @logger.error("Task update failed (attempt #{attempt + 1}/#{RETRY_BACKOFFS.size}): #{e.message}")

            if attempt == RETRY_BACKOFFS.size - 1
              # All retries exhausted - CRITICAL: task result is lost
              @logger.fatal("CRITICAL: Task update failed after #{RETRY_BACKOFFS.size} attempts. " \
                            "Task #{task_result.task_id} result is LOST.")

              @event_dispatcher.publish(Events::TaskUpdateFailure.new(
                task_type: @worker.task_definition_name,
                task_id: task_result.task_id,
                worker_id: @worker_id,
                workflow_instance_id: task_result.workflow_instance_id,
                cause: e,
                retry_count: RETRY_BACKOFFS.size,
                task_result: task_result
              ))
            end
          end
        end
      end

      # Register task definition if configured
      def register_task_definition
        @logger.info("Task definition registration not yet implemented")
        # TODO: Implement task definition registration
      end

      # Cleanup resources
      def cleanup
        @executor.shutdown
        @executor.wait_for_termination(5)
        @executor.kill unless @executor.shutdown?

        @event_dispatcher.clear
      rescue StandardError => e
        @logger.warn("Error during cleanup: #{e.message}")
      end
    end
  end
end
