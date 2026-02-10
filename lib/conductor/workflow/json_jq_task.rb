# frozen_string_literal: true

module Conductor
  module Workflow
    # JsonJqTask performs JSON transformations using JQ expressions
    # Useful for complex data manipulation without writing worker code
    class JsonJqTask < TaskInterface
      # Create a new JsonJqTask
      # @param task_ref_name [String] Unique reference name for this task
      # @param jq_expression [String] JQ expression for transformation
      # @example
      #   jq = JsonJqTask.new('transform', '.users | map(.name)')
      #   jq.input('data', '${workflow.input.userData}')
      def initialize(task_ref_name, jq_expression)
        super(
          task_reference_name: task_ref_name,
          task_type: TaskType::JSON_JQ_TRANSFORM,
          input_parameters: {
            'queryExpression' => jq_expression
          }
        )
      end
    end
  end
end
