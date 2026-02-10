# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # ToolSpec defines a tool specification for LLM function calling
      class ToolSpec
        attr_accessor :name, :type, :description, :config_params,
                      :integration_names, :input_schema, :output_schema

        # @param name [String] Tool name
        # @param type [String] Tool type (default: 'SIMPLE')
        # @param description [String, nil] Tool description
        # @param config_params [Hash, nil] Configuration parameters
        # @param integration_names [Hash<String,String>, nil] Integration name mappings
        # @param input_schema [Hash, nil] JSON schema for inputs
        # @param output_schema [Hash, nil] JSON schema for outputs
        def initialize(name:, type: 'SIMPLE', description: nil, config_params: nil,
                       integration_names: nil, input_schema: nil, output_schema: nil)
          @name = name
          @type = type
          @description = description
          @config_params = config_params
          @integration_names = integration_names
          @input_schema = input_schema
          @output_schema = output_schema
        end

        # Convert to hash for serialization
        # @return [Hash] The tool spec as a hash with camelCase keys
        def to_h
          result = {
            'name' => @name,
            'type' => @type
          }
          result['description'] = @description if @description
          result['configParams'] = @config_params if @config_params
          result['integrationNames'] = @integration_names if @integration_names
          result['inputSchema'] = @input_schema if @input_schema
          result['outputSchema'] = @output_schema if @output_schema
          result
        end
      end
    end
  end
end
