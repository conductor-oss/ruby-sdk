# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

# Prompt API integration tests - run with:
# ORKES_INTEGRATION=true bundle exec rspec spec/integration/prompt_spec.rb --format documentation
#
# These tests cover Orkes prompt template management APIs:
# 1. save_prompt - Create/update prompt template
# 2. get_prompt - Get specific prompt
# 3. get_prompts - List all prompts
# 4. delete_prompt - Delete prompt
# 5. get_tags_for_prompt_template - Get tags
# 6. update_tag_for_prompt_template - Set tags
# 7. delete_tag_for_prompt_template - Remove tags
# 8. test_prompt - Test prompt with variables

RSpec.describe 'Prompt API Integration', skip: !ENV['ORKES_INTEGRATION'] do
  let(:server_url) { ENV['ORKES_SERVER_URL'] || 'https://developer.orkescloud.com/api' }
  let(:auth_key) { ENV['ORKES_AUTH_KEY'] }
  let(:auth_secret) { ENV['ORKES_AUTH_SECRET'] }
  let(:test_id) { "ruby_sdk_prompt_#{SecureRandom.hex(4)}" }

  let(:configuration) do
    Conductor::Configuration.new(
      server_api_url: server_url,
      auth_key: auth_key,
      auth_secret: auth_secret
    )
  end

  let(:clients) { Conductor::Orkes::OrkesClients.new(configuration) }
  let(:prompt_client) { clients.get_prompt_client }
  let(:api_client) { Conductor::Http::ApiClient.new(configuration: configuration) }
  let(:prompt_api) { Conductor::Http::Api::PromptResourceApi.new(api_client) }

  # Helper to skip tests that hit free tier limits
  def skip_if_limit_reached(error)
    if error.is_a?(Conductor::ApiError) && error.status == 402
      skip "Orkes free tier limit reached: #{error.message}"
    else
      raise error
    end
  end

  describe 'Prompt CRUD Operations' do
    let(:prompt_name) { "#{test_id}_test_prompt" }
    let(:prompt_template) do
      <<~TEMPLATE
        You are a helpful assistant.

        User: ${user_input}

        Please provide a helpful response.
      TEMPLATE
    end

    after do
      # Clean up prompt
      begin
        prompt_api.delete_prompt(prompt_name)
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    it '1. save_prompt - creates a new prompt template' do
      prompt_api.save_prompt(
        prompt_name,
        prompt_template,
        description: 'Test prompt for Ruby SDK integration tests'
      )

      # Verify it was created
      prompts = prompt_api.get_prompts
      prompt_names = prompts.map { |p| p.is_a?(Hash) ? p['name'] : p.name }
      expect(prompt_names).to include(prompt_name)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '2. get_prompt - retrieves a specific prompt' do
      # First create a prompt
      prompt_api.save_prompt(
        prompt_name,
        prompt_template,
        description: 'Test prompt'
      )

      # Get the prompt
      prompt = prompt_api.get_prompt(prompt_name)

      expect(prompt).not_to be_nil
      name = prompt.is_a?(Hash) ? prompt['name'] : prompt.name
      expect(name).to eq(prompt_name)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '3. get_prompts - lists all prompts' do
      # First create a prompt
      prompt_api.save_prompt(
        prompt_name,
        prompt_template,
        description: 'Test prompt'
      )

      # Get all prompts
      prompts = prompt_api.get_prompts

      expect(prompts).to be_an(Array)

      # Our prompt should be in the list
      prompt_names = prompts.map { |p| p.is_a?(Hash) ? p['name'] : p.name }
      expect(prompt_names).to include(prompt_name)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '4. delete_prompt - removes a prompt template' do
      # First create a prompt
      prompt_api.save_prompt(
        prompt_name,
        prompt_template,
        description: 'Test prompt'
      )

      # Verify it exists
      prompts_before = prompt_api.get_prompts
      names_before = prompts_before.map { |p| p.is_a?(Hash) ? p['name'] : p.name }
      expect(names_before).to include(prompt_name)

      # Delete it
      prompt_api.delete_prompt(prompt_name)

      # Verify it's gone
      prompts_after = prompt_api.get_prompts
      names_after = prompts_after.map { |p| p.is_a?(Hash) ? p['name'] : p.name }
      expect(names_after).not_to include(prompt_name)
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '1b. save_prompt - updates an existing prompt' do
      # Create initial prompt
      prompt_api.save_prompt(
        prompt_name,
        prompt_template,
        description: 'Initial version'
      )

      # Update the prompt
      updated_template = <<~TEMPLATE
        You are an expert assistant.

        User Input: ${user_input}
        Context: ${context}

        Provide a detailed and helpful response.
      TEMPLATE

      prompt_api.save_prompt(
        prompt_name,
        updated_template,
        description: 'Updated version'
      )

      # Verify the update
      prompt = prompt_api.get_prompt(prompt_name)
      template = prompt.is_a?(Hash) ? prompt['template'] : prompt.template
      expect(template).to include('expert assistant')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Prompt Tag Operations' do
    let(:prompt_name) { "#{test_id}_tag_prompt" }
    let(:prompt_template) { 'Test prompt for tags: ${input}' }

    before do
      # Create a prompt for testing tags
      begin
        prompt_api.save_prompt(
          prompt_name,
          prompt_template,
          description: 'Prompt for tag testing'
        )
      rescue Conductor::ApiError => e
        skip_if_limit_reached(e)
      end
    end

    after do
      begin
        prompt_api.delete_prompt(prompt_name)
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    it '6. update_tag_for_prompt_template - sets tags on a prompt' do
      tags = [
        { key: 'environment', value: 'test' },
        { key: 'team', value: 'sdk' },
        { key: 'purpose', value: 'integration-testing' }
      ]

      prompt_api.update_tag_for_prompt_template(prompt_name, tags)

      # Verify tags were set
      retrieved_tags = prompt_api.get_tags_for_prompt_template(prompt_name)
      expect(retrieved_tags).to be_an(Array)

      tag_keys = retrieved_tags.map { |t| t.is_a?(Hash) ? t['key'] : t.key }
      expect(tag_keys).to include('environment')
      expect(tag_keys).to include('team')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '5. get_tags_for_prompt_template - retrieves tags' do
      # First set some tags
      tags = [
        { key: 'category', value: 'test' },
        { key: 'version', value: '1.0' }
      ]
      prompt_api.update_tag_for_prompt_template(prompt_name, tags)

      # Get the tags
      retrieved_tags = prompt_api.get_tags_for_prompt_template(prompt_name)

      expect(retrieved_tags).to be_an(Array)
      expect(retrieved_tags).not_to be_empty

      tag_map = retrieved_tags.map do |t|
        key = t.is_a?(Hash) ? t['key'] : t.key
        value = t.is_a?(Hash) ? t['value'] : t.value
        [key, value]
      end.to_h

      expect(tag_map['category']).to eq('test')
      expect(tag_map['version']).to eq('1.0')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it '7. delete_tag_for_prompt_template - removes specific tags' do
      # Set initial tags
      initial_tags = [
        { key: 'keep', value: 'yes' },
        { key: 'remove', value: 'this' },
        { key: 'also_remove', value: 'that' }
      ]
      prompt_api.update_tag_for_prompt_template(prompt_name, initial_tags)

      # Verify tags were set
      tags_before = prompt_api.get_tags_for_prompt_template(prompt_name)
      expect(tags_before.length).to be >= 3

      # Delete specific tags
      tags_to_delete = [
        { key: 'remove', value: 'this' },
        { key: 'also_remove', value: 'that' }
      ]
      prompt_api.delete_tag_for_prompt_template(prompt_name, tags_to_delete)

      # Verify only 'keep' tag remains
      tags_after = prompt_api.get_tags_for_prompt_template(prompt_name)
      tag_keys = tags_after.map { |t| t.is_a?(Hash) ? t['key'] : t.key }

      expect(tag_keys).to include('keep')
      expect(tag_keys).not_to include('remove')
      expect(tag_keys).not_to include('also_remove')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Prompt Testing' do
    let(:prompt_name) { "#{test_id}_testable_prompt" }

    before do
      # Create a prompt for testing
      prompt_template = <<~TEMPLATE
        Respond with: Hello, ${name}! Your request was: ${request}
      TEMPLATE

      begin
        prompt_api.save_prompt(
          prompt_name,
          prompt_template,
          description: 'Prompt for test_prompt API'
        )
      rescue Conductor::ApiError => e
        skip_if_limit_reached(e)
      end
    end

    after do
      begin
        prompt_api.delete_prompt(prompt_name)
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    it '8. test_prompt - tests prompt variable substitution' do
      # Test the prompt with variables
      # Note: The test_prompt API requires integration with an LLM provider
      # This test verifies the API endpoint works but may return an error
      # if no LLM integration is configured

      test_request = {
        promptName: prompt_name,
        promptVariables: {
          'name' => 'Ruby SDK',
          'request' => 'integration test'
        }
      }

      begin
        result = prompt_api.test_prompt(test_request)
        expect(result).not_to be_nil
      rescue Conductor::ApiError => e
        # 400/500 errors are acceptable if no LLM provider is configured
        if e.status == 400 || e.status == 500
          skip 'Prompt testing requires LLM provider integration'
        else
          skip_if_limit_reached(e)
        end
      end
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end

  describe 'Advanced Prompt Patterns' do
    let(:prompt_name) { "#{test_id}_advanced_prompt" }

    after do
      begin
        prompt_api.delete_prompt(prompt_name)
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    it 'creates prompt with multiple variables' do
      template = <<~TEMPLATE
        System: You are a ${role} assistant specializing in ${domain}.

        Context: ${context}

        User Query: ${query}

        Instructions:
        1. Analyze the query in context
        2. Provide ${response_style} response
        3. Include relevant examples if needed

        Response:
      TEMPLATE

      prompt_api.save_prompt(
        prompt_name,
        template,
        description: 'Multi-variable prompt template'
      )

      # Verify creation
      prompt = prompt_api.get_prompt(prompt_name)
      expect(prompt).not_to be_nil

      # Check template contains all variables
      prompt_template = prompt.is_a?(Hash) ? prompt['template'] : prompt.template
      expect(prompt_template).to include('${role}')
      expect(prompt_template).to include('${domain}')
      expect(prompt_template).to include('${context}')
      expect(prompt_template).to include('${query}')
      expect(prompt_template).to include('${response_style}')
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end

    it 'creates prompt with versioning' do
      template_v1 = 'Version 1: Hello ${name}'

      # Create initial version
      prompt_api.save_prompt(
        prompt_name,
        template_v1,
        description: 'Version 1'
      )

      # Create new version with auto_increment
      template_v2 = 'Version 2: Welcome ${name}!'
      prompt_api.save_prompt(
        prompt_name,
        template_v2,
        description: 'Version 2',
        auto_increment: true
      )

      # Get the prompt to verify
      prompt = prompt_api.get_prompt(prompt_name)
      expect(prompt).not_to be_nil
    rescue Conductor::ApiError => e
      skip_if_limit_reached(e)
    end
  end
end
