# frozen_string_literal: true

require 'spec_helper'
require 'conductor/agents'

RSpec.describe Conductor::Agents::SystemWorkers do
  a = Conductor::Agents

  def task(input)
    Conductor::Http::Models::Task.from_hash('taskId' => 't', 'inputData' => input)
  end

  it 'termination returns should_continue and reason' do
    body = described_class.termination(a::Termination::TextMention.new('DONE'))
    expect(body.call(task('result' => 'all DONE', 'iteration' => 1))).to eq('should_continue' => false,
                                                                            'reason' => "Text 'DONE' found in output")
    expect(body.call(task('result' => 'working'))['should_continue']).to be true
  end

  it 'termination keeps going when the condition raises' do
    cond = a::Termination::TextMention.new('x')
    allow(cond).to receive(:should_terminate).and_raise('boom')
    expect(described_class.termination(cond, logger: Logger.new(nil)).call(task({}))).to eq('should_continue' => true, 'reason' => '')
  end

  it 'guardrail passes, fails with retry, downgrades to raise when retries are exhausted or fix has no output' do
    retry_g = a::Guardrail.new(name: 'g', on_fail: :retry, max_retries: 2) { |c| c.include?('ok') }
    body = described_class.guardrail(retry_g)
    expect(body.call(task('content' => 'ok'))).to eq(described_class.pass_result)
    expect(body.call(task('content' => 'bad', 'iteration' => 1))).to include('passed' => false, 'on_fail' => 'retry',
                                                                             'guardrail_name' => 'g', 'should_continue' => true)
    expect(body.call(task('content' => 'bad', 'iteration' => 2))).to include('on_fail' => 'raise', 'should_continue' => false)

    fix_g = a::Guardrail.new(name: 'f', on_fail: :fix) { |_c| a::GuardrailResult.new(passed: false, message: 'm') }
    expect(described_class.guardrail(fix_g).call(task('content' => 'x'))).to include('on_fail' => 'raise', 'fixed_output' => nil)
    fixer = a::Guardrail.new(name: 'f2', on_fail: :fix) { |_c| a::GuardrailResult.new(passed: false, fixed_output: 'clean') }
    expect(described_class.guardrail(fixer).call(task('content' => { 'a' => 1 }))).to include('on_fail' => 'fix', 'fixed_output' => 'clean')
  end

  it 'guardrail reports its own exceptions as failures' do
    g = a::Guardrail.new(name: 'g', on_fail: :raise) { |_c| raise 'oops' }
    expect(described_class.guardrail(g, logger: Logger.new(nil)).call(task('content' => 'x'))).to include('passed' => false,
                                                                                                          'message' => 'Guardrail error: oops')
  end

  it 'callback passes messages / llm_result and returns the chain result' do
    chain = ->(**kw) { { 'seen' => kw.keys.map(&:to_s) } }
    expect(described_class.callback(chain).call(task('messages' => [], 'llm_result' => 'x'))).to eq('seen' => %w[messages llm_result])
    expect(described_class.callback(->(**) { raise 'x' }, logger: Logger.new(nil)).call(task({}))).to eq({})
  end

  it 'handoff evaluates the condition' do
    h = a::Handoff::OnCondition.new(target: 'filer') { |ctx| ctx['result'].to_s.include?('go') }
    expect(described_class.handoff(h).call(task('result' => 'go'))).to eq('handoff' => true, 'target' => 'filer')
    expect(described_class.handoff(h).call(task('result' => 'stay'))).to eq('handoff' => false, 'target' => 'filer')
  end
end
