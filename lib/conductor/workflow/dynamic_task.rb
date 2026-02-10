# frozen_string_literal: true

module Conductor
  module Workflow
    # DynamicTask resolves the actual task type at runtime
    class DynamicTask < TaskInterface
      # Create a new DynamicTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param dynamic_task_name_param [String] Parameter name that resolves to the task type at runtime
      def initialize(task_ref_name, dynamic_task_name_param = 'taskToExecute')
        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::DYNAMIC
        )
        @dynamic_task_name_param = dynamic_task_name_param
      end

      # Convert to WorkflowTask
      # @return [Conductor::Http::Models::WorkflowTask]
      def to_workflow_task
        workflow_task = super
        workflow_task.dynamic_task_name_param = @dynamic_task_name_param
        workflow_task
      end
    end
  end
end
