#!/usr/bin/env ruby
# frozen_string_literal: true

# Event Handler Example
#
# Demonstrates creating and managing event handlers that trigger
# workflows based on external events.
#
# Usage:
#   bundle exec ruby examples/event_handler.rb

require_relative '../lib/conductor'

def main
  config = Conductor::Configuration.new
  api_client = Conductor::Http::ApiClient.new(configuration: config)
  event_api = Conductor::Http::Api::EventResourceApi.new(api_client)

  puts '=' * 70
  puts 'Event Handler Example'
  puts '=' * 70
  puts "Server: #{config.server_url}"
  puts

  handler_name = "ruby_order_event_handler_#{Time.now.to_i}"

  # Create an event handler
  event_handler = {
    'name' => handler_name,
    'event' => 'order:created',
    'actions' => [
      {
        'action' => 'start_workflow',
        'start_workflow' => {
          'name' => 'process_order_workflow',
          'version' => 1,
          'input' => {
            'orderId' => '${event.orderId}',
            'customerId' => '${event.customerId}'
          }
        }
      }
    ],
    'active' => true
  }

  begin
    # Add event handler
    puts "Creating event handler: #{handler_name}"
    event_api.add_event_handler(event_handler)
    puts 'Event handler created!'

    # Get all event handlers
    handlers = event_api.get_event_handlers
    puts "\nAll event handlers (#{handlers.length} total):"
    handlers.first(5).each do |h|
      name = h.is_a?(Hash) ? h['name'] : h.name
      puts "  - #{name}"
    end

    # Get handlers for specific event
    puts "\nHandlers for 'order:created' event:"
    begin
      order_handlers = event_api.get_event_handlers_for_event('order:created', true)
      order_handlers.each do |h|
        name = h.is_a?(Hash) ? h['name'] : h.name
        puts "  - #{name}"
      end
    rescue StandardError => e
      puts "  Could not fetch: #{e.message}"
    end

  ensure
    # Cleanup
    puts "\nDeleting event handler..."
    begin
      event_api.remove_event_handler(handler_name)
      puts 'Event handler deleted'
    rescue StandardError => e
      puts "Could not delete: #{e.message}"
    end
  end

  puts "\nEvent handler example complete!"
end

if __FILE__ == $PROGRAM_NAME
  begin
    main
  rescue Conductor::ApiError => e
    puts "API Error: #{e.message}"
  rescue StandardError => e
    puts "Error: #{e.message}"
  end
end
