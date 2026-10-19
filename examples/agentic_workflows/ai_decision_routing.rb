# frozen_string_literal: true

# Port of Python PR #511: the server evaluates one synchronous decision SWITCH.
# No Ruby worker or client-side inference is needed. The server needs a JEV provider.
# Run: CONDUCTOR_SERVER_URL=http://localhost:8081/api CONDUCTOR_DECISION_PROVIDER=openrouter \
#   bundle exec ruby -Ilib examples/agentic_workflows/ai_decision_routing.rb
require 'conductor'
require 'optparse'

module ExampleAiDecisionRouting
  def self.build(model: 'jev-1.13', provider: ENV['CONDUCTOR_DECISION_PROVIDER'])
    models = Conductor::Http::Models
    inputs = {
      'model' => model,
      'state' => '${workflow.input.request}',
      'questions' => {
        'route' => {
          'type' => 'choice',
          'instructions' => 'Choose the team best suited to handle this request.',
          'choices' => {
            'billing' => 'Payments, invoices, refunds, or subscriptions.',
            'technical' => 'Errors, outages, or product troubleshooting.'
          }
        }
      }
    }
    inputs['provider'] = provider unless provider.nil?
    billing = models::WorkflowTask.new(
      name: 'handle_billing', task_reference_name: 'handle_billing', type: 'INLINE',
      input_parameters: { 'evaluatorType' => 'graaljs', 'expression' => '({team: "billing", nextAction: "review_invoice", ' \
                  'message: "Check invoice line items and payment records.", request: $.request})',
      'request' => '${workflow.input.request}' }
    )
    technical = models::WorkflowTask.new(
      name: 'handle_technical', task_reference_name: 'handle_technical', type: 'INLINE',
      input_parameters: { 'evaluatorType' => 'graaljs', 'expression' => '({team: "technical", nextAction: "collect_diagnostics", ' \
                  'message: "Collect error logs and steps to reproduce.", request: $.request})',
      'request' => '${workflow.input.request}' }
    )
    decision = Conductor::Workflow::Dsl::TaskRef.new(
      ref_name: 'route_request', task_name: 'route_request', task_type: 'SWITCH', input_parameters: inputs,
      options: { evaluator_type: 'decision', expression: 'route',
                 decision_cases: { 'billing' => [billing], 'technical' => [technical] }, default_case: [] }
    )
    result = models::WorkflowTask.new(
      name: 'selected_result', task_reference_name: 'selected_result', type: 'INLINE',
      input_parameters: { 'evaluatorType' => 'graaljs', 'expression' => '$.billing || $.technical',
      'billing' => '${handle_billing.output.result}', 'technical' => '${handle_technical.output.result}' }
    )
    models::WorkflowDef.new(
      name: 'ai_decision_routing_ruby', version: 1, tasks: [decision.to_workflow_task, result],
      input_parameters: ['request'],
      output_parameters: {
        'selectedCase' => '${route_request.output.selectedCase}', 'answers' => '${route_request.output.answers}',
        'usage' => '${route_request.output.usage}', 'cost' => '${route_request.output.usage.cost}',
        'latencyMs' => '${route_request.output.latencyMs}', 'result' => '${selected_result.output.result}'
      }
    )
  end

  def self.run(request: 'I was charged twice on my latest invoice.', **options)
    executor = Conductor::Workflow::WorkflowExecutor.new
    workflow = build(**options)
    executor.register_workflow(workflow, overwrite: true)
    id = executor.start_workflow(Conductor::Http::Models::StartWorkflowRequest.new(
                                   name: workflow.name, version: 1, input: { 'request' => request }
                                 ))
    puts "Workflow: #{id}"
    result = executor.wait_for_workflow(id, timeout_seconds: 120)
    raise "#{result.status}: #{result.reason_for_incompletion}" unless result.status == 'COMPLETED'

    puts JSON.pretty_generate(result.output)
    result
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |parser|
    parser.on('--request REQUEST') { |value| options[:request] = value }
    parser.on('--model MODEL') { |value| options[:model] = value }
    parser.on('--provider PROVIDER') { |value| options[:provider] = value }
  end.parse!
  ExampleAiDecisionRouting.run(**options)
end
