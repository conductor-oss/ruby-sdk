# frozen_string_literal: true

require 'spec_helper'
require 'conductor/agents'
require 'stringio'
require 'json'
require_relative '../../../examples/agents/catalog'

RSpec.describe 'Agent examples on a Conductor playback server' do
  def workflow_tasks(runtime, execution_id)
    client = Conductor::Client::WorkflowClient.new(runtime.configuration)
    pending = [execution_id]
    seen = []
    tasks = []
    until pending.empty?
      id = pending.pop
      next if seen.include?(id)

      seen << id
      workflow = client.get_workflow(id)
      tasks.concat(workflow.tasks)
      pending.concat(workflow.tasks.filter_map(&:sub_workflow_id))
    end
    tasks
  end

  before do
    skip 'Set CONDUCTOR_AGENTS_PLAYBACK=true and start the dedicated playback server' unless ENV['CONDUCTOR_AGENTS_PLAYBACK'] == 'true'
  end

  after do |example|
    path = ENV.fetch('CONDUCTOR_PLAYBACK_EXPECTED_FAILURES', nil)
    File.write(path, JSON.generate([@expected_failed_execution])) if path && @expected_failed_execution && example.exception.nil?
  end

  AgentExamples::EXAMPLES.each_key do |name|
    it "runs #{name} from the example file", :aggregate_failures do
      runtime = Conductor::Agents::AgentRuntime.new(logger: Logger.new(nil))
      output = StringIO.new
      executions = AgentExamples.load(name).run(runtime: runtime, input: StringIO.new("y\ny\n"), output: output)
      expect(executions).not_to be_empty
      executions.each do |execution|
        expect(execution.done?).to be true
        expect(execution.status).to eq(name == '22_llm_guardrails' ? 'FAILED' : 'COMPLETED'), output.string
        expect(execution.events.map { |event| event['event'] }).to include(name == '22_llm_guardrails' ? 'error' : 'done')
        expect(runtime.client.get_status(execution.execution_id)['isComplete']).to be true
        tasks = workflow_tasks(runtime, execution.execution_id)
        llm_tasks = tasks.select { |task| task.task_type == 'LLM_CHAT_COMPLETE' }
        expect(llm_tasks).not_to be_empty
        expect(llm_tasks.map { |task| task.input_data['llmProvider'] }.uniq).to eq(['mock'])
        expect(llm_tasks.map(&:status).uniq).to eq(['COMPLETED'])

        case name
        when '09_human_in_the_loop', '09c_hitl_streaming'
          approvals = tasks.select { |task| task.task_type == 'HUMAN' }
          expect(approvals).not_to be_empty
          expect(approvals.map(&:output_data)).to all(include('approved' => true, 'reason' => 'y'))
          expect(execution.events.map { |event| event['event'] }).to include('waiting')
        when '10_guardrails', '21_regex_guardrails'
          expect(execution.answer.to_s).not_to match(/4532-0150-1234-5678|alice\.johnson@example\.com|123-45-6789/)
        when '22_llm_guardrails'
          decisions = tasks.filter_map { |task| task.output_data['result'] if task.output_data['result'].is_a?(Hash) }
          expect(decisions).to include(include('guardrail_name' => 'content_safety', 'passed' => false, 'on_fail' => 'raise'))
          @expected_failed_execution = execution.execution_id
        when '103_plan_and_compile'
          expect(tasks.count { |task| task.task_type == 'factorial' && task.status == 'COMPLETED' }).to eq(5)
          expect(tasks).to include(have_attributes(task_type: 'PLAN_AND_COMPILE', status: 'COMPLETED'))
        when '33_external_workers'
          expect(runtime.running_workers).to eq(['format_response'])
          %w[get_customer check_inventory process_order].each do |type|
            expect(tasks).to include(have_attributes(task_type: type, status: 'COMPLETED'))
          end
        end
      end
    ensure
      runtime&.shutdown
    end
  end
end
