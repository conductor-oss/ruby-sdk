# frozen_string_literal: true

require 'spec_helper'
require 'conductor/agents'

RSpec.describe Conductor::Agents::CallbackHandler do
  let(:timing) do
    Class.new(described_class) do
      def on_model_start(**_kwargs)
        { 'seen' => true }
      end
    end
  end

  let(:noisy) do
    Class.new(described_class) do
      def on_model_start(**_kwargs)
        raise 'boom'
      end

      def on_model_end(**_kwargs)
        nil
      end
    end
  end

  it 'knows which positions a handler overrides' do
    handler = timing.new
    expect(handler.handles?('before_model')).to be true
    expect(handler.handles?(:after_model)).to be false
  end

  it 'chains handlers with first-non-empty-hash-wins and skips errors' do
    chain = described_class.chain('before_model', [noisy.new, timing.new], logger: Logger.new(nil))
    expect(chain.call(messages: [])).to eq('seen' => true)
  end

  it 'returns nil when nothing is registered and {} when handlers return nil' do
    expect(described_class.chain('after_agent', [timing.new])).to be_nil
    expect(described_class.chain('after_model', [noisy.new]).call(llm_result: 'x')).to eq({})
  end

  it 'runs procs before handlers' do
    chain = described_class.chain('before_model', [timing.new], [->(**_) { { 'proc' => 1 } }])
    expect(chain.call).to eq('proc' => 1)
  end
end
