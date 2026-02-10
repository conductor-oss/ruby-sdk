# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # ToolCall represents a tool invocation in an LLM conversation
      class ToolCall
        attr_accessor :name, :task_reference_name, :integration_names, :type,
                      :input_parameters, :output

        # @param name [String] Tool name
        # @param task_reference_name [String, nil] Task reference name
        # @param integration_names [Hash<String,String>, nil] Integration name mappings
        # @param type [String] Tool type (default: 'SIMPLE')
        # @param input_parameters [Hash, nil] Input parameters for the tool
        # @param output [Hash, nil] Expected output
        def initialize(name:, task_reference_name: nil, integration_names: nil,
                       type: 'SIMPLE', input_parameters: nil, output: nil)
          @name = name
          @task_reference_name = task_reference_name
          @integration_names = integration_names
          @type = type
          @input_parameters = input_parameters
          @output = output
        end

        # Convert to hash for serialization
        # @return [Hash] The tool call as a hash with camelCase keys
        def to_h
          result = {
            'name' => @name,
            'type' => @type
          }
          result['taskReferenceName'] = @task_reference_name if @task_reference_name
          result['integrationNames'] = @integration_names if @integration_names
          result['inputParameters'] = @input_parameters if @input_parameters
          result['output'] = @output if @output
          result
        end
      end
    end
  end
end
