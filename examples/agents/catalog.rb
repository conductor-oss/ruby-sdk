# frozen_string_literal: true

# This catalog contains no agent definitions or prompts. Both tests and the CLI use
# the numbered examples directly.
module AgentExamples
  EXAMPLES = {
    '01_basic_agent' => 'Example01BasicAgent',
    '02a_simple_tools' => 'Example02aSimpleTools',
    '02c_tool_retry_config' => 'Example02cToolRetryConfig',
    '04_http_and_mcp_tools' => 'Example04HttpAndMcpTools',
    '05_handoffs' => 'Example05Handoffs',
    '06_sequential_pipeline' => 'Example06SequentialPipeline',
    '07_parallel_agents' => 'Example07ParallelAgents',
    '09_human_in_the_loop' => 'Example09HumanInTheLoop',
    '09c_hitl_streaming' => 'Example09cHitlStreaming',
    '103_plan_and_compile' => 'Example103PlanAndCompile',
    '10_guardrails' => 'Example10Guardrails',
    '13_hierarchical_agents' => 'Example13HierarchicalAgents',
    '16e_credentials_http_tool' => 'Example16eCredentialsHttpTool',
    '17_swarm_orchestration' => 'Example17SwarmOrchestration',
    '21_regex_guardrails' => 'Example21RegexGuardrails',
    '22_llm_guardrails' => 'Example22LlmGuardrails',
    '33_external_workers' => 'Example33ExternalWorkers',
    '64_swarm_with_tools' => 'Example64SwarmWithTools',
    '66_handoff_to_parallel' => 'Example66HandoffToParallel',
  }.freeze

  def self.load(name)
    require_relative name
    Object.const_get(EXAMPLES.fetch(name))
  end
end
