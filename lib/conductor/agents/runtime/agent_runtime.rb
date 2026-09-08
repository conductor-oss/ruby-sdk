# frozen_string_literal: true

require 'securerandom'
require 'logger'
require 'set'
require_relative '../errors'
require_relative '../config_serializer'
require_relative 'agent_config'
require_relative 'execution'
require_relative 'approval_request'
require_relative 'sse_client'
require_relative 'status_poller'
require_relative 'tool_registry'
require_relative '../../client/agent_client'
require_relative '../../worker/task_handler'

module Conductor
  module Agents
    # Runs agents against a Conductor server: serializes the agentConfig, starts the
    # execution, registers the workers the server asks for, and streams the result.
    #
    #   runtime = Conductor::Agents::AgentRuntime.new(configuration: Conductor::Configuration.new)
    #   runtime.call_sync(agent, 'Weather in Lisbon?')
    #
    # Conductor::Agents.runtime holds a default instance built from the environment;
    # Agent#call_sync / #call_async use it.
    class AgentRuntime
      attr_reader :configuration, :agent_config, :client, :api_client, :logger

      def initialize(configuration: nil, agent_config: nil, logger: nil, api_client: nil, agent_client: nil)
        @configuration = configuration || Configuration.new
        @agent_config = agent_config || AgentConfig.from_env
        @logger = logger || Logger.new($stdout, level: Logger::INFO, progname: 'conductor-agents')
        @api_client = api_client || Http::ApiClient.new(configuration: @configuration)
        @client = agent_client || Client::AgentClient.new(@api_client)
        @registry = ToolRegistry.new(@agent_config, logger: @logger)
        @handlers = []
        @running_workers = Set.new
        @stream_threads = []
        @mutex = Mutex.new
      end

      # Run and wait for the answer
      # @return [String]
      def call_sync(agent, prompt, session_id: nil, timeout: nil, **options)
        call_async(agent, prompt, session_id: session_id, **options).result(timeout: timeout)
      end

      # Start the agent and return immediately with an Execution
      # @param session_id [String, nil] conversation id to continue
      # @param media [Array<String>, nil], context [Hash, nil], idempotency_key [String, nil], timeout_seconds [Integer, nil]
      # @yield [answer, execution] runs on the stream thread when the execution finishes
      # @return [Execution]
      def call_async(agent, prompt, session_id: nil, media: nil, context: nil, idempotency_key: nil,
                     timeout_seconds: nil, &on_done)
        payload = start_payload(agent, prompt, session_id: session_id, media: media, context: context,
                                               idempotency_key: idempotency_key, timeout_seconds: timeout_seconds)
        response = @client.start_agent(payload)
        execution_id = response['executionId'] || raise(Error, "server returned no executionId: #{response.inspect}")

        execution = Execution.new(execution_id, client: @client, agent_name: response['agentName'] || agent.name, runtime: self)
        start_workers(agent, response['requiredWorkers'], domain: payload['runId'])
        attach(execution, agent: agent, &on_done)
        execution
      end

      # Register agents on the server without running them
      # @return [Array<String>] deployed agent names
      def deploy(*agents)
        agents.flatten.map do |agent|
          response = @client.deploy_agent('agentConfig' => ConfigSerializer.serialize(agent))
          response['agentName'] || agent.name
        end
      end

      # Compile without registering: { "workflowDef", "requiredWorkers" }
      def compile(agent)
        @client.compile_agent('agentConfig' => ConfigSerializer.serialize(agent))
      end

      # Deploy, start workers for every tool, and (by default) block until INT/TERM
      def serve(*agents, blocking: true)
        agents = agents.flatten
        agents.each do |agent|
          response = @client.deploy_agent('agentConfig' => ConfigSerializer.serialize(agent))
          start_workers(agent, response['requiredWorkers'], domain: nil)
        end
        return self unless blocking

        wait_for_signal
        shutdown
        self
      end

      # Follow an execution on a background thread (used by call_async and Execution#result)
      def attach(execution, agent: nil, &on_done)
        execution.attached!
        thread = Thread.new do
          Thread.current.name = "conductor-agent-stream-#{execution.execution_id}"
          follow(execution, agent, &on_done)
        end
        @mutex.synchronize { @stream_threads << thread }
        thread
      end

      # Stop workers and stream threads
      def shutdown(timeout: 5)
        handlers, threads = @mutex.synchronize do
          h = @handlers.dup
          t = @stream_threads.dup
          @handlers.clear
          @stream_threads.clear
          @running_workers.clear
          [h, t]
        end
        handlers.each { |h| h.stop(timeout: timeout) }
        threads.each do |t|
          t.join(timeout)
          t.kill if t.alive?
        end
        self
      end

      # Names of the workers currently polling
      def running_workers
        @mutex.synchronize { @running_workers.map(&:first) }
      end

      # Build the AgentStartRequest body
      def start_payload(agent, prompt, session_id: nil, media: nil, context: nil, idempotency_key: nil, timeout_seconds: nil)
        payload = {
          'agentConfig' => ConfigSerializer.serialize(agent),
          'prompt' => prompt.to_s,
          'sessionId' => session_id.to_s,
          'media' => Array(media)
        }
        payload['context'] = context if context && !context.empty?
        payload['idempotencyKey'] = idempotency_key if idempotency_key
        payload['timeoutSeconds'] = timeout_seconds if timeout_seconds
        payload['runId'] = SecureRandom.hex(16) if agent.stateful_tree?
        payload
      end

      private

      # Start workers for the tools and system tasks the server requires (skipping ones already polling)
      def start_workers(agent, required_workers, domain:)
        workers = @registry.workers_for(agent, required_workers: required_workers, domain: domain)
        fresh = @mutex.synchronize do
          workers.reject { |w| @running_workers.include?([w.task_definition_name, w.domain]) }
                 .each { |w| @running_workers << [w.task_definition_name, w.domain] }
        end
        return if fresh.empty?

        handler = Worker::TaskHandler.new(workers: fresh, configuration: @configuration, logger: @logger,
                                          scan_for_annotated_workers: false, register_task_definitions: true)
        handler.start
        @mutex.synchronize { @handlers << handler }
        @logger.info("agent workers started: #{fresh.map(&:task_definition_name).join(', ')}")
      end

      def follow(execution, agent, &on_done)
        events = event_source(execution.execution_id)
        events.each do |event|
          handle_event(execution, agent, event)
          break if execution.done?
        end
        execution.fail('stream ended before the execution finished') unless execution.done?
      rescue StandardError => e
        @logger.error("stream for #{execution.execution_id} failed: #{e.class}: #{e.message}")
        execution.fail("#{e.class}: #{e.message}") unless execution.done?
      ensure
        run_callback(on_done, execution.answer, execution) if on_done
      end

      def event_source(execution_id)
        poller = StatusPoller.new(@client, interval: @agent_config.status_poll_interval_seconds, logger: @logger)
        return poller.each_event(execution_id) unless @agent_config.streaming_enabled

        sse = SseClient.new(@api_client, logger: @logger)
        Enumerator.new do |y|
          sse.each_event(execution_id) { |ev| y << ev }
        rescue SseUnavailableError => e
          @logger.info("SSE unavailable (#{e.message}); polling status instead")
          poller.each_event(execution_id) { |ev| y << ev }
        end
      end

      def handle_event(execution, agent, event)
        data = event['data'] || {}
        execution.record_event(event)
        case event['event'].to_s
        when 'message'
          execution.append_text(data['content'])
        when 'tool_call'
          execution.add_tool_call(data['toolName'], strip_injected(data['args']))
        when 'tool_result'
          execution.add_tool_result(data['toolName'], data['result'])
        when 'waiting'
          handle_waiting(execution, agent, data)
        when 'done'
          execution.token_usage = fetch_token_usage(execution.execution_id)
          execution.finish(status: 'COMPLETED', output: data['output'] || {})
        when 'error'
          execution.finish(status: data['status'] || 'FAILED', output: data['output'] || {},
                           reason: data['content'] || 'execution failed')
        end
      end

      def handle_waiting(execution, agent, data)
        pending = data['pendingTool'] || {}
        request = ApprovalRequest.new(execution.execution_id, pending, client: @client, execution: execution)
        execution.mark_waiting(request)
        handler = agent&.approval_handler
        return if handler.nil? || request.tool_calls.empty?

        run_callback(handler, request)
      end

      def run_callback(callable, *args)
        callable.call(*args)
      rescue StandardError => e
        @logger.error("callback raised #{e.class}: #{e.message}")
      end

      def strip_injected(args)
        return {} unless args.is_a?(Hash)

        args.reject { |k, _| Dispatch::INJECTED_KEYS.include?(k.to_s) }
      end

      # Sum tokenUsage over the execution and its sub-agent executions
      def fetch_token_usage(execution_id, visited = Set.new)
        return TokenUsage.new if visited.include?(execution_id) || visited.size > 50

        visited << execution_id
        run = @client.get_execution(execution_id)
        usage = run['tokenUsage'] || {}
        total = TokenUsage.new(prompt_tokens: usage['promptTokens'].to_i, completion_tokens: usage['completionTokens'].to_i,
                               total_tokens: usage['totalTokens'].to_i)
        Array(run['tasks']).each do |task|
          sub = task['subWorkflowId']
          total += fetch_token_usage(sub, visited) if sub && !sub.to_s.empty?
        end
        total
      rescue StandardError => e
        @logger.debug("token usage unavailable for #{execution_id}: #{e.message}")
        TokenUsage.new
      end

      def wait_for_signal
        queue = Queue.new
        %w[INT TERM].each { |sig| trap(sig) { queue << sig } }
        @logger.info('serving agents; press Ctrl-C to stop')
        queue.pop
      end
    end
  end
end
