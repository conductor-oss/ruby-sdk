# frozen_string_literal: true

require 'logger'
require_relative 'worker'
require_relative 'worker_registry'
require_relative 'worker_config'
require_relative 'task_runner'
require_relative 'task_definition_registrar'
require_relative 'events/sync_event_dispatcher'
require_relative 'events/listener_registry'

module Conductor
  module Worker
    # TaskHandler - The top-level orchestrator that manages all workers
    # Creates one Thread per worker, each running a TaskRunner
    #
    # Supports multiple execution modes based on worker configuration:
    # - :thread (default) - Thread-based with ThreadPoolExecutor
    # - :ractor - Ractor-based for true parallelism (Ruby 3.1+)
    # - :fiber - Fiber-based with async gem for high I/O concurrency
    class TaskHandler
      attr_reader :workers, :configuration, :event_dispatcher

      # Initialize TaskHandler
      # @param workers [Array<Worker>, nil] Pre-created worker instances
      # @param configuration [Configuration, nil] Conductor configuration
      # @param scan_for_annotated_workers [Boolean] Auto-discover workers from registry
      # @param import_modules [Array<String>, nil] Ruby files to require (triggers registration)
      # @param event_listeners [Array<Object>, nil] Custom event listeners
      # @param logger [Logger, nil] Logger instance
      # @param register_task_definitions [Boolean] Auto-register task definitions on start
      def initialize(
        workers: nil,
        configuration: nil,
        scan_for_annotated_workers: true,
        import_modules: nil,
        event_listeners: nil,
        logger: nil,
        register_task_definitions: false
      )
        @configuration = configuration || Configuration.new
        @logger = logger || create_default_logger
        @event_dispatcher = Events::SyncEventDispatcher.new
        @workers = []
        @threads = []
        @runners = []
        @ractors = []  # For Ractor-based workers
        @running = false
        @mutex = Mutex.new
        @register_task_definitions = register_task_definitions

        # Register event listeners
        register_listeners(event_listeners) if event_listeners

        # Import modules (triggers worker_task registrations)
        import_worker_modules(import_modules) if import_modules

        # Discover workers from registry
        discover_registered_workers if scan_for_annotated_workers

        # Add provided workers
        add_workers(workers) if workers
      end

      # Add workers to the handler
      # @param workers [Array<Worker>] Workers to add
      # @return [self]
      def add_workers(workers)
        workers.each { |w| add_worker(w) }
        self
      end

      # Add a single worker
      # @param worker [Worker] Worker to add
      # @return [self]
      def add_worker(worker)
        @mutex.synchronize do
          @workers << worker
        end
        self
      end

      # Start all worker threads
      # @return [self]
      def start
        @mutex.synchronize do
          return self if @running

          @running = true

          # Register task definitions if enabled
          register_all_task_definitions if @register_task_definitions

          @workers.each do |worker|
            start_worker(worker)
          end

          @logger.info("TaskHandler started with #{@workers.size} workers")
        end

        self
      end

      private

      # Start a single worker with appropriate runner type
      # @param worker [Worker] The worker to start
      def start_worker(worker)
        # Determine execution mode from worker configuration
        isolation = worker.respond_to?(:isolation) ? worker.isolation : :thread
        executor = worker.respond_to?(:executor) ? worker.executor : :thread_pool

        case isolation
        when :ractor
          start_ractor_worker(worker)
        else
          # Thread-based execution (default)
          case executor
          when :fiber
            start_fiber_worker(worker)
          else
            start_thread_worker(worker)
          end
        end
      end

      # Start a thread-based worker (default mode)
      # @param worker [Worker] The worker to start
      def start_thread_worker(worker)
        runner = TaskRunner.new(
          worker,
          configuration: @configuration,
          event_dispatcher: @event_dispatcher,
          logger: @logger
        )
        @runners << runner

        thread = Thread.new(runner) do |r|
          Thread.current.name = "conductor-worker-#{r.worker.task_definition_name}"
          r.run
        rescue StandardError => e
          @logger.fatal("Fatal error in worker '#{r.worker.task_definition_name}': #{e.message}")
          @logger.debug(e.backtrace.join("\n")) if e.backtrace
        end

        @threads << thread
      end

      # Start a Ractor-based worker for true parallelism
      # @param worker [Worker] The worker to start
      def start_ractor_worker(worker)
        require_relative 'ractor_task_runner'

        RactorSupport.require_ractors!

        thread_count = worker.respond_to?(:thread_count) ? worker.thread_count : 1

        # Create event receiver Ractor to collect events from worker Ractors
        event_receiver = create_event_receiver_ractor(worker.task_definition_name)

        # Create multiple Ractors for parallelism
        thread_count.times do |i|
          ractor = Ractor.new(worker, @configuration, i, event_receiver) do |w, config, ractor_id, evt_queue|
            runner = RactorTaskRunner.new(
              w,
              configuration: config,
              ractor_id: ractor_id,
              event_queue: evt_queue
            )
            runner.run
          end
          @ractors << ractor
        end

        @logger.info("Started #{thread_count} Ractor(s) for '#{worker.task_definition_name}'")
      end

      # Start a fiber-based worker for high I/O concurrency
      # @param worker [Worker] The worker to start
      def start_fiber_worker(worker)
        require_relative 'fiber_executor'

        AsyncSupport.require_async!

        runner = FiberTaskRunner.new(
          worker,
          configuration: @configuration,
          event_dispatcher: @event_dispatcher,
          logger: @logger
        )
        @runners << runner

        thread = Thread.new(runner) do |r|
          Thread.current.name = "conductor-fiber-#{r.worker.task_definition_name}"
          r.run
        rescue StandardError => e
          @logger.fatal("Fatal error in fiber worker '#{r.worker.task_definition_name}': #{e.message}")
          @logger.debug(e.backtrace.join("\n")) if e.backtrace
        end

        @threads << thread
      end

      # Create event receiver Ractor to forward events to dispatcher
      # @param task_name [String] Task name for logging
      # @return [Ractor] Event receiver Ractor
      def create_event_receiver_ractor(task_name)
        dispatcher = @event_dispatcher
        logger = @logger

        Thread.new do
          Thread.current.name = "conductor-event-receiver-#{task_name}"
          # Note: In production, this would need proper Ractor communication
          # For now, events from Ractors are logged but not dispatched
          # due to Ractor isolation constraints
          logger.debug("Event receiver started for #{task_name}")
        end

        # Return nil for now - Ractor event communication needs more work
        nil
      end

      # Register all task definitions
      def register_all_task_definitions
        registrar = TaskDefinitionRegistrar.new(@configuration, logger: @logger)
        @workers.each do |worker|
          registrar.register(worker)
        end
      end

      public

      # Stop all workers gracefully
      # @param timeout [Integer] Seconds to wait before force-killing threads
      # @return [self]
      def stop(timeout: 5)
        @mutex.synchronize do
          return self unless @running

          @logger.info("Stopping TaskHandler...")

          # Signal all runners to shutdown
          @runners.each(&:shutdown)

          # Wait for threads to finish
          @threads.each do |thread|
            thread.join(timeout)
            thread.kill if thread.alive?
          end

          # Shutdown Ractors
          @ractors.each do |ractor|
            begin
              # Ractors don't have a clean shutdown mechanism
              # They'll be GC'd when no longer referenced
              ractor.take if ractor.respond_to?(:take)
            rescue Ractor::ClosedError, Ractor::RemoteError
              # Ractor already finished
            end
          end

          @runners.clear
          @threads.clear
          @ractors.clear
          @running = false

          @logger.info("TaskHandler stopped")
        end

        self
      end

      # Wait for all worker threads to complete (blocking)
      # @return [self]
      def join
        @threads.each(&:join)
        self
      end

      # Check if handler is running
      # @return [Boolean]
      def running?
        @running
      end

      # Get list of worker names
      # @return [Array<String>]
      def worker_names
        @workers.map(&:task_definition_name)
      end

      # Context manager pattern - execute block and stop on exit
      # @yield [self]
      # @return [Object] Block return value
      def self.run(workers: nil, configuration: nil, **options)
        handler = new(workers: workers, configuration: configuration, **options)
        begin
          yield handler if block_given?
        ensure
          handler.stop
        end
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

      # Register event listeners
      # @param listeners [Array<Object>] Listeners to register
      def register_listeners(listeners)
        listeners.each do |listener|
          Events::ListenerRegistry.register_task_runner_listener(listener, @event_dispatcher)
        end
      end

      # Import worker modules from file paths
      # @param modules [Array<String>] File paths or module names to require
      def import_worker_modules(modules)
        modules.each do |mod|
          begin
            if File.exist?(mod)
              require mod
            else
              require mod
            end
          rescue LoadError => e
            @logger.warn("Failed to load module '#{mod}': #{e.message}")
          end
        end
      end

      # Discover workers from the global registry
      def discover_registered_workers
        WorkerRegistry.all.each do |definition|
          worker = Worker.new(
            definition[:task_definition_name],
            definition[:execute_function],
            **definition[:options]
          )
          @workers << worker
        end

        @logger.info("Discovered #{WorkerRegistry.count} workers from registry") if WorkerRegistry.count.positive?
      end
    end
  end
end
