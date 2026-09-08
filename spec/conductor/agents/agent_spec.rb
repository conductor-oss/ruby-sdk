# frozen_string_literal: true

require 'spec_helper'
require 'support/agent_tools'

RSpec.describe Conductor::Agents::Agent do
  let(:model) { 'openai/gpt-4o' }

  describe '#initialize' do
    it 'validates the name pattern and max_turns' do
      expect { described_class.new(name: '1bad', model: model) }.to raise_error(Conductor::Agents::ConfigurationError, /name/)
      expect { described_class.new(name: 'has space', model: model) }.to raise_error(Conductor::Agents::ConfigurationError)
      expect { described_class.new(name: 'ok', model: model, max_turns: 0) }.to raise_error(Conductor::Agents::ConfigurationError, /max_turns/)
      expect(described_class.new(name: 'ok-name_1', model: model).name).to eq('ok-name_1')
    end

    it 'normalizes the strategy and requires a router for :router' do
      expect(described_class.new(name: 'a', model: model).strategy).to eq('handoff')
      expect(described_class.new(name: 'a', model: model).strategy_set?).to be false
      expect(described_class.new(name: 'a', model: model, strategy: :round_robin).strategy).to eq('round_robin')
      expect { described_class.new(name: 'a', model: model, strategy: :zigzag) }.to raise_error(Conductor::Agents::ConfigurationError)
      expect { described_class.new(name: 'a', model: model, strategy: :router) }.to raise_error(Conductor::Agents::ConfigurationError, /router/)
    end

    it 'accepts tools and agents lists' do
      child = described_class.new(name: 'c', model: model)
      agent = described_class.new(name: 'a', model: model, tools: [:current], agents: [child])
      expect(agent.tools.map(&:name)).to eq(['current'])
      expect(agent.agents).to eq([child])
    end
  end

  describe '#add_tool' do
    let(:agent) { described_class.new(name: 'a', model: model) }

    it 'accepts a symbol from the global registry, a ToolDef, a Tools module and an Agent' do
      agent.add_tool :current
      agent.add_tool Conductor::Agents::ToolDef.http('fetch', 'http://x')
      agent.add_tool SpecTools::Github
      agent.add_tool described_class.new(name: 'helper', model: model)
      expect(agent.tools.map(&:name)).to eq(%w[current fetch create_issue gh_cli dynamic_secret helper])
      expect(agent.tool('helper').tool_type).to eq('agent_tool')
    end

    it 'adds explicit credentials on a copy so the registry tool stays untouched' do
      agent.add_tool :create_issue, credentials: ['EXTRA']
      expect(agent.tool('create_issue').credentials).to eq(%w[GH_TOKEN EXTRA])
      expect(SpecTools::Github[:create_issue].credentials).to eq(['GH_TOKEN'])
    end

    it 'rejects unknown names, duplicates and junk' do
      expect { agent.add_tool :missing }.to raise_error(Conductor::Agents::ConfigurationError, /no tool named/)
      agent.add_tool :current
      expect { agent.add_tool :current }.to raise_error(Conductor::Agents::ConfigurationError, /duplicate/)
      expect { agent.add_tool 42 }.to raise_error(Conductor::Agents::ConfigurationError)
      expect { agent.add_tool Comparable }.to raise_error(Conductor::Agents::ConfigurationError, /no tools/)
    end
  end

  describe 'team sugar' do
    it 'add_agent rejects non-agents and duplicate names' do
      team = described_class.new(name: 'team')
      a = described_class.new(name: 'a', model: model)
      team.add_agent(a)
      expect { team.add_agent(described_class.new(name: 'a', model: model)) }.to raise_error(Conductor::Agents::ConfigurationError, /duplicate/)
      expect { team.add_agent('a') }.to raise_error(Conductor::Agents::ConfigurationError)
      team.add_agents(described_class.new(name: 'b', model: model), described_class.new(name: 'c', model: model))
      expect(team.agents.map(&:name)).to eq(%w[a b c])
    end

    it 'hands_off_to builds OnTextMention or OnCondition' do
      triage = described_class.new(name: 'triage', model: model)
      filer = described_class.new(name: 'filer', model: model)
      triage.hands_off_to filer, on: 'ACTIONABLE'
      triage.hands_off_to filer, on: ->(ctx) { ctx['iteration'] > 3 }
      expect(triage.handoffs[0]).to be_a(Conductor::Agents::Handoff::OnTextMention)
      expect(triage.handoffs[0].target).to eq('filer')
      expect(triage.handoffs[0].text).to eq('ACTIONABLE')
      expect(triage.handoffs[1]).to be_a(Conductor::Agents::Handoff::OnCondition)
    end

    it '>> builds a flattened sequential pipeline' do
      a = described_class.new(name: 'a', model: model)
      b = described_class.new(name: 'b', model: model)
      c = described_class.new(name: 'c', model: model)
      pipeline = a >> b >> c
      expect(pipeline.name).to eq('a_b_c')
      expect(pipeline.strategy).to eq('sequential')
      expect(pipeline.agents).to eq([a, b, c])
      expect(pipeline.model).to eq(model)
    end
  end

  describe 'guardrail and termination sugar' do
    let(:agent) { described_class.new(name: 'a', model: model) }

    it 'redact adds a fixing regex guardrail' do
      agent.redact %w[password api.key]
      g = agent.guardrails.first
      expect(g).to be_a(Conductor::Agents::RegexGuardrail)
      expect(g.on_fail).to eq('fix')
      expect(g.position).to eq('output')
      expect(g.pattern_strings).to eq(['password', 'api\.key'])
      expect(g.name).to eq('a_redact')
    end

    it 'stop_when and stop_after combine with OR' do
      agent.stop_when 'ISSUE_FILED'
      expect(agent.termination).to be_a(Conductor::Agents::Termination::TextMention)
      agent.stop_after messages: 12
      expect(agent.termination).to be_a(Conductor::Agents::Termination::Or)
      expect(agent.termination.conditions.map(&:class)).to eq([Conductor::Agents::Termination::TextMention,
                                                               Conductor::Agents::Termination::MaxMessage])
    end
  end

  describe 'callbacks' do
    it 'collects positions from handlers and blocks' do
      handler = Class.new(Conductor::Agents::CallbackHandler) do
        def on_tool_end(**_kwargs)
          nil
        end
      end.new
      agent = described_class.new(name: 'a', model: model, callbacks: [handler])
      agent.callback(:before_model) { |**_| nil }
      expect(agent.callback_positions).to eq(%w[before_model after_tool])
      expect { agent.callback(:sideways) { nil } }.to raise_error(Conductor::Agents::ConfigurationError)
    end
  end

  describe '#on_approval' do
    it 'stores the handler' do
      agent = described_class.new(name: 'a', model: model)
      handler = proc { |req| req.approve }
      agent.on_approval(&handler)
      expect(agent.approval_handler).to eq(handler)
    end
  end

  describe 'introspection' do
    it 'walks the whole tree and detects stateful members' do
      leaf = described_class.new(name: 'leaf', model: model, stateful: true)
      router = described_class.new(name: 'router', model: model)
      tool_agent = described_class.new(name: 'tool_agent', model: model)
      root = described_class.new(name: 'root', model: model, agents: [leaf], strategy: :router, router: router)
      root.add_tool tool_agent
      expect(root.all_agents.map(&:name)).to eq(%w[root leaf router tool_agent])
      expect(root.stateful_tree?).to be true
      expect(described_class.new(name: 'x', model: model).stateful_tree?).to be false
    end
  end

  describe '#call_sync / #call_async' do
    it 'delegates to the default runtime' do
      runtime = double('runtime')
      allow(Conductor::Agents).to receive(:runtime).and_return(runtime)
      agent = described_class.new(name: 'a', model: model)
      expect(runtime).to receive(:call_sync).with(agent, 'hi', session_id: 's').and_return('answer')
      expect(runtime).to receive(:call_async).with(agent, 'hi', session_id: nil)
      expect(agent.call_sync('hi', session_id: 's')).to eq('answer')
      agent.call_async('hi')
    end
  end
end
