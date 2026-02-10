# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # SchedulerResourceApi - API for workflow schedule operations
      class SchedulerResourceApi
        attr_accessor :api_client

        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # Save (create/update) a workflow schedule
        # @param [SaveScheduleRequest] body Schedule request
        # @return [void]
        def save_schedule(body)
          @api_client.call_api(
            '/scheduler/schedules',
            'POST',
            body: body,
            return_http_data_only: true
          )
        end

        # Get a schedule by name
        # @param [String] name Schedule name
        # @return [WorkflowSchedule]
        def get_schedule(name)
          @api_client.call_api(
            '/scheduler/schedules/{name}',
            'GET',
            path_params: { name: name },
            return_type: 'WorkflowSchedule',
            return_http_data_only: true
          )
        end

        # Get all schedules
        # @param [String] workflow_name Filter by workflow name (optional)
        # @return [Array<WorkflowSchedule>]
        def get_all_schedules(workflow_name: nil)
          query_params = {}
          query_params[:workflowName] = workflow_name if workflow_name

          @api_client.call_api(
            '/scheduler/schedules',
            'GET',
            query_params: query_params,
            return_type: 'Array<WorkflowSchedule>',
            return_http_data_only: true
          )
        end

        # Delete a schedule
        # @param [String] name Schedule name
        # @return [void]
        def delete_schedule(name)
          @api_client.call_api(
            '/scheduler/schedules/{name}',
            'DELETE',
            path_params: { name: name },
            return_http_data_only: true
          )
        end

        # Pause a schedule
        # @param [String] name Schedule name
        # @return [void]
        def pause_schedule(name)
          @api_client.call_api(
            '/scheduler/schedules/{name}/pause',
            'GET',
            path_params: { name: name },
            return_http_data_only: true
          )
        end

        # Resume a schedule
        # @param [String] name Schedule name
        # @return [void]
        def resume_schedule(name)
          @api_client.call_api(
            '/scheduler/schedules/{name}/resume',
            'GET',
            path_params: { name: name },
            return_http_data_only: true
          )
        end

        # Pause all schedules
        # @return [Hash]
        def pause_all_schedules
          @api_client.call_api(
            '/scheduler/admin/pause',
            'GET',
            return_type: 'Hash<String, Object>',
            return_http_data_only: true
          )
        end

        # Resume all schedules
        # @return [Hash]
        def resume_all_schedules
          @api_client.call_api(
            '/scheduler/admin/resume',
            'GET',
            return_type: 'Hash<String, Object>',
            return_http_data_only: true
          )
        end

        # Get next few schedule execution times
        # @param [String] cron_expression Cron expression
        # @param [Integer] schedule_start_time Start time (epoch ms, optional)
        # @param [Integer] schedule_end_time End time (epoch ms, optional)
        # @param [Integer] limit Number of times to return (optional)
        # @return [Array<Integer>]
        def get_next_few_schedules(cron_expression, schedule_start_time: nil, schedule_end_time: nil, limit: nil)
          query_params = { cronExpression: cron_expression }
          query_params[:scheduleStartTime] = schedule_start_time if schedule_start_time
          query_params[:scheduleEndTime] = schedule_end_time if schedule_end_time
          query_params[:limit] = limit if limit

          @api_client.call_api(
            '/scheduler/nextFewSchedules',
            'GET',
            query_params: query_params,
            return_type: 'Array<Integer>',
            return_http_data_only: true
          )
        end

        # Search schedule executions
        # @param [Integer] start Start index (default: 0)
        # @param [Integer] size Page size (default: 100)
        # @param [String] sort Sort order (optional)
        # @param [String] free_text Free text search (default: '*')
        # @param [String] query Query string (optional)
        # @return [SearchResult]
        def search_v2(start: 0, size: 100, sort: nil, free_text: '*', query: nil)
          query_params = { start: start, size: size, freeText: free_text }
          query_params[:sort] = sort if sort
          query_params[:query] = query if query

          @api_client.call_api(
            '/scheduler/search/executions',
            'GET',
            query_params: query_params,
            return_type: 'SearchResult',
            return_http_data_only: true
          )
        end

        # Requeue all execution records
        # @return [Hash]
        def requeue_all_execution_records
          @api_client.call_api(
            '/scheduler/admin/requeue',
            'GET',
            return_type: 'Hash<String, Object>',
            return_http_data_only: true
          )
        end

        # Set tags for a schedule
        # @param [String] name Schedule name
        # @param [Array<Hash>] tags List of tags
        # @return [void]
        def put_tag_for_schedule(name, tags)
          @api_client.call_api(
            '/scheduler/schedules/{name}/tags',
            'PUT',
            path_params: { name: name },
            body: tags,
            return_http_data_only: true
          )
        end

        # Get tags for a schedule
        # @param [String] name Schedule name
        # @return [Array<Hash>]
        def get_tags_for_schedule(name)
          @api_client.call_api(
            '/scheduler/schedules/{name}/tags',
            'GET',
            path_params: { name: name },
            return_type: 'Array<Object>',
            return_http_data_only: true
          )
        end

        # Delete tags for a schedule
        # @param [String] name Schedule name
        # @param [Array<Hash>] tags List of tags to delete
        # @return [void]
        def delete_tag_for_schedule(name, tags)
          @api_client.call_api(
            '/scheduler/schedules/{name}/tags',
            'DELETE',
            path_params: { name: name },
            body: tags,
            return_http_data_only: true
          )
        end
      end
    end
  end
end
