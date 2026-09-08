# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'json_schemer'
require 'conductor/agents'
require_relative '../../../examples/agents/golden_agents'

# Contract tests: the Ruby serializer must produce exactly what the Python SDK produces
# (golden configs vendored from python-sdk/examples/agents/_configs) and every config must
# validate against the published agent schema.
RSpec.describe 'agentConfig contract' do
  fixtures = File.expand_path('../../fixtures/agents', __dir__)
  schema = JSONSchemer.schema(JSON.parse(File.read(File.join(fixtures, 'agent-schema.json'))))
  golden_files = Dir[File.join(fixtures, 'configs', '*.json')]

  it 'has a golden fixture for every example and vice versa' do
    expect(golden_files.map { |f| File.basename(f, '.json') }).to match_array(GoldenAgents::EXAMPLES.keys)
  end

  golden_files.each do |file|
    name = File.basename(file, '.json')

    it "serializes #{name} exactly like the Python SDK" do
      expected = JSON.parse(File.read(file))
      actual = JSON.parse(JSON.generate(Conductor::Agents::ConfigSerializer.serialize(GoldenAgents::EXAMPLES.fetch(name).call)))
      expect(actual).to eq(expected)
    end

    it "#{name} validates against agent-schema.json" do
      config = JSON.parse(JSON.generate(Conductor::Agents::ConfigSerializer.serialize(GoldenAgents::EXAMPLES.fetch(name).call)))
      errors = schema.validate(config).map { |e| e['error'] }
      expect(errors).to eq([])
    end
  end

  it 'rejects unknown root keys (the schema is closed)' do
    expect(schema.valid?({ 'name' => 'x', 'bogus' => 1 })).to be false
  end
end
