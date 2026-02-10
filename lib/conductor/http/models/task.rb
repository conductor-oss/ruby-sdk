# frozen_string_literal: true

require_relative 'base_model'

module Conductor
  module Http
    module Models
      # Task model representing a task in a workflow
      class Task < BaseModel
        SWAGGER_TYPES = {
          task_type: 'String',
          status: 'String',
          input_data: 'Hash<String, Object>',
          reference_task_name: 'String',
          retry_count: 'Integer',
          seq: 'Integer',
          correlation_id: 'String',
          poll_count: 'Integer',
          task_def_name: 'String',
          scheduled_time: 'Integer',
          start_time: 'Integer',
          end_time: 'Integer',
          update_time: 'Integer',
          start_delay_in_seconds: 'Integer',
          retried_task_id: 'String',
          retried: 'Boolean',
          executed: 'Boolean',
          callback_from_worker: 'Boolean',
          response_timeout_seconds: 'Integer',
          workflow_instance_id: 'String',
          workflow_type: 'String',
          task_id: 'String',
          reason_for_incompletion: 'String',
          callback_after_seconds: 'Integer',
          worker_id: 'String',
          output_data: 'Hash<String, Object>',
          workflow_task: 'WorkflowTask',
          domain: 'String',
          rate_limit_per_frequency: 'Integer',
          rate_limit_frequency_in_seconds: 'Integer',
          external_input_payload_storage_path: 'String',
          external_output_payload_storage_path: 'String',
          workflow_priority: 'Integer',
          execution_name_space: 'String',
          isolation_group_id: 'String',
          iteration: 'Integer',
          sub_workflow_id: 'String',
          subworkflow_changed: 'Boolean',
          parent_task_id: 'String',
          first_start_time: 'Integer',
          loop_over_task: 'Boolean',
          task_definition: 'TaskDef',
          queue_wait_time: 'Integer'
        }.freeze

        ATTRIBUTE_MAP = {
          task_type: :taskType,
          status: :status,
          input_data: :inputData,
          reference_task_name: :referenceTaskName,
          retry_count: :retryCount,
          seq: :seq,
          correlation_id: :correlationId,
          poll_count: :pollCount,
          task_def_name: :taskDefName,
          scheduled_time: :scheduledTime,
          start_time: :startTime,
          end_time: :endTime,
          update_time: :updateTime,
          start_delay_in_seconds: :startDelayInSeconds,
          retried_task_id: :retriedTaskId,
          retried: :retried,
          executed: :executed,
          callback_from_worker: :callbackFromWorker,
          response_timeout_seconds: :responseTimeoutSeconds,
          workflow_instance_id: :workflowInstanceId,
          workflow_type: :workflowType,
          task_id: :taskId,
          reason_for_incompletion: :reasonForIncompletion,
          callback_after_seconds: :callbackAfterSeconds,
          worker_id: :workerId,
          output_data: :outputData,
          workflow_task: :workflowTask,
          domain: :domain,
          rate_limit_per_frequency: :rateLimitPerFrequency,
          rate_limit_frequency_in_seconds: :rateLimitFrequencyInSeconds,
          external_input_payload_storage_path: :externalInputPayloadStoragePath,
          external_output_payload_storage_path: :externalOutputPayloadStoragePath,
          workflow_priority: :workflowPriority,
          execution_name_space: :executionNameSpace,
          isolation_group_id: :isolationGroupId,
          iteration: :iteration,
          sub_workflow_id: :subWorkflowId,
          subworkflow_changed: :subworkflowChanged,
          parent_task_id: :parentTaskId,
          first_start_time: :firstStartTime,
          loop_over_task: :loopOverTask,
          task_definition: :taskDefinition,
          queue_wait_time: :queueWaitTime
        }.freeze

        attr_accessor :task_type, :status, :input_data, :reference_task_name,
                      :retry_count, :seq, :correlation_id, :poll_count, :task_def_name,
                      :scheduled_time, :start_time, :end_time, :update_time,
                      :start_delay_in_seconds, :retried_task_id, :retried, :executed,
                      :callback_from_worker, :response_timeout_seconds, :workflow_instance_id,
                      :workflow_type, :task_id, :reason_for_incompletion,
                      :callback_after_seconds, :worker_id, :output_data, :workflow_task,
                      :domain, :rate_limit_per_frequency, :rate_limit_frequency_in_seconds,
                      :external_input_payload_storage_path, :external_output_payload_storage_path,
                      :workflow_priority, :execution_name_space, :isolation_group_id,
                      :iteration, :sub_workflow_id, :subworkflow_changed, :parent_task_id,
                      :first_start_time, :loop_over_task, :task_definition, :queue_wait_time

        # Initialize a new Task
        # @param [Hash] attributes Model attributes in the form of hash
        def initialize(attributes = {})
          return unless attributes.is_a?(Hash)

          # Set all attributes from the hash
          SWAGGER_TYPES.each_key do |key|
            send("#{key}=", attributes[key]) if attributes.key?(key)
          end

          # Set default values for collections
          @input_data ||= {}
          @output_data ||= {}
        end

        # Check if task is in terminal state
        # @return [Boolean] true if task is completed, failed, or cancelled
        def terminal?
          %w[COMPLETED FAILED FAILED_WITH_TERMINAL_ERROR CANCELED TIMED_OUT SKIPPED].include?(status)
        end

        # Check if task completed successfully
        # @return [Boolean] true if task status is COMPLETED
        def completed?
          status == 'COMPLETED'
        end

        # Check if task failed
        # @return [Boolean] true if task status is FAILED or FAILED_WITH_TERMINAL_ERROR
        def failed?
          %w[FAILED FAILED_WITH_TERMINAL_ERROR].include?(status)
        end

        # Check if task is in progress
        # @return [Boolean] true if task status is IN_PROGRESS or SCHEDULED
        def in_progress?
          %w[IN_PROGRESS SCHEDULED].include?(status)
        end
      end
    end
  end
end
