# frozen_string_literal: true

module Conductor
  module Workflow
    # Base class for all workflow task types in the DSL
    # Provides common functionality for task definition and serialization
    class TaskInterface
      attr_accessor :task_reference_name, :task_type, :name, :description, :optional,
                    :input_parameters, :cache_key, :cache_ttl_second, :expression,
                    :evaluator_type

      # Initialize a task interface
      # @param task_reference_name [String] Unique reference name for this task in the workflow
      # @param task_type [String] The type of task (from TaskType constants)
      # @param task_name [String, nil] The task definition name (defaults to task_reference_name)
      # @param description [String, nil] Optional description
      # @param optional [Boolean, nil] Whether the task is optional
      # @param input_parameters [Hash, nil] Input parameters for the task
      # @param cache_key [String, nil] Cache key for task caching
      # @param cache_ttl_second [Integer] Cache TTL in seconds (0 = disabled)
      def initialize(task_reference_name:, task_type:, task_name: nil, description: nil,
                     optional: nil, input_parameters: nil, cache_key: nil, cache_ttl_second: 0)
        @task_reference_name = task_reference_name
        @task_type = task_type
        @name = task_name || task_reference_name
        @description = description
        @optional = optional
        @input_parameters = input_parameters || {}
        @cache_key = cache_key
        @cache_ttl_second = cache_ttl_second
        @expression = nil
        @evaluator_type = nil
      end

      # Set a single input parameter (fluent interface)
      # @param key [String, Symbol] Parameter name
      # @param value [Object] Parameter value
      # @return [self] Returns self for chaining
      def input_parameter(key, value)
        @input_parameters[key.to_s] = value
        self
      end

      # Alias for input_parameter
      alias input input_parameter

      # Configure task caching (fluent interface)
      # @param cache_key [String] The cache key
      # @param ttl_seconds [Integer] TTL in seconds
      # @return [self] Returns self for chaining
      def cache(cache_key, ttl_seconds)
        @cache_key = cache_key
        @cache_ttl_second = ttl_seconds
        self
      end

      # Get a reference to this task's output (for wiring task inputs)
      # @param json_path [String, nil] Optional JSON path within the output
      # @return [String] Expression string for referencing this task's output
      # @example
      #   task.output           # => "${task_ref.output}"
      #   task.output('result') # => "${task_ref.output.result}"
      #   task.output('.data')  # => "${task_ref.output.data}"
      def output(json_path = nil)
        if json_path.nil?
          "${#{task_reference_name}.output}"
        elsif json_path.start_with?('.')
          "${#{task_reference_name}.output#{json_path}}"
        else
          "${#{task_reference_name}.output.#{json_path}}"
        end
      end

      # Get a reference to this task's input (for wiring task inputs)
      # @param json_path [String, nil] Optional JSON path within the input
      # @return [String] Expression string for referencing this task's input
      def task_input(json_path = nil)
        if json_path.nil?
          "${#{task_reference_name}.input}"
        else
          "${#{task_reference_name}.input.#{json_path}}"
        end
      end

      # Convert this task to a WorkflowTask model for serialization
      # @return [Conductor::Http::Models::WorkflowTask] The workflow task representation
      def to_workflow_task
        cache_config = nil
        if @cache_ttl_second.positive? && @cache_key
          cache_config = Conductor::Http::Models::CacheConfig.new(
            key: @cache_key,
            ttl_in_second: @cache_ttl_second
          )
        end

        Conductor::Http::Models::WorkflowTask.new(
          name: @name,
          task_reference_name: @task_reference_name,
          type: @task_type,
          description: @description,
          input_parameters: @input_parameters,
          optional: @optional,
          cache_config: cache_config,
          expression: @expression,
          evaluator_type: @evaluator_type
        )
      end

      # Dynamic attribute access for output references
      # Allows syntax like: task.result instead of task.output('result')
      def method_missing(method_name, *args, &block)
        # Only handle attribute-style access (no args, no block)
        if args.empty? && block.nil? && !method_name.to_s.start_with?('_')
          output(method_name.to_s)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        !method_name.to_s.start_with?('_') || super
      end
    end

    # Helper function to convert a list of TaskInterface objects to WorkflowTask objects
    # @param tasks [Array<TaskInterface>] List of task interfaces
    # @return [Array<Conductor::Http::Models::WorkflowTask>] List of workflow tasks
    def self.tasks_to_workflow_tasks(*tasks)
      converted = []
      tasks.flatten.each do |task|
        wf_task = task.to_workflow_task
        if wf_task.is_a?(Array)
          # Some tasks (like DynamicFork) return multiple workflow tasks
          converted.concat(wf_task)
        else
          converted << wf_task
        end
      end
      converted
    end
  end
end
