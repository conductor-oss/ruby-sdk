# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # GenerateAudioTask - Generate audio using an LLM provider (text-to-speech)
      class GenerateAudioTask < TaskInterface
        # @param task_ref_name [String] Unique reference name
        # @param llm_provider [String] LLM provider integration name
        # @param model [String] Audio generation model name
        # @param text [String, nil] Text to convert to audio
        # @param voice [String, nil] Voice selection
        # @param speed [Float, nil] Playback speed
        # @param response_format [String, nil] Output audio format
        # @param n [Integer] Number of outputs (default: 1)
        # @param prompt [String, nil] Prompt template name
        # @param prompt_variables [Hash, nil] Variables for the prompt
        # @param task_name [String, nil] Task definition name
        def initialize(task_ref_name, llm_provider, model,
                       text: nil, voice: nil, speed: nil,
                       response_format: nil, n: 1, prompt: nil,
                       prompt_variables: nil, task_name: nil)
          input_params = {
            'llmProvider' => llm_provider,
            'model' => model,
            'n' => n
          }
          input_params['text'] = text if text
          input_params['voice'] = voice if voice
          input_params['speed'] = speed unless speed.nil?
          input_params['responseFormat'] = response_format if response_format
          input_params['prompt'] = prompt if prompt
          input_params['promptVariables'] = prompt_variables if prompt_variables

          super(
            task_reference_name: task_ref_name,
            task_type: TaskType::GENERATE_AUDIO,
            task_name: task_name || 'generate_audio',
            input_parameters: input_params
          )
        end
      end
    end
  end
end
