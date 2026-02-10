# frozen_string_literal: true

require_relative 'base_model'
require_relative 'task_result_status'

module Conductor
  module Http
    module Models
      # TaskResult model representing the result of task execution
      class TaskResult < BaseModel
        SWAGGER_TYPES = {
          workflow_instance_id: 'String',
          task_id: 'String',
          reason_for_incompletion: 'String',
          callback_after_seconds: 'Integer',
          worker_id: 'String',
          status: 'String',
          output_data: 'Hash<String, Object>',
          logs: 'Array<TaskExecLog>',
          external_output_payload_storage_path: 'String',
          sub_workflow_id: 'String',
          extend_lease: 'Boolean'
        }.freeze

        ATTRIBUTE_MAP = {
          workflow_instance_id: :workflowInstanceId,
          task_id: :taskId,
          reason_for_incompletion: :reasonForIncompletion,
          callback_after_seconds: :callbackAfterSeconds,
          worker_id: :workerId,
          status: :status,
          output_data: :outputData,
          logs: :logs,
          external_output_payload_storage_path: :externalOutputPayloadStoragePath,
          sub_workflow_id: :subWorkflowId,
          extend_lease: :extendLease
        }.freeze

        attr_accessor :workflow_instance_id, :task_id, :reason_for_incompletion,
                      :callback_after_seconds, :worker_id, :status, :output_data,
                      :logs, :external_output_payload_storage_path, :sub_workflow_id,
                      :extend_lease

        # Initialize a new TaskResult
        # @param [Hash] attributes Model attributes in the form of hash
        def initialize(attributes = {})
          return unless attributes.is_a?(Hash)

          self.workflow_instance_id = attributes[:workflow_instance_id] if attributes.key?(:workflow_instance_id)
          self.task_id = attributes[:task_id] if attributes.key?(:task_id)
          self.reason_for_incompletion = attributes[:reason_for_incompletion] if attributes.key?(:reason_for_incompletion)
          self.callback_after_seconds = attributes[:callback_after_seconds] if attributes.key?(:callback_after_seconds)
          self.worker_id = attributes[:worker_id] if attributes.key?(:worker_id)
          self.status = attributes[:status] if attributes.key?(:status)
          self.output_data = attributes[:output_data] || {}
          self.logs = attributes[:logs] || []
          if attributes.key?(:external_output_payload_storage_path)
            self.external_output_payload_storage_path = attributes[:external_output_payload_storage_path]
          end
          self.sub_workflow_id = attributes[:sub_workflow_id] if attributes.key?(:sub_workflow_id)
          self.extend_lease = attributes[:extend_lease] || false
        end

        # Add a key-value pair to output_data
        # @param [String] key The key
        # @param [Object] value The value
        # @return [TaskResult] self for chaining
        def add_output_data(key, value)
          @output_data ||= {}
          @output_data[key] = value
          self
        end

        # Add a log message
        # @param [String] log_message The log message
        # @return [TaskResult] self for chaining
        def log(log_message)
          @logs ||= []
          @logs << log_message
          self
        end

        # Create a COMPLETED task result
        # @return [TaskResult]
        def self.complete
          new(status: TaskResultStatus::COMPLETED)
        end

        # Create a FAILED task result
        # @param [String] failure_reason Optional failure reason
        # @return [TaskResult]
        def self.failed(failure_reason = nil)
          result = new(status: TaskResultStatus::FAILED)
          result.reason_for_incompletion = failure_reason if failure_reason
          result
        end

        # Create an IN_PROGRESS task result
        # @return [TaskResult]
        def self.in_progress
          new(status: TaskResultStatus::IN_PROGRESS)
        end

        # Create a FAILED_WITH_TERMINAL_ERROR task result
        # @param [String] failure_reason Optional failure reason
        # @return [TaskResult]
        def self.failed_with_terminal_error(failure_reason = nil)
          result = new(status: TaskResultStatus::FAILED_WITH_TERMINAL_ERROR)
          result.reason_for_incompletion = failure_reason if failure_reason
          result
        end
      end
    end
  end
end
