# frozen_string_literal: true

require_relative 'agent'

module Conductor
  module Agents
    # Serializes an Agent tree into the agentConfig JSON the server compiles. Same shape
    # as the Python SDK's AgentConfigSerializer: camelCase keys, nils dropped, strategy only
    # on agents with sub-agents, agent credentials at the top level and tool credentials
    # under config.credentials.
    #
    # Two Ruby-specific rules:
    # - a team parent with no model inherits the first member's model (the server requires
    #   a model on every agent config);
    # - members that declared hands_off_to make a team with no explicit strategy a swarm,
    #   and their handoffs are hoisted to the team, which is where the server reads them.
    class ConfigSerializer
      def self.serialize(agent)
        new.serialize(agent)
      end

      # @param agent [Agent]
      # @return [Hash] agentConfig
      def serialize(agent)
        serialize_agent(agent)
      end

      private

      def serialize_agent(agent)
        has_sub_agents = !agent.agents.empty?
        strategy, handoffs = effective_strategy_and_handoffs(agent)

        config = {
          'name' => agent.name,
          'model' => effective_model(agent),
          'baseUrl' => agent.base_url,
          'strategy' => has_sub_agents || agent.planner || agent.fallback ? strategy : nil,
          'maxTurns' => agent.max_turns,
          'timeoutSeconds' => agent.timeout_seconds,
          'external' => agent.external,
          'description' => agent.description,
          'instructions' => serialize_instructions(agent.instructions)
        }
        config['tools'] = agent.tools.map { |t| serialize_tool(t, agent_stateful: agent.stateful) } unless agent.tools.empty?
        config['agents'] = agent.agents.map { |a| serialize_agent(a) } if has_sub_agents
        config.merge!(serialize_plan(agent))
        config['router'] = serialize_router(agent) unless agent.router.nil?
        config['outputType'] = serialize_output_type(agent.output_type) unless agent.output_type.nil?
        config['guardrails'] = agent.guardrails.map { |g| serialize_guardrail(g) } unless agent.guardrails.empty?
        config['memory'] = serialize_memory(agent.memory) if agent.memory && !agent.memory.empty?
        config.merge!(serialize_scalars(agent))
        config['termination'] = serialize_termination(agent.termination) unless agent.termination.nil?
        config['handoffs'] = handoffs.map { |h| serialize_handoff(h, agent.name) } unless handoffs.empty?
        config.merge!(serialize_extras(agent))
        config.compact
      end

      def serialize_scalars(agent)
        {
          'maxTokens' => agent.max_tokens,
          'temperature' => agent.temperature
        }
      end

      def serialize_plan(agent)
        config = {}
        config['planner'] = serialize_agent(agent.planner) if agent.planner
        config['fallback'] = serialize_agent(agent.fallback) if agent.fallback
        config['fallbackMaxTurns'] = agent.fallback_max_turns unless agent.fallback_max_turns.nil?
        config['plannerContext'] = agent.planner_context unless agent.planner_context.empty?
        config
      end

      def serialize_extras(agent)
        extras = {}
        extras['metadata'] = agent.metadata if agent.metadata && !agent.metadata.empty?
        callbacks = agent.callback_positions.map { |p| { 'position' => p, 'taskName' => "#{agent.name}_#{p}" } }
        extras['callbacks'] = callbacks unless callbacks.empty?
        extras['prefillTools'] = agent.prefill_tools.map(&:to_h) unless agent.prefill_tools.empty?
        extras['credentials'] = agent.credentials unless agent.credentials.empty?
        extras
      end

      def effective_model(agent)
        return agent.model if agent.model && !agent.model.to_s.empty?
        return nil if agent.external

        inherited = (agent.agents + [agent.planner, agent.fallback].compact).map { |a| effective_model(a) }.compact.first
        return inherited if inherited

        raise ConfigurationError,
              "agent #{agent.name.inspect} has no model: pass model: 'provider/model' (the server requires one)"
      end

      # Swarm hoisting: members with hands_off_to make the parent a swarm unless the user chose a strategy
      def effective_strategy_and_handoffs(agent)
        member_handoffs = agent.agents.flat_map(&:handoffs)
        return [agent.strategy, agent.handoffs] if member_handoffs.empty?

        strategy = agent.strategy_set? ? agent.strategy : Strategy::SWARM
        return [strategy, agent.handoffs] unless strategy == Strategy::SWARM

        hoisted = (agent.handoffs + member_handoffs).uniq { |h| [h.class, h.target, h.respond_to?(:text) ? h.text : nil] }
        [strategy, hoisted]
      end

      def serialize_instructions(instructions)
        case instructions
        when PromptTemplate then instructions.to_h
        when Proc, Method then instructions.call
        when nil then nil
        else
          s = instructions.to_s
          s.empty? ? nil : s
        end
      end

      def serialize_tool(tool_def, agent_stateful: false)
        result = {
          'name' => tool_def.name,
          'description' => tool_def.description,
          'inputSchema' => tool_def.input_schema,
          'toolType' => tool_def.tool_type
        }
        result['outputSchema'] = tool_def.output_schema unless tool_def.output_schema.nil? || tool_def.output_schema.empty?
        result['approvalRequired'] = true if tool_def.approval_required
        result['stateful'] = true if agent_stateful || tool_def.stateful
        result['timeoutSeconds'] = tool_def.timeout_seconds unless tool_def.timeout_seconds.nil?
        result['maxCalls'] = tool_def.max_calls unless tool_def.max_calls.nil?

        unless tool_def.config.empty?
          config = tool_def.config.transform_keys(&:to_s)
          config['agentConfig'] = serialize_agent(config.delete('agent')) if tool_def.tool_type == ToolType::AGENT_TOOL && config.key?('agent')
          result['config'] = config
        end

        result['guardrails'] = tool_def.guardrails.map { |g| serialize_guardrail(g) } unless tool_def.guardrails.empty?

        unless tool_def.credentials.empty?
          result['config'] ||= {}
          result['config']['credentials'] = tool_def.credentials
        end

        result
      end

      def serialize_guardrail(guardrail)
        result = {
          'name' => guardrail.name,
          'position' => guardrail.position,
          'onFail' => guardrail.on_fail,
          'maxRetries' => guardrail.max_retries,
          'guardrailType' => guardrail.guardrail_type
        }
        case guardrail
        when RegexGuardrail
          result['patterns'] = guardrail.pattern_strings
          result['mode'] = guardrail.mode
          result['message'] = guardrail.message if guardrail.message
        when LlmGuardrail
          result['model'] = guardrail.model
          result['policy'] = guardrail.policy
          result['maxTokens'] = guardrail.max_tokens if guardrail.max_tokens
        else
          result['taskName'] = guardrail.name
        end
        result
      end

      def serialize_termination(condition)
        case condition
        when Termination::TextMention
          { 'type' => 'text_mention', 'text' => condition.text, 'caseSensitive' => condition.case_sensitive }
        when Termination::StopMessage
          { 'type' => 'stop_message', 'stopMessage' => condition.stop_message }
        when Termination::MaxMessage
          { 'type' => 'max_message', 'maxMessages' => condition.max_messages }
        when Termination::TokenUsage
          h = { 'type' => 'token_usage' }
          h['maxTotalTokens'] = condition.max_total_tokens unless condition.max_total_tokens.nil?
          h['maxPromptTokens'] = condition.max_prompt_tokens unless condition.max_prompt_tokens.nil?
          h['maxCompletionTokens'] = condition.max_completion_tokens unless condition.max_completion_tokens.nil?
          h
        when Termination::And
          { 'type' => 'and', 'conditions' => condition.conditions.map { |c| serialize_termination(c) } }
        when Termination::Or
          { 'type' => 'or', 'conditions' => condition.conditions.map { |c| serialize_termination(c) } }
        else
          { 'type' => 'unknown' }
        end
      end

      def serialize_handoff(handoff, agent_name)
        result = { 'target' => handoff.target }
        case handoff
        when Handoff::OnToolResult
          result['type'] = 'on_tool_result'
          result['toolName'] = handoff.tool_name
          result['resultContains'] = handoff.result_contains if handoff.result_contains
        when Handoff::OnTextMention
          result['type'] = 'on_text_mention'
          result['text'] = handoff.text
        when Handoff::OnCondition
          result['type'] = 'on_condition'
          result['taskName'] = "#{agent_name}_handoff_#{handoff.target}"
        else
          result['type'] = 'unknown'
        end
        result
      end

      def serialize_router(agent)
        router = agent.router
        return serialize_agent(router) if router.is_a?(Agent)
        return { 'taskName' => "#{agent.name}_router_fn" } if router.respond_to?(:call)

        nil
      end

      # output_type: a JSON schema Hash, optionally wrapped as { schema:, class_name: }
      def serialize_output_type(output_type)
        schema = output_type.respond_to?(:to_json_schema) ? output_type.to_json_schema : output_type
        schema = schema.transform_keys(&:to_s) if schema.is_a?(Hash)
        if schema.is_a?(Hash) && (schema.key?('schema') || schema.key?('className') || schema.key?('class_name'))
          result = {}
          result['schema'] = schema['schema'] if schema['schema']
          class_name = schema['className'] || schema['class_name']
          result['className'] = class_name if class_name
          return result
        end

        result = { 'schema' => schema }
        result['className'] = schema['title'] if schema.is_a?(Hash) && schema['title']
        result
      end

      def serialize_memory(memory)
        result = {}
        result['messages'] = memory.messages unless memory.messages.empty?
        result['maxMessages'] = memory.max_messages if memory.max_messages
        result
      end
    end
  end
end
