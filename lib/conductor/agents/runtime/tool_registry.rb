# frozen_string_literal: true

require 'set'
require_relative '../errors'
require_relative 'dispatch'
require_relative 'system_workers'
require_relative '../../worker/worker'
require_relative '../../http/models/task_def'

module Conductor
  module Agents
    # Turns an agent tree into the Conductor workers this process must run: one per
    # local tool (worker/cli tools with a func) and one per compiler-generated system task
    # the server listed in requiredWorkers.
    class ToolRegistry
      SYSTEM_SUFFIX_TERMINATION = '_termination'

      attr_reader :logger

      def initialize(agent_config, logger: nil)
        @agent_config = agent_config
        @logger = logger
      end

      # @param agent [Agent] root agent
      # @param required_workers [Array<String>, nil] from the start/deploy response (nil = register everything)
      # @param domain [String, nil] task domain for stateful runs (the runId)
      # @return [Array<Worker::Worker>]
      def workers_for(agent, required_workers: nil, domain: nil)
        required = required_workers.nil? ? nil : Set.new(required_workers.map(&:to_s))
        workers = tool_workers(agent, domain: domain)
        workers += system_workers(agent, required, domain: domain)
        warn_unhandled(required, workers)
        workers
      end

      # Workers for every local tool in the tree (deduplicated by name)
      def tool_workers(agent, domain: nil)
        seen = {}
        agent.all_agents.each do |a|
          a.tools.each do |tool_def|
            next unless tool_def.local?
            next if seen.key?(tool_def.name)

            seen[tool_def.name] = build_tool_worker(tool_def, a, domain: domain)
          end
        end
        seen.values
      end

      # Workers for compiler-generated tasks: termination, custom guardrails, callbacks, on_condition handoffs
      def system_workers(agent, required, domain: nil)
        workers = []
        agent.all_agents.each do |a|
          if a.termination
            name = "#{a.name}#{SYSTEM_SUFFIX_TERMINATION}"
            workers << build_system_worker(name, SystemWorkers.termination(a.termination, logger: @logger), domain, a) if wanted?(required, name)
          end
          a.guardrails.each do |g|
            next if g.external? || g.is_a?(RegexGuardrail) || g.is_a?(LlmGuardrail)

            workers << build_system_worker(g.name, SystemWorkers.guardrail(g, logger: @logger), domain, a) if wanted?(required, g.name)
          end
          a.callback_positions.each do |position|
            name = "#{a.name}_#{position}"
            next unless wanted?(required, name)

            workers << build_system_worker(name, SystemWorkers.callback(a.callback_chain(position, logger: @logger), logger: @logger), domain, a)
          end
          a.handoffs.each do |h|
            next unless h.is_a?(Handoff::OnCondition)

            name = "#{a.name}_handoff_#{h.target}"
            workers << build_system_worker(name, SystemWorkers.handoff(h, logger: @logger), domain, a) if wanted?(required, name)
          end
        end
        workers.uniq(&:task_definition_name)
      end

      # Task definition for a tool worker (same defaults as the Python SDK)
      def task_def_for(name, retry_count: 2, retry_delay_seconds: 2, retry_logic: 'LINEAR_BACKOFF', credentials: [])
        Http::Models::TaskDef.new(
          name: name,
          retry_count: retry_count,
          retry_delay_seconds: retry_delay_seconds,
          retry_logic: retry_logic,
          timeout_seconds: 0,
          response_timeout_seconds: 10,
          timeout_policy: 'RETRY',
          runtime_metadata: credentials.uniq
        )
      end

      private

      def wanted?(required, name)
        required.nil? || required.include?(name)
      end

      def build_tool_worker(tool_def, agent, domain:)
        credentials = tool_def.credentials + agent.credentials
        Worker::Worker.new(
          tool_def.name,
          ->(task) { Dispatch.run_tool_task(task, tool_def, logger: @logger) },
          **worker_options(domain, @agent_config.worker_thread_count),
          task_def_template: task_def_for(tool_def.name, retry_count: tool_def.retry_count,
                                                         retry_delay_seconds: tool_def.retry_delay_seconds,
                                                         retry_logic: tool_def.retry_logic, credentials: credentials)
        )
      end

      def build_system_worker(name, body, domain, agent)
        Worker::Worker.new(
          name, body,
          **worker_options(domain, @agent_config.system_worker_thread_count),
          task_def_template: task_def_for(name, credentials: agent.credentials)
        )
      end

      # When a run has a runId the server maps every required worker to that domain, so all
      # workers of the run poll on it.
      def worker_options(domain, thread_count)
        {
          register_task_def: true,
          overwrite_task_def: true,
          lease_extend_enabled: true,
          poll_interval: @agent_config.worker_poll_interval_ms,
          thread_count: thread_count,
          domain: domain
        }
      end

      def warn_unhandled(required, workers)
        return if required.nil?

        handled = workers.map(&:task_definition_name)
        missing = required.to_a - handled
        return if missing.empty?

        @logger&.warn("server requires workers this process does not provide: #{missing.join(', ')} " \
                      '(tasks of these types will stay SCHEDULED until some worker serves them)')
      end
    end
  end
end
