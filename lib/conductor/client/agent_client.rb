# frozen_string_literal: true

require_relative '../exceptions'
require_relative '../http/api/agent_resource_api'

module Conductor
  module Client
    # AgentClient - High-level client for the server-side agent runtime.
    #
    # Mirrors the Python SDK's OrkesAgentClient: hashes in, hashes out, and every
    # transport error is re-raised as AgentApiError (AgentNotFoundError on 404).
    class AgentClient
      attr_reader :agent_api

      # @param api_client [Http::ApiClient]
      def initialize(api_client)
        @agent_api = Http::Api::AgentResourceApi.new(api_client)
      end

      # @param payload [Hash] AgentStartRequest
      # @return [Hash] { "executionId", "agentName", "requiredWorkers" }
      def start_agent(payload)
        wrap { @agent_api.start(payload) }
      end

      # @return [Hash] { "agentName", "requiredWorkers" }
      def deploy_agent(payload)
        wrap { @agent_api.deploy(payload) }
      end

      # @return [Hash] { "workflowDef", "requiredWorkers" }
      def compile_agent(payload)
        wrap { @agent_api.compile(payload) }
      end

      def get_status(execution_id)
        wrap { @agent_api.status(execution_id) }
      end

      def get_execution(execution_id)
        wrap { @agent_api.execution(execution_id) }
      end

      def list_executions(params = {})
        wrap { @agent_api.executions(params) }
      end

      # Respond to a waiting execution. Hashes pass through; anything else is wrapped as
      # { "output" => value } like the Python client does.
      def respond(execution_id, body)
        payload = body.is_a?(Hash) ? body : { 'output' => body }
        wrap { @agent_api.respond(execution_id, payload) }
      end

      def approve(execution_id)
        respond(execution_id, { 'approved' => true })
      end

      def reject(execution_id, reason = '')
        respond(execution_id, { 'approved' => false, 'reason' => reason.to_s })
      end

      def send_message(execution_id, message)
        respond(execution_id, { 'message' => message.to_s })
      end

      def stop(execution_id)
        wrap { @agent_api.stop(execution_id) }
      end

      def signal(execution_id, message)
        wrap { @agent_api.signal(execution_id, message) }
      end

      def pause(execution_id)
        wrap { @agent_api.pause(execution_id) }
      end

      def resume(execution_id)
        wrap { @agent_api.resume(execution_id) }
      end

      def cancel(execution_id, reason: nil)
        wrap { @agent_api.cancel(execution_id, reason: reason) }
      end

      def list_agents
        wrap { @agent_api.list }
      end

      def get_agent(name, version: nil)
        wrap { @agent_api.get_agent(name, version: version) }
      end

      def delete_agent(name, version: nil)
        wrap { @agent_api.delete(name, version: version) }
      end

      private

      def wrap
        yield
      rescue AgentApiError
        raise
      rescue ApiError => e
        raise AgentApiError.from_api_error(e)
      end
    end
  end
end
