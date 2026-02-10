# frozen_string_literal: true

require_relative '../api_client'

module Conductor
  module Http
    module Api
      # EventResourceApi - API for event handler operations
      class EventResourceApi
        attr_accessor :api_client

        def initialize(api_client = nil)
          @api_client = api_client || ApiClient.new
        end

        # Add an event handler
        # @param [EventHandler] body Event handler definition
        # @return [void]
        def add_event_handler(body)
          @api_client.call_api(
            '/event',
            'POST',
            body: body,
            return_http_data_only: true
          )
        end

        # Update an event handler
        # @param [EventHandler] body Event handler definition
        # @return [void]
        def update_event_handler(body)
          @api_client.call_api(
            '/event',
            'PUT',
            body: body,
            return_http_data_only: true
          )
        end

        # Get all event handlers
        # @return [Array<EventHandler>]
        def get_event_handlers
          @api_client.call_api(
            '/event',
            'GET',
            return_type: 'Array<EventHandler>',
            return_http_data_only: true
          )
        end

        # Get event handlers for a specific event
        # @param [String] event Event name
        # @param [Boolean] active_only Only return active handlers (default: true)
        # @return [Array<EventHandler>]
        def get_event_handlers_for_event(event, active_only: true)
          @api_client.call_api(
            '/event/{event}',
            'GET',
            path_params: { event: event },
            query_params: { activeOnly: active_only },
            return_type: 'Array<EventHandler>',
            return_http_data_only: true
          )
        end

        # Remove an event handler
        # @param [String] name Event handler name
        # @return [void]
        def remove_event_handler(name)
          @api_client.call_api(
            '/event/{name}',
            'DELETE',
            path_params: { name: name },
            return_http_data_only: true
          )
        end

        # Get queue configuration
        # @param [String] queue_type Queue type
        # @param [String] queue_name Queue name
        # @return [Hash]
        def get_queue_config(queue_type, queue_name)
          @api_client.call_api(
            '/event/queue/config/{queueType}/{queueName}',
            'GET',
            path_params: { queueType: queue_type, queueName: queue_name },
            return_type: 'Hash<String, Object>',
            return_http_data_only: true
          )
        end

        # Update queue configuration
        # @param [String] queue_type Queue type
        # @param [String] queue_name Queue name
        # @param [String] body Queue configuration (JSON string)
        # @return [void]
        def put_queue_config(queue_type, queue_name, body)
          @api_client.call_api(
            '/event/queue/config/{queueType}/{queueName}',
            'PUT',
            path_params: { queueType: queue_type, queueName: queue_name },
            body: body,
            return_http_data_only: true
          )
        end

        # Delete queue configuration
        # @param [String] queue_type Queue type
        # @param [String] queue_name Queue name
        # @return [void]
        def delete_queue_config(queue_type, queue_name)
          @api_client.call_api(
            '/event/queue/config/{queueType}/{queueName}',
            'DELETE',
            path_params: { queueType: queue_type, queueName: queue_name },
            return_http_data_only: true
          )
        end

        # Get all queue names
        # @return [Hash<String, String>]
        def get_queue_names
          @api_client.call_api(
            '/event/queue/config',
            'GET',
            return_type: 'Hash<String, String>',
            return_http_data_only: true
          )
        end
      end
    end
  end
end
