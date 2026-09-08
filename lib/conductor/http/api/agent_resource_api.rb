# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # AgentResourceApi - REST bindings for the server-side agent runtime (/api/agent/*)
      #
      # Every method returns the parsed JSON body as a Hash (or Array) so that callers
      # see exactly the keys the server sent (executionId, requiredWorkers, isComplete, ...).
      # The SSE stream endpoint is not here: it needs a long-lived streaming connection and
      # lives in Conductor::Agents::Runtime::SseClient.
      class AgentResourceApi
        HASH = 'Hash<String, Object>'

        attr_accessor :api_client

        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # Start an agent execution
        # @param body [Hash] AgentStartRequest: agentConfig | name, prompt, sessionId, media, context, runId, ...
        # @return [Hash] { "executionId", "agentName", "requiredWorkers" }
        def start(body)
          post('/agent/start', body)
        end

        # Register (deploy) an agent definition without starting it
        # @param body [Hash] AgentStartRequest with agentConfig
        # @return [Hash] { "agentName", "requiredWorkers" }
        def deploy(body)
          post('/agent/deploy', body)
        end

        # Compile an agent config into a workflow definition without registering it
        # @param body [Hash] AgentStartRequest with agentConfig
        # @return [Hash] { "workflowDef", "requiredWorkers" }
        def compile(body)
          post('/agent/compile', body)
        end

        # Get the status of an execution
        # @return [Hash] { "executionId", "status", "isComplete", "isRunning", "isWaiting", "output", "pendingTool", ... }
        def status(execution_id)
          get('/agent/{executionId}/status', execution_id)
        end

        # Get an execution with its tasks and token usage
        # @return [Hash] { "executionId", "status", "output", "tokenUsage", "tasks" }
        def execution(execution_id)
          get('/agent/execution/{executionId}', execution_id)
        end

        # List executions
        # @param params [Hash] start, size, sort, freeText, status, agentName, sessionId
        # @return [Hash] { "totalHits", "results" }
        def executions(params = {})
          @api_client.call_api('/agent/executions', 'GET', query_params: params, return_type: HASH,
                                                           return_http_data_only: true)
        end

        # Respond to a waiting execution (approval, human input, free text)
        # @param body [Hash] e.g. { "approved" => true } or { "approved" => false, "reason" => "..." }
        def respond(execution_id, body)
          post_action(execution_id, 'respond', body)
        end

        # Ask the agent loop to stop after the current iteration
        def stop(execution_id)
          post_action(execution_id, 'stop')
        end

        # Inject a signal message into the next LLM turn
        def signal(execution_id, message)
          post_action(execution_id, 'signal', { 'message' => message })
        end

        # Pause the execution
        def pause(execution_id)
          @api_client.call_api('/agent/{executionId}/pause', 'PUT', path_params: { executionId: execution_id },
                                                                    return_http_data_only: true)
        end

        # Resume a paused execution
        def resume(execution_id)
          @api_client.call_api('/agent/{executionId}/resume', 'PUT', path_params: { executionId: execution_id },
                                                                     return_http_data_only: true)
        end

        # Cancel (terminate) the execution
        def cancel(execution_id, reason: nil)
          query = reason ? { reason: reason } : {}
          @api_client.call_api('/agent/{executionId}/cancel', 'DELETE', path_params: { executionId: execution_id },
                                                                        query_params: query, return_http_data_only: true)
        end

        # List deployed agents
        # @return [Array<Hash>]
        def list
          @api_client.call_api('/agent/list', 'GET', return_type: 'Array<Object>', return_http_data_only: true)
        end

        # Get a deployed agent definition by name
        # @return [Hash] the agentConfig as deployed
        def get_agent(name, version: nil)
          query = version ? { version: version } : {}
          @api_client.call_api('/agent/{name}', 'GET', path_params: { name: name }, query_params: query,
                                                       return_type: HASH, return_http_data_only: true)
        end

        # Delete a deployed agent definition
        def delete(name, version: nil)
          query = version ? { version: version } : {}
          @api_client.call_api('/agent/{name}', 'DELETE', path_params: { name: name }, query_params: query,
                                                          return_http_data_only: true)
        end

        private

        def get(path, execution_id)
          @api_client.call_api(path, 'GET', path_params: { executionId: execution_id }, return_type: HASH,
                                            return_http_data_only: true)
        end

        def post(path, body)
          @api_client.call_api(path, 'POST', body: body, return_type: HASH, return_http_data_only: true)
        end

        def post_action(execution_id, action, body = nil)
          @api_client.call_api("/agent/{executionId}/#{action}", 'POST', path_params: { executionId: execution_id },
                                                                         body: body, return_http_data_only: true)
        end
      end
    end
  end
end
