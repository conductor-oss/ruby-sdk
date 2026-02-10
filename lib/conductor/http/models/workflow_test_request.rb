# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Request to test a workflow with mocked task outputs
      class WorkflowTestRequest < BaseModel
        SWAGGER_TYPES = {
          workflow_def: 'WorkflowDef',
          name: 'String',
          version: 'Integer',
          input: 'Hash<String, Object>',
          correlation_id: 'String',
          task_ref_to_mock_output: 'Hash<String, Array<WorkflowTestTaskResult>>',
          external_input_payload_storage_path: 'String',
          sub_workflow_test_request: 'Hash<String, WorkflowTestRequest>'
        }.freeze

        ATTRIBUTE_MAP = {
          workflow_def: :workflowDef,
          name: :name,
          version: :version,
          input: :input,
          correlation_id: :correlationId,
          task_ref_to_mock_output: :taskRefToMockOutput,
          external_input_payload_storage_path: :externalInputPayloadStoragePath,
          sub_workflow_test_request: :subWorkflowTestRequest
        }.freeze

        attr_accessor :workflow_def, :name, :version, :input, :correlation_id,
                      :task_ref_to_mock_output, :external_input_payload_storage_path,
                      :sub_workflow_test_request

        def initialize(params = {})
          @workflow_def = params[:workflow_def]
          @name = params[:name]
          @version = params[:version]
          @input = params[:input] || {}
          @correlation_id = params[:correlation_id]
          @task_ref_to_mock_output = params[:task_ref_to_mock_output] || {}
          @external_input_payload_storage_path = params[:external_input_payload_storage_path]
          @sub_workflow_test_request = params[:sub_workflow_test_request] || {}
        end
      end

      # Mock task result for workflow testing
      class WorkflowTestTaskResult < BaseModel
        SWAGGER_TYPES = {
          status: 'String',
          output: 'Hash<String, Object>'
        }.freeze

        ATTRIBUTE_MAP = {
          status: :status,
          output: :output
        }.freeze

        attr_accessor :status, :output

        def initialize(params = {})
          @status = params[:status] || 'COMPLETED'
          @output = params[:output] || {}
        end
      end
    end
  end
end
