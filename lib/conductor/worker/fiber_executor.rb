# frozen_string_literal: true

module Conductor
  module Worker
    # FiberExecutor - Fiber-based executor using the async gem
    # Provides lightweight cooperative concurrency for high I/O workloads
    #
    # Unlike ThreadPoolExecutor which uses OS threads (~8KB each),
    # FiberExecutor uses fibers (~400 bytes each), enabling thousands
    # of concurrent tasks within a single thread.
    #
    # Requirements:
    # - async gem must be installed (optional dependency)
    # - All I/O must be non-blocking (use async-compatible libraries)
    #
    # @example
    #   worker = Worker.new('io_task', executor: :fiber, thread_count: 100) { |t| async_http_call(t) }
    #   handler = TaskHandler.new(workers: [worker])
    #   handler.start
    class FiberExecutor
      attr_reader :max_concurrency

      # Initialize FiberExecutor
      # @param max_concurrency [Integer] Maximum concurrent fibers (semaphore limit)
      def initialize(max_concurrency)
        @max_concurrency = max_concurrency
        @running_fibers = []
        @semaphore = nil
        @scheduler = nil
        @shutdown = false

        # Lazy-load the async gem
        load_async_gem
      end

      # Submit a task for execution
      # @param block [Proc] Block to execute in a fiber
      # @return [Object] Fiber task handle
      def submit(&block)
        raise 'FiberExecutor not started' unless @scheduler

        # Wrap the block with semaphore for concurrency control
        fiber_task = @scheduler.async do
          @semaphore.acquire
          begin
            block.call
          ensure
            @semaphore.release
          end
        end

        @running_fibers << fiber_task
        cleanup_completed_fibers
        fiber_task
      end

      # Get current number of running fibers
      # @return [Integer]
      def running_count
        cleanup_completed_fibers
        @running_fibers.size
      end

      # Check if at capacity
      # @return [Boolean]
      def at_capacity?
        running_count >= @max_concurrency
      end

      # Wait for all fibers to complete
      # @param timeout [Float, nil] Optional timeout in seconds
      def wait_for_completion(timeout: nil)
        cleanup_completed_fibers
        @running_fibers.each do |fiber|
          begin
            fiber.wait
          rescue StandardError
            # Ignore errors during wait
          end
        end
        @running_fibers.clear
      end

      # Start the fiber scheduler
      # Must be called before submitting tasks
      # @yield Block to execute within the scheduler
      def start(&block)
        Async do |task|
          @scheduler = task
          @semaphore = Async::Semaphore.new(@max_concurrency)
          block.call(self) if block_given?
        end
      end

      # Signal shutdown
      def shutdown
        @shutdown = true
        @running_fibers.each do |fiber|
          begin
            fiber.stop
          rescue StandardError
            # Ignore errors during shutdown
          end
        end
        @running_fibers.clear
      end

      # Check if shutdown
      # @return [Boolean]
      def shutdown?
        @shutdown
      end

      private

      # Load the async gem
      def load_async_gem
        require 'async'
        require 'async/semaphore'
      rescue LoadError
        raise ConfigurationError,
              "The 'async' gem is required for fiber executor. " \
              "Add `gem 'async'` to your Gemfile."
      end

      # Remove completed fibers from tracking
      def cleanup_completed_fibers
        @running_fibers.reject! do |fiber|
          fiber.finished? || fiber.stopped?
        end
      end
    end

    # FiberTaskRunner - TaskRunner variant that uses FiberExecutor
    # Runs within an async event loop for fiber-based concurrency
    class FiberTaskRunner
      # Retry backoffs for task update (in seconds)
      RETRY_BACKOFFS = [0, 10, 20, 30].freeze

      # Maximum exponent for adaptive backoff
      MAX_BACKOFF_EXPONENT = 10

      # Maximum auth failure backoff in seconds
      MAX_AUTH_BACKOFF_SECONDS = 60

      attr_reader :worker

      # Initialize FiberTaskRunner
      # @param worker [Worker] The worker instance
      # @param configuration [Configuration] Conductor configuration
      # @param event_dispatcher [SyncEventDispatcher] Event dispatcher
      # @param logger [Logger] Logger instance
      def initialize(worker, configuration:, event_dispatcher: nil, logger: nil)
        @worker = worker
        @configuration = configuration || Configuration.new
        @event_dispatcher = event_dispatcher || Events::SyncEventDispatcher.new
        @logger = logger || create_default_logger

        # Resolve worker configuration
        resolved = WorkerConfig.resolve(
          worker.task_definition_name,
          extract_worker_options(worker)
        )
        @poll_interval = resolved[:poll_interval]
        @max_workers = resolved[:thread_count]  # thread_count becomes fiber concurrency
        @worker_id = resolved[:worker_id]
        @domain = resolved[:domain]
        @poll_timeout = resolved[:poll_timeout]

        # State tracking
        @consecutive_empty_polls = 0
        @auth_failures = 0
        @last_auth_failure_time = nil
        @last_poll_time = nil
        @poll_count = 0
        @shutdown = false
      end

      # Main run loop - runs within async event loop
      def run
        @logger.info("Starting FiberTaskRunner for '#{@worker.task_definition_name}' " \
                     "(fiber_concurrency=#{@max_workers})")

        # Create task client (using async-compatible HTTP if available)
        @task_client = Client::TaskClient.new(@configuration)

        # Create fiber executor
        @executor = FiberExecutor.new(@max_workers)

        # Start the async event loop
        @executor.start do |executor|
          until @shutdown
            begin
              run_once(executor)
              # Small sleep to prevent tight loop (async-friendly)
              sleep(0.001)
            rescue StandardError => e
              @logger.error("Error in fiber polling loop: #{e.message}")
              sleep(1)
            end
          end
        end

        cleanup
        @logger.info("FiberTaskRunner stopped")
      end

      # Single iteration
      # @param executor [FiberExecutor] The fiber executor
      def run_once(executor)
        # Check capacity
        return if executor.at_capacity?

        available_slots = @max_workers - executor.running_count

        # Adaptive backoff
        if @consecutive_empty_polls > 0
          backoff_ms = calculate_adaptive_backoff
          elapsed_ms = @last_poll_time ? (Time.now - @last_poll_time) * 1000 : backoff_ms
          return if elapsed_ms < backoff_ms
        end

        # Poll for tasks
        @last_poll_time = Time.now
        tasks = batch_poll(available_slots)

        if tasks.empty?
          @consecutive_empty_polls += 1
        else
          @consecutive_empty_polls = 0
          tasks.each do |task|
            executor.submit { execute_and_update(task) }
          end
        end
      end

      # Signal shutdown
      def shutdown
        @shutdown = true
        @executor&.shutdown
      end

      private

      def create_default_logger
        logger = Logger.new($stdout)
        logger.level = Logger::INFO
        logger
      end

      def extract_worker_options(worker)
        options = {}
        Worker::DEFAULTS.keys.each do |key|
          options[key] = worker.send(key) if worker.respond_to?(key)
        end
        options
      end

      def calculate_adaptive_backoff
        exponent = [@consecutive_empty_polls, MAX_BACKOFF_EXPONENT].min
        [1.0 * (2**exponent), @poll_interval].min
      end

      def batch_poll(count)
        return [] if @worker.paused

        if @auth_failures > 0 && @last_auth_failure_time
          backoff_seconds = [2**@auth_failures, MAX_AUTH_BACKOFF_SECONDS].min
          elapsed = Time.now - @last_auth_failure_time
          return [] if elapsed < backoff_seconds
        end

        @event_dispatcher.publish(Events::PollStarted.new(
          task_type: @worker.task_definition_name,
          worker_id: @worker_id,
          poll_count: @poll_count
        ))

        start_time = Time.now

        begin
          domain_param = @domain.to_s.empty? ? nil : @domain

          tasks = @task_client.batch_poll(
            @worker.task_definition_name,
            count: count,
            timeout: @poll_timeout,
            worker_id: @worker_id,
            domain: domain_param
          )

          tasks ||= []
          duration_ms = (Time.now - start_time) * 1000
          @poll_count += 1

          @event_dispatcher.publish(Events::PollCompleted.new(
            task_type: @worker.task_definition_name,
            duration_ms: duration_ms,
            tasks_received: tasks.size
          ))

          @auth_failures = 0
          tasks
        rescue AuthorizationError => e
          @auth_failures += 1
          @last_auth_failure_time = Time.now
          @event_dispatcher.publish(Events::PollFailure.new(
            task_type: @worker.task_definition_name,
            duration_ms: (Time.now - start_time) * 1000,
            cause: e
          ))
          []
        rescue StandardError => e
          @event_dispatcher.publish(Events::PollFailure.new(
            task_type: @worker.task_definition_name,
            duration_ms: (Time.now - start_time) * 1000,
            cause: e
          ))
          []
        end
      end

      def execute_and_update(task)
        task_result = execute_task(task)
        return if task_result.nil?
        return if task_result.status == Http::Models::TaskResultStatus::IN_PROGRESS &&
                  task_result.callback_after_seconds&.positive?

        update_task_with_retry(task_result)
      end

      def execute_task(task)
        task_obj = Http::Models::Task.from_hash(task)

        initial_result = Http::Models::TaskResult.new
        initial_result.task_id = task_obj.task_id
        initial_result.workflow_instance_id = task_obj.workflow_instance_id
        initial_result.worker_id = @worker_id

        # Fiber-local context (uses Fiber.current storage if available)
        set_fiber_context(task_obj, initial_result)

        start_time = Time.now

        @event_dispatcher.publish(Events::TaskExecutionStarted.new(
          task_type: @worker.task_definition_name,
          task_id: task_obj.task_id,
          worker_id: @worker_id,
          workflow_instance_id: task_obj.workflow_instance_id
        ))

        begin
          task_result = @worker.execute(task_obj)
          duration_ms = (Time.now - start_time) * 1000

          ctx = get_fiber_context
          if ctx&.task_result&.logs && !ctx.task_result.logs.empty?
            task_result.logs ||= []
            task_result.logs.concat(ctx.task_result.logs)
          end
          task_result.callback_after_seconds ||= ctx&.callback_after_seconds

          output_size = task_result.output_data.to_json.bytesize rescue 0

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
          handle_execution_error(task_obj, e, start_time, retryable: false)

        rescue StandardError => e
          handle_execution_error(task_obj, e, start_time, retryable: true)

        ensure
          clear_fiber_context
        end
      end

      # Fiber-local context storage
      def set_fiber_context(task, task_result)
        # Try Fiber.current storage (Ruby 3.2+), fall back to Thread.current
        if Fiber.current.respond_to?(:[]=)
          Fiber.current[:conductor_task_context] = TaskContext.new(task, task_result)
        else
          Thread.current[:conductor_task_context] = TaskContext.new(task, task_result)
        end
      end

      def get_fiber_context
        if Fiber.current.respond_to?(:[])
          Fiber.current[:conductor_task_context]
        else
          Thread.current[:conductor_task_context]
        end
      end

      def clear_fiber_context
        if Fiber.current.respond_to?(:[]=)
          Fiber.current[:conductor_task_context] = nil
        else
          Thread.current[:conductor_task_context] = nil
        end
      end

      def handle_execution_error(task, error, start_time, retryable:)
        duration_ms = (Time.now - start_time) * 1000

        task_result = if retryable
                        Http::Models::TaskResult.failed(error.message)
                      else
                        Http::Models::TaskResult.failed_with_terminal_error(error.message)
                      end

        task_result.task_id = task.task_id
        task_result.workflow_instance_id = task.workflow_instance_id
        task_result.worker_id = @worker_id
        task_result.log("Error: #{error.class}: #{error.message}")

        @event_dispatcher.publish(Events::TaskExecutionFailure.new(
          task_type: @worker.task_definition_name,
          task_id: task.task_id,
          worker_id: @worker_id,
          workflow_instance_id: task.workflow_instance_id,
          duration_ms: duration_ms,
          cause: error,
          is_retryable: retryable
        ))

        task_result
      end

      def update_task_with_retry(task_result)
        RETRY_BACKOFFS.each_with_index do |backoff, attempt|
          sleep(backoff) if backoff.positive?

          begin
            @task_client.update_task(task_result)
            return
          rescue StandardError => e
            @logger.error("Update failed (attempt #{attempt + 1}): #{e.message}")

            if attempt == RETRY_BACKOFFS.size - 1
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

      def cleanup
        @executor&.shutdown
        @event_dispatcher.clear
      end
    end

    # Helper to check async gem availability
    module AsyncSupport
      class << self
        def available?
          return @available if defined?(@available)

          @available = begin
            require 'async'
            true
          rescue LoadError
            false
          end
        end

        def require_async!
          return if available?

          raise ConfigurationError,
                "The 'async' gem is required for fiber executor. " \
                "Add `gem 'async'` to your Gemfile."
        end
      end
    end
  end
end
