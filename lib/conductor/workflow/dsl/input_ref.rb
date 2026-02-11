# frozen_string_literal: true

module Conductor
  module Workflow
    module Dsl
      # InputRef provides access to workflow inputs and variables
      # wf[:order_id] => "${workflow.input.order_id}"
      # wf.var(:counter) => "${workflow.variables.counter}"
      class InputRef
        # Access workflow input by field name
        # @param field [String, Symbol] The input field name
        # @return [OutputRef] An OutputRef pointing to the workflow input
        def [](field)
          OutputRef.new("workflow.input.#{field}")
        end

        # Access workflow variable by name
        # @param name [String, Symbol] The variable name
        # @return [OutputRef] An OutputRef pointing to the workflow variable
        def var(name)
          OutputRef.new("workflow.variables.#{name}")
        end

        # Access workflow output (for sub-workflows)
        # @param field [String, Symbol, nil] Optional field name
        # @return [OutputRef] An OutputRef pointing to workflow output
        def output(field = nil)
          if field
            OutputRef.new("workflow.output.#{field}")
          else
            OutputRef.new('workflow.output')
          end
        end
      end
    end
  end
end
