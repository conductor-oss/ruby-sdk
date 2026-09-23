# frozen_string_literal: true

require 'spec_helper'
require 'conductor/agents'
require 'stringio'
require_relative '../../../examples/agents/catalog'

RSpec.describe 'Agent examples on a Conductor playback server' do
  before do
    skip 'Set CONDUCTOR_AGENTS_PLAYBACK=true and start the dedicated playback server' unless ENV['CONDUCTOR_AGENTS_PLAYBACK'] == 'true'
  end

  AgentExamples::EXAMPLES.each_key do |name|
    it "runs #{name} from the example file", :aggregate_failures do
      runtime = Conductor::Agents::AgentRuntime.new(logger: Logger.new(nil))
      output = StringIO.new
      executions = AgentExamples.load(name).run(runtime: runtime, input: StringIO.new("y\ny\n"), output: output)
      expect(executions).not_to be_empty
      executions.each do |execution|
        expect(execution.done?).to be true
        expect(runtime.client.get_status(execution.execution_id)['isComplete']).to be true
      end
    ensure
      runtime&.shutdown
    end
  end
end
