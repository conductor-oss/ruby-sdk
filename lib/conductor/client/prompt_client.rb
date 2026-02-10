# frozen_string_literal: true

module Conductor
  module Client
    # PromptClient - High-level client for prompt template management operations (Orkes)
    class PromptClient
      def initialize(api_client)
        @prompt_api = Http::Api::PromptResourceApi.new(api_client)
      end

      def save_prompt(prompt_name, description, prompt_template, models: nil, version: nil, auto_increment: false)
        @prompt_api.save_prompt(
          prompt_name, prompt_template,
          description: description, models: models,
          version: version, auto_increment: auto_increment
        )
      end

      def get_prompt(prompt_name)
        @prompt_api.get_prompt(prompt_name)
      end

      def get_prompts
        @prompt_api.get_prompts
      end

      def delete_prompt(prompt_name)
        @prompt_api.delete_prompt(prompt_name)
      end

      def get_tags_for_prompt_template(prompt_name)
        @prompt_api.get_tags_for_prompt_template(prompt_name)
      end

      def update_tag_for_prompt_template(prompt_name, tags)
        @prompt_api.update_tag_for_prompt_template(prompt_name, tags)
      end

      def delete_tag_for_prompt_template(prompt_name, tags)
        @prompt_api.delete_tag_for_prompt_template(prompt_name, tags)
      end

      def test_prompt(prompt_text, variables, ai_integration, text_complete_model, temperature: 0.1, top_p: 0.9,
                      stop_words: nil)
        request = Http::Models::PromptTemplateTestRequest.new(
          prompt: prompt_text,
          prompt_variables: variables,
          llm_provider: ai_integration,
          model: text_complete_model,
          temperature: temperature,
          top_p: top_p,
          stop_words: stop_words
        )
        @prompt_api.test_prompt(request)
      end
    end
  end
end
