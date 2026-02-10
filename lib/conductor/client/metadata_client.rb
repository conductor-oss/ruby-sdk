# frozen_string_literal: true

require_relative '../configuration'
require_relative '../http/api_client'
require_relative '../http/api/metadata_resource_api'

module Conductor
  module Client
    # MetadataClient - High-level client for workflow and task metadata operations
    # Provides a clean interface for registering and managing workflow/task definitions
    class MetadataClient
      attr_reader :metadata_api

      # Initialize MetadataClient
      # @param [Configuration] configuration Optional configuration
      def initialize(configuration = nil)
        @configuration = configuration || Configuration.new
        api_client = Http::ApiClient.new(configuration: @configuration)
        @metadata_api = Http::Api::MetadataResourceApi.new(api_client)
      end

      # ==========================================
      # Workflow Definition Operations
      # ==========================================

      # Register a workflow definition
      # @param [WorkflowDef] workflow_def Workflow definition to register
      # @param [Boolean] overwrite Overwrite existing definition (default: true)
      # @return [void]
      def register_workflow_def(workflow_def, overwrite: true)
        @metadata_api.create_workflow(workflow_def, overwrite: overwrite)
      end

      # Update a workflow definition
      # @param [WorkflowDef] workflow_def Workflow definition to update
      # @param [Boolean] overwrite Overwrite existing definition (default: true)
      # @return [void]
      def update_workflow_def(workflow_def, overwrite: true)
        @metadata_api.update_workflows([workflow_def], overwrite: overwrite)
      end

      # Unregister (delete) a workflow definition
      # @param [String] name Workflow name
      # @param [Integer] version Workflow version
      # @return [void]
      def unregister_workflow_def(name, version:)
        @metadata_api.unregister_workflow_def(name, version: version)
      end

      # Get a workflow definition by name
      # @param [String] name Workflow name
      # @param [Integer] version Workflow version (optional, returns latest if not specified)
      # @return [WorkflowDef] Workflow definition
      def get_workflow_def(name, version: nil)
        @metadata_api.get_workflow_def(name, version: version)
      end

      # Get all workflow definitions
      # @return [Array<WorkflowDef>] List of workflow definitions
      def get_all_workflow_defs
        @metadata_api.get_all_workflows
      end

      # ==========================================
      # Task Definition Operations
      # ==========================================

      # Register a task definition
      # @param [TaskDef] task_def Task definition to register
      # @return [void]
      def register_task_def(task_def)
        @metadata_api.register_task_def([task_def])
      end

      # Register multiple task definitions
      # @param [Array<TaskDef>] task_defs List of task definitions to register
      # @return [void]
      def register_task_defs(task_defs)
        @metadata_api.register_task_def(task_defs)
      end

      # Update a task definition
      # @param [TaskDef] task_def Task definition to update
      # @return [void]
      def update_task_def(task_def)
        @metadata_api.update_task_def(task_def)
      end

      # Unregister (delete) a task definition
      # @param [String] task_type Task type name
      # @return [void]
      def unregister_task_def(task_type)
        @metadata_api.unregister_task_def(task_type)
      end

      # Get a task definition by name
      # @param [String] task_type Task type name
      # @return [TaskDef] Task definition
      def get_task_def(task_type)
        @metadata_api.get_task_def(task_type)
      end

      # Get all task definitions
      # @return [Array<TaskDef>] List of task definitions
      def get_all_task_defs
        @metadata_api.get_all_task_defs
      end

      # ==========================================
      # Workflow Metadata (Tags) Operations
      # ==========================================

      # Add metadata (tags) to a workflow
      # @param [String] workflow_name Workflow name
      # @param [Object] tag Tag/metadata to add
      # @param [Integer] version Workflow version (optional)
      # @return [void]
      def add_workflow_tag(workflow_name, tag, version: nil)
        @metadata_api.create_workflow_metadata(workflow_name, tag, version: version)
      end

      # Get metadata (tags) for a workflow
      # @param [String] workflow_name Workflow name
      # @param [Integer] version Workflow version (optional)
      # @return [Object] Workflow metadata/tags
      def get_workflow_tags(workflow_name, version: nil)
        @metadata_api.get_workflow_metadata(workflow_name, version: version)
      end

      # Delete metadata (tags) from a workflow
      # @param [String] workflow_name Workflow name
      # @param [Integer] version Workflow version
      # @return [void]
      def delete_workflow_tag(workflow_name, version:)
        @metadata_api.delete_workflow_metadata(workflow_name, version: version)
      end
    end
  end
end
