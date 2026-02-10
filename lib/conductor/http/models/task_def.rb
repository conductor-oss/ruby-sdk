# frozen_string_literal: true

module Conductor
  module Http
    module Models
      # Retry logic options for task definitions
      module RetryLogic
        FIXED = 'FIXED'
        EXPONENTIAL_BACKOFF = 'EXPONENTIAL_BACKOFF'
        LINEAR_BACKOFF = 'LINEAR_BACKOFF'
      end

      # Timeout policy for task definitions
      module TaskTimeoutPolicy
        RETRY = 'RETRY'
        TIME_OUT_WF = 'TIME_OUT_WF'
        ALERT_ONLY = 'ALERT_ONLY'
      end

      # Task definition model for registering task types with Conductor
      class TaskDef < BaseModel
        SWAGGER_TYPES = {
          name: 'String',
          description: 'String',
          retry_count: 'Integer',
          timeout_seconds: 'Integer',
          input_keys: 'Array<String>',
          output_keys: 'Array<String>',
          timeout_policy: 'String',
          retry_logic: 'String',
          retry_delay_seconds: 'Integer',
          response_timeout_seconds: 'Integer',
          concurrent_exec_limit: 'Integer',
          rate_limit_per_frequency: 'Integer',
          rate_limit_frequency_in_seconds: 'Integer',
          isolation_group_id: 'String',
          execution_name_space: 'String',
          owner_email: 'String',
          poll_timeout_seconds: 'Integer',
          backoff_scale_factor: 'Integer'
        }.freeze

        ATTRIBUTE_MAP = {
          name: :name,
          description: :description,
          retry_count: :retryCount,
          timeout_seconds: :timeoutSeconds,
          input_keys: :inputKeys,
          output_keys: :outputKeys,
          timeout_policy: :timeoutPolicy,
          retry_logic: :retryLogic,
          retry_delay_seconds: :retryDelaySeconds,
          response_timeout_seconds: :responseTimeoutSeconds,
          concurrent_exec_limit: :concurrentExecLimit,
          rate_limit_per_frequency: :rateLimitPerFrequency,
          rate_limit_frequency_in_seconds: :rateLimitFrequencyInSeconds,
          isolation_group_id: :isolationGroupId,
          execution_name_space: :executionNameSpace,
          owner_email: :ownerEmail,
          poll_timeout_seconds: :pollTimeoutSeconds,
          backoff_scale_factor: :backoffScaleFactor
        }.freeze

        attr_accessor :name, :description, :retry_count, :timeout_seconds,
                      :input_keys, :output_keys, :timeout_policy, :retry_logic,
                      :retry_delay_seconds, :response_timeout_seconds,
                      :concurrent_exec_limit, :rate_limit_per_frequency,
                      :rate_limit_frequency_in_seconds, :isolation_group_id,
                      :execution_name_space, :owner_email, :poll_timeout_seconds,
                      :backoff_scale_factor

        def initialize(params = {})
          @name = params[:name]
          @description = params[:description]
          @retry_count = params[:retry_count] || 3
          @timeout_seconds = params[:timeout_seconds] || 3600
          @input_keys = params[:input_keys] || []
          @output_keys = params[:output_keys] || []
          @timeout_policy = params[:timeout_policy] || TaskTimeoutPolicy::TIME_OUT_WF
          @retry_logic = params[:retry_logic] || RetryLogic::FIXED
          @retry_delay_seconds = params[:retry_delay_seconds] || 60
          @response_timeout_seconds = params[:response_timeout_seconds] || 600
          @concurrent_exec_limit = params[:concurrent_exec_limit]
          @rate_limit_per_frequency = params[:rate_limit_per_frequency]
          @rate_limit_frequency_in_seconds = params[:rate_limit_frequency_in_seconds]
          @isolation_group_id = params[:isolation_group_id]
          @execution_name_space = params[:execution_name_space]
          @owner_email = params[:owner_email]
          @poll_timeout_seconds = params[:poll_timeout_seconds]
          @backoff_scale_factor = params[:backoff_scale_factor] || 1
        end
      end
    end
  end
end
