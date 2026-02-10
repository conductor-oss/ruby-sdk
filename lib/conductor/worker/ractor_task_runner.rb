# frozen_string_literal: true

require 'logger'
require_relative '../http/models/task'
require_relative '../http/models/task_result'
require_relative '../http/models/task_result_status'
require_relative '../exceptions'
require_relative 'task_context'
require_relative 'task_in_progress'
require_relative 'worker_config'
require_relative 'events/task_runner_events'

module Conductor
  module Worker
    # RactorTaskRunner - Ractor-based runner for CPU-bound workers
    # Provides true parallelism by running in isolated Ractors (no GVL sharing)
    #
    # Key differences from TaskRunner:
    # - Creates HTTP client INSIDE the Ractor (can't be shared)
    # - Sequential task execution within each Ractor
    # - Events sent to main thread via Ractor messaging
    # - Parallelism comes from multiple Ractors (thread_count = Ractor count)
    # - Requires Ruby 3.1+
    #
    # @example
    #   worker = Worker.new('cpu_task', isolation: :ractor, thread_count: 4) { |t| heavy_computation(t) }
    #   handler = TaskHandler.new(workers: [worker])
    #   handler.start
    class RactorTaskRunner
      # Retry backoffs for task update (in seconds)
      RETRY_BACKOFFS = [0, 10, 20, 30].freeze

      # Maximum exponent for adaptive backoff
      MAX_BACKOFF_EXPONENT = 10

      # Maximum auth failure backoff in seconds
      MAX_AUTH_BACKOFF_SECONDS = 60

      attr_reader :worker, :ractor_id

      # Initialize RactorTaskRunner
      # Note: HTTP client is created inside run() after Ractor starts
      # @param worker [Worker] The worker instance (must be Ractor-safe)
      # @param configuration [Configuration] Conductor configuration (serializable parts)
      # @param ractor_id [Integer] Identifier for this Ractor instance
      # @param event_queue [Ractor] Main Ractor to send events to (optional)
      def initialize(worker, configuration:, ractor_id: 0, event_queue: nil)
        @worker = worker
        @configuration_hash = serialize_configuration(configuration)
        @ractor_id = ractor_id
        @event_queue = event_queue

        # These will be created inside the Ractor
        @task_client = nil
        @logger = nil

        # State tracking (will be initialized in run)
        @consecutive_empty_polls = 0
        @auth_failures = 0
        @last_auth_failure_time = nil
        @last_poll_time = nil
        @poll_count = 0
        @shutdown = false
      end

      # Main polling loop - runs inside a Ractor
      # Creates HTTP client after Ractor starts (can't be passed in)
      def run
        setup_ractor_resources
        @logger.info("[Ractor #{@ractor_id}] Starting RactorTaskRunner for '#{@worker.task_definition_name}'")

        until @shutdown
          begin
            run_once
          rescue StandardError => e
            @logger.error("[Ractor #{@ractor_id}] Error in polling loop: #{e.message}")
            sleep(1)
          end
        end

        cleanup
        @logger.info("[Ractor #{@ractor_id}] RactorTaskRunner stopped")
      end

      # Single iteration of the polling loop
      def run_once
        # Adaptive backoff for empty polls
        if @consecutive_empty_polls > 0
          backoff_ms = calculate_adaptive_backoff
          elapsed_ms = @last_poll_time ? (Time.now - @last_poll_time) * 1000 : backoff_ms

          if elapsed_ms < backoff_ms
            sleep((backoff_ms - elapsed_ms) / 1000.0)
            return
          end
        end

        # Poll for a single task (Ractor processes sequentially)
        @last_poll_time = Time.now
        task = poll_task

        if task.nil?
          @consecutive_empty_polls += 1
        else
          @consecutive_empty_polls = 0
          execute_and_update(task)
        end
      end

      # Signal shutdown
      def shutdown
        @shutdown = true
      end

      private

      # Serialize configuration for Ractor transfer
      # @param config [Configuration] Configuration object
      # @return [Hash] Serializable configuration hash
      def serialize_configuration(config)
        {
          server_api_url: config.server_api_url,
          authentication_settings: config.authentication_settings ? {
            key_id: config.authentication_settings.key_id,
            key_secret: config.authentication_settings.key_secret
          } : nil
        }
      end

      # Setup resources that must be created inside the Ractor
      def setup_ractor_resources
        # Create logger
        @logger = Logger.new($stdout)
        @logger.level = Logger::INFO
        @logger.formatter = proc do |severity, datetime, _progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity} [R#{@ractor_id}] -- #{msg}\n"
        end

        # Recreate configuration from hash
        config = Configuration.new(
          server_api_url: @configuration_hash[:server_api_url]
        )
        if @configuration_hash[:authentication_settings]
          config.authentication_settings = Configuration::AuthenticationSettings.new(
            key_id: @configuration_hash[:authentication_settings][:key_id],
            key_secret: @configuration_hash[:authentication_settings][:key_secret]
          )
        end

        # Create HTTP client inside Ractor
        @task_client = Client::TaskClient.new(config)

        # Resolve worker configuration
        resolved = WorkerConfig.resolve(
          @worker.task_definition_name,
          extract_worker_options
        )
        @poll_interval = resolved[:poll_interval]
        @worker_id = "#{resolved[:worker_id]}-ractor-#{@ractor_id}"
        @domain = resolved[:domain]
        @poll_timeout = resolved[:poll_timeout]
      end

      # Extract worker options
      # @return [Hash]
      def extract_worker_options
        options = {}
        Worker::DEFAULTS.keys.each do |key|
          options[key] = @worker.send(key) if @worker.respond_to?(key)
        end
        options
      end

      # Calculate adaptive backoff
      # @return [Float] Backoff in milliseconds
      def calculate_adaptive_backoff
        exponent = [@consecutive_empty_polls, MAX_BACKOFF_EXPONENT].min
        [1.0 * (2**exponent), @poll_interval].min
      end

      # Poll for a single task
      # @return [Hash, nil] Task data or nil
      def poll_task
        return nil if @worker.paused

        # Auth failure backoff
        if @auth_failures > 0 && @last_auth_failure_time
          backoff_seconds = [2**@auth_failures, MAX_AUTH_BACKOFF_SECONDS].min
          elapsed = Time.now - @last_auth_failure_time
          return nil if elapsed < backoff_seconds
        end

        publish_event(Events::PollStarted.new(
          task_type: @worker.task_definition_name,
          worker_id: @worker_id,
          poll_count: @poll_count
        ))

        start_time = Time.now

        begin
          domain_param = @domain.to_s.empty? ? nil : @domain

          # Poll for single task (Ractor processes one at a time)
          tasks = @task_client.batch_poll(
            @worker.task_definition_name,
            count: 1,
            timeout: @poll_timeout,
            worker_id: @worker_id,
            domain: domain_param
          )

          tasks ||= []
          duration_ms = (Time.now - start_time) * 1000
          @poll_count += 1

          publish_event(Events::PollCompleted.new(
            task_type: @worker.task_definition_name,
            duration_ms: duration_ms,
            tasks_received: tasks.size
          ))

          @auth_failures = 0
          tasks.first
        rescue AuthorizationError => e
          handle_auth_failure(e, start_time)
          nil
        rescue StandardError => e
          handle_poll_failure(e, start_time)
          nil
        end
      end

      # Handle auth failure
      def handle_auth_failure(error, start_time)
        @auth_failures += 1
        @last_auth_failure_time = Time.now
        duration_ms = (Time.now - start_time) * 1000

        publish_event(Events::PollFailure.new(
          task_type: @worker.task_definition_name,
          duration_ms: duration_ms,
          cause: error
        ))

        @logger.warn("[Ractor #{@ractor_id}] Auth failure ##{@auth_failures}: #{error.message}")
      end

      # Handle poll failure
      def handle_poll_failure(error, start_time)
        duration_ms = (Time.now - start_time) * 1000

        publish_event(Events::PollFailure.new(
          task_type: @worker.task_definition_name,
          duration_ms: duration_ms,
          cause: error
        ))

        @logger.error("[Ractor #{@ractor_id}] Poll failed: #{error.message}")
      end

      # Execute task and update result
      # @param task [Hash] Task data
      def execute_and_update(task)
        task_result = execute_task(task)
        return if task_result.nil?
        return if task_result.status == Http::Models::TaskResultStatus::IN_PROGRESS &&
                  task_result.callback_after_seconds&.positive?

        update_task_with_retry(task_result)
      end

      # Execute a task
      # @param task [Hash] Task data
      # @return [TaskResult, nil]
      def execute_task(task)
        task_obj = Http::Models::Task.from_hash(task)

        initial_result = Http::Models::TaskResult.new
        initial_result.task_id = task_obj.task_id
        initial_result.workflow_instance_id = task_obj.workflow_instance_id
        initial_result.worker_id = @worker_id

        # Set Ractor-local context
        set_ractor_context(task_obj, initial_result)

        start_time = Time.now

        publish_event(Events::TaskExecutionStarted.new(
          task_type: @worker.task_definition_name,
          task_id: task_obj.task_id,
          worker_id: @worker_id,
          workflow_instance_id: task_obj.workflow_instance_id
        ))

        begin
          task_result = @worker.execute(task_obj)
          duration_ms = (Time.now - start_time) * 1000

          # Merge context
          ctx = get_ractor_context
          if ctx&.task_result&.logs && !ctx.task_result.logs.empty?
            task_result.logs ||= []
            task_result.logs.concat(ctx.task_result.logs)
          end
          task_result.callback_after_seconds ||= ctx&.callback_after_seconds

          output_size = calculate_output_size(task_result)

          publish_event(Events::TaskExecutionCompleted.new(
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
          clear_ractor_context
        end
      end

      # Ractor-local context using Thread.current (each Ractor has its own threads)
      def set_ractor_context(task, task_result)
        Thread.current[:conductor_task_context] = TaskContext.new(task, task_result)
      end

      def get_ractor_context
        Thread.current[:conductor_task_context]
      end

      def clear_ractor_context
        Thread.current[:conductor_task_context] = nil
      end

      # Calculate output size
      def calculate_output_size(task_result)
        return 0 unless task_result.output_data

        task_result.output_data.to_json.bytesize
      rescue StandardError
        0
      end

      # Handle non-retryable error
      def handle_non_retryable_error(task, error, start_time)
        duration_ms = (Time.now - start_time) * 1000

        task_result = Http::Models::TaskResult.failed_with_terminal_error(error.message)
        task_result.task_id = task.task_id
        task_result.workflow_instance_id = task.workflow_instance_id
        task_result.worker_id = @worker_id
        task_result.log("NonRetryableError: #{error.class}: #{error.message}")

        publish_event(Events::TaskExecutionFailure.new(
          task_type: @worker.task_definition_name,
          task_id: task.task_id,
          worker_id: @worker_id,
          workflow_instance_id: task.workflow_instance_id,
          duration_ms: duration_ms,
          cause: error,
          is_retryable: false
        ))

        task_result
      end

      # Handle retryable error
      def handle_retryable_error(task, error, start_time)
        duration_ms = (Time.now - start_time) * 1000

        task_result = Http::Models::TaskResult.failed(error.message)
        task_result.task_id = task.task_id
        task_result.workflow_instance_id = task.workflow_instance_id
        task_result.worker_id = @worker_id
        task_result.log("Error: #{error.class}: #{error.message}")

        publish_event(Events::TaskExecutionFailure.new(
          task_type: @worker.task_definition_name,
          task_id: task.task_id,
          worker_id: @worker_id,
          workflow_instance_id: task.workflow_instance_id,
          duration_ms: duration_ms,
          cause: error,
          is_retryable: true
        ))

        task_result
      end

      # Update task with retry
      def update_task_with_retry(task_result)
        RETRY_BACKOFFS.each_with_index do |backoff, attempt|
          sleep(backoff) if backoff.positive?

          begin
            @task_client.update_task(task_result)
            return
          rescue StandardError => e
            @logger.error("[Ractor #{@ractor_id}] Update failed (attempt #{attempt + 1}): #{e.message}")

            if attempt == RETRY_BACKOFFS.size - 1
              @logger.fatal("[Ractor #{@ractor_id}] CRITICAL: Task #{task_result.task_id} result LOST")

              publish_event(Events::TaskUpdateFailure.new(
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

      # Publish event - sends to main Ractor if configured, otherwise logs
      # @param event [ConductorEvent] Event to publish
      def publish_event(event)
        if @event_queue
          begin
            @event_queue.send(event)
          rescue Ractor::ClosedError
            # Event queue closed, ignore
          end
        end
      end

      # Cleanup resources
      def cleanup
        # Nothing to cleanup - HTTP client will be GC'd
      end
    end

    # Helper module to check Ractor availability
    module RactorSupport
      class << self
        # Check if Ractors are available (Ruby 3.1+)
        # @return [Boolean]
        def available?
          return @available if defined?(@available)

          @available = begin
            RUBY_VERSION >= '3.1' && defined?(Ractor)
          rescue StandardError
            false
          end
        end

        # Raise error if Ractors not available
        def require_ractors!
          return if available?

          raise ConfigurationError,
                "Ractors require Ruby 3.1 or later. Current version: #{RUBY_VERSION}"
        end
      end
    end
  end
end
