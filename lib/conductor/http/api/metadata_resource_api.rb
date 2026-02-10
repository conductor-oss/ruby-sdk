# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # MetadataResourceApi - API for workflow and task metadata operations
      # Manages task definitions and workflow definitions
      class MetadataResourceApi
        attr_accessor :api_client

        # Initialize MetadataResourceApi
        # @param [ApiClient] api_client Optional API client
        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # ==========================================
        # Workflow Definition Operations
        # ==========================================

        # Create a new workflow definition
        # @param [WorkflowDef] body Workflow definition
        # @param [Boolean] overwrite Overwrite existing definition (default: false)
        # @return [Object] Response object
        def create_workflow(body, overwrite: false)
          @api_client.call_api(
            '/metadata/workflow',
            'POST',
            query_params: { overwrite: overwrite },
            body: body,
            return_type: 'Object',
            return_http_data_only: true
          )
        end

        # Update workflow definition(s)
        # @param [Array<WorkflowDef>] body List of workflow definitions
        # @param [Boolean] overwrite Overwrite existing definitions (default: true)
        # @return [Object] Response object
        def update_workflows(body, overwrite: true)
          @api_client.call_api(
            '/metadata/workflow',
            'PUT',
            query_params: { overwrite: overwrite },
            body: body,
            return_type: 'Object',
            return_http_data_only: true
          )
        end

        # Get a workflow definition by name
        # @param [String] name Workflow name
        # @param [Integer] version Workflow version (optional, returns latest if not specified)
        # @return [WorkflowDef] Workflow definition
        def get_workflow_def(name, version: nil)
          query_params = {}
          query_params[:version] = version if version

          @api_client.call_api(
            '/metadata/workflow/{name}',
            'GET',
            path_params: { name: name },
            query_params: query_params,
            return_type: 'WorkflowDef',
            return_http_data_only: true
          )
        end

        # Get all workflow definitions
        # @param [String] access Access level filter (optional)
        # @return [Array<WorkflowDef>] List of workflow definitions
        def get_all_workflows(access: nil)
          query_params = {}
          query_params[:access] = access if access

          @api_client.call_api(
            '/metadata/workflow',
            'GET',
            query_params: query_params,
            return_type: 'Array<WorkflowDef>',
            return_http_data_only: true
          )
        end

        # Unregister (delete) a workflow definition
        # @param [String] name Workflow name
        # @param [Integer] version Workflow version
        # @return [void]
        def unregister_workflow_def(name, version:)
          @api_client.call_api(
            '/metadata/workflow/{name}/{version}',
            'DELETE',
            path_params: { name: name, version: version },
            return_http_data_only: true
          )
        end

        # ==========================================
        # Task Definition Operations
        # ==========================================

        # Register (create) task definition(s)
        # @param [Array<TaskDef>] body List of task definitions
        # @return [Object] Response object
        def register_task_def(body)
          # Ensure body is an array
          task_defs = body.is_a?(Array) ? body : [body]

          @api_client.call_api(
            '/metadata/taskdefs',
            'POST',
            body: task_defs,
            return_type: 'Object',
            return_http_data_only: true
          )
        end

        # Update an existing task definition
        # @param [TaskDef] body Task definition
        # @return [Object] Response object
        def update_task_def(body)
          @api_client.call_api(
            '/metadata/taskdefs',
            'PUT',
            body: body,
            return_type: 'Object',
            return_http_data_only: true
          )
        end

        # Get a task definition by name
        # @param [String] task_type Task type name
        # @return [TaskDef] Task definition
        def get_task_def(task_type)
          @api_client.call_api(
            '/metadata/taskdefs/{tasktype}',
            'GET',
            path_params: { tasktype: task_type },
            return_type: 'TaskDef',
            return_http_data_only: true
          )
        end

        # Get all task definitions
        # @param [String] access Access level filter (optional)
        # @return [Array<TaskDef>] List of task definitions
        def get_all_task_defs(access: nil)
          query_params = {}
          query_params[:access] = access if access

          @api_client.call_api(
            '/metadata/taskdefs',
            'GET',
            query_params: query_params,
            return_type: 'Array<TaskDef>',
            return_http_data_only: true
          )
        end

        # Unregister (delete) a task definition
        # @param [String] task_type Task type name
        # @return [void]
        def unregister_task_def(task_type)
          @api_client.call_api(
            '/metadata/taskdefs/{tasktype}',
            'DELETE',
            path_params: { tasktype: task_type },
            return_http_data_only: true
          )
        end

        # ==========================================
        # Workflow Metadata (Tags) Operations
        # ==========================================

        # Store metadata (tags) associated with a workflow
        # @param [String] name Workflow name
        # @param [Object] body Workflow tag/metadata
        # @param [Integer] version Workflow version (optional)
        # @return [void]
        def create_workflow_metadata(name, body, version: nil)
          query_params = {}
          query_params[:version] = version if version

          @api_client.call_api(
            '/metadata/tags/workflow/{name}',
            'POST',
            path_params: { name: name },
            query_params: query_params,
            body: body,
            return_http_data_only: true
          )
        end

        # Get metadata (tags) associated with a workflow
        # @param [String] name Workflow name
        # @param [Integer] version Workflow version (optional)
        # @return [Object] Workflow metadata/tags
        def get_workflow_metadata(name, version: nil)
          query_params = {}
          query_params[:version] = version if version

          @api_client.call_api(
            '/metadata/tags/workflow/{name}',
            'GET',
            path_params: { name: name },
            query_params: query_params,
            return_type: 'Object',
            return_http_data_only: true
          )
        end

        # Delete metadata (tags) associated with a workflow
        # @param [String] name Workflow name
        # @param [Integer] version Workflow version
        # @return [void]
        def delete_workflow_metadata(name, version:)
          @api_client.call_api(
            '/metadata/tags/workflow/{name}',
            'DELETE',
            path_params: { name: name },
            query_params: { version: version },
            return_http_data_only: true
          )
        end
      end
    end
  end
end
