# frozen_string_literal: true

module Conductor
  module Workflow
    # DynamicForkTask creates parallel tasks dynamically at runtime
    # The tasks and their inputs are determined by expressions evaluated during execution
    class DynamicForkTask < TaskInterface
      attr_accessor :tasks_param, :tasks_input_param_name, :join_task

      # Create a new DynamicForkTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param tasks_param [String] Expression/parameter name containing the dynamic tasks array
      # @param tasks_input_param_name [String] Expression/parameter name for task inputs
      # @param join_task [JoinTask, nil] Optional join task (auto-created if not provided)
      # @example
      #   dynamic_fork = DynamicForkTask.new('parallel_process',
      #     tasks_param: '${generate_tasks_ref.output.tasks}',
      #     tasks_input_param_name: '${generate_tasks_ref.output.inputs}'
      #   )
      def initialize(task_ref_name, tasks_param: 'dynamicTasks', tasks_input_param_name: 'dynamicTasksInputs',
                     join_task: nil)
        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::FORK_JOIN_DYNAMIC
        )
        @tasks_param = tasks_param
        @tasks_input_param_name = tasks_input_param_name
        @join_task = join_task&.dup
      end

      # Convert to WorkflowTask(s)
      # Returns array with fork task and join task
      # @return [Array<Conductor::Http::Models::WorkflowTask>]
      def to_workflow_task
        workflow_task = super
        workflow_task.dynamic_fork_join_tasks_param = @tasks_param
        workflow_task.dynamic_fork_tasks_input_param_name = @tasks_input_param_name

        tasks = [workflow_task]

        tasks << @join_task.to_workflow_task if @join_task

        tasks
      end
    end
  end
end
