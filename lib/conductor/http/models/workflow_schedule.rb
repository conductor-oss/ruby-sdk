# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Workflow schedule definition
      class SaveScheduleRequest < BaseModel
        SWAGGER_TYPES = {
          name: 'String',
          cron_expression: 'String',
          start_workflow_request: 'StartWorkflowRequest',
          paused: 'Boolean',
          run_catchup_schedule_instances: 'Boolean',
          schedule_start_time: 'Integer',
          schedule_end_time: 'Integer',
          created_by: 'String',
          updated_by: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          name: :name,
          cron_expression: :cronExpression,
          start_workflow_request: :startWorkflowRequest,
          paused: :paused,
          run_catchup_schedule_instances: :runCatchupScheduleInstances,
          schedule_start_time: :scheduleStartTime,
          schedule_end_time: :scheduleEndTime,
          created_by: :createdBy,
          updated_by: :updatedBy
        }.freeze

        attr_accessor :name, :cron_expression, :start_workflow_request, :paused,
                      :run_catchup_schedule_instances, :schedule_start_time,
                      :schedule_end_time, :created_by, :updated_by

        def initialize(params = {})
          @name = params[:name]
          @cron_expression = params[:cron_expression]
          @start_workflow_request = params[:start_workflow_request]
          @paused = params.fetch(:paused, false)
          @run_catchup_schedule_instances = params.fetch(:run_catchup_schedule_instances, false)
          @schedule_start_time = params[:schedule_start_time]
          @schedule_end_time = params[:schedule_end_time]
          @created_by = params[:created_by]
          @updated_by = params[:updated_by]
        end
      end

      # Workflow schedule (returned from server)
      class WorkflowSchedule < BaseModel
        SWAGGER_TYPES = {
          name: 'String',
          cron_expression: 'String',
          start_workflow_request: 'StartWorkflowRequest',
          paused: 'Boolean',
          run_catchup_schedule_instances: 'Boolean',
          schedule_start_time: 'Integer',
          schedule_end_time: 'Integer',
          create_time: 'Integer',
          updated_time: 'Integer',
          created_by: 'String',
          updated_by: 'String'
        }.freeze

        ATTRIBUTE_MAP = {
          name: :name,
          cron_expression: :cronExpression,
          start_workflow_request: :startWorkflowRequest,
          paused: :paused,
          run_catchup_schedule_instances: :runCatchupScheduleInstances,
          schedule_start_time: :scheduleStartTime,
          schedule_end_time: :scheduleEndTime,
          create_time: :createTime,
          updated_time: :updatedTime,
          created_by: :createdBy,
          updated_by: :updatedBy
        }.freeze

        attr_accessor :name, :cron_expression, :start_workflow_request, :paused,
                      :run_catchup_schedule_instances, :schedule_start_time,
                      :schedule_end_time, :create_time, :updated_time,
                      :created_by, :updated_by

        def initialize(params = {})
          @name = params[:name]
          @cron_expression = params[:cron_expression]
          @start_workflow_request = params[:start_workflow_request]
          @paused = params.fetch(:paused, false)
          @run_catchup_schedule_instances = params.fetch(:run_catchup_schedule_instances, false)
          @schedule_start_time = params[:schedule_start_time]
          @schedule_end_time = params[:schedule_end_time]
          @create_time = params[:create_time]
          @updated_time = params[:updated_time]
          @created_by = params[:created_by]
          @updated_by = params[:updated_by]
        end
      end
    end
  end
end
