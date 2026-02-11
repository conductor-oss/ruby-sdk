# frozen_string_literal: true

require_relative '../task_type'

module Conductor
  module Workflow
    module Dsl
      # WorkflowBuilder is the core DSL engine for building Conductor workflows.
      # It provides Ruby-idiomatic methods for defining tasks and control flow.
      #
      # @example Simple workflow
      #   builder = WorkflowBuilder.new('my_workflow', version: 1)
      #   user = builder.simple :get_user, user_id: builder.wf[:user_id]
      #   builder.simple :send_email, email: user[:email]
      #
      class WorkflowBuilder
        attr_reader :name, :tasks

        def initialize(name, version: nil, description: nil, executor: nil)
          @name = name
          @version = version
          @description = description
          @executor = executor
          @tasks = []
          @output_params = {}
          @input_params = []
          @ref_counter = Hash.new(0)
          @timeout_seconds = 60
          @owner_email = nil
          @restartable = true
          @failure_workflow = nil
        end

        # Get the workflow version
        # @return [Integer, nil] Workflow version
        attr_reader :version

        # Returns the workflow input proxy for accessing workflow inputs
        # @return [InputRef] Proxy for workflow.input, workflow.variables, etc.
        # @example
        #   wf[:user_id] # => "${workflow.input.user_id}"
        #   wf.var(:counter) # => "${workflow.variables.counter}"
        def wf
          @wf_input ||= InputRef.new
        end

        # Configure workflow metadata
        def set_version(v)
          @version = v
        end

        def description(text = nil)
          return @description if text.nil?

          @description = text
        end

        def timeout(seconds)
          @timeout_seconds = seconds
        end

        def owner_email(email)
          @owner_email = email
        end

        def restartable(value)
          @restartable = value
        end

        def failure_workflow(name)
          @failure_workflow = name
        end

        # Define workflow output parameters
        # @param params [Hash] Output parameter mappings
        # @example
        #   output user_email: user[:email], order_id: wf[:order_id]
        def output(**params)
          @output_params.merge!(resolve_hash(params))
        end

        # ===================================================================
        # SIMPLE TASK METHODS
        # ===================================================================

        # Add a SIMPLE task (worker task)
        # @param task_name [Symbol, String] The task name
        # @param inputs [Hash] Input parameters
        # @return [TaskRef] Reference to the created task
        def simple(task_name, **inputs)
          add_task(task_name, TaskType::SIMPLE, inputs, {})
        end

        # Add an HTTP task
        # @param task_name [Symbol, String] The task name
        # @param url [String, OutputRef] The URL to call
        # @param method [Symbol, String] HTTP method (:get, :post, :put, :delete, etc.)
        # @param body [Hash, String, nil] Request body
        # @param headers [Hash, nil] Request headers
        # @param options [Hash] Additional options (optional, start_delay, etc.)
        # @return [TaskRef] Reference to the created task
        def http(task_name, url:, method: :get, body: nil, headers: nil, **options)
          http_request = {
            'uri' => resolve_value(url),
            'method' => method.to_s.upcase
          }
          http_request['body'] = resolve_value(body) if body
          http_request['headers'] = resolve_value(headers) if headers

          add_task(task_name, TaskType::HTTP, { 'http_request' => http_request }, options)
        end

        # Add a WAIT task
        # @param seconds [Integer, nil] Duration to wait in seconds
        # @param until_time [String, nil] Wait until specific time (ISO8601 format)
        # @param options [Hash] Additional options
        # @return [TaskRef] Reference to the created task
        def wait(seconds = nil, until_time: nil, **options)
          inputs = {}
          inputs['duration'] = "#{seconds} seconds" if seconds
          inputs['until'] = until_time if until_time

          add_task('wait', TaskType::WAIT, inputs, options)
        end

        # Add a TERMINATE task
        # @param status [Symbol, String] Termination status (:completed, :failed)
        # @param reason [String] Reason for termination
        # @param options [Hash] Additional options
        # @return [TaskRef] Reference to the created task
        def terminate(status, reason, **options)
          inputs = {
            'terminationStatus' => status.to_s.upcase,
            'terminationReason' => reason
          }
          add_task('terminate', TaskType::TERMINATE, inputs, options)
        end

        # Add a SUB_WORKFLOW task
        # @param task_name [Symbol, String] The task name
        # @param workflow [String] Name of the workflow to call
        # @param version [Integer, nil] Version of the workflow
        # @param inputs [Hash] Input parameters for the sub-workflow
        # @return [TaskRef] Reference to the created task
        def sub_workflow(task_name, workflow:, version: nil, **inputs)
          add_task(
            task_name,
            TaskType::SUB_WORKFLOW,
            inputs,
            {
              sub_workflow_name: workflow,
              sub_workflow_version: version
            }
          )
        end

        # Add a HUMAN task
        # @param task_name [Symbol, String] The task name
        # @param assignee [String, nil] Email or ID of the assignee
        # @param display_name [String, nil] Display name for the task
        # @param inputs [Hash] Input parameters
        # @return [TaskRef] Reference to the created task
        def human(task_name, assignee: nil, display_name: nil, **inputs)
          inputs = inputs.merge('assignee' => assignee) if assignee
          inputs = inputs.merge('displayName' => display_name) if display_name
          add_task(task_name, TaskType::HUMAN, inputs, {})
        end

        # Add a SET_VARIABLE task
        # @param variables [Hash] Variables to set
        # @param options [Hash] Additional options
        # @return [TaskRef] Reference to the created task
        def set(**variables)
          add_task('set_variable', TaskType::SET_VARIABLE, resolve_hash(variables), {})
        end

        # Add an INLINE (JavaScript) task
        # @param task_name [Symbol, String] The task name
        # @param script [String] JavaScript code to execute
        # @param bindings [Hash] Variable bindings for the script
        # @return [TaskRef] Reference to the created task
        def javascript(task_name, script:, **bindings)
          inputs = resolve_hash(bindings)
          add_task(task_name, TaskType::INLINE, inputs, { expression: script, evaluator_type: 'javascript' })
        end

        # Add a JSON_JQ_TRANSFORM task
        # @param task_name [Symbol, String] The task name
        # @param query [String] JQ query expression
        # @param inputs [Hash] Input data to transform
        # @return [TaskRef] Reference to the created task
        def jq(task_name, query:, **inputs)
          add_task(task_name, TaskType::JSON_JQ_TRANSFORM, inputs, { query_expression: query })
        end

        # Add an EVENT task
        # @param task_name [Symbol, String] The task name
        # @param sink [String] Event sink name
        # @param inputs [Hash] Event payload
        # @return [TaskRef] Reference to the created task
        def event(task_name, sink:, **inputs)
          add_task(task_name, TaskType::EVENT, inputs, { sink: sink })
        end

        # Add a KAFKA_PUBLISH task
        # @param task_name [Symbol, String] The task name
        # @param topic [String] Kafka topic
        # @param value [Object] Message value
        # @param key [String, nil] Message key
        # @param headers [Hash, nil] Message headers
        # @return [TaskRef] Reference to the created task
        def kafka_publish(task_name, topic:, value:, key: nil, headers: nil)
          inputs = {
            'kafka_request' => {
              'topic' => topic,
              'value' => resolve_value(value)
            }
          }
          inputs['kafka_request']['key'] = key if key
          inputs['kafka_request']['headers'] = resolve_value(headers) if headers

          add_task(task_name, TaskType::KAFKA_PUBLISH, inputs, {})
        end

        # Add a START_WORKFLOW task (fire-and-forget, does not wait for completion)
        # @param task_name [Symbol, String] The task name
        # @param workflow [String] Name of the workflow to start
        # @param version [Integer, nil] Workflow version (optional)
        # @param inputs [Hash] Input parameters for the started workflow
        # @return [TaskRef] Reference to the created task
        # @example
        #   start_workflow :trigger_async, workflow: 'async_processing', user_id: wf[:user_id]
        def start_workflow(task_name, workflow:, version: nil, **inputs)
          start_workflow_input = {
            'name' => workflow,
            'input' => resolve_hash(inputs)
          }
          start_workflow_input['version'] = version if version

          add_task(task_name, TaskType::START_WORKFLOW, { 'startWorkflow' => start_workflow_input }, {})
        end

        # Add a WAIT_FOR_WEBHOOK task (waits for external webhook callback)
        # @param task_name [Symbol, String] The task name
        # @param matches [Hash] Match conditions for the webhook payload
        # @return [TaskRef] Reference to the created task
        # @example
        #   wait_for_webhook :payment_callback, matches: { 'order_id' => wf[:order_id] }
        def wait_for_webhook(task_name, matches: {})
          add_task(task_name, TaskType::WAIT_FOR_WEBHOOK, { 'matches' => resolve_hash(matches) }, {})
        end

        # Add an HTTP_POLL task (polls HTTP endpoint until condition is met)
        # @param task_name [Symbol, String] The task name
        # @param url [String] The URL to poll
        # @param method [Symbol, String] HTTP method (default: :get)
        # @param body [Hash, String, nil] Request body
        # @param headers [Hash, nil] Request headers
        # @param termination_condition [String] JavaScript condition for when to stop polling
        # @param polling_interval [Integer] Polling interval in seconds (default: 60)
        # @param polling_strategy [String] 'FIXED' or 'LINEAR_BACKOFF' (default: 'FIXED')
        # @return [TaskRef] Reference to the created task
        # @example
        #   http_poll :check_status, url: 'https://api.example.com/status',
        #             termination_condition: '$.response.body.status == "complete"',
        #             polling_interval: 30
        def http_poll(task_name, url:, method: :get, body: nil, headers: nil,
                      termination_condition: nil, polling_interval: 60, polling_strategy: 'FIXED')
          http_request = {
            'uri' => resolve_value(url),
            'method' => method.to_s.upcase
          }
          http_request['body'] = resolve_value(body) if body
          http_request['headers'] = resolve_value(headers) if headers

          inputs = {
            'http_request' => http_request,
            'pollingInterval' => polling_interval,
            'pollingStrategy' => polling_strategy
          }
          inputs['terminationCondition'] = termination_condition if termination_condition

          add_task(task_name, TaskType::HTTP_POLL, inputs, {})
        end

        # Add a DYNAMIC task (task name determined at runtime)
        # @param task_name [Symbol, String] The base task name
        # @param dynamic_task_param [String] Expression for dynamic task name
        # @param inputs [Hash] Input parameters
        # @return [TaskRef] Reference to the created task
        # @example
        #   dynamic :process, dynamic_task_param: '${decide_task_ref.output.taskName}'
        def dynamic(task_name, dynamic_task_param:, **inputs)
          add_task(task_name, TaskType::DYNAMIC, inputs, { dynamic_task_name_param: dynamic_task_param })
        end

        # Add a DYNAMIC fork task (parallel tasks determined at runtime)
        # @param task_name [Symbol, String] The task name
        # @param tasks_param [String, OutputRef] Expression for dynamic tasks array
        # @param tasks_input_param [String, OutputRef] Expression for task inputs
        # @return [TaskRef] Reference to the created task
        # @example
        #   dynamic_fork :parallel_process,
        #                tasks_param: generator[:tasks],
        #                tasks_input_param: generator[:inputs]
        def dynamic_fork(task_name, tasks_param:, tasks_input_param:)
          add_task(
            task_name,
            TaskType::FORK_JOIN_DYNAMIC,
            {},
            {
              dynamic_fork_tasks_param: resolve_value(tasks_param),
              dynamic_fork_tasks_input_param: resolve_value(tasks_input_param)
            }
          )
        end

        # Add a GET_DOCUMENT task (retrieve and parse a document from URL)
        # @param task_name [Symbol, String] The task name
        # @param url [String] URL of the document
        # @param media_type [String] MIME type of the document
        # @return [TaskRef] Reference to the created task
        # @example
        #   get_document :fetch_pdf, url: 'https://example.com/doc.pdf', media_type: 'application/pdf'
        def get_document(task_name, url:, media_type:)
          inputs = {
            'url' => resolve_value(url),
            'mediaType' => media_type
          }
          add_task(task_name, TaskType::GET_DOCUMENT, inputs, {})
        end

        # ===================================================================
        # LLM TASK METHODS
        # ===================================================================

        # Add an LLM_CHAT_COMPLETE task
        # @param task_name [Symbol, String] The task name
        # @param provider [String] LLM provider (e.g., 'openai', 'azure_openai')
        # @param model [String] Model name
        # @param messages [Array<ChatMessage, Hash>] Chat messages
        # @param temperature [Float, nil] Temperature (0.0-1.0)
        # @param top_p [Float, nil] Top-p sampling parameter
        # @param stop_words [Array<String>, nil] Stop sequences
        # @param max_tokens [Integer, nil] Maximum tokens to generate
        # @param options [Hash] Additional options
        # @return [TaskRef] Reference to the created task
        def llm_chat(task_name, provider:, model:, messages: nil, temperature: nil, top_p: nil,
                     stop_words: nil, max_tokens: nil, **options)
          # Auto-convert hash messages to ChatMessage objects
          converted_messages = messages&.map do |msg|
            if msg.is_a?(Hash)
              Conductor::Workflow::Llm::ChatMessage.new(**msg)
            else
              msg
            end
          end

          inputs = {
            'llmProvider' => provider,
            'model' => model
          }
          inputs['messages'] = converted_messages.map(&:to_h) if converted_messages
          inputs['temperature'] = temperature if temperature
          inputs['topP'] = top_p if top_p
          inputs['stopWords'] = stop_words if stop_words
          inputs['maxTokens'] = max_tokens if max_tokens

          add_task(task_name, TaskType::LLM_CHAT_COMPLETE, inputs, options)
        end

        # Add an LLM_TEXT_COMPLETE task
        # @param task_name [Symbol, String] The task name
        # @param provider [String] LLM provider
        # @param model [String] Model name
        # @param prompt [String] Text prompt
        # @param temperature [Float, nil] Temperature
        # @param max_tokens [Integer, nil] Maximum tokens
        # @param options [Hash] Additional options
        # @return [TaskRef] Reference to the created task
        def llm_complete(task_name, provider:, model:, prompt:, temperature: nil, max_tokens: nil, **options)
          inputs = {
            'llmProvider' => provider,
            'model' => model,
            'prompt' => resolve_value(prompt)
          }
          inputs['temperature'] = temperature if temperature
          inputs['maxTokens'] = max_tokens if max_tokens

          add_task(task_name, TaskType::LLM_TEXT_COMPLETE, inputs, options)
        end

        # Add an LLM_GENERATE_EMBEDDINGS task
        # @param task_name [Symbol, String] The task name
        # @param provider [String] LLM provider
        # @param model [String] Model name
        # @param text [String, Array<String>] Text(s) to embed
        # @param options [Hash] Additional options
        # @return [TaskRef] Reference to the created task
        def llm_embed(task_name, provider:, model:, text:, **options)
          inputs = {
            'llmProvider' => provider,
            'model' => model,
            'text' => resolve_value(text)
          }
          add_task(task_name, TaskType::LLM_GENERATE_EMBEDDINGS, inputs, options)
        end

        # Add an LLM_INDEX_TEXT task
        # @param task_name [Symbol, String] The task name
        # @param vector_db [String] Vector database provider
        # @param namespace [String] Index namespace
        # @param index [String] Index name
        # @param embeddings [Array, OutputRef] Embeddings to index
        # @param doc_id [String, OutputRef, nil] Document ID
        # @param options [Hash] Additional options
        # @return [TaskRef] Reference to the created task
        def llm_index(task_name, vector_db:, namespace:, index:, embeddings:, doc_id: nil, **options)
          inputs = {
            'vectorDB' => vector_db,
            'namespace' => namespace,
            'index' => index,
            'embeddingModelProvider' => resolve_value(embeddings)
          }
          inputs['docId'] = resolve_value(doc_id) if doc_id

          add_task(task_name, TaskType::LLM_INDEX_TEXT, inputs, options)
        end

        # Add an LLM_SEARCH_INDEX task
        # @param task_name [Symbol, String] The task name
        # @param vector_db [String] Vector database provider
        # @param namespace [String] Index namespace
        # @param index [String] Index name
        # @param query_embeddings [Array, OutputRef] Query embeddings
        # @param top_k [Integer] Number of results to return
        # @param options [Hash] Additional options
        # @return [TaskRef] Reference to the created task
        def llm_search(task_name, vector_db:, namespace:, index:, query_embeddings:, top_k: 10, **options)
          inputs = {
            'vectorDB' => vector_db,
            'namespace' => namespace,
            'index' => index,
            'queryEmbeddings' => resolve_value(query_embeddings),
            'k' => top_k
          }
          add_task(task_name, TaskType::LLM_SEARCH_INDEX, inputs, options)
        end

        # Add a GENERATE_IMAGE task
        # @param task_name [Symbol, String] The task name
        # @param provider [String] Image generation provider
        # @param model [String] Model name
        # @param prompt [String] Image generation prompt
        # @param size [String, nil] Image size (e.g., '1024x1024')
        # @param options [Hash] Additional options
        # @return [TaskRef] Reference to the created task
        def generate_image(task_name, provider:, model:, prompt:, size: nil, **options)
          inputs = {
            'llmProvider' => provider,
            'model' => model,
            'prompt' => resolve_value(prompt)
          }
          inputs['size'] = size if size

          add_task(task_name, TaskType::GENERATE_IMAGE, inputs, options)
        end

        # Add a GENERATE_AUDIO task (text-to-speech)
        # @param task_name [Symbol, String] The task name
        # @param provider [String] LLM provider integration name
        # @param model [String] Audio generation model name
        # @param text [String, nil] Text to convert to audio
        # @param voice [String, nil] Voice selection
        # @param speed [Float, nil] Playback speed
        # @param response_format [String, nil] Output audio format
        # @param n [Integer] Number of outputs (default: 1)
        # @param options [Hash] Additional options
        # @return [TaskRef] Reference to the created task
        # @example
        #   generate_audio :tts, provider: 'openai', model: 'tts-1', text: 'Hello world', voice: 'alloy'
        def generate_audio(task_name, provider:, model:, text: nil, voice: nil, speed: nil,
                           response_format: nil, n: 1, **options)
          inputs = {
            'llmProvider' => provider,
            'model' => model,
            'n' => n
          }
          inputs['text'] = resolve_value(text) if text
          inputs['voice'] = voice if voice
          inputs['speed'] = speed if speed
          inputs['responseFormat'] = response_format if response_format

          add_task(task_name, TaskType::GENERATE_AUDIO, inputs, options)
        end

        # Add an LLM_STORE_EMBEDDINGS task (store vectors in a vector database)
        # @param task_name [Symbol, String] The task name
        # @param vector_db [String] Vector DB integration name
        # @param index [String] Index/collection name
        # @param embeddings [Array, OutputRef] Embedding vector(s) to store
        # @param namespace [String, nil] Namespace/partition
        # @param id [String, nil] Document ID
        # @param metadata [Hash, nil] Document metadata
        # @param embedding_model [String, nil] Model used to generate embeddings
        # @param embedding_model_provider [String, nil] Provider used to generate embeddings
        # @param options [Hash] Additional options
        # @return [TaskRef] Reference to the created task
        # @example
        #   llm_store_embeddings :store_vectors, vector_db: 'pinecone', index: 'docs',
        #                        embeddings: embed_task[:embeddings], id: 'doc-123'
        def llm_store_embeddings(task_name, vector_db:, index:, embeddings:, namespace: nil,
                                 id: nil, metadata: nil, embedding_model: nil,
                                 embedding_model_provider: nil, **options)
          inputs = {
            'vectorDB' => vector_db,
            'index' => index,
            'embeddings' => resolve_value(embeddings)
          }
          inputs['namespace'] = namespace if namespace
          inputs['id'] = resolve_value(id) if id
          inputs['metadata'] = resolve_hash(metadata) if metadata
          inputs['embeddingModel'] = embedding_model if embedding_model
          inputs['embeddingModelProvider'] = embedding_model_provider if embedding_model_provider

          add_task(task_name, TaskType::LLM_STORE_EMBEDDINGS, inputs, options)
        end

        # Add an LLM_SEARCH_EMBEDDINGS task (search vector database by embeddings)
        # @param task_name [Symbol, String] The task name
        # @param vector_db [String] Vector DB integration name
        # @param index [String] Index/collection name
        # @param embeddings [Array, OutputRef] Query embedding vector
        # @param namespace [String, nil] Namespace/partition
        # @param max_results [Integer] Maximum results to return (default: 1)
        # @param embedding_model [String, nil] Embedding model name
        # @param embedding_model_provider [String, nil] Embedding provider name
        # @param options [Hash] Additional options
        # @return [TaskRef] Reference to the created task
        # @example
        #   llm_search_embeddings :find_similar, vector_db: 'pinecone', index: 'docs',
        #                         embeddings: query_embed[:embeddings], max_results: 5
        def llm_search_embeddings(task_name, vector_db:, index:, embeddings:, namespace: nil,
                                  max_results: 1, embedding_model: nil,
                                  embedding_model_provider: nil, **options)
          inputs = {
            'vectorDB' => vector_db,
            'index' => index,
            'embeddings' => resolve_value(embeddings),
            'maxResults' => max_results
          }
          inputs['namespace'] = namespace if namespace
          inputs['embeddingModel'] = embedding_model if embedding_model
          inputs['embeddingModelProvider'] = embedding_model_provider if embedding_model_provider

          add_task(task_name, TaskType::LLM_SEARCH_EMBEDDINGS, inputs, options)
        end

        # Add an LLM_GET_EMBEDDINGS task (retrieve stored embeddings)
        # @param task_name [Symbol, String] The task name
        # @param vector_db [String] Vector DB integration name
        # @param index [String] Index/collection name
        # @param ids [Array<String>, OutputRef] Document IDs to retrieve
        # @param namespace [String, nil] Namespace/partition
        # @param options [Hash] Additional options
        # @return [TaskRef] Reference to the created task
        def llm_get_embeddings(task_name, vector_db:, index:, ids:, namespace: nil, **options)
          inputs = {
            'vectorDB' => vector_db,
            'index' => index,
            'ids' => resolve_value(ids)
          }
          inputs['namespace'] = namespace if namespace

          add_task(task_name, TaskType::LLM_GET_EMBEDDINGS, inputs, options)
        end

        # Add a LIST_MCP_TOOLS task (list available tools from MCP server)
        # @param task_name [Symbol, String] The task name
        # @param mcp_server [String] MCP server integration name
        # @param headers [Hash, nil] Optional HTTP headers
        # @param options [Hash] Additional options
        # @return [TaskRef] Reference to the created task
        # @example
        #   list_mcp_tools :get_tools, mcp_server: 'my-mcp-server'
        def list_mcp_tools(task_name, mcp_server:, headers: nil, **options)
          inputs = { 'mcpServer' => mcp_server }
          inputs['headers'] = resolve_hash(headers) if headers

          add_task(task_name, TaskType::LIST_MCP_TOOLS, inputs, options)
        end

        # Add a CALL_MCP_TOOL task (invoke a tool on MCP server)
        # @param task_name [Symbol, String] The task name
        # @param mcp_server [String] MCP server integration name
        # @param method [String] Tool method name
        # @param arguments [Hash, nil] Arguments to pass to the tool
        # @param headers [Hash, nil] Optional HTTP headers
        # @param options [Hash] Additional options
        # @return [TaskRef] Reference to the created task
        # @example
        #   call_mcp_tool :execute_tool, mcp_server: 'my-mcp-server',
        #                 method: 'search', arguments: { query: 'test' }
        def call_mcp_tool(task_name, mcp_server:, method:, arguments: nil, headers: nil, **options)
          inputs = {
            'mcpServer' => mcp_server,
            'method' => method,
            'arguments' => resolve_hash(arguments || {})
          }
          inputs['headers'] = resolve_hash(headers) if headers

          add_task(task_name, TaskType::CALL_MCP_TOOL, inputs, options)
        end

        # ===================================================================
        # CONTROL FLOW METHODS
        # ===================================================================

        # Create a parallel execution block (FORK_JOIN)
        # @yield Block containing tasks to execute in parallel
        # @return [TaskRef] Reference to the JOIN task
        # @example
        #   parallel do
        #     simple :task1
        #     simple :task2
        #   end
        def parallel(&block)
          builder = ParallelBuilder.new(self)
          builder.instance_eval(&block)
          branches = builder.finalize

          # Create FORK_JOIN task
          fork_ref = add_fork_join_task(branches)

          # Create JOIN task
          join_on_refs = branches.map { |branch| branch.last.ref_name }
          add_join_task(join_on_refs)
        end

        # Create a switch/decision block
        # @param expression [String, OutputRef] The expression to evaluate
        # @yield Block containing on/otherwise clauses
        # @return [TaskRef] Reference to the SWITCH task
        # @example
        #   decide user[:country] do
        #     on 'US' do
        #       simple :us_flow
        #     end
        #     on 'UK' do
        #       simple :uk_flow
        #     end
        #     otherwise do
        #       simple :default_flow
        #     end
        #   end
        def decide(expression, &block)
          builder = SwitchBuilder.new(resolve_value(expression), self)
          builder.instance_eval(&block)

          add_switch_task(builder)
        end

        # Create a loop that executes N times
        # @param count [Integer] Number of iterations
        # @yield Block containing tasks to loop
        # @return [TaskRef] Reference to the DO_WHILE task
        # @example
        #   loop_times 3 do
        #     simple :process_batch
        #   end
        def loop_times(count, &block)
          loop_while("$.loop_counter < #{count}", &block)
        end

        # Create a loop with a custom condition
        # @param condition [String] JavaScript condition to evaluate
        # @yield Block containing tasks to loop
        # @return [TaskRef] Reference to the DO_WHILE task
        # @example
        #   loop_while "$.has_more == true" do
        #     simple :fetch_page
        #   end
        def loop_while(condition, &block)
          # Collect tasks in the loop body
          loop_tasks = []
          collector = TaskCollector.new(self, loop_tasks)
          collector.instance_eval(&block)

          add_do_while_task(condition, loop_tasks)
        end

        # Create a loop that iterates over items in an array
        # @param items [OutputRef, String] Expression or reference to array to iterate over
        # @yield Block containing tasks to execute for each item
        # @return [TaskRef] Reference to the DO_WHILE task
        # @example
        #   loop_over user_list[:users] do
        #     simple :process_user, user: iteration[:item]
        #   end
        def loop_over(items, &block)
          # Set up the loop with array iteration pattern
          loop_tasks = []
          collector = LoopCollector.new(self, loop_tasks)
          collector.instance_eval(&block)

          # Create a set variable task to track iteration
          items_expr = resolve_value(items)
          condition = '$.iteration_index < $.items.length()'

          add_do_while_task_with_items(condition, loop_tasks, items_expr)
        end

        # Define an inline sub-workflow that executes as a SUB_WORKFLOW task
        # @param task_name [Symbol, String] The task name for the sub-workflow
        # @param version [Integer] Version of the inline workflow (default: 1)
        # @yield Block containing the sub-workflow definition
        # @return [TaskRef] Reference to the SUB_WORKFLOW task
        # @example
        #   inline_workflow :process_order do
        #     validate = simple :validate
        #     simple :process, data: validate[:result]
        #   end
        def inline_workflow(task_name, version: 1, &block)
          # Create a nested builder for the inline workflow
          inline_builder = WorkflowBuilder.new(
            "#{@name}_#{task_name}_inline",
            version: version
          )
          inline_builder.instance_eval(&block)

          # Get the workflow def from the inline builder
          inline_def = inline_builder.to_workflow_def

          add_task(
            task_name,
            TaskType::SUB_WORKFLOW,
            {},
            { inline_workflow_def: inline_def }
          )
        end

        # Create a branch that only executes if a condition is true
        # @param condition [String, OutputRef] The condition to evaluate
        # @yield Block containing tasks to execute if condition is true
        # @return [TaskRef] Reference to the SWITCH task
        # @example
        #   when_true order[:is_premium] do
        #     simple :apply_discount
        #   end
        def when_true(condition, &block)
          decide condition do
            on 'true', &block
          end
        end

        # Create a branch that only executes if a condition is false
        # @param condition [String, OutputRef] The condition to evaluate
        # @yield Block containing tasks to execute if condition is false
        # @return [TaskRef] Reference to the SWITCH task
        def when_false(condition, &block)
          decide condition do
            on 'false', &block
          end
        end

        # ===================================================================
        # INTERNAL METHODS
        # ===================================================================

        private

        # Add a task to the workflow
        # @param task_name [Symbol, String] The task name
        # @param task_type [String] The task type constant
        # @param input_parameters [Hash] Input parameters
        # @param options [Hash] Additional task options
        # @return [TaskRef] Reference to the created task
        def add_task(task_name, task_type, input_parameters, options = {})
          ref_name = generate_ref_name(task_name)
          resolved_inputs = resolve_hash(input_parameters)

          task_ref = TaskRef.new(
            ref_name: ref_name,
            task_name: task_name.to_s,
            task_type: task_type,
            input_parameters: resolved_inputs,
            options: options
          )

          @tasks << task_ref
          task_ref
        end

        # Generate a unique reference name for a task
        # @param task_name [Symbol, String] The task name
        # @return [String] Unique reference name
        def generate_ref_name(task_name)
          base = "#{task_name}_ref"
          @ref_counter[base] += 1
          @ref_counter[base] == 1 ? base : "#{base}_#{@ref_counter[base]}"
        end

        # Resolve a value (OutputRef, Hash, Array, or literal)
        # @param value [Object] The value to resolve
        # @return [Object] Resolved value
        def resolve_value(value)
          case value
          when OutputRef, InputRef
            value.to_s
          when Hash
            resolve_hash(value)
          when Array
            value.map { |v| resolve_value(v) }
          else
            value
          end
        end

        # Resolve all values in a hash and stringify keys
        # @param hash [Hash] The hash to resolve
        # @return [Hash] Hash with string keys and resolved values
        def resolve_hash(hash)
          hash.transform_keys(&:to_s).transform_values { |v| resolve_value(v) }
        end

        # Add a FORK_JOIN task
        # @param branches [Array<Array<TaskRef>>] The task branches
        # @return [TaskRef] Reference to the FORK task
        def add_fork_join_task(branches)
          ref_name = generate_ref_name('fork')

          task_ref = TaskRef.new(
            ref_name: ref_name,
            task_name: 'fork',
            task_type: TaskType::FORK_JOIN,
            input_parameters: {},
            options: { fork_branches: branches }
          )

          @tasks << task_ref
          task_ref
        end

        # Add a JOIN task
        # @param join_on [Array<String>] Task ref names to join on
        # @return [TaskRef] Reference to the JOIN task
        def add_join_task(join_on)
          ref_name = generate_ref_name('join')

          task_ref = TaskRef.new(
            ref_name: ref_name,
            task_name: 'join',
            task_type: TaskType::JOIN,
            input_parameters: {},
            options: { join_on: join_on }
          )

          @tasks << task_ref
          task_ref
        end

        # Add a SWITCH task
        # @param builder [SwitchBuilder] The switch builder
        # @return [TaskRef] Reference to the SWITCH task
        def add_switch_task(builder)
          ref_name = generate_ref_name('switch')

          task_ref = TaskRef.new(
            ref_name: ref_name,
            task_name: 'switch',
            task_type: TaskType::SWITCH,
            input_parameters: {},
            options: {
              expression: builder.expression,
              decision_cases: builder.cases,
              default_case: builder.default
            }
          )

          @tasks << task_ref
          task_ref
        end

        # Add a DO_WHILE task
        # @param condition [String] Loop condition
        # @param loop_tasks [Array<TaskRef>] Tasks in the loop body
        # @return [TaskRef] Reference to the DO_WHILE task
        def add_do_while_task(condition, loop_tasks)
          ref_name = generate_ref_name('do_while')

          task_ref = TaskRef.new(
            ref_name: ref_name,
            task_name: 'do_while',
            task_type: TaskType::DO_WHILE,
            input_parameters: {},
            options: {
              loop_condition: condition,
              loop_over: loop_tasks
            }
          )

          @tasks << task_ref
          task_ref
        end

        # Add a DO_WHILE task with items for iteration
        # @param condition [String] Loop condition
        # @param loop_tasks [Array<TaskRef>] Tasks in the loop body
        # @param items_expr [String] Expression for items array
        # @return [TaskRef] Reference to the DO_WHILE task
        def add_do_while_task_with_items(condition, loop_tasks, items_expr)
          ref_name = generate_ref_name('do_while')

          task_ref = TaskRef.new(
            ref_name: ref_name,
            task_name: 'do_while',
            task_type: TaskType::DO_WHILE,
            input_parameters: {
              'items' => items_expr,
              'iteration_index' => 0
            },
            options: {
              loop_condition: condition,
              loop_over: loop_tasks
            }
          )

          @tasks << task_ref
          task_ref
        end

        # Convert the builder to a WorkflowDef model
        # @return [Conductor::Http::Models::WorkflowDef] The workflow definition
        def to_workflow_def
          workflow_tasks = convert_tasks_to_workflow_tasks

          Conductor::Http::Models::WorkflowDef.new(
            name: @name,
            version: @version,
            description: @description,
            tasks: workflow_tasks,
            input_parameters: @input_params,
            output_parameters: @output_params,
            timeout_seconds: @timeout_seconds,
            owner_email: @owner_email,
            restartable: @restartable,
            failure_workflow: @failure_workflow,
            schema_version: 2
          )
        end

        # Convert TaskRefs to WorkflowTask models
        # @return [Array<Conductor::Http::Models::WorkflowTask>] Workflow tasks
        def convert_tasks_to_workflow_tasks
          @tasks.flat_map do |task_ref|
            wf_task = task_ref.to_workflow_task
            # FORK_JOIN returns an array [fork_task, join_task]
            wf_task.is_a?(Array) ? wf_task : [wf_task]
          end
        end

        # Make to_workflow_def accessible to WorkflowDefinition
        public :to_workflow_def
      end

      # Helper class for collecting tasks in a block
      class TaskCollector
        def initialize(parent_builder, task_array)
          @parent = parent_builder
          @tasks = task_array
        end

        # Access workflow inputs
        def wf
          @parent.wf
        end

        def method_missing(name, *args, **kwargs, &block)
          if @parent.respond_to?(name, true)
            task_ref = @parent.send(name, *args, **kwargs, &block)
            @tasks << task_ref if task_ref.is_a?(TaskRef)
            task_ref
          else
            super
          end
        end

        def respond_to_missing?(name, include_private = false)
          @parent.respond_to?(name, include_private) || super
        end
      end

      # Helper class for collecting tasks in a loop with iteration access
      class LoopCollector < TaskCollector
        # Access current iteration data within a loop_over block
        # @return [OutputRef] Reference to iteration data
        # @example
        #   loop_over items do
        #     simple :process, item: iteration[:item], index: iteration[:index]
        #   end
        def iteration
          @iteration_ref ||= OutputRef.new('do_while_ref.output')
        end

        # Alias for iteration[:item]
        def current_item
          iteration[:item]
        end

        # Alias for iteration[:index]
        def current_index
          iteration[:index]
        end
      end
    end
  end
end
