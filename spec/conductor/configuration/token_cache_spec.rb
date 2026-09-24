# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Conductor::Configuration, '#auth_token' do
  it 'starts with no token and a zero update time' do
    config = described_class.new(server_api_url: 'http://a/api')
    expect(config.auth_token).to be_nil
    expect(config.token_update_time).to eq(0)
  end

  it 'caches the token per instance' do
    a = described_class.new(server_api_url: 'http://a/api')
    b = described_class.new(server_api_url: 'http://b/api')

    a.update_token('token-a')

    expect(a.auth_token).to eq('token-a')
    expect(a.token_update_time).to be > 0
    expect(b.auth_token).to be_nil
    expect(b.token_update_time).to eq(0)
  end

  it 'keeps the deprecated class-level accessors working with a warning' do
    expect { described_class.auth_token = 'legacy' }.to output(/deprecated/).to_stderr
    expect(described_class.auth_token).to eq('legacy')
    described_class.auth_token = nil
  end
end
