# frozen_string_literal: true

require_relative 'errors'
require_relative 'tool'
require_relative 'tools'
require_relative 'guardrail'
require_relative 'termination'
require_relative 'handoff'
require_relative 'callback_handler'
require_relative 'memory'
require_relative 'prompt_template'

module Conductor
  module Agents
    # Multi-agent orchestration strategies (wire values are lowercase snake_case)
    module Strategy
      HANDOFF = 'handoff'
      SEQUENTIAL = 'sequential'
      PARALLEL = 'parallel'
      ROUTER = 'router'
      ROUND_ROBIN = 'round_robin'
      RANDOM = 'random'
      SWARM = 'swarm'
      MANUAL = 'manual'
      PLAN_EXECUTE = 'plan_execute'
      ALL = [HANDOFF, SEQUENTIAL, PARALLEL, ROUTER, ROUND_ROBIN, RANDOM, SWARM, MANUAL, PLAN_EXECUTE].freeze

      def self.normalize(value)
        s = value.to_s.downcase
        raise ConfigurationError, "invalid strategy #{value.inspect}; use one of #{ALL.join(', ')}" unless ALL.include?(s)

        s
      end
    end

    # An agent definition. Nothing here talks to the server: ConfigSerializer turns the
    # tree into agentConfig and AgentRuntime runs it (call_sync / call_async delegate to
    # Conductor::Agents.runtime).
    #
    #   agent = Agent.new(name: 'weather', model: 'openai/gpt-4o', instructions: 'Answer weather questions.')
    #   agent.add_tool :get_weather
    #   puts agent.call_sync('Weather in Lisbon?')
    class Agent
      NAME_PATTERN = /\A[a-zA-Z_][a-zA-Z0-9_-]*\z/

      attr_reader :name, :tools, :agents, :guardrails, :handoffs, :callbacks, :credentials, :callback_procs
      attr_accessor :model, :instructions, :router, :output_type, :memory, :termination,
                    :max_turns, :max_tokens, :timeout_seconds, :temperature, :stateful,
                    :metadata, :description, :external, :base_url, :prefill_tools, :approval_handler,
                    :planner, :fallback, :fallback_max_turns, :planner_context

      # @param name [String] ^[a-zA-Z_][a-zA-Z0-9_-]*$
      # @param model [String, nil] "provider/model"; the left side is the server integration name
      # @param instructions [String, PromptTemplate, Proc]
      # @param strategy [Symbol, String] how sub-agents are orchestrated (default :handoff)
      def initialize(name:, model: nil, instructions: '', tools: [], agents: [], strategy: nil, router: nil,
                     output_type: nil, guardrails: [], memory: nil, termination: nil, handoffs: [], callbacks: [],
                     credentials: [], max_turns: 25, max_tokens: nil, timeout_seconds: 0, temperature: nil,
                     stateful: false, metadata: nil, description: nil, external: false, base_url: nil,
                     prefill_tools: [], planner: nil, fallback: nil, fallback_max_turns: nil, planner_context: [])
        @name = name.to_s
        raise ConfigurationError, "invalid agent name #{name.inspect}: must match #{NAME_PATTERN.source}" unless NAME_PATTERN.match?(@name)
        raise ConfigurationError, 'max_turns must be >= 1' unless max_turns.is_a?(Integer) && max_turns >= 1

        @model = model
        @instructions = instructions
        @tools = []
        @agents = []
        @strategy = strategy.nil? ? nil : Strategy.normalize(strategy)
        @router = router
        @output_type = output_type
        @guardrails = Array(guardrails)
        @memory = memory
        @termination = termination
        @handoffs = Array(handoffs)
        @callbacks = Array(callbacks)
        @callback_procs = Hash.new { |h, k| h[k] = [] }
        @credentials = Array(credentials).map(&:to_s).uniq
        @max_turns = max_turns
        @max_tokens = max_tokens
        @timeout_seconds = timeout_seconds
        @temperature = temperature
        @stateful = stateful ? true : false
        @metadata = metadata
        @description = description
        @external = external ? true : false
        @base_url = base_url
        @prefill_tools = Array(prefill_tools)
        @approval_handler = nil
        @planner = planner
        @fallback = fallback
        @fallback_max_turns = fallback_max_turns
        @planner_context = Array(planner_context)
        [planner, fallback].compact.each do |child|
          raise ConfigurationError, 'planner and fallback must be Agents' unless child.is_a?(Agent)
        end
        raise ConfigurationError, 'strategy: :plan_execute requires planner:' if @strategy == Strategy::PLAN_EXECUTE && planner.nil?
        raise ConfigurationError, 'planner and fallback require strategy: :plan_execute' if (planner || fallback) && @strategy != Strategy::PLAN_EXECUTE
        raise ConfigurationError, 'strategy: :plan_execute requires tools:' if @strategy == Strategy::PLAN_EXECUTE && Array(tools).empty?

        Array(tools).each { |t| add_tool(t) }
        Array(agents).each { |a| add_agent(a) }
        raise ConfigurationError, 'strategy: :router requires router:' if @strategy == Strategy::ROUTER && @router.nil?
      end

      # ── Strategy ──────────────────────────────────────────────────────

      # @return [String] effective strategy (default handoff)
      def strategy
        @strategy || Strategy::HANDOFF
      end

      def strategy=(value)
        @strategy = value.nil? ? nil : Strategy.normalize(value)
      end

      # True when the user set a strategy explicitly
      def strategy_set?
        !@strategy.nil?
      end

      # ── Tools ─────────────────────────────────────────────────────────

      # Give the agent a tool.
      # @param tool [Symbol, String, Tool, Module, Class, Agent] a tool name defined with
      #   `tool def`, a Tool, a module that `extend Conductor::Agents::Tools`, or another
      #   Agent (wrapped as an agent tool)
      # @param credentials [Array<String>, nil] secret names when the scanner cannot see them
      # @return [self]
      def add_tool(tool, credentials: nil)
        resolve_tool_defs(tool).each do |tool_def|
          td = credentials ? tool_def.dup.tap { |d| d.credentials = tool_def.credentials.dup } : tool_def
          td.add_credentials(*credentials) if credentials
          raise ConfigurationError, "duplicate tool name #{td.name.inspect} on agent #{@name}" if @tools.any? { |t| t.name == td.name }

          @tools << td
        end
        self
      end

      def add_tools(*tools)
        tools.flatten.each { |t| add_tool(t) }
        self
      end

      # @return [Tool, nil]
      def tool(name)
        @tools.find { |t| t.name == name.to_s }
      end

      # ── Team ──────────────────────────────────────────────────────────

      # Add a member agent (same as agents: in the constructor)
      def add_agent(agent)
        raise ConfigurationError, "add_agent expects an Agent, got #{agent.class}" unless agent.is_a?(Agent)
        raise ConfigurationError, "duplicate sub-agent name #{agent.name.inspect} under #{@name}" if @agents.any? { |a| a.name == agent.name }

        @agents << agent
        self
      end

      def add_agents(*agents)
        agents.flatten.each { |a| add_agent(a) }
        self
      end

      # Hand off to +agent+ when this agent's output mentions +on+ (String), or when the
      # block/proc given as +on+ returns true.
      def hands_off_to(agent, on:)
        handoff = if on.respond_to?(:call)
                    Handoff::OnCondition.new(target: agent, condition: on)
                  else
                    Handoff::OnTextMention.new(target: agent, text: on)
                  end
        @handoffs << handoff
        self
      end

      def add_handoff(handoff)
        @handoffs << handoff
        self
      end

      # Sequential pipeline: a >> b >> c
      def >>(other)
        raise ConfigurationError, ">> expects an Agent, got #{other.class}" unless other.is_a?(Agent)

        left = sequential_pipeline? ? @agents : [self]
        right = other.sequential_pipeline? ? other.agents : [other]
        members = left + right
        Agent.new(name: members.map(&:name).join('_'), model: @model || other.model,
                  agents: members, strategy: Strategy::SEQUENTIAL)
      end

      def sequential_pipeline?
        @strategy == Strategy::SEQUENTIAL && !@agents.empty?
      end

      # ── Guardrails / termination sugar ────────────────────────────────

      # Scrub these words from the output before anyone sees it
      def redact(words, name: "#{@name}_redact")
        patterns = Array(words).map { |w| w.is_a?(Regexp) ? w : Regexp.escape(w.to_s) }
        @guardrails << RegexGuardrail.new(patterns, mode: :block, position: :output, on_fail: :fix, name: name)
        self
      end

      def add_guardrail(guardrail)
        @guardrails << guardrail
        self
      end

      # Stop when the output contains +text+
      def stop_when(text, case_sensitive: false)
        add_termination(Termination::TextMention.new(text, case_sensitive: case_sensitive))
      end

      # Stop after +messages+ messages
      def stop_after(messages:)
        add_termination(Termination::MaxMessage.new(messages))
      end

      def add_termination(condition)
        @termination = @termination ? (@termination | condition) : condition
        self
      end

      # ── Callbacks ─────────────────────────────────────────────────────

      def add_callback(handler)
        @callbacks << handler
        self
      end

      # Register a block for a callback position (before_model, after_model, ...)
      def callback(position, &block)
        pos = position.to_s
        raise ConfigurationError, "unknown callback position #{position.inspect}" unless CallbackHandler::POSITIONS.include?(pos)

        @callback_procs[pos] << block
        self
      end

      # Callables for +position+, or nil when nothing is registered
      def callback_chain(position, logger: nil)
        CallbackHandler.chain(position, @callbacks, @callback_procs[position.to_s], logger: logger)
      end

      # Positions with at least one handler or proc
      def callback_positions
        CallbackHandler::POSITIONS.reject { |p| callback_chain(p).nil? }
      end

      # ── Approval ──────────────────────────────────────────────────────

      # Decide approval-required tool calls: the block receives an ApprovalRequest
      def on_approval(&block)
        @approval_handler = block
        self
      end

      # ── Credentials ───────────────────────────────────────────────────

      def add_credentials(*names)
        @credentials = (@credentials + names.flatten.map(&:to_s)).uniq
        self
      end

      # ── Execution (delegates to the default runtime) ──────────────────

      # Run and block until the answer is ready
      # @return [String]
      def call_sync(prompt, session_id: nil, **options)
        Conductor::Agents.runtime.call_sync(self, prompt, session_id: session_id, **options)
      end

      # Run in the background; returns an Execution. The block (if given) receives the answer.
      def call_async(prompt, session_id: nil, **options, &on_done)
        Conductor::Agents.runtime.call_async(self, prompt, session_id: session_id, **options, &on_done)
      end

      # ── Introspection ─────────────────────────────────────────────────

      # Every agent in the tree (self first), including router, planner-style children and agent tools
      def all_agents
        list = [self]
        @agents.each { |a| list.concat(a.all_agents) }
        [@router, @planner, @fallback].each { |a| list.concat(a.all_agents) if a.is_a?(Agent) }
        @tools.each do |t|
          child = t.config['agent'] if t.tool_type == ToolType::AGENT_TOOL
          list.concat(child.all_agents) if child.is_a?(Agent)
        end
        list.uniq
      end

      # True when this agent or anything under it is stateful
      def stateful_tree?
        all_agents.any? { |a| a.stateful || a.tools.any?(&:stateful) }
      end

      def to_s
        "#<Conductor::Agents::Agent #{@name} model=#{@model.inspect} tools=#{@tools.size} agents=#{@agents.size}>"
      end
      alias inspect to_s

      private

      def resolve_tool_defs(tool)
        case tool
        when Tool then [tool]
        when Symbol, String
          [Tools.lookup(tool) || raise(ConfigurationError, "no tool named #{tool.inspect}; define it with `tool def #{tool}(...)` first")]
        when Agent then [Tool.agent(tool)]
        when Module
          raise ConfigurationError, "#{tool} has no tools; use `extend Conductor::Agents::Tools` and `tool def ...`" unless tool.respond_to?(:tool_defs)

          tool.tool_defs
        else
          raise ConfigurationError, "cannot use #{tool.inspect} as a tool"
        end
      end
    end
  end
end
