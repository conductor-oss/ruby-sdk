# frozen_string_literal: true

require 'spec_helper'
require 'conductor/agents'

RSpec.describe Conductor::Agents::AgentConfig do
  it 'has the Python defaults' do
    c = described_class.from_env({})
    expect(c.worker_poll_interval_ms).to eq(100)
    expect(c.worker_thread_count).to eq(1)
    expect(c.auto_register_integrations).to be false
    expect(c.streaming_enabled).to be true
  end

  it 'reads CONDUCTOR_AGENT_* variables with Python boolean parsing' do
    env = { 'CONDUCTOR_AGENT_WORKER_POLL_INTERVAL' => '250', 'CONDUCTOR_AGENT_WORKER_THREADS' => '4',
            'CONDUCTOR_AGENT_INTEGRATIONS_AUTO_REGISTER' => 'yes', 'CONDUCTOR_AGENT_STREAMING_ENABLED' => 'off' }
    c = described_class.from_env(env)
    expect(c.worker_poll_interval_ms).to eq(250)
    expect(c.worker_thread_count).to eq(4)
    expect(c.auto_register_integrations).to be true
    expect(c.streaming_enabled).to be false
  end

  it 'ignores blank and garbage values' do
    c = described_class.from_env('CONDUCTOR_AGENT_WORKER_THREADS' => 'lots', 'CONDUCTOR_AGENT_STREAMING_ENABLED' => ' ')
    expect(c.worker_thread_count).to eq(1)
    expect(c.streaming_enabled).to be true
  end
end
