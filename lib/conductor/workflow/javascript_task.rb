# frozen_string_literal: true

module Conductor
  module Workflow
    # JavascriptTask executes inline JavaScript/GraalJS code
    # Useful for data transformation and simple logic without needing a worker
    class JavascriptTask < TaskInterface
      # Create a new JavascriptTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param script [String] JavaScript code to execute
      # @param bindings [Hash<String, Object>, nil] Optional variable bindings accessible in script
      # @example
      #   js = JavascriptTask.new('transform_data',
      #     'function e() { return $.input1 + $.input2; } e();',
      #     { 'input1' => '${workflow.input.a}', 'input2' => '${workflow.input.b}' }
      #   )
      def initialize(task_ref_name, script, bindings = nil)
        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::INLINE,
          input_parameters: {
            'evaluatorType' => 'graaljs',
            'expression' => script
          }
        )
        @input_parameters.merge!(bindings) if bindings
      end

      # Override output to point to result (JS tasks return in .result)
      # @param json_path [String, nil] Optional JSON path
      # @return [String] Expression for output
      def output(json_path = nil)
        if json_path.nil?
          "${#{task_reference_name}.output.result}"
        else
          "${#{task_reference_name}.output.result.#{json_path}}"
        end
      end

      # Set the evaluator type (fluent interface)
      # @param type [String] Evaluator type ('graaljs' or 'javascript')
      # @return [self]
      def evaluator_type(type)
        @input_parameters['evaluatorType'] = type
        self
      end
    end

    # InlineTask is an alias for JavascriptTask
    InlineTask = JavascriptTask
  end
end
