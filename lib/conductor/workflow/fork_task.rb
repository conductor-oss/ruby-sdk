# frozen_string_literal: true

module Conductor
  module Workflow
    # ForkTask executes multiple task branches in parallel
    # Each branch is an array of tasks that execute sequentially
    class ForkTask < TaskInterface
      attr_accessor :forked_tasks, :join_on

      # Create a new ForkTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param forked_tasks [Array<Array<TaskInterface>>] List of task branches to execute in parallel
      # @param join_on [Array<String>, nil] Optional list of task refs to wait for (auto-generated if nil)
      # @example
      #   fork = ForkTask.new('parallel_tasks', [
      #     [task_a1, task_a2],  # Branch 1
      #     [task_b1]            # Branch 2
      #   ])
      def initialize(task_ref_name, forked_tasks, join_on: nil)
        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::FORK_JOIN
        )
        @forked_tasks = forked_tasks.map do |branch|
          branch.is_a?(Array) ? branch.dup : [branch]
        end
        @join_on = join_on&.dup
      end

      # Convert to WorkflowTask(s)
      # Returns an array containing the fork task and optionally a join task
      # @return [Array<Conductor::Http::Models::WorkflowTask>] Fork task, optionally followed by join task
      def to_workflow_task
        tasks = []
        workflow_task = super

        # Convert forked tasks to workflow tasks
        workflow_task.fork_tasks = @forked_tasks.map do |branch|
          branch.map(&:to_workflow_task)
        end

        # Auto-generate join_on from last task of each branch
        workflow_task.join_on = @forked_tasks.map do |branch|
          branch.last.task_reference_name
        end

        # If explicit join_on provided, create a join task
        if @join_on
          join_task = JoinTask.new("#{task_reference_name}_join", join_on: @join_on)
          tasks << workflow_task
          tasks << join_task.to_workflow_task
          return tasks
        end

        workflow_task
      end
    end
  end
end
