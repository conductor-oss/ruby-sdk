# frozen_string_literal: true

require 'json'
require_relative 'errors'

module Conductor
  module Agents
    # Wire values for ToolConfig#toolType. Only +worker+ and +cli+ tools run in this
    # process; every other type is executed by the Conductor server.
    module ToolType
      WORKER = 'worker'
      HTTP = 'http'
      API = 'api'
      MCP = 'mcp'
      HUMAN = 'human'
      AGENT_TOOL = 'agent_tool'
      GENERATE_IMAGE = 'generate_image'
      GENERATE_AUDIO = 'generate_audio'
      GENERATE_VIDEO = 'generate_video'
      GENERATE_PDF = 'generate_pdf'
      RAG_INDEX = 'rag_index'
      RAG_SEARCH = 'rag_search'
      PULL_WORKFLOW_MESSAGES = 'pull_workflow_messages'
      CLI = 'cli'

      MEDIA = [GENERATE_IMAGE, GENERATE_AUDIO, GENERATE_VIDEO, GENERATE_PDF].freeze
      RAG = [RAG_INDEX, RAG_SEARCH].freeze
      LOCAL = [WORKER, CLI].freeze
      ALL = [WORKER, HTTP, API, MCP, HUMAN, AGENT_TOOL, *MEDIA, *RAG, PULL_WORKFLOW_MESSAGES, CLI].freeze

      def self.valid?(type)
        ALL.include?(type.to_s)
      end
    end

    # A tool call with pre-filled arguments (Agent#prefill_tools)
    PrefillToolCall = Struct.new(:tool_name, :arguments, :tool, keyword_init: true) do
      def to_h
        { 'toolName' => tool_name, 'arguments' => arguments || {} }
      end
    end

    # A tool an agent can call. This is the developer-facing type: the counterpart of
    # the Java SDK's @Tool / HttpTool / McpTool builders and the Python SDK's @tool /
    # http_tool / mcp_tool functions. The wire-level tool config the server receives is
    # produced by ConfigSerializer and never handed to developers.
    #
    # Worker tools are created by the Tools DSL (+tool def ...+); server-side tools by
    # the factories below (Tool.http, .mcp, .human, .agent, ...).
    class Tool
      RETRY_POLICIES = %w[fixed linear_backoff exponential_backoff].freeze
      RETRY_LOGIC = {
        'fixed' => 'FIXED',
        'linear_backoff' => 'LINEAR_BACKOFF',
        'exponential_backoff' => 'EXPONENTIAL_BACKOFF'
      }.freeze
      CREDENTIAL_PLACEHOLDER = /\$\{(\w+)\}/

      attr_accessor :name, :description, :input_schema, :output_schema, :func,
                    :approval_required, :timeout_seconds, :tool_type, :config,
                    :guardrails, :credentials, :stateful, :max_calls,
                    :retry_count, :retry_delay_seconds, :retry_policy

      # @param name [String] tool name; for worker tools this is also the Conductor task name
      # @param func [Proc, Method, nil] local implementation; nil for server-side tools
      def initialize(name:, description: '', input_schema: nil, output_schema: nil, func: nil,
                     approval_required: false, timeout_seconds: nil, tool_type: ToolType::WORKER,
                     config: nil, guardrails: nil, credentials: nil, stateful: false, max_calls: nil,
                     retry_count: 2, retry_delay_seconds: 2, retry_policy: 'linear_backoff')
        raise ConfigurationError, 'tool name is required' if name.nil? || name.to_s.empty?
        raise ConfigurationError, "unknown tool_type #{tool_type.inspect}" unless ToolType.valid?(tool_type)
        unless RETRY_POLICIES.include?(retry_policy.to_s) || RETRY_LOGIC.value?(retry_policy.to_s)
          raise ConfigurationError, "retry_policy must be one of #{RETRY_POLICIES.join(', ')}"
        end

        @name = name.to_s
        @description = description.to_s
        @input_schema = input_schema || {}
        @output_schema = output_schema || {}
        @func = func
        @approval_required = approval_required ? true : false
        @timeout_seconds = timeout_seconds
        @tool_type = tool_type.to_s
        @config = config || {}
        @guardrails = Array(guardrails)
        @credentials = Array(credentials).map(&:to_s).uniq
        @stateful = stateful ? true : false
        @max_calls = max_calls
        @retry_count = retry_count
        @retry_delay_seconds = retry_delay_seconds
        @retry_policy = retry_policy.to_s
      end

      # True when this tool needs a worker polling in this process
      def local?
        !@func.nil? && ToolType::LOCAL.include?(@tool_type)
      end

      def server_side?
        !local?
      end

      # Conductor retryLogic value for this tool's retry policy
      def retry_logic
        RETRY_LOGIC.fetch(@retry_policy) { @retry_policy.upcase }
      end

      # Add secret names this tool needs (deduplicated)
      # @return [self]
      def add_credentials(*names)
        @credentials = (@credentials + names.flatten.map(&:to_s)).uniq
        self
      end

      # A copy of this tool guarded by +guardrails+ (replaces any existing ones)
      # @return [Tool]
      def with_guardrails(*guardrails)
        copy = dup
        copy.guardrails = guardrails.flatten
        copy
      end

      # Build a pre-filled call for Agent#prefill_tools
      def call(**args)
        PrefillToolCall.new(tool_name: @name, arguments: args.transform_keys(&:to_s), tool: self)
      end

      def to_s
        "#<Conductor::Agents::Tool #{@name} (#{@tool_type})>"
      end
      alias inspect to_s

      class << self
        # Tool backed by an HTTP endpoint; the server makes the call.
        # Headers may reference secrets as ${NAME}; every placeholder must be listed in +credentials+.
        def http(name, url, description: '', method: 'GET', headers: nil, input_schema: nil,
                 accept: ['application/json'], content_type: 'application/json', credentials: nil)
          creds = Array(credentials).map(&:to_s)
          validate_placeholders!(headers, creds)
          new(
            name: name, description: description,
            input_schema: input_schema || { 'type' => 'object', 'properties' => {} },
            tool_type: ToolType::HTTP,
            config: { 'url' => url, 'method' => method.to_s.upcase, 'headers' => headers || {},
                      'accept' => accept, 'contentType' => content_type },
            credentials: creds
          )
        end

        # Tools discovered from an OpenAPI endpoint; the server does the discovery.
        def api(url, name: 'api_tools', description: nil, headers: nil, tool_names: nil, max_tools: 64, credentials: nil)
          creds = Array(credentials).map(&:to_s)
          validate_placeholders!(headers, creds)
          config = { 'url' => url }
          config['headers'] = headers if headers
          config['tool_names'] = Array(tool_names) if tool_names
          config['max_tools'] = max_tools
          new(name: name, description: description || "API tools from #{url}", tool_type: ToolType::API,
              config: config, credentials: creds)
        end

        # Tools served by an MCP server; discovery (LIST_MCP_TOOLS) and calls happen on the server.
        def mcp(server_url, name: 'mcp_tools', description: nil, headers: nil, tool_names: nil,
                max_tools: 64, credentials: nil)
          creds = Array(credentials).map(&:to_s)
          validate_placeholders!(headers, creds)
          config = { 'server_url' => server_url }
          config['headers'] = headers if headers
          config['tool_names'] = Array(tool_names) if tool_names
          config['max_tools'] = max_tools
          new(name: name, description: description || "MCP tools from #{server_url}", tool_type: ToolType::MCP,
              config: config, credentials: creds)
        end

        # Tool that pauses for a human answer (Conductor HUMAN task)
        def human(name, description:, input_schema: nil)
          new(
            name: name, description: description, tool_type: ToolType::HUMAN,
            input_schema: input_schema || {
              'type' => 'object',
              'properties' => { 'question' => { 'type' => 'string',
                                                'description' => 'The question or request for the human operator.' } },
              'required' => ['question']
            }
          )
        end

        # Another agent exposed as a tool (runs as a sub-workflow)
        def agent(agent, name: nil, description: nil, retry_count: nil, retry_delay_seconds: nil, optional: nil)
          agent_name = agent.respond_to?(:name) ? agent.name : agent.to_s
          config = { 'agent' => agent }
          config['retryCount'] = retry_count unless retry_count.nil?
          config['retryDelaySeconds'] = retry_delay_seconds unless retry_delay_seconds.nil?
          config['optional'] = optional unless optional.nil?
          new(
            name: name || agent_name,
            description: description || "Invoke the #{agent_name} agent",
            input_schema: {
              'type' => 'object',
              'properties' => { 'request' => { 'type' => 'string',
                                               'description' => 'The request or question to send to this agent.' } },
              'required' => ['request']
            },
            tool_type: ToolType::AGENT_TOOL,
            config: config
          )
        end

        # Media generation tools (server-side)
        def image(name, description:, llm_provider:, model:, input_schema: nil, **defaults)
          media(ToolType::GENERATE_IMAGE, 'GENERATE_IMAGE', name, description, llm_provider, model, input_schema, defaults)
        end

        def audio(name, description:, llm_provider:, model:, input_schema: nil, **defaults)
          media(ToolType::GENERATE_AUDIO, 'GENERATE_AUDIO', name, description, llm_provider, model, input_schema, defaults)
        end

        def video(name, description:, llm_provider:, model:, input_schema: nil, **defaults)
          media(ToolType::GENERATE_VIDEO, 'GENERATE_VIDEO', name, description, llm_provider, model, input_schema, defaults)
        end

        def pdf(name = 'generate_pdf', description: 'Generate a PDF document.', input_schema: nil, **defaults)
          new(name: name, description: description, tool_type: ToolType::GENERATE_PDF,
              input_schema: input_schema || { 'type' => 'object', 'properties' => {} },
              config: { 'taskType' => 'GENERATE_PDF' }.merge(stringify(defaults)))
        end

        # RAG tools (server-side)
        def index(name, description:, vector_db:, index:, embedding_model_provider:, embedding_model:,
                  namespace: 'default_ns', chunk_size: nil, chunk_overlap: nil, dimensions: nil, input_schema: nil)
          config = { 'taskType' => 'LLM_INDEX_TEXT', 'vectorDB' => vector_db, 'namespace' => namespace, 'index' => index,
                     'embeddingModelProvider' => embedding_model_provider, 'embeddingModel' => embedding_model }
          config['chunkSize'] = chunk_size if chunk_size
          config['chunkOverlap'] = chunk_overlap if chunk_overlap
          config['dimensions'] = dimensions if dimensions
          new(name: name, description: description, tool_type: ToolType::RAG_INDEX,
              input_schema: input_schema || { 'type' => 'object', 'properties' => {} }, config: config)
        end

        def search(name, description:, vector_db:, index:, embedding_model_provider:, embedding_model:,
                   namespace: 'default_ns', max_results: 5, dimensions: nil, input_schema: nil)
          config = { 'taskType' => 'LLM_SEARCH_INDEX', 'vectorDB' => vector_db, 'namespace' => namespace, 'index' => index,
                     'embeddingModelProvider' => embedding_model_provider, 'embeddingModel' => embedding_model,
                     'maxResults' => max_results }
          config['dimensions'] = dimensions if dimensions
          new(name: name, description: description, tool_type: ToolType::RAG_SEARCH,
              input_schema: input_schema || { 'type' => 'object', 'properties' => {} }, config: config)
        end

        # Wait for messages posted to the execution (PULL_WORKFLOW_MESSAGES)
        def wait_for_message(name, description:, batch_size: 1, blocking: true)
          config = { 'batchSize' => batch_size }
          config['blocking'] = false unless blocking
          new(name: name, description: description, tool_type: ToolType::PULL_WORKFLOW_MESSAGES,
              input_schema: { 'type' => 'object', 'properties' => {} }, config: config)
        end

        private

        def media(tool_type, task_type, name, description, llm_provider, model, input_schema, defaults)
          new(name: name, description: description, tool_type: tool_type,
              input_schema: input_schema || { 'type' => 'object', 'properties' => {} },
              config: { 'taskType' => task_type, 'llmProvider' => llm_provider, 'model' => model }.merge(stringify(defaults)))
        end

        def stringify(hash)
          hash.transform_keys(&:to_s)
        end

        def validate_placeholders!(headers, credentials)
          return unless headers

          placeholders = headers.to_s.scan(CREDENTIAL_PLACEHOLDER).flatten.uniq
          missing = placeholders - credentials
          return if missing.empty?

          raise ConfigurationError,
                "Header placeholder(s) #{missing.inspect} not declared in credentials: #{credentials.inspect}"
        end
      end
    end
  end
end
