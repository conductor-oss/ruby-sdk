# frozen_string_literal: true

module Conductor
  module Agents
    # A tool call observed on the stream or awaiting approval
    ToolCall = Struct.new(:name, :arguments, :result, keyword_init: true) do
      def to_s
        "#<ToolCall #{name} #{(arguments || {}).map { |k, v| "#{k}: #{v.inspect}" }.join(' ')}>"
      end
      alias_method :inspect, :to_s
    end
  end
end
