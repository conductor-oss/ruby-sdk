# frozen_string_literal: true

module Conductor
  module Workflow
    # JoinTask waits for forked tasks to complete
    # Used in conjunction with ForkTask for parallel execution
    class JoinTask < TaskInterface
      attr_accessor :join_on

      # Create a new JoinTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param join_on [Array<String>, nil] List of task reference names to wait for
      # @param join_on_script [String, nil] Optional JavaScript expression for join condition
      def initialize(task_ref_name, join_on: nil, join_on_script: nil)
        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::JOIN
        )
        @join_on = join_on&.dup

        if join_on_script
          @evaluator_type = 'js'
          @expression = join_on_script
        end
      end

      # Convert to WorkflowTask
      # @return [Conductor::Http::Models::WorkflowTask]
      def to_workflow_task
        workflow_task = super
        workflow_task.join_on = @join_on
        workflow_task
      end
    end
  end
end
