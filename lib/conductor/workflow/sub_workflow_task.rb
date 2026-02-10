# frozen_string_literal: true

module Conductor
  module Workflow
    # SubWorkflowTask executes another workflow as a task
    # References a workflow by name/version registered with Conductor
    class SubWorkflowTask < TaskInterface
      attr_accessor :workflow_name, :workflow_version, :task_to_domain_map

      # Create a new SubWorkflowTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param workflow_name [String] Name of the sub-workflow to execute
      # @param version [Integer, nil] Version of the sub-workflow (nil = latest)
      # @param task_to_domain_map [Hash<String, String>, nil] Task to domain mapping
      # @example
      #   sub = SubWorkflowTask.new('call_child_workflow', 'child_workflow', version: 1)
      #   sub.input('parentData', '${workflow.input.data}')
      def initialize(task_ref_name, workflow_name, version: nil, task_to_domain_map: nil)
        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::SUB_WORKFLOW
        )
        @workflow_name = workflow_name
        @workflow_version = version
        @task_to_domain_map = task_to_domain_map&.dup
      end

      # Convert to WorkflowTask
      # @return [Conductor::Http::Models::WorkflowTask]
      def to_workflow_task
        workflow_task = super
        workflow_task.sub_workflow_param = Conductor::Http::Models::SubWorkflowParams.new(
          name: @workflow_name,
          version: @workflow_version,
          task_to_domain: @task_to_domain_map
        )
        workflow_task
      end
    end

    # InlineSubWorkflowTask embeds a workflow definition inline
    # Useful for workflows that don't need to be registered separately
    class InlineSubWorkflowTask < TaskInterface
      attr_accessor :workflow

      # Create a new InlineSubWorkflowTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param workflow [ConductorWorkflow] The workflow to embed inline
      def initialize(task_ref_name, workflow)
        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::SUB_WORKFLOW
        )
        @workflow = workflow
      end

      # Convert to WorkflowTask
      # @return [Conductor::Http::Models::WorkflowTask]
      def to_workflow_task
        workflow_task = super
        workflow_task.sub_workflow_param = Conductor::Http::Models::SubWorkflowParams.new(
          name: @workflow.name,
          version: @workflow.version,
          workflow_definition: @workflow.to_workflow_def
        )
        workflow_task
      end
    end
  end
end
