# frozen_string_literal: true

require_relative '../configuration'
require_relative '../http/api_client'
require_relative '../http/api/scheduler_resource_api'

module Conductor
  module Client
    # SchedulerClient - High-level client for workflow schedule operations
    class SchedulerClient
      attr_reader :scheduler_api

      # Initialize SchedulerClient
      # @param [Configuration] configuration Optional configuration
      def initialize(configuration = nil)
        @configuration = configuration || Configuration.new
        api_client = Http::ApiClient.new(configuration: @configuration)
        @scheduler_api = Http::Api::SchedulerResourceApi.new(api_client)
      end

      # Save (create/update) a schedule
      # @param [SaveScheduleRequest] request Schedule request
      # @return [void]
      def save_schedule(request)
        @scheduler_api.save_schedule(request)
      end

      # Get a schedule by name
      # @param [String] name Schedule name
      # @return [WorkflowSchedule]
      def get_schedule(name)
        @scheduler_api.get_schedule(name)
      end

      # Get all schedules
      # @param [String] workflow_name Filter by workflow name (optional)
      # @return [Array<WorkflowSchedule>]
      def get_all_schedules(workflow_name: nil)
        @scheduler_api.get_all_schedules(workflow_name: workflow_name)
      end

      # Delete a schedule
      # @param [String] name Schedule name
      # @return [void]
      def delete_schedule(name)
        @scheduler_api.delete_schedule(name)
      end

      # Pause a schedule
      # @param [String] name Schedule name
      # @return [void]
      def pause_schedule(name)
        @scheduler_api.pause_schedule(name)
      end

      # Resume a schedule
      # @param [String] name Schedule name
      # @return [void]
      def resume_schedule(name)
        @scheduler_api.resume_schedule(name)
      end

      # Pause all schedules
      # @return [Hash]
      def pause_all_schedules
        @scheduler_api.pause_all_schedules
      end

      # Resume all schedules
      # @return [Hash]
      def resume_all_schedules
        @scheduler_api.resume_all_schedules
      end

      # Get next few schedule execution times
      # @param [String] cron_expression Cron expression
      # @param [Integer] schedule_start_time Start time (epoch ms, optional)
      # @param [Integer] schedule_end_time End time (epoch ms, optional)
      # @param [Integer] limit Number of times to return (optional)
      # @return [Array<Integer>]
      def get_next_few_schedule_execution_times(cron_expression, schedule_start_time: nil, schedule_end_time: nil, limit: nil)
        @scheduler_api.get_next_few_schedules(
          cron_expression,
          schedule_start_time: schedule_start_time,
          schedule_end_time: schedule_end_time,
          limit: limit
        )
      end

      # Search schedule executions
      # @param [Integer] start Start index (default: 0)
      # @param [Integer] size Page size (default: 100)
      # @param [String] sort Sort order (optional)
      # @param [String] free_text Free text search (default: '*')
      # @param [String] query Query string (optional)
      # @return [SearchResult]
      def search_schedule_executions(start: 0, size: 100, sort: nil, free_text: '*', query: nil)
        @scheduler_api.search_v2(start: start, size: size, sort: sort, free_text: free_text, query: query)
      end

      # Requeue all execution records
      # @return [Hash]
      def requeue_all_execution_records
        @scheduler_api.requeue_all_execution_records
      end

      # Set tags for a schedule
      # @param [String] name Schedule name
      # @param [Array<Hash>] tags Tags to set
      # @return [void]
      def set_scheduler_tags(name, tags)
        @scheduler_api.put_tag_for_schedule(name, tags)
      end

      # Get tags for a schedule
      # @param [String] name Schedule name
      # @return [Array<Hash>]
      def get_scheduler_tags(name)
        @scheduler_api.get_tags_for_schedule(name)
      end

      # Delete tags for a schedule
      # @param [String] name Schedule name
      # @param [Array<Hash>] tags Tags to delete
      # @return [void]
      def delete_scheduler_tags(name, tags)
        @scheduler_api.delete_tag_for_schedule(name, tags)
      end
    end
  end
end
