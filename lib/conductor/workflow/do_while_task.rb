# frozen_string_literal: true

module Conductor
  module Workflow
    # DoWhileTask executes a set of tasks repeatedly until a condition is met
    # The loop continues while the termination_condition evaluates to true
    class DoWhileTask < TaskInterface
      attr_accessor :loop_condition, :loop_over

      # Create a new DoWhileTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param termination_condition [String] JavaScript expression that returns true to continue, false to stop
      # @param tasks [Array<TaskInterface>, TaskInterface] Tasks to execute in each iteration
      # @example
      #   loop = DoWhileTask.new('retry_loop',
      #     'if ($.retry_loop.iteration < 3) { true; } else { false; }',
      #     [process_task, check_task]
      #   )
      def initialize(task_ref_name, termination_condition, tasks)
        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::DO_WHILE
        )
        @loop_condition = termination_condition
        @loop_over = tasks.is_a?(Array) ? tasks.dup : [tasks]
      end

      # Convert to WorkflowTask
      # @return [Conductor::Http::Models::WorkflowTask]
      def to_workflow_task
        workflow_task = super
        workflow_task.loop_condition = @loop_condition
        workflow_task.loop_over = Workflow.tasks_to_workflow_tasks(*@loop_over)
        workflow_task
      end
    end

    # LoopTask is a convenience wrapper for DoWhileTask that runs a fixed number of iterations
    class LoopTask < DoWhileTask
      # Create a new LoopTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param iterations [Integer] Number of times to execute the loop
      # @param tasks [Array<TaskInterface>, TaskInterface] Tasks to execute in each iteration
      # @example
      #   loop = LoopTask.new('process_batch', 5, [batch_task])
      def initialize(task_ref_name, iterations, tasks)
        condition = "if ( $.#{task_ref_name}.iteration < #{iterations} ) { true; } else { false; }"
        super(task_ref_name, condition, tasks)
      end
    end

    # ForEachTask iterates over a collection
    class ForEachTask < DoWhileTask
      # Create a new ForEachTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param tasks [Array<TaskInterface>, TaskInterface] Tasks to execute for each item
      # @param iterate_over [String] Expression pointing to the collection to iterate
      # @example
      #   foreach = ForEachTask.new('process_items', [item_task], '${workflow.input.items}')
      def initialize(task_ref_name, tasks, iterate_over)
        # The iteration count is determined dynamically by the items length
        condition = "if ( $.#{task_ref_name}.iteration < $.#{task_ref_name}.items.length ) { true; } else { false; }"
        super(task_ref_name, condition, tasks)
        input_parameter('items', iterate_over)
      end
    end
  end
end
