# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Generic scrollable search result
      class SearchResult < BaseModel
        SWAGGER_TYPES = {
          total_hits: 'Integer',
          results: 'Array<Object>'
        }.freeze

        ATTRIBUTE_MAP = {
          total_hits: :totalHits,
          results: :results
        }.freeze

        attr_accessor :total_hits, :results

        def initialize(params = {})
          @total_hits = params[:total_hits] || 0
          @results = params[:results] || []
        end
      end

      # Workflow summary for search results
      class WorkflowSummary < BaseModel
        SWAGGER_TYPES = {
          workflow_id: 'String',
          correlation_id: 'String',
          workflow_type: 'String',
          version: 'Integer',
          start_time: 'String',
          update_time: 'String',
          end_time: 'String',
          status: 'String',
          input: 'String',
          output: 'String',
          reason_for_incompletion: 'String',
          execution_time: 'Integer',
          event: 'String',
          failed_reference_task_names: 'String',
          external_input_payload_storage_path: 'String',
          external_output_payload_storage_path: 'String',
          priority: 'Integer',
          input_size: 'Integer',
          output_size: 'Integer',
          failed_task_names: 'Array<String>'
        }.freeze

        ATTRIBUTE_MAP = {
          workflow_id: :workflowId,
          correlation_id: :correlationId,
          workflow_type: :workflowType,
          version: :version,
          start_time: :startTime,
          update_time: :updateTime,
          end_time: :endTime,
          status: :status,
          input: :input,
          output: :output,
          reason_for_incompletion: :reasonForIncompletion,
          execution_time: :executionTime,
          event: :event,
          failed_reference_task_names: :failedReferenceTaskNames,
          external_input_payload_storage_path: :externalInputPayloadStoragePath,
          external_output_payload_storage_path: :externalOutputPayloadStoragePath,
          priority: :priority,
          input_size: :inputSize,
          output_size: :outputSize,
          failed_task_names: :failedTaskNames
        }.freeze

        attr_accessor :workflow_id, :correlation_id, :workflow_type, :version,
                      :start_time, :update_time, :end_time, :status, :input, :output,
                      :reason_for_incompletion, :execution_time, :event,
                      :failed_reference_task_names,
                      :external_input_payload_storage_path,
                      :external_output_payload_storage_path,
                      :priority, :input_size, :output_size, :failed_task_names

        def initialize(params = {})
          @workflow_id = params[:workflow_id]
          @correlation_id = params[:correlation_id]
          @workflow_type = params[:workflow_type]
          @version = params[:version]
          @start_time = params[:start_time]
          @update_time = params[:update_time]
          @end_time = params[:end_time]
          @status = params[:status]
          @input = params[:input]
          @output = params[:output]
          @reason_for_incompletion = params[:reason_for_incompletion]
          @execution_time = params[:execution_time]
          @event = params[:event]
          @failed_reference_task_names = params[:failed_reference_task_names]
          @external_input_payload_storage_path = params[:external_input_payload_storage_path]
          @external_output_payload_storage_path = params[:external_output_payload_storage_path]
          @priority = params[:priority]
          @input_size = params[:input_size]
          @output_size = params[:output_size]
          @failed_task_names = params[:failed_task_names] || []
        end
      end

      # Task summary for search results
      class TaskSummary < BaseModel
        SWAGGER_TYPES = {
          workflow_id: 'String',
          workflow_type: 'String',
          correlation_id: 'String',
          scheduled_time: 'String',
          start_time: 'String',
          update_time: 'String',
          end_time: 'String',
          status: 'String',
          reason_for_incompletion: 'String',
          execution_time: 'Integer',
          queue_wait_time: 'Integer',
          task_def_name: 'String',
          task_type: 'String',
          input: 'String',
          output: 'String',
          task_id: 'String',
          external_input_payload_storage_path: 'String',
          external_output_payload_storage_path: 'String',
          workflow_priority: 'Integer',
          domain: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          workflow_id: :workflowId,
          workflow_type: :workflowType,
          correlation_id: :correlationId,
          scheduled_time: :scheduledTime,
          start_time: :startTime,
          update_time: :updateTime,
          end_time: :endTime,
          status: :status,
          reason_for_incompletion: :reasonForIncompletion,
          execution_time: :executionTime,
          queue_wait_time: :queueWaitTime,
          task_def_name: :taskDefName,
          task_type: :taskType,
          input: :input,
          output: :output,
          task_id: :taskId,
          external_input_payload_storage_path: :externalInputPayloadStoragePath,
          external_output_payload_storage_path: :externalOutputPayloadStoragePath,
          workflow_priority: :workflowPriority,
          domain: :domain
        }.freeze

        attr_accessor :workflow_id, :workflow_type, :correlation_id, :scheduled_time,
                      :start_time, :update_time, :end_time, :status,
                      :reason_for_incompletion, :execution_time, :queue_wait_time,
                      :task_def_name, :task_type, :input, :output, :task_id,
                      :external_input_payload_storage_path,
                      :external_output_payload_storage_path,
                      :workflow_priority, :domain

        def initialize(params = {})
          @workflow_id = params[:workflow_id]
          @workflow_type = params[:workflow_type]
          @correlation_id = params[:correlation_id]
          @scheduled_time = params[:scheduled_time]
          @start_time = params[:start_time]
          @update_time = params[:update_time]
          @end_time = params[:end_time]
          @status = params[:status]
          @reason_for_incompletion = params[:reason_for_incompletion]
          @execution_time = params[:execution_time]
          @queue_wait_time = params[:queue_wait_time]
          @task_def_name = params[:task_def_name]
          @task_type = params[:task_type]
          @input = params[:input]
          @output = params[:output]
          @task_id = params[:task_id]
          @external_input_payload_storage_path = params[:external_input_payload_storage_path]
          @external_output_payload_storage_path = params[:external_output_payload_storage_path]
          @workflow_priority = params[:workflow_priority]
          @domain = params[:domain]
        end
      end
    end
  end
end
