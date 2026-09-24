# frozen_string_literal: true

module Conductor
  module Agents
    # Reference to a prompt template stored on the server, used as Agent#instructions.
    class PromptTemplate
      attr_reader :name, :variables, :version

      def initialize(name:, variables: {}, version: nil)
        @name = name.to_s
        @variables = variables || {}
        @version = version
      end

      def to_h
        h = { 'type' => 'prompt_template', 'name' => @name }
        h['variables'] = @variables unless @variables.empty?
        h['version'] = @version unless @version.nil?
        h
      end
    end
  end
end
