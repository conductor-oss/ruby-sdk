# frozen_string_literal: true

require_relative 'errors'

module Conductor
  module Agents
    # Result of a guardrail check
    GuardrailResult = Struct.new(:passed, :message, :fixed_output, keyword_init: true) do
      def initialize(passed:, message: '', fixed_output: nil)
        super
      end

      def passed?
        passed ? true : false
      end
    end

    # Validation applied to an agent's input or output.
    #
    #   Guardrail.new(name: 'no_pii', position: :output, on_fail: :retry) do |content|
    #     content =~ SSN ? GuardrailResult.new(passed: false, message: 'Redact it') : GuardrailResult.new(passed: true)
    #   end
    #
    # A guardrail with a block runs as a worker in this process (guardrailType "custom");
    # one with only a name references a worker running elsewhere ("external").
    class Guardrail
      POSITIONS = %w[input output].freeze
      ON_FAIL = %w[retry raise fix human].freeze

      attr_reader :name, :position, :on_fail, :max_retries, :func

      # @param name [String, nil] required when no block is given
      # @param position [Symbol, String] :input or :output
      # @param on_fail [Symbol, String] :retry, :raise, :fix or :human
      def initialize(name: nil, position: :output, on_fail: :raise, max_retries: 3, func: nil, &block)
        @position = position.to_s
        @on_fail = on_fail.to_s
        raise ConfigurationError, "invalid position #{position.inspect}; use :input or :output" unless POSITIONS.include?(@position)
        raise ConfigurationError, "invalid on_fail #{on_fail.inspect}; use one of #{ON_FAIL.join(', ')}" unless ON_FAIL.include?(@on_fail)
        raise ConfigurationError, 'on_fail: :human is only valid for position: :output' if @on_fail == 'human' && @position == 'input'
        raise ConfigurationError, 'max_retries must be >= 1' if max_retries.to_i < 1

        @func = func || block
        raise ConfigurationError, 'a guardrail needs a name or a block' if @func.nil? && name.nil?

        @name = (name || 'guardrail').to_s
        @max_retries = max_retries.to_i
      end

      # True when the check runs somewhere else (no local implementation)
      def external?
        @func.nil?
      end

      # @param content [String]
      # @return [GuardrailResult]
      def check(content)
        raise Error, "cannot check external guardrail #{@name.inspect} locally" if external?

        result = @func.call(content)
        return result if result.is_a?(GuardrailResult)
        return GuardrailResult.new(passed: result) if [true, false].include?(result)

        raise Error, "guardrail #{@name.inspect} must return a GuardrailResult or true/false, got #{result.class}"
      end

      # Wire discriminator (see ConfigSerializer)
      def guardrail_type
        external? ? 'external' : 'custom'
      end

      def to_s
        "#<#{self.class.name.split('::').last} #{@name} position=#{@position} on_fail=#{@on_fail}>"
      end
      alias inspect to_s
    end

    # Reject content that matches (mode :block) or fails to match (mode :allow) regex patterns.
    class RegexGuardrail < Guardrail
      MODES = %w[block allow].freeze

      attr_reader :pattern_strings, :mode, :message

      # @param patterns [String, Regexp, Array<String, Regexp>]
      def initialize(patterns, mode: :block, position: :output, on_fail: :raise, name: 'regex_guardrail',
                     message: nil, max_retries: 3)
        @mode = mode.to_s
        raise ConfigurationError, "invalid mode #{mode.inspect}; use :block or :allow" unless MODES.include?(@mode)

        @pattern_strings = Array(patterns).map { |p| p.is_a?(Regexp) ? p.source : p.to_s }
        @patterns = @pattern_strings.map { |p| Regexp.new(p) }
        @message = message
        super(name: name, position: position, on_fail: on_fail, max_retries: max_retries, func: method(:evaluate))
      end

      def guardrail_type
        'regex'
      end

      private

      def evaluate(content)
        text = content.to_s
        matched = @patterns.any? { |p| p.match?(text) }
        if @mode == 'block' && matched
          GuardrailResult.new(passed: false, message: @message || 'Content matched a blocked pattern.')
        elsif @mode == 'allow' && !matched
          GuardrailResult.new(passed: false, message: @message || 'Content did not match any allowed pattern.')
        else
          GuardrailResult.new(passed: true)
        end
      end
    end

    # Ask an LLM (on the server) whether content complies with a policy.
    class LlmGuardrail < Guardrail
      attr_reader :model, :policy, :max_tokens

      # @param model [String] "provider/model"
      def initialize(model, policy, position: :output, on_fail: :raise, name: 'llm_guardrail', max_retries: 3,
                     max_tokens: nil)
        raise ConfigurationError, 'LlmGuardrail needs a model in "provider/model" form' unless model.to_s.include?('/')

        @model = model
        @policy = policy
        @max_tokens = max_tokens
        super(name: name, position: position, on_fail: on_fail, max_retries: max_retries, func: method(:evaluate))
      end

      def guardrail_type
        'llm'
      end

      private

      # The server compiles this guardrail into an LLM task; there is no local evaluation.
      def evaluate(_content)
        GuardrailResult.new(passed: false, message: 'LlmGuardrail is evaluated by the Conductor server')
      end
    end
  end
end
