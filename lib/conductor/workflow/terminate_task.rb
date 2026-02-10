# frozen_string_literal: true

module Conductor
  module Workflow
    # Workflow status values for TerminateTask
    module TerminationStatus
      COMPLETED = 'COMPLETED'
      FAILED = 'FAILED'
      TERMINATED = 'TERMINATED'
    end

    # TerminateTask ends workflow execution with a specific status
    class TerminateTask < TaskInterface
      # Create a new TerminateTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param status [String] Termination status (use TerminationStatus constants)
      # @param termination_reason [String] Reason for termination
      # @example
      #   terminate = TerminateTask.new('end_workflow',
      #     TerminationStatus::FAILED,
      #     'Validation failed'
      #   )
      def initialize(task_ref_name, status, termination_reason)
        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::TERMINATE,
          input_parameters: {
            'terminationStatus' => status,
            'terminationReason' => termination_reason
          }
        )
      end
    end
  end
end
