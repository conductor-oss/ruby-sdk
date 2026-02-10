# frozen_string_literal: true

module Conductor
  module Workflow
    # StartWorkflowTask starts another workflow as a task (fire-and-forget)
    # Unlike SubWorkflowTask, this does NOT wait for the child workflow to complete
    class StartWorkflowTask < TaskInterface
      # Create a new StartWorkflowTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param workflow_name [String] Name of the workflow to start
      # @param version [Integer, nil] Workflow version (optional, uses latest)
      # @param start_workflow_input [Hash] Input for the started workflow (optional)
      def initialize(task_ref_name, workflow_name, version: nil, start_workflow_input: nil)
        input_params = {
          'startWorkflow' => {
            'name' => workflow_name,
            'input' => start_workflow_input || {}
          }.tap { |h| h['version'] = version if version }
        }

        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::START_WORKFLOW,
          input_parameters: input_params
        )
      end
    end
  end
end
