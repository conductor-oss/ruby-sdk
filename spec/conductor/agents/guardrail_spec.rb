# frozen_string_literal: true

require 'spec_helper'
require 'conductor/agents'

RSpec.describe Conductor::Agents::Guardrail do
  it 'validates position, on_fail, human-on-input and max_retries' do
    expect { described_class.new(name: 'g', position: :middle) }.to raise_error(Conductor::Agents::ConfigurationError)
    expect { described_class.new(name: 'g', on_fail: :explode) }.to raise_error(Conductor::Agents::ConfigurationError)
    expect { described_class.new(name: 'g', position: :input, on_fail: :human) }.to raise_error(Conductor::Agents::ConfigurationError)
    expect { described_class.new(name: 'g', max_retries: 0) }.to raise_error(Conductor::Agents::ConfigurationError)
    expect { described_class.new }.to raise_error(Conductor::Agents::ConfigurationError)
  end

  it 'is external without a block and custom with one' do
    external = described_class.new(name: 'remote')
    expect(external.external?).to be true
    expect(external.guardrail_type).to eq('external')
    expect { external.check('x') }.to raise_error(Conductor::Agents::Error)

    custom = described_class.new(name: 'no_pii', on_fail: :retry) { |c| !c.include?('ssn') }
    expect(custom.guardrail_type).to eq('custom')
    expect(custom.check('fine').passed?).to be true
    expect(custom.check('ssn 1').passed?).to be false
    expect(custom.on_fail).to eq('retry')
    expect(custom.position).to eq('output')
  end
end

RSpec.describe Conductor::Agents::RegexGuardrail do
  it 'blocks matches in block mode with the custom or default message' do
    g = described_class.new(['\d{3}-\d{2}-\d{4}'], name: 'no_ssn', message: 'No SSNs')
    expect(g.check('my ssn is 123-45-6789').message).to eq('No SSNs')
    expect(g.check('nothing here').passed?).to be true
    expect(described_class.new('x').check('x').message).to eq('Content matched a blocked pattern.')
  end

  it 'requires a match in allow mode and accepts Regexp patterns' do
    g = described_class.new(/^\s*[{\[]/, mode: :allow)
    expect(g.check('{"a":1}').passed?).to be true
    expect(g.check('nope').message).to eq('Content did not match any allowed pattern.')
    expect(g.pattern_strings).to eq(['^\s*[{\[]'])
    expect(g.guardrail_type).to eq('regex')
  end

  it 'rejects invalid modes' do
    expect { described_class.new('x', mode: :maybe) }.to raise_error(Conductor::Agents::ConfigurationError)
  end
end

RSpec.describe Conductor::Agents::LlmGuardrail do
  it 'stores model, policy and max_tokens and evaluates on the server' do
    g = described_class.new('openai/gpt-4o-mini', 'No medical advice', name: 'safety', max_tokens: 100)
    expect(g.guardrail_type).to eq('llm')
    expect(g.model).to eq('openai/gpt-4o-mini')
    expect(g.check('anything').passed?).to be false
    expect { described_class.new('gpt-4o', 'p') }.to raise_error(Conductor::Agents::ConfigurationError)
  end
end
