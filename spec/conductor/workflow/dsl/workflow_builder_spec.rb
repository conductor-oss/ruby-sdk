# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Conductor::Workflow::Dsl::WorkflowBuilder do
  let(:builder) { described_class.new('test_workflow', version: 1) }

  describe '#initialize' do
    it 'creates a builder with name and version' do
      expect(builder.name).to eq('test_workflow')
      expect(builder.version).to eq(1)
    end

    it 'creates a builder with optional description' do
      b = described_class.new('my_workflow', version: 2, description: 'Test workflow')
      expect(b.description).to eq('Test workflow')
    end
  end

  describe '#wf' do
    it 'returns an InputRef' do
      expect(builder.wf).to be_a(Conductor::Workflow::Dsl::InputRef)
    end

    it 'returns the same InputRef instance on multiple calls' do
      first_call = builder.wf
      expect(builder.wf).to be(first_call)
    end
  end

  # ===================================================================
  # BASIC TASK METHODS
  # ===================================================================

  describe '#simple' do
    it 'creates a simple task and returns TaskRef' do
      task_ref = builder.simple(:my_task, input1: 'value1', input2: 'value2')

      expect(task_ref).to be_a(Conductor::Workflow::Dsl::TaskRef)
      expect(task_ref.task_name).to eq('my_task')
      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::SIMPLE)
      expect(task_ref.ref_name).to eq('my_task_ref')
      expect(task_ref.inputs).to eq('input1' => 'value1', 'input2' => 'value2')
    end

    it 'generates unique ref names for duplicate task names' do
      task1 = builder.simple(:my_task)
      task2 = builder.simple(:my_task)
      task3 = builder.simple(:my_task)

      expect(task1.ref_name).to eq('my_task_ref')
      expect(task2.ref_name).to eq('my_task_ref_2')
      expect(task3.ref_name).to eq('my_task_ref_3')
    end
  end

  describe '#http' do
    it 'creates an HTTP task with all options' do
      task_ref = builder.http(:api_call, url: 'https://api.example.com', method: :post,
                                         body: { key: 'value' }, headers: { 'Content-Type' => 'application/json' })

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::HTTP)
      expect(task_ref.inputs['http_request']['uri']).to eq('https://api.example.com')
      expect(task_ref.inputs['http_request']['method']).to eq('POST')
      expect(task_ref.inputs['http_request']['body']).to eq({ 'key' => 'value' })
      expect(task_ref.inputs['http_request']['headers']).to eq({ 'Content-Type' => 'application/json' })
    end

    it 'defaults to GET method' do
      task_ref = builder.http(:get_data, url: 'https://api.example.com/data')

      expect(task_ref.inputs['http_request']['method']).to eq('GET')
    end
  end

  describe '#wait' do
    it 'creates a wait task with duration in seconds' do
      task_ref = builder.wait(30)

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::WAIT)
      expect(task_ref.inputs['duration']).to eq('30 seconds')
    end

    it 'creates a wait task with until_time' do
      task_ref = builder.wait(until_time: '2024-12-25T00:00:00Z')

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::WAIT)
      expect(task_ref.inputs['until']).to eq('2024-12-25T00:00:00Z')
    end
  end

  describe '#terminate' do
    it 'creates a terminate task with failed status' do
      task_ref = builder.terminate(:failed, 'Something went wrong')

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::TERMINATE)
      expect(task_ref.inputs['terminationStatus']).to eq('FAILED')
      expect(task_ref.inputs['terminationReason']).to eq('Something went wrong')
    end

    it 'creates a terminate task with completed status' do
      task_ref = builder.terminate(:completed, 'Task finished successfully')

      expect(task_ref.inputs['terminationStatus']).to eq('COMPLETED')
    end
  end

  describe '#sub_workflow' do
    it 'creates a sub-workflow task with version and inputs' do
      task_ref = builder.sub_workflow(:call_sub, workflow: 'sub_workflow_name', version: 2,
                                                 input1: 'value1')

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::SUB_WORKFLOW)
      expect(task_ref.options[:sub_workflow_name]).to eq('sub_workflow_name')
      expect(task_ref.options[:sub_workflow_version]).to eq(2)
      expect(task_ref.inputs['input1']).to eq('value1')
    end
  end

  describe '#human' do
    it 'creates a human task with assignee' do
      task_ref = builder.human(:review_task, assignee: 'user@example.com', display_name: 'Review Document')

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::HUMAN)
      expect(task_ref.inputs['assignee']).to eq('user@example.com')
      expect(task_ref.inputs['displayName']).to eq('Review Document')
    end
  end

  describe '#set' do
    it 'creates a set variable task' do
      task_ref = builder.set(counter: 0, status: 'initialized')

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::SET_VARIABLE)
      expect(task_ref.inputs['counter']).to eq(0)
      expect(task_ref.inputs['status']).to eq('initialized')
    end
  end

  describe '#javascript' do
    it 'creates an inline JavaScript task' do
      task_ref = builder.javascript(:calc, script: 'return $.input1 + $.input2;', input1: 5, input2: 3)

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::INLINE)
      expect(task_ref.options[:expression]).to eq('return $.input1 + $.input2;')
      expect(task_ref.options[:evaluator_type]).to eq('javascript')
      expect(task_ref.inputs['input1']).to eq(5)
    end
  end

  describe '#jq' do
    it 'creates a JQ transform task' do
      task_ref = builder.jq(:transform, query: '.items | map(.name)', data: { items: [] })

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::JSON_JQ_TRANSFORM)
      expect(task_ref.options[:query_expression]).to eq('.items | map(.name)')
    end
  end

  describe '#event' do
    it 'creates an event task' do
      task_ref = builder.event(:send_event, sink: 'kafka:my-topic', message: 'test')

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::EVENT)
      expect(task_ref.options[:sink]).to eq('kafka:my-topic')
      expect(task_ref.inputs['message']).to eq('test')
    end
  end

  describe '#kafka_publish' do
    it 'creates a Kafka publish task' do
      task_ref = builder.kafka_publish(:publish, topic: 'my-topic', value: { data: 'test' }, key: 'key1')

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::KAFKA_PUBLISH)
      expect(task_ref.inputs['kafka_request']['topic']).to eq('my-topic')
      expect(task_ref.inputs['kafka_request']['value']).to eq({ 'data' => 'test' })
      expect(task_ref.inputs['kafka_request']['key']).to eq('key1')
    end
  end

  # ===================================================================
  # PHASE 2 TASK METHODS
  # ===================================================================

  describe '#start_workflow' do
    it 'creates a fire-and-forget start workflow task' do
      task_ref = builder.start_workflow(:trigger, workflow: 'async_process', version: 1, user_id: 123)

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::START_WORKFLOW)
      expect(task_ref.inputs['startWorkflow']['name']).to eq('async_process')
      expect(task_ref.inputs['startWorkflow']['version']).to eq(1)
      expect(task_ref.inputs['startWorkflow']['input']).to eq({ 'user_id' => 123 })
    end
  end

  describe '#wait_for_webhook' do
    it 'creates a wait for webhook task' do
      task_ref = builder.wait_for_webhook(:payment_callback, matches: { order_id: '${workflow.input.order_id}' })

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::WAIT_FOR_WEBHOOK)
      expect(task_ref.inputs['matches']).to eq({ 'order_id' => '${workflow.input.order_id}' })
    end
  end

  describe '#http_poll' do
    it 'creates an HTTP poll task with all options' do
      task_ref = builder.http_poll(:check_status,
                                   url: 'https://api.example.com/status',
                                   termination_condition: '$.response.body.status == "complete"',
                                   polling_interval: 30,
                                   polling_strategy: 'LINEAR_BACKOFF')

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::HTTP_POLL)
      expect(task_ref.inputs['http_request']['uri']).to eq('https://api.example.com/status')
      expect(task_ref.inputs['terminationCondition']).to eq('$.response.body.status == "complete"')
      expect(task_ref.inputs['pollingInterval']).to eq(30)
      expect(task_ref.inputs['pollingStrategy']).to eq('LINEAR_BACKOFF')
    end
  end

  describe '#dynamic' do
    it 'creates a dynamic task' do
      task_ref = builder.dynamic(:process, dynamic_task_param: '${decide_ref.output.taskName}', data: 'test')

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::DYNAMIC)
      expect(task_ref.options[:dynamic_task_name_param]).to eq('${decide_ref.output.taskName}')
      expect(task_ref.inputs['data']).to eq('test')
    end
  end

  describe '#dynamic_fork' do
    it 'creates a dynamic fork task' do
      task_ref = builder.dynamic_fork(:parallel_process,
                                      tasks_param: '${generator_ref.output.tasks}',
                                      tasks_input_param: '${generator_ref.output.inputs}')

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::FORK_JOIN_DYNAMIC)
      expect(task_ref.options[:dynamic_fork_tasks_param]).to eq('${generator_ref.output.tasks}')
      expect(task_ref.options[:dynamic_fork_tasks_input_param]).to eq('${generator_ref.output.inputs}')
    end
  end

  describe '#get_document' do
    it 'creates a get document task' do
      task_ref = builder.get_document(:fetch_pdf, url: 'https://example.com/doc.pdf', media_type: 'application/pdf')

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::GET_DOCUMENT)
      expect(task_ref.inputs['url']).to eq('https://example.com/doc.pdf')
      expect(task_ref.inputs['mediaType']).to eq('application/pdf')
    end
  end

  # ===================================================================
  # LLM TASK METHODS
  # ===================================================================

  describe '#llm_chat' do
    it 'creates an LLM chat task with messages' do
      messages = [
        { role: :system, message: 'You are a helpful assistant' },
        { role: :user, message: 'Hello!' }
      ]
      task_ref = builder.llm_chat(:chat, provider: 'openai', model: 'gpt-4', messages: messages, temperature: 0.7)

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::LLM_CHAT_COMPLETE)
      expect(task_ref.inputs['llmProvider']).to eq('openai')
      expect(task_ref.inputs['model']).to eq('gpt-4')
      expect(task_ref.inputs['messages'].size).to eq(2)
      expect(task_ref.inputs['temperature']).to eq(0.7)
    end
  end

  describe '#llm_complete' do
    it 'creates an LLM text completion task' do
      task_ref = builder.llm_complete(:complete, provider: 'openai', model: 'gpt-3.5-turbo',
                                                 prompt: 'Complete this: ', max_tokens: 100)

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::LLM_TEXT_COMPLETE)
      expect(task_ref.inputs['llmProvider']).to eq('openai')
      expect(task_ref.inputs['prompt']).to eq('Complete this: ')
      expect(task_ref.inputs['maxTokens']).to eq(100)
    end
  end

  describe '#llm_embed' do
    it 'creates an embedding generation task' do
      task_ref = builder.llm_embed(:embed, provider: 'openai', model: 'text-embedding-ada-002',
                                           text: 'Sample text')

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::LLM_GENERATE_EMBEDDINGS)
      expect(task_ref.inputs['llmProvider']).to eq('openai')
      expect(task_ref.inputs['model']).to eq('text-embedding-ada-002')
      expect(task_ref.inputs['text']).to eq('Sample text')
    end
  end

  describe '#llm_index' do
    it 'creates an LLM index text task' do
      task_ref = builder.llm_index(:index, vector_db: 'pinecone', namespace: 'default',
                                           index: 'my-index', embeddings: '${embed_ref.output.embeddings}')

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::LLM_INDEX_TEXT)
      expect(task_ref.inputs['vectorDB']).to eq('pinecone')
      expect(task_ref.inputs['namespace']).to eq('default')
      expect(task_ref.inputs['index']).to eq('my-index')
    end
  end

  describe '#llm_search' do
    it 'creates an LLM search index task' do
      task_ref = builder.llm_search(:search, vector_db: 'pinecone', namespace: 'default',
                                             index: 'my-index', query_embeddings: '${embed_ref.output.embeddings}',
                                             top_k: 5)

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::LLM_SEARCH_INDEX)
      expect(task_ref.inputs['vectorDB']).to eq('pinecone')
      expect(task_ref.inputs['k']).to eq(5)
    end
  end

  describe '#generate_image' do
    it 'creates an image generation task' do
      task_ref = builder.generate_image(:gen_img, provider: 'openai', model: 'dall-e-3',
                                                  prompt: 'A sunset over mountains', size: '1024x1024')

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::GENERATE_IMAGE)
      expect(task_ref.inputs['llmProvider']).to eq('openai')
      expect(task_ref.inputs['model']).to eq('dall-e-3')
      expect(task_ref.inputs['prompt']).to eq('A sunset over mountains')
      expect(task_ref.inputs['size']).to eq('1024x1024')
    end
  end

  describe '#generate_audio' do
    it 'creates a text-to-speech task' do
      task_ref = builder.generate_audio(:tts, provider: 'openai', model: 'tts-1',
                                              text: 'Hello world', voice: 'alloy', speed: 1.0)

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::GENERATE_AUDIO)
      expect(task_ref.inputs['llmProvider']).to eq('openai')
      expect(task_ref.inputs['model']).to eq('tts-1')
      expect(task_ref.inputs['text']).to eq('Hello world')
      expect(task_ref.inputs['voice']).to eq('alloy')
    end
  end

  describe '#llm_store_embeddings' do
    it 'creates an embedding storage task' do
      task_ref = builder.llm_store_embeddings(:store, vector_db: 'pinecone', index: 'my-index',
                                                      embeddings: '${embed_ref.output.embeddings}',
                                                      id: 'doc-123', metadata: { source: 'test' })

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::LLM_STORE_EMBEDDINGS)
      expect(task_ref.inputs['vectorDB']).to eq('pinecone')
      expect(task_ref.inputs['index']).to eq('my-index')
      expect(task_ref.inputs['id']).to eq('doc-123')
      expect(task_ref.inputs['metadata']).to eq({ 'source' => 'test' })
    end
  end

  describe '#llm_search_embeddings' do
    it 'creates an embedding search task' do
      task_ref = builder.llm_search_embeddings(:find, vector_db: 'pinecone', index: 'my-index',
                                                      embeddings: '${query_embed.output.embeddings}',
                                                      max_results: 10)

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::LLM_SEARCH_EMBEDDINGS)
      expect(task_ref.inputs['vectorDB']).to eq('pinecone')
      expect(task_ref.inputs['maxResults']).to eq(10)
    end
  end

  describe '#list_mcp_tools' do
    it 'creates a list MCP tools task' do
      task_ref = builder.list_mcp_tools(:get_tools, mcp_server: 'my-mcp-server')

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::LIST_MCP_TOOLS)
      expect(task_ref.inputs['mcpServer']).to eq('my-mcp-server')
    end
  end

  describe '#call_mcp_tool' do
    it 'creates a call MCP tool task' do
      task_ref = builder.call_mcp_tool(:run_tool, mcp_server: 'my-mcp-server',
                                                  method: 'search', arguments: { query: 'test' })

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::CALL_MCP_TOOL)
      expect(task_ref.inputs['mcpServer']).to eq('my-mcp-server')
      expect(task_ref.inputs['method']).to eq('search')
      expect(task_ref.inputs['arguments']).to eq({ 'query' => 'test' })
    end
  end

  # ===================================================================
  # CONTROL FLOW METHODS
  # ===================================================================

  describe '#parallel' do
    it 'creates parallel tasks with FORK_JOIN and JOIN' do
      builder.parallel do
        simple :task1
        simple :task2
      end

      workflow_def = builder.to_workflow_def
      task_types = workflow_def.tasks.map(&:type)

      expect(task_types).to include(Conductor::Workflow::TaskType::FORK_JOIN)
      expect(task_types).to include(Conductor::Workflow::TaskType::JOIN)
    end
  end

  describe '#decide' do
    it 'creates a SWITCH task with cases' do
      builder.decide '${some_ref.output.status}' do
        on 'success' do
          simple :success_handler
        end
        on 'failure' do
          simple :failure_handler
        end
        otherwise do
          simple :default_handler
        end
      end

      workflow_def = builder.to_workflow_def
      switch_task = workflow_def.tasks.find { |t| t.type == Conductor::Workflow::TaskType::SWITCH }

      expect(switch_task).not_to be_nil
      expect(switch_task.decision_cases.keys).to include('success', 'failure')
      expect(switch_task.default_case).not_to be_empty
    end
  end

  describe '#loop_times' do
    it 'creates a DO_WHILE task with counter condition' do
      builder.loop_times 3 do
        simple :process_batch
      end

      workflow_def = builder.to_workflow_def
      do_while_task = workflow_def.tasks.find { |t| t.type == Conductor::Workflow::TaskType::DO_WHILE }

      expect(do_while_task).not_to be_nil
      expect(do_while_task.loop_condition).to eq('$.loop_counter < 3')
    end
  end

  describe '#loop_while' do
    it 'creates a DO_WHILE task with custom condition' do
      builder.loop_while '$.has_more == true' do
        simple :fetch_page
      end

      workflow_def = builder.to_workflow_def
      do_while_task = workflow_def.tasks.find { |t| t.type == Conductor::Workflow::TaskType::DO_WHILE }

      expect(do_while_task).not_to be_nil
      expect(do_while_task.loop_condition).to eq('$.has_more == true')
    end
  end

  describe '#inline_workflow' do
    it 'creates a SUB_WORKFLOW task with inline definition' do
      task_ref = builder.inline_workflow(:process_order, version: 1) do
        simple :validate
        simple :process
      end

      expect(task_ref.task_type).to eq(Conductor::Workflow::TaskType::SUB_WORKFLOW)
      expect(task_ref.options[:inline_workflow_def]).not_to be_nil
      expect(task_ref.options[:inline_workflow_def].name).to eq('test_workflow_process_order_inline')
    end
  end

  describe '#when_true' do
    it 'creates a conditional branch for true condition' do
      builder.when_true '${check_ref.output.is_valid}' do
        simple :process_valid
      end

      workflow_def = builder.to_workflow_def
      switch_task = workflow_def.tasks.find { |t| t.type == Conductor::Workflow::TaskType::SWITCH }

      expect(switch_task).not_to be_nil
      expect(switch_task.decision_cases.keys).to include('true')
    end
  end

  # ===================================================================
  # OUTPUT AND CONFIGURATION
  # ===================================================================

  describe '#output' do
    it 'sets workflow output parameters' do
      builder.output(result: 'success', count: 42)

      workflow_def = builder.to_workflow_def
      expect(workflow_def.output_parameters['result']).to eq('success')
      expect(workflow_def.output_parameters['count']).to eq(42)
    end

    it 'resolves OutputRef in output parameters' do
      task = builder.simple(:get_result)
      builder.output(data: task[:result])

      workflow_def = builder.to_workflow_def
      expect(workflow_def.output_parameters['data']).to eq('${get_result_ref.output.result}')
    end
  end

  describe '#timeout' do
    it 'sets workflow timeout' do
      builder.timeout(3600)

      workflow_def = builder.to_workflow_def
      expect(workflow_def.timeout_seconds).to eq(3600)
    end
  end

  describe '#owner_email' do
    it 'sets workflow owner email' do
      builder.owner_email('owner@example.com')

      workflow_def = builder.to_workflow_def
      expect(workflow_def.owner_email).to eq('owner@example.com')
    end
  end

  # ===================================================================
  # VALUE RESOLUTION
  # ===================================================================

  describe 'resolving OutputRef values' do
    it 'resolves OutputRef in task inputs' do
      task1 = builder.simple(:task1)
      task2 = builder.simple(:task2, input: task1[:output_field])

      expect(task2.inputs['input']).to eq('${task1_ref.output.output_field}')
    end

    it 'resolves nested OutputRef' do
      task1 = builder.simple(:task1)
      task2 = builder.simple(:task2, data: task1[:response][:body][:items])

      expect(task2.inputs['data']).to eq('${task1_ref.output.response.body.items}')
    end
  end

  describe 'resolving InputRef values' do
    it 'resolves workflow input references' do
      task = builder.simple(:task1, user_id: builder.wf[:user_id])

      expect(task.inputs['user_id']).to eq('${workflow.input.user_id}')
    end

    it 'resolves workflow variable references' do
      task = builder.simple(:task1, counter: builder.wf.var(:counter))

      expect(task.inputs['counter']).to eq('${workflow.variables.counter}')
    end
  end

  # ===================================================================
  # WORKFLOW DEF CONVERSION
  # ===================================================================

  describe '#to_workflow_def' do
    it 'converts to WorkflowDef model' do
      builder.simple(:task1, input: 'value')
      builder.simple(:task2)
      builder.output(result: 'done')

      workflow_def = builder.to_workflow_def

      expect(workflow_def).to be_a(Conductor::Http::Models::WorkflowDef)
      expect(workflow_def.name).to eq('test_workflow')
      expect(workflow_def.version).to eq(1)
      expect(workflow_def.tasks.size).to eq(2)
      expect(workflow_def.output_parameters['result']).to eq('done')
    end

    it 'includes all workflow metadata' do
      builder.timeout(1800)
      builder.owner_email('test@example.com')
      builder.restartable(false)
      builder.failure_workflow('error_handler')
      builder.simple(:task1)

      workflow_def = builder.to_workflow_def

      expect(workflow_def.timeout_seconds).to eq(1800)
      expect(workflow_def.owner_email).to eq('test@example.com')
      expect(workflow_def.restartable).to eq(false)
      expect(workflow_def.failure_workflow).to eq('error_handler')
    end
  end
end
