#!/usr/bin/env ruby
# frozen_string_literal: true

# Secrets Management Example
#
# Demonstrates using the SecretClient to manage sensitive data
# like API keys, passwords, and tokens.
#
# Usage:
#   bundle exec ruby examples/orkes/secrets_example.rb

require_relative '../../lib/conductor'

def main
  config = Conductor::Configuration.new
  clients = Conductor::Orkes::OrkesClients.new(config)
  secret_client = clients.get_secret_client

  puts '=' * 70
  puts 'Secrets Management Example'
  puts '=' * 70
  puts "Server: #{config.server_url}"
  puts

  secret_name = "test_api_key_ruby_#{Time.now.to_i}"

  begin
    # Create a secret
    puts "Creating secret: #{secret_name}"
    secret_client.put_secret(secret_name, 'super-secret-value-12345')
    puts 'Secret created successfully'

    # List all secrets (names only - values are never exposed)
    puts "\nListing all secrets:"
    secrets = secret_client.list_all_secret_names
    secrets.first(5).each { |s| puts "  - #{s}" }
    puts "  ... (#{secrets.length} total)"

    # Check if secret exists
    exists = secret_client.secret_exists?(secret_name)
    puts "\nSecret '#{secret_name}' exists: #{exists}"

    # Update the secret
    puts "\nUpdating secret..."
    secret_client.put_secret(secret_name, 'updated-secret-value-67890')
    puts 'Secret updated'
  ensure
    # Clean up
    puts "\nDeleting secret..."
    begin
      secret_client.delete_secret(secret_name)
      puts 'Secret deleted'
    rescue StandardError => e
      puts "Could not delete: #{e.message}"
    end
  end

  puts "\nSecrets example complete!"
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
