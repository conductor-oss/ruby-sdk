#!/usr/bin/env ruby
# frozen_string_literal: true

# Dump the serialized agentConfig JSON for the golden examples, for cross-SDK comparison
# with python-sdk/examples/agents/dump_agent_configs.py (same file names, sorted keys).
#
#   CONDUCTOR_AGENT_LLM_MODEL=anthropic/claude-sonnet-4-6 bundle exec ruby examples/agents/dump_agent_configs.rb [out_dir]
require 'json'
require_relative '../../lib/conductor/agents'
require_relative 'golden_agents'

out_dir = ARGV[0] || File.join(__dir__, '_configs')
Dir.mkdir(out_dir) unless Dir.exist?(out_dir)

def sort_keys(value)
  case value
  when Hash then value.keys.sort.to_h { |k| [k, sort_keys(value[k])] }
  when Array then value.map { |v| sort_keys(v) }
  else value
  end
end

GoldenAgents::EXAMPLES.each do |name, build|
  config = Conductor::Agents::ConfigSerializer.serialize(build.call)
  File.write(File.join(out_dir, "#{name}.json"), JSON.pretty_generate(sort_keys(config)))
  puts "  [OK] #{name}"
rescue StandardError => e
  puts "  [FAIL] #{name}: #{e.message}"
end
puts "\nConfigs written to #{out_dir}"
