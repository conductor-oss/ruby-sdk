# frozen_string_literal: true

require 'json'
require_relative '../errors'

module Conductor
  module Agents
    # Bodies for the compiler-generated SIMPLE tasks the server asks the SDK to serve
    # (they appear in requiredWorkers next to the user's tools). Ports of the Python
    # SDK's TerminationEntry, GuardrailEntry, CallbackEntry and OnCondition handoff workers.
    module SystemWorkers
      module_function

      # <agent>_termination: { should_continue, reason }
      def termination(condition, logger: nil)
        lambda do |task|
          input = stringify(task.input_data)
          context = { 'result' => input['result'].to_s, 'messages' => input['messages'] || [],
                      'iteration' => input['iteration'].to_i, 'token_usage' => input['token_usage'] }
          begin
            outcome = condition.should_terminate(context)
            { 'should_continue' => !outcome.should_terminate, 'reason' => outcome.reason.to_s }
          rescue StandardError => e
            logger&.error("termination condition failed: #{e.class}: #{e.message}")
            { 'should_continue' => true, 'reason' => '' }
          end
        end
      end

      # <guardrail name>: { passed, message, on_fail, fixed_output, guardrail_name, should_continue }
      def guardrail(guardrail, logger: nil)
        lambda do |task|
          input = stringify(task.input_data)
          content = stringify_content(input['content'])
          iteration = input['iteration'].to_i
          begin
            result = guardrail.check(content)
            return pass_result if result.passed?

            on_fail = guardrail.on_fail
            fixed = result.fixed_output
            on_fail = 'raise' if on_fail == 'retry' && iteration >= guardrail.max_retries
            on_fail = 'raise' if on_fail == 'fix' && fixed.nil?
            { 'passed' => false, 'message' => result.message.to_s, 'on_fail' => on_fail, 'fixed_output' => fixed,
              'guardrail_name' => guardrail.name, 'should_continue' => on_fail == 'retry' }
          rescue StandardError => e
            logger&.error("guardrail #{guardrail.name} raised: #{e.class}: #{e.message}")
            on_fail = guardrail.on_fail
            on_fail = 'raise' if on_fail == 'retry' && iteration >= guardrail.max_retries
            { 'passed' => false, 'message' => "Guardrail error: #{e.message}", 'on_fail' => on_fail, 'fixed_output' => nil,
              'guardrail_name' => guardrail.name, 'should_continue' => on_fail == 'retry' }
          end
        end
      end

      # <agent>_<position>: the callback chain's Hash (or {})
      def callback(chain, logger: nil)
        lambda do |task|
          input = stringify(task.input_data)
          kwargs = {}
          kwargs[:messages] = input['messages'] if input.key?('messages')
          kwargs[:llm_result] = input['llm_result'] if input.key?('llm_result')
          begin
            result = chain.call(**kwargs)
            result.is_a?(Hash) ? result : {}
          rescue StandardError => e
            logger&.error("callback failed: #{e.class}: #{e.message}")
            {}
          end
        end
      end

      # <agent>_handoff_<target>: { handoff, target }
      def handoff(condition, logger: nil)
        lambda do |task|
          input = stringify(task.input_data)
          begin
            { 'handoff' => condition.should_handoff(input) ? true : false, 'target' => condition.target }
          rescue StandardError => e
            logger&.error("handoff condition failed: #{e.class}: #{e.message}")
            { 'handoff' => false, 'target' => condition.target }
          end
        end
      end

      def pass_result
        { 'passed' => true, 'message' => '', 'on_fail' => 'pass', 'fixed_output' => nil, 'guardrail_name' => '',
          'should_continue' => false }
      end

      # Function-based routers return the selected sub-agent's name.
      def router(callable, agent_names, logger: nil)
        lambda do |task|
          { 'selected_agent' => callable.call(stringify(task.input_data).fetch('prompt', '')).to_s }
        rescue StandardError => e
          logger&.error("router failed: #{e.class}: #{e.message}")
          { 'selected_agent' => agent_names.first || '' }
        end
      end

      def stringify(input)
        (input || {}).transform_keys(&:to_s)
      end

      def stringify_content(content)
        return '' if content.nil?
        return content if content.is_a?(String)

        JSON.generate(content)
      rescue StandardError
        content.to_s
      end
    end
  end
end
