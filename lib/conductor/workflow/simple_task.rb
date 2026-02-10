# frozen_string_literal: true

module Conductor
  module Workflow
    # SimpleTask represents a task executed by a worker
    # This is the most common task type for custom business logic
    class SimpleTask < TaskInterface
      # Create a new SimpleTask
      # @param task_def_name [String] The name of the task definition (registered with Conductor)
      # @param task_reference_name [String] Unique reference name for this task in the workflow
      # @example
      #   task = SimpleTask.new('my_worker_task', 'task_ref_1')
      #   task.input('userId', '${workflow.input.userId}')
      def initialize(task_def_name, task_reference_name)
        super(
          task_reference_name: task_reference_name,
          task_type: TaskType::SIMPLE,
          task_name: task_def_name
        )
      end
    end

    # Factory method for creating SimpleTask with inputs
    # @param task_def_name [String] The name of the task definition
    # @param task_reference_name [String] Unique reference name for this task
    # @param inputs [Hash] Input parameters for the task
    # @return [SimpleTask] The configured task
    # @example
    #   task = Conductor::Workflow.simple_task('my_task', 'ref', { userId: '${workflow.input.userId}' })
    def self.simple_task(task_def_name, task_reference_name, inputs = {})
      task = SimpleTask.new(task_def_name, task_reference_name)
      inputs.each { |k, v| task.input_parameter(k, v) }
      task
    end
  end
end
