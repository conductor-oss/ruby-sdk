#!/usr/bin/env ruby
# frozen_string_literal: true

# Prompt Management Journey - Comprehensive Example
#
# Demonstrates all Prompt Management APIs through building an
# AI-powered customer service system.
#
# APIs Covered:
# - save_prompt, get_prompt, get_prompts, delete_prompt
# - get_tags_for_prompt_template, update_tag_for_prompt_template, delete_tag_for_prompt_template
# - test_prompt
#
# Usage:
#   bundle exec ruby examples/prompt_journey.rb

require_relative '../lib/conductor'

class PromptJourney
  AI_INTEGRATION = ENV.fetch('AI_INTEGRATION', 'openai')
  AI_MODEL = ENV.fetch('AI_MODEL', 'gpt-4o-mini')

  def initialize
    @config = Conductor::Configuration.new
    @clients = Conductor::Orkes::OrkesClients.new(@config)
    @prompt_client = @clients.get_prompt_client
    @created_prompts = []

    puts '=' * 70
    puts 'Prompt Management Journey'
    puts '=' * 70
    puts "Server: #{@config.server_url}"
    puts "AI Integration: #{AI_INTEGRATION}"
    puts
  end

  def run
    create_prompts
    retrieve_prompts
    test_prompts
    manage_tags
    cleanup
  end

  private

  def create_prompts
    puts "\n--- Creating Prompt Templates ---"

    # Customer service greeting prompt
    greeting_prompt = <<~PROMPT
      You are a friendly customer service representative for TechMart.
      
      Customer Name: ${customer_name}
      Issue Category: ${issue_category}
      
      Please greet the customer warmly and ask how you can help them today.
      Keep your response concise and professional.
    PROMPT

    @prompt_client.save_prompt(
      'cs_greeting_ruby',
      greeting_prompt,
      description: 'Customer service greeting template'
    )
    @created_prompts << 'cs_greeting_ruby'
    puts "Created prompt: cs_greeting_ruby"

    # Product recommendation prompt
    recommendation_prompt = <<~PROMPT
      Based on the following customer preferences, recommend 3 products:
      
      Budget: ${budget}
      Category: ${category}
      Previous Purchases: ${previous_purchases}
      
      Format your response as a numbered list with brief descriptions.
    PROMPT

    @prompt_client.save_prompt(
      'product_recommendation_ruby',
      recommendation_prompt,
      description: 'Product recommendation template'
    )
    @created_prompts << 'product_recommendation_ruby'
    puts "Created prompt: product_recommendation_ruby"

    # Issue resolution prompt
    resolution_prompt = <<~PROMPT
      You are helping resolve a customer issue.
      
      Issue: ${issue_description}
      Product: ${product_name}
      Purchase Date: ${purchase_date}
      
      Provide a helpful resolution or next steps. Be empathetic and solution-focused.
    PROMPT

    @prompt_client.save_prompt(
      'issue_resolution_ruby',
      resolution_prompt,
      description: 'Issue resolution template'
    )
    @created_prompts << 'issue_resolution_ruby'
    puts "Created prompt: issue_resolution_ruby"
  end

  def retrieve_prompts
    puts "\n--- Retrieving Prompts ---"

    # Get specific prompt
    prompt = @prompt_client.get_prompt('cs_greeting_ruby')
    puts "Retrieved prompt: cs_greeting_ruby"
    puts "  Description: #{prompt['description'] || prompt.description rescue 'N/A'}"

    # Get all prompts
    all_prompts = @prompt_client.get_prompts
    puts "\nAll prompts (#{all_prompts.length} total):"
    all_prompts.first(5).each do |p|
      name = p.is_a?(Hash) ? p['name'] : p.name
      puts "  - #{name}"
    end
  end

  def test_prompts
    puts "\n--- Testing Prompts ---"

    # Test the greeting prompt
    test_input = {
      'customer_name' => 'John Smith',
      'issue_category' => 'Technical Support'
    }

    puts "Testing cs_greeting_ruby with:"
    test_input.each { |k, v| puts "  #{k}: #{v}" }

    begin
      result = @prompt_client.test_prompt(
        'cs_greeting_ruby',
        test_input,
        AI_INTEGRATION,
        AI_MODEL
      )

      puts "\nAI Response:"
      puts '-' * 40
      response = result.is_a?(Hash) ? result['response'] : result.response rescue result
      puts response.to_s[0..500]
      puts '-' * 40
    rescue Conductor::ApiError => e
      puts "Test failed (AI integration may not be configured): #{e.message}"
    end

    # Test product recommendation
    puts "\nTesting product_recommendation_ruby..."
    rec_input = {
      'budget' => '$500',
      'category' => 'Electronics',
      'previous_purchases' => 'Laptop, Headphones'
    }

    begin
      result = @prompt_client.test_prompt(
        'product_recommendation_ruby',
        rec_input,
        AI_INTEGRATION,
        AI_MODEL
      )
      response = result.is_a?(Hash) ? result['response'] : result.response rescue result
      puts "Response preview: #{response.to_s[0..200]}..."
    rescue Conductor::ApiError => e
      puts "Test failed: #{e.message}"
    end
  end

  def manage_tags
    puts "\n--- Managing Tags ---"

    tags = [
      { 'key' => 'department', 'value' => 'customer_service' },
      { 'key' => 'language', 'value' => 'english' },
      { 'key' => 'version', 'value' => 'v1' }
    ]

    # Add tags
    puts "Adding tags to cs_greeting_ruby..."
    @prompt_client.update_tag_for_prompt_template('cs_greeting_ruby', tags)

    # Get tags
    retrieved_tags = @prompt_client.get_tags_for_prompt_template('cs_greeting_ruby')
    puts "Retrieved tags:"
    retrieved_tags.each do |tag|
      key = tag.is_a?(Hash) ? tag['key'] : tag.key
      value = tag.is_a?(Hash) ? tag['value'] : tag.value
      puts "  #{key}: #{value}"
    end

    # Delete specific tag
    puts "\nDeleting 'version' tag..."
    @prompt_client.delete_tag_for_prompt_template(
      'cs_greeting_ruby',
      [{ 'key' => 'version', 'value' => 'v1' }]
    )

    # Verify deletion
    remaining_tags = @prompt_client.get_tags_for_prompt_template('cs_greeting_ruby')
    puts "Remaining tags: #{remaining_tags.length}"
  end

  def cleanup
    puts "\n--- Cleanup ---"

    @created_prompts.each do |name|
      begin
        @prompt_client.delete_prompt(name)
        puts "Deleted prompt: #{name}"
      rescue StandardError => e
        puts "Could not delete #{name}: #{e.message}"
      end
    end

    puts "\nPrompt journey complete!"
  end
end

if __FILE__ == $PROGRAM_NAME
  begin
    PromptJourney.new.run
  rescue Conductor::ApiError => e
    puts "API Error: #{e.message}"
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts e.backtrace.first(3).join("\n")
  end
end
