# frozen_string_literal: true

require_relative 'errors'

module Conductor
  module Agents
    # Composable rules that decide when an agent loop stops.
    #
    #   stop = Termination::TextMention.new('DONE') | Termination::MaxMessage.new(20)
    #   Agent.new(..., termination: stop)
    #
    # Conditions serialize to the server (ConfigSerializer) and the same objects back the
    # local <agent>_termination worker the server asks for.
    module Termination
      Result = Struct.new(:should_terminate, :reason, keyword_init: true) do
        def initialize(should_terminate:, reason: '')
          super
        end
      end

      # Base class. Context keys: result, messages, iteration, token_usage (String or Symbol keys).
      class Condition
        def should_terminate(_context)
          raise NotImplementedError
        end

        def &(other)
          And.new(self, other)
        end

        def |(other)
          Or.new(self, other)
        end

        def to_s
          "#<#{self.class.name.split('::').last}>"
        end
        alias inspect to_s

        protected

        def ctx(context, key)
          return nil unless context.respond_to?(:key?)

          context.key?(key.to_s) ? context[key.to_s] : context[key.to_sym]
        end
      end

      # Stop when the output contains +text+
      class TextMention < Condition
        attr_reader :text, :case_sensitive

        def initialize(text, case_sensitive: false)
          raise ConfigurationError, 'text is required' if text.to_s.empty?

          @text = text.to_s
          @case_sensitive = case_sensitive ? true : false
          super()
        end

        def should_terminate(context)
          result = ctx(context, :result).to_s
          needle = @text
          unless @case_sensitive
            result = result.downcase
            needle = needle.downcase
          end
          return Result.new(should_terminate: true, reason: "Text '#{@text}' found in output") if result.include?(needle)

          Result.new(should_terminate: false)
        end
      end

      # Stop when the whole output (stripped) equals +stop_message+
      class StopMessage < Condition
        attr_reader :stop_message

        def initialize(stop_message = 'TERMINATE')
          @stop_message = stop_message.to_s
          super()
        end

        def should_terminate(context)
          return Result.new(should_terminate: true, reason: "Stop message '#{@stop_message}' received") if ctx(context, :result).to_s.strip == @stop_message

          Result.new(should_terminate: false)
        end
      end

      # Stop after +max_messages+ messages (falls back to the loop iteration count)
      class MaxMessage < Condition
        attr_reader :max_messages

        def initialize(max_messages)
          raise ConfigurationError, 'max_messages must be >= 1' unless max_messages.is_a?(Integer) && max_messages >= 1

          @max_messages = max_messages
          super()
        end

        def should_terminate(context)
          messages = ctx(context, :messages)
          count = messages.is_a?(Array) ? messages.size : 0
          count = ctx(context, :iteration).to_i if count.zero?
          return Result.new(should_terminate: true, reason: "Message count (#{count}) >= limit (#{@max_messages})") if count >= @max_messages

          Result.new(should_terminate: false)
        end
      end

      # Stop when token usage crosses a budget
      class TokenUsage < Condition
        attr_reader :max_total_tokens, :max_prompt_tokens, :max_completion_tokens

        def initialize(max_total_tokens: nil, max_prompt_tokens: nil, max_completion_tokens: nil)
          raise ConfigurationError, 'at least one token limit must be specified' if [max_total_tokens, max_prompt_tokens, max_completion_tokens].all?(&:nil?)

          @max_total_tokens = max_total_tokens
          @max_prompt_tokens = max_prompt_tokens
          @max_completion_tokens = max_completion_tokens
          super()
        end

        def should_terminate(context)
          usage = ctx(context, :token_usage)
          return Result.new(should_terminate: false) unless usage.respond_to?(:key?)

          checks = [
            [@max_total_tokens, usage_value(usage, 'total_tokens', 'totalTokens'), 'Total'],
            [@max_prompt_tokens, usage_value(usage, 'prompt_tokens', 'promptTokens'), 'Prompt'],
            [@max_completion_tokens, usage_value(usage, 'completion_tokens', 'completionTokens'), 'Completion']
          ]
          checks.each do |limit, value, label|
            next if limit.nil? || value < limit

            return Result.new(should_terminate: true, reason: "#{label} tokens (#{value}) >= limit (#{limit})")
          end
          Result.new(should_terminate: false)
        end

        private

        def usage_value(usage, *keys)
          keys.each do |k|
            v = usage[k] || usage[k.to_sym]
            return v.to_i unless v.nil?
          end
          0
        end
      end

      # All children must trigger
      class And < Condition
        attr_reader :conditions

        def initialize(*conditions)
          @conditions = conditions.flat_map { |c| c.is_a?(And) ? c.conditions : [c] }
          super()
        end

        def should_terminate(context)
          reasons = []
          @conditions.each do |c|
            r = c.should_terminate(context)
            return Result.new(should_terminate: false) unless r.should_terminate

            reasons << r.reason unless r.reason.to_s.empty?
          end
          Result.new(should_terminate: true, reason: reasons.join(' AND '))
        end
      end

      # Any child triggers
      class Or < Condition
        attr_reader :conditions

        def initialize(*conditions)
          @conditions = conditions.flat_map { |c| c.is_a?(Or) ? c.conditions : [c] }
          super()
        end

        def should_terminate(context)
          @conditions.each do |c|
            r = c.should_terminate(context)
            return r if r.should_terminate
          end
          Result.new(should_terminate: false)
        end
      end
    end
  end
end
