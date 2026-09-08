# frozen_string_literal: true

require_relative 'errors'

module Conductor
  module Agents
    # Rules that transfer control between agents in a team (swarm orchestration).
    #
    #   Handoff::OnTextMention.new(target: 'filer', text: 'ACTIONABLE')
    #   Handoff::OnToolResult.new(target: 'refund', tool_name: 'check_order')
    #   Handoff::OnCondition.new(target: 'summarizer') { |ctx| ctx['iteration'].to_i > 5 }
    module Handoff
      # Base class. +target+ is the receiving agent's name (an Agent is accepted too).
      class Condition
        attr_reader :target

        def initialize(target:)
          @target = target.respond_to?(:name) ? target.name.to_s : target.to_s
          raise ConfigurationError, 'handoff target is required' if @target.empty?
        end

        # @param _context [Hash] result, tool_name, tool_result, messages, iteration
        def should_handoff(_context)
          false
        end

        def to_s
          "#<#{self.class.name.split('::').last} -> #{@target}>"
        end
        alias inspect to_s

        protected

        def ctx(context, key)
          return nil unless context.respond_to?(:key?)

          context.key?(key.to_s) ? context[key.to_s] : context[key.to_sym]
        end
      end

      # After a named tool ran (optionally only when its result contains a substring)
      class OnToolResult < Condition
        attr_reader :tool_name, :result_contains

        def initialize(target:, tool_name:, result_contains: nil)
          @tool_name = tool_name.to_s
          @result_contains = result_contains
          super(target: target)
        end

        def should_handoff(context)
          return false unless ctx(context, :tool_name).to_s == @tool_name
          return true if @result_contains.nil?

          ctx(context, :tool_result).to_s.include?(@result_contains.to_s)
        end
      end

      # When the output mentions +text+ (case-insensitive)
      class OnTextMention < Condition
        attr_reader :text

        def initialize(target:, text:)
          @text = text.to_s
          raise ConfigurationError, 'text is required' if @text.empty?

          super(target: target)
        end

        def should_handoff(context)
          ctx(context, :result).to_s.downcase.include?(@text.downcase)
        end
      end

      # When a block returns true; runs as the <agent>_handoff_<target> worker
      class OnCondition < Condition
        attr_reader :condition

        def initialize(target:, condition: nil, &block)
          @condition = condition || block
          raise ConfigurationError, 'OnCondition needs a block' if @condition.nil?

          super(target: target)
        end

        def should_handoff(context)
          @condition.call(context) ? true : false
        rescue StandardError
          false
        end
      end
    end
  end
end
