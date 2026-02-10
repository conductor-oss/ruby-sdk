# frozen_string_literal: true

require_relative 'base_model'

module Conductor
  module Http
    module Models
      # StartWorkflowRequest model for starting a workflow execution
      class StartWorkflowRequest < BaseModel
        SWAGGER_TYPES = {
          name: 'String',
          version: 'Integer',
          correlation_id: 'String',
          input: 'Hash<String, Object>',
          task_to_domain: 'Hash<String, String>',
          workflow_def: 'WorkflowDef',
          external_input_payload_storage_path: 'String',
          priority: 'Integer',
          created_by: 'String',
          idempotency_key: 'String',
          idempotency_strategy: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          name: :name,
          version: :version,
          correlation_id: :correlationId,
          input: :input,
          task_to_domain: :taskToDomain,
          workflow_def: :workflowDef,
          external_input_payload_storage_path: :externalInputPayloadStoragePath,
          priority: :priority,
          created_by: :createdBy,
          idempotency_key: :idempotencyKey,
          idempotency_strategy: :idempotencyStrategy
        }.freeze

        # Idempotency strategies
        module IdempotencyStrategy
          FAIL = 'FAIL'
          RETURN_EXISTING = 'RETURN_EXISTING'
        end

        attr_accessor :name, :version, :correlation_id, :input, :task_to_domain,
                      :workflow_def, :external_input_payload_storage_path, :priority,
                      :created_by, :idempotency_key, :idempotency_strategy

        # Initialize a new StartWorkflowRequest
        # @param [Hash] attributes Model attributes in the form of hash
        def initialize(attributes = {})
          return unless attributes.is_a?(Hash)

          self.name = attributes[:name] if attributes.key?(:name)
          self.version = attributes[:version] if attributes.key?(:version)
          self.correlation_id = attributes[:correlation_id] if attributes.key?(:correlation_id)
          self.input = attributes[:input] if attributes.key?(:input)
          self.task_to_domain = attributes[:task_to_domain] if attributes.key?(:task_to_domain)
          self.workflow_def = attributes[:workflow_def] if attributes.key?(:workflow_def)
          self.external_input_payload_storage_path = attributes[:external_input_payload_storage_path] if attributes.key?(:external_input_payload_storage_path)
          self.priority = attributes[:priority] if attributes.key?(:priority)
          self.created_by = attributes[:created_by] if attributes.key?(:created_by)
          self.idempotency_key = attributes[:idempotency_key] if attributes.key?(:idempotency_key)
          self.idempotency_strategy = attributes[:idempotency_strategy] if attributes.key?(:idempotency_strategy)
        end
      end
    end
  end
end
