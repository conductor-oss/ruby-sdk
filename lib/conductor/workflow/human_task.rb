# frozen_string_literal: true

module Conductor
  module Workflow
    # HumanTask creates a task that requires human intervention
    # The task stays in IN_PROGRESS until a human completes it via the API
    class HumanTask < TaskInterface
      # Create a new HumanTask
      # @param task_ref_name [String] Unique reference name for this task
      def initialize(task_ref_name)
        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::HUMAN
        )
      end
    end
  end
end
