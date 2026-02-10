# frozen_string_literal: true

require_relative '../http/models/task'
require_relative '../http/models/task_result'
require_relative '../http/models/task_result_status'
require_relative '../exceptions'
require_relative 'worker_registry'
require_relative 'task_in_progress'

module Conductor
  module Worker
    # Worker class that wraps an execute function
    # Handles various return types and keyword argument mapping
    class Worker
      # @return [String] Task definition name in Conductor
      attr_reader :task_definition_name

      # @return [Proc, Method, nil] Function to execute tasks
      attr_reader :execute_function

      # Configuration attributes
      attr_accessor :poll_interval, :thread_count, :domain, :worker_id,
                    :poll_timeout, :register_task_def, :overwrite_task_def,
                    :strict_schema, :paused, :isolation, :executor,
                    :task_def_template

      # Default configuration values
      DEFAULTS = {
        poll_interval: 100,       # milliseconds
        thread_count: 1,
        domain: nil,
        worker_id: nil,
        poll_timeout: 100,        # milliseconds
        register_task_def: false,
        overwrite_task_def: true,
        strict_schema: false,
        paused: false,
        isolation: :thread,
        executor: :thread_pool
      }.freeze

      # Initialize a worker
      # @param task_definition_name [String] Task definition name in Conductor
      # @param execute_function [Proc, Method, nil] Function to execute tasks
      # @param options [Hash] Worker configuration options
      # @yield [task] Block to execute tasks (alternative to execute_function)
      def initialize(task_definition_name, execute_function = nil, **options, &block)
        @task_definition_name = task_definition_name
        @execute_function = execute_function || block

        raise ArgumentError, 'execute_function or block required' unless @execute_function

        # Apply options with defaults
        DEFAULTS.each do |key, default|
          value = options.key?(key) ? options[key] : default
          send("#{key}=", value)
        end

        @task_def_template = options[:task_def_template]

        # Analyze the execute function for parameter mapping
        @takes_task_object = analyze_execute_function
      end

      # Alias for task_definition_name (compatibility)
      def task_type
        @task_definition_name
      end

      # Get polling interval in seconds
      # @return [Float]
      def polling_interval_seconds
        @poll_interval / 1000.0
      end

      # Execute a task
      # Handles keyword argument mapping and various return types
      # @param task [Task] The task to execute
      # @return [TaskResult, TaskInProgress] Execution result
      def execute(task)
        # Convert task if needed
        task_obj = task.is_a?(Http::Models::Task) ? task : Http::Models::Task.from_hash(task)

        # Call the execute function with appropriate arguments
        output = call_execute_function(task_obj)

        # Handle different return types
        convert_output_to_result(output, task_obj)
      end

      # Define a worker using a block
      # Registers the worker in the global registry
      # @param task_definition_name [String] Task definition name
      # @param options [Hash] Worker configuration options
      # @yield [task] Block to execute tasks
      # @return [Worker] The created worker
      def self.define(task_definition_name, **options, &block)
        worker = new(task_definition_name, nil, **options, &block)
        WorkerRegistry.register(task_definition_name, block, options)
        worker
      end

      private

      # Analyze the execute function to determine how to call it
      # @return [Boolean] True if function takes a Task object directly
      def analyze_execute_function
        return true unless @execute_function.respond_to?(:parameters)

        params = @execute_function.parameters
        return true if params.empty?

        # Check if first parameter is a positional arg (likely task)
        first_param_type, first_param_name = params.first

        # If it's a positional arg (required or optional), assume it takes task
        return true if %i[req opt rest].include?(first_param_type)

        # If it's a keyword arg named 'task', it takes task
        return true if first_param_name == :task && %i[keyreq key].include?(first_param_type)

        # Otherwise, it uses keyword args from input_data
        false
      end

      # Call the execute function with appropriate arguments
      # @param task [Task] The task object
      # @return [Object] Raw output from the execute function
      def call_execute_function(task)
        if @takes_task_object
          # Pass the full task object
          @execute_function.call(task)
        else
          # Map input_data to keyword arguments
          kwargs = extract_keyword_args(task)
          @execute_function.call(**kwargs)
        end
      end

      # Extract keyword arguments from task input_data
      # @param task [Task] The task object
      # @return [Hash] Keyword arguments
      def extract_keyword_args(task)
        input_data = task.input_data || {}
        kwargs = {}

        return kwargs unless @execute_function.respond_to?(:parameters)

        @execute_function.parameters.each do |type, name|
          key = name.to_s
          sym_key = name.to_sym

          case type
          when :keyreq # Required keyword arg
            kwargs[sym_key] = if input_data.key?(key)
                                input_data[key]
                              elsif input_data.key?(sym_key)
                                input_data[sym_key]
                              end
          when :key # Optional keyword arg
            if input_data.key?(key)
              kwargs[sym_key] = input_data[key]
            elsif input_data.key?(sym_key)
              kwargs[sym_key] = input_data[sym_key]
            end
            # Don't include if not in input_data (use default)
          when :keyrest # **kwargs
            # Include all remaining input_data
            input_data.each do |k, v|
              kwargs[k.to_sym] = v unless kwargs.key?(k.to_sym)
            end
          end
        end

        kwargs
      end

      # Convert execute function output to TaskResult
      # @param output [Object] Raw output from execute function
      # @param task [Task] The task object
      # @return [TaskResult, TaskInProgress]
      def convert_output_to_result(output, task)
        task_result = case output
                      when Http::Models::TaskResult
                        output
                      when TaskInProgress
                        result = Http::Models::TaskResult.in_progress
                        result.callback_after_seconds = output.callback_after_seconds
                        result.output_data = output.output if output.output
                        result
                      when Hash
                        result = Http::Models::TaskResult.complete
                        result.output_data = output
                        result
                      when true
                        Http::Models::TaskResult.complete
                      when false
                        Http::Models::TaskResult.failed('Worker returned false')
                      when nil
                        Http::Models::TaskResult.complete
                      else
                        result = Http::Models::TaskResult.complete
                        result.output_data = { 'result' => output }
                        result
                      end

        # Set task identifiers
        task_result.task_id = task.task_id
        task_result.workflow_instance_id = task.workflow_instance_id

        task_result
      end
    end

    # Mixin module for class-based workers
    # Include this in your worker class to use the worker_task DSL
    #
    # @example
    #   class MyWorker
    #     include Conductor::Worker::WorkerMixin
    #
    #     worker_task 'my_task', poll_interval: 200, thread_count: 5
    #
    #     def execute(task)
    #       { result: 'success' }
    #     end
    #   end
    module WorkerMixin
      def self.included(base)
        base.extend(ClassMethods)
        base.class_eval do
          attr_accessor :poll_interval, :thread_count, :domain, :worker_id,
                        :poll_timeout, :register_task_def, :overwrite_task_def,
                        :strict_schema, :paused, :isolation, :executor
        end
      end

      module ClassMethods
        # Define a worker for a specific task type
        # @param task_definition_name [String] Task definition name
        # @param options [Hash] Worker options
        def worker_task(task_definition_name, **options)
          @task_definition_name = task_definition_name
          @worker_options = options

          # Apply defaults
          Worker::DEFAULTS.each do |key, default|
            instance_variable_set("@#{key}", options.fetch(key, default))
          end
        end

        # @return [String] Task definition name
        def task_definition_name
          @task_definition_name
        end

        # Alias for compatibility
        def task_type
          @task_definition_name
        end

        # @return [Hash] Worker options
        def worker_options
          @worker_options || {}
        end

        # Configuration readers
        Worker::DEFAULTS.each_key do |key|
          define_method(key) do
            instance_variable_get("@#{key}") || Worker::DEFAULTS[key]
          end
        end
      end

      # Execute the task - must be overridden by worker class
      # @param task [Task] The task to execute
      # @return [TaskResult, Hash, Boolean, nil] Execution result
      def execute(task)
        raise NotImplementedError, 'Worker must implement #execute method'
      end

      # Get polling interval in seconds
      # @return [Float]
      def polling_interval_seconds
        (self.class.poll_interval || Worker::DEFAULTS[:poll_interval]) / 1000.0
      end

      # Convenience method to get task input data
      # @param task [Task] The task
      # @return [Hash] Input data
      def get_input_data(task)
        task.input_data || {}
      end

      # Convenience method to get a specific input value
      # @param task [Task] The task
      # @param key [String, Symbol] The input key
      # @param default [Object] Default value if key not found
      # @return [Object] The input value
      def get_input(task, key, default = nil)
        get_input_data(task)[key.to_s] || default
      end
    end

    # Module for method annotation style workers
    # Extend this in your module to use worker_task on methods
    #
    # @example
    #   module MyWorkers
    #     extend Conductor::Worker::Annotatable
    #
    #     worker_task 'greet_user', poll_interval: 100
    #     def self.greet(name:, greeting: 'Hello')
    #       "#{greeting}, #{name}!"
    #     end
    #   end
    module Annotatable
      # Mark the next defined method as a worker
      # @param task_definition_name [String] Task definition name
      # @param options [Hash] Worker options
      def worker_task(task_definition_name, **options)
        @pending_worker_task = {
          task_definition_name: task_definition_name,
          options: options
        }
      end

      # Hook called when a method is added
      def singleton_method_added(method_name)
        super
        return unless @pending_worker_task

        pending = @pending_worker_task
        @pending_worker_task = nil

        # Get the method and register it
        method_obj = method(method_name)
        WorkerRegistry.register(
          pending[:task_definition_name],
          method_obj,
          pending[:options]
        )
      end
    end

    # Module-level worker_task for defining workers at the top level
    # @param task_definition_name [String] Task definition name
    # @param options [Hash] Worker options
    # @yield [task] Block to execute tasks
    # @return [Worker] The created worker
    def self.worker_task(task_definition_name, **options, &block)
      Worker.define(task_definition_name, **options, &block)
    end
  end
end
