# frozen_string_literal: true

module Conductor
  module Workflow
    module Dsl
      # OutputRef enables chained [] access for nested output paths
      # task[:response][:body][:items] => "${task_ref.output.response.body.items}"
      class OutputRef
        attr_reader :path

        def initialize(path)
          @path = path
        end

        # Enable chained [] access
        # @param field [String, Symbol] The field name
        # @return [OutputRef] A new OutputRef with the extended path
        def [](field)
          OutputRef.new("#{@path}.#{field}")
        end

        # Convert to expression string for use in input parameters
        # @return [String] The expression in ${...} format
        def to_s
          "${#{@path}}"
        end

        # Allow use in string interpolation
        alias to_str to_s

        # Compare OutputRefs by their paths
        def ==(other)
          other.is_a?(OutputRef) && @path == other.path
        end

        alias eql? ==

        def hash
          @path.hash
        end
      end
    end
  end
end
