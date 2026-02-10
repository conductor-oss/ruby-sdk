# frozen_string_literal: true

module Conductor
  module Workflow
    # SetVariableTask sets workflow-level variables
    # Variables persist across task executions and can be used for tracking state
    class SetVariableTask < TaskInterface
      # Create a new SetVariableTask
      # @param task_ref_name [String] Unique reference name for this task
      # @example
      #   set_var = SetVariableTask.new('update_counter')
      #     .input('counter', '${workflow.variables.counter + 1}')
      #     .input('lastUpdated', '${workflow.input.timestamp}')
      def initialize(task_ref_name)
        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::SET_VARIABLE
        )
      end
    end
  end
end
