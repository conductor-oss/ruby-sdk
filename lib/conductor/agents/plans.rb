# frozen_string_literal: true

require_relative 'agent'

module Conductor
  module Agents
    # Build the server-side planner, optional recovery agent, and coordinator.
    module Plans
      def plan_execute(name:, tools:, model:, planner_instructions: '', fallback_instructions: nil,
                       fallback_max_turns: nil, planner_context: [])
        planner = Agent.new(name: "#{name}_planner", model: model, instructions: planner_instructions)
        unless fallback_instructions.nil? || fallback_instructions.empty?
          fallback = Agent.new(name: "#{name}_fallback", model: model,
                               instructions: fallback_instructions, tools: tools)
        end
        Agent.new(name: name, model: model, strategy: :plan_execute, tools: tools,
                  planner: planner, fallback: fallback, fallback_max_turns: fallback_max_turns,
                  planner_context: planner_context)
      end
    end
  end
end
