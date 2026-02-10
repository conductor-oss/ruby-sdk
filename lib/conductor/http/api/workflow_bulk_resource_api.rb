# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # WorkflowBulkResourceApi - Bulk operations on workflows
      class WorkflowBulkResourceApi
        attr_accessor :api_client

        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # Pause workflows in bulk
        # @param [Array<String>] workflow_ids List of workflow IDs
        # @return [BulkResponse]
        def pause_workflow(workflow_ids)
          @api_client.call_api(
            '/workflow/bulk/pause',
            'PUT',
            body: workflow_ids,
            return_type: 'BulkResponse',
            return_http_data_only: true
          )
        end

        # Resume workflows in bulk
        # @param [Array<String>] workflow_ids List of workflow IDs
        # @return [BulkResponse]
        def resume_workflow(workflow_ids)
          @api_client.call_api(
            '/workflow/bulk/resume',
            'PUT',
            body: workflow_ids,
            return_type: 'BulkResponse',
            return_http_data_only: true
          )
        end

        # Restart workflows in bulk
        # @param [Array<String>] workflow_ids List of workflow IDs
        # @param [Boolean] use_latest_definitions Use latest definitions (default: false)
        # @return [BulkResponse]
        def restart(workflow_ids, use_latest_definitions: false)
          @api_client.call_api(
            '/workflow/bulk/restart',
            'POST',
            query_params: { useLatestDefinitions: use_latest_definitions },
            body: workflow_ids,
            return_type: 'BulkResponse',
            return_http_data_only: true
          )
        end

        # Retry workflows in bulk
        # @param [Array<String>] workflow_ids List of workflow IDs
        # @return [BulkResponse]
        def retry(workflow_ids)
          @api_client.call_api(
            '/workflow/bulk/retry',
            'POST',
            body: workflow_ids,
            return_type: 'BulkResponse',
            return_http_data_only: true
          )
        end

        # Terminate workflows in bulk
        # @param [Array<String>] workflow_ids List of workflow IDs
        # @param [String] reason Termination reason (optional)
        # @param [Boolean] trigger_failure_workflow Trigger failure workflow (default: false)
        # @return [BulkResponse]
        def terminate(workflow_ids, reason: nil, trigger_failure_workflow: false)
          query_params = { triggerFailureWorkflow: trigger_failure_workflow }
          query_params[:reason] = reason if reason

          @api_client.call_api(
            '/workflow/bulk/terminate',
            'POST',
            query_params: query_params,
            body: workflow_ids,
            return_type: 'BulkResponse',
            return_http_data_only: true
          )
        end
      end
    end
  end
end
