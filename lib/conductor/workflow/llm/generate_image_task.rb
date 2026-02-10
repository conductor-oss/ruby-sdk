# frozen_string_literal: true

module Conductor
  module Workflow
    module Llm
      # GenerateImageTask - Generate images using an LLM provider
      class GenerateImageTask < TaskInterface
        # @param task_ref_name [String] Unique reference name
        # @param llm_provider [String] LLM provider integration name
        # @param model [String] Image generation model name
        # @param prompt [String] Image generation prompt
        # @param width [Integer] Image width (default: 1024)
        # @param height [Integer] Image height (default: 1024)
        # @param size [String, nil] Image size string (e.g. '1024x1024')
        # @param style [String, nil] Image style
        # @param n [Integer] Number of images (default: 1)
        # @param weight [Float, nil] Prompt weight
        # @param output_format [String] Output format (default: 'png')
        # @param prompt_variables [Hash, nil] Variables for the prompt
        # @param task_name [String, nil] Task definition name
        def initialize(task_ref_name, llm_provider, model, prompt,
                       width: 1024, height: 1024, size: nil, style: nil,
                       n: 1, weight: nil, output_format: 'png',
                       prompt_variables: nil, task_name: nil)
          input_params = {
            'llmProvider' => llm_provider,
            'model' => model,
            'prompt' => prompt,
            'width' => width,
            'height' => height,
            'n' => n,
            'outputFormat' => output_format
          }
          input_params['size'] = size if size
          input_params['style'] = style if style
          input_params['weight'] = weight unless weight.nil?
          input_params['promptVariables'] = prompt_variables if prompt_variables

          super(
            task_reference_name: task_ref_name,
            task_type: TaskType::GENERATE_IMAGE,
            task_name: task_name || 'generate_image',
            input_parameters: input_params
          )
        end
      end
    end
  end
end
