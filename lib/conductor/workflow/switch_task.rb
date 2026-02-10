# frozen_string_literal: true

module Conductor
  module Workflow
    # SwitchTask provides conditional branching in workflows
    # Evaluates an expression and routes to different task branches based on the result
    class SwitchTask < TaskInterface
      attr_accessor :decision_cases, :default_case_tasks, :use_javascript

      # Create a new SwitchTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param case_expression [String] Expression to evaluate for switching
      # @param use_javascript [Boolean] Whether to use JavaScript evaluator (default: false uses value-param)
      # @example
      #   switch = SwitchTask.new('route_task', '${workflow.input.type}')
      #     .switch_case('A', [task_a])
      #     .switch_case('B', [task_b])
      #     .default_case([task_default])
      def initialize(task_ref_name, case_expression, use_javascript: false)
        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::SWITCH
        )
        @case_expression = case_expression
        @use_javascript = use_javascript
        @decision_cases = {}
        @default_case_tasks = nil
      end

      # Add a case branch (fluent interface)
      # @param case_name [String] The case value to match
      # @param tasks [Array<TaskInterface>, TaskInterface] Tasks to execute for this case
      # @return [self] Returns self for chaining
      def switch_case(case_name, tasks)
        @decision_cases[case_name] = tasks.is_a?(Array) ? tasks.dup : [tasks]
        self
      end

      # Set the default case branch (fluent interface)
      # @param tasks [Array<TaskInterface>, TaskInterface] Tasks to execute when no case matches
      # @return [self] Returns self for chaining
      def default_case(tasks)
        @default_case_tasks = tasks.is_a?(Array) ? tasks.dup : [tasks]
        self
      end

      # Convert to WorkflowTask
      # @return [Conductor::Http::Models::WorkflowTask]
      def to_workflow_task
        workflow_task = super

        if @use_javascript
          workflow_task.evaluator_type = EvaluatorType::ECMASCRIPT
          workflow_task.expression = @case_expression
        else
          workflow_task.evaluator_type = EvaluatorType::VALUE_PARAM
          workflow_task.input_parameters['switchCaseValue'] = @case_expression
          workflow_task.expression = 'switchCaseValue'
        end

        # Convert decision cases
        workflow_task.decision_cases = {}
        @decision_cases.each do |case_value, tasks|
          workflow_task.decision_cases[case_value] = Workflow.tasks_to_workflow_tasks(*tasks)
        end

        # Convert default case
        workflow_task.default_case = if @default_case_tasks
                                       Workflow.tasks_to_workflow_tasks(*@default_case_tasks)
                                     else
                                       []
                                     end

        workflow_task
      end

      private

      attr_accessor :case_expression
    end
  end
end
