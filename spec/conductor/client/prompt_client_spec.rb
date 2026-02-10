# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Conductor::Client::PromptClient do
  let(:api_client) { instance_double(Conductor::Http::ApiClient) }
  let(:prompt_api) { instance_double(Conductor::Http::Api::PromptResourceApi) }
  let(:client) { described_class.new(api_client) }

  before do
    allow(Conductor::Http::Api::PromptResourceApi).to receive(:new).with(api_client).and_return(prompt_api)
  end

  describe '#save_prompt' do
    it 'delegates with correct argument mapping' do
      expect(prompt_api).to receive(:save_prompt).with(
        'my_prompt', 'Hello ${name}',
        description: 'A greeting prompt',
        models: ['gpt-4'],
        version: nil,
        auto_increment: false
      )
      client.save_prompt('my_prompt', 'A greeting prompt', 'Hello ${name}', models: ['gpt-4'])
    end

    it 'passes all optional parameters' do
      expect(prompt_api).to receive(:save_prompt).with(
        'p1', 'template text',
        description: 'desc',
        models: ['gpt-4', 'claude'],
        version: 2,
        auto_increment: true
      )
      client.save_prompt('p1', 'desc', 'template text', models: ['gpt-4', 'claude'], version: 2, auto_increment: true)
    end
  end

  describe '#get_prompt' do
    it 'delegates to prompt_api' do
      expect(prompt_api).to receive(:get_prompt).with('my_prompt')
      client.get_prompt('my_prompt')
    end
  end

  describe '#get_prompts' do
    it 'delegates to prompt_api' do
      expect(prompt_api).to receive(:get_prompts).and_return([])
      result = client.get_prompts
      expect(result).to eq([])
    end
  end

  describe '#delete_prompt' do
    it 'delegates to prompt_api' do
      expect(prompt_api).to receive(:delete_prompt).with('old_prompt')
      client.delete_prompt('old_prompt')
    end
  end

  describe '#get_tags_for_prompt_template' do
    it 'delegates to prompt_api' do
      expect(prompt_api).to receive(:get_tags_for_prompt_template).with('my_prompt').and_return([])
      client.get_tags_for_prompt_template('my_prompt')
    end
  end

  describe '#update_tag_for_prompt_template' do
    it 'delegates to prompt_api' do
      tags = [double('tag')]
      expect(prompt_api).to receive(:update_tag_for_prompt_template).with('my_prompt', tags)
      client.update_tag_for_prompt_template('my_prompt', tags)
    end
  end

  describe '#delete_tag_for_prompt_template' do
    it 'delegates to prompt_api' do
      tags = [double('tag')]
      expect(prompt_api).to receive(:delete_tag_for_prompt_template).with('my_prompt', tags)
      client.delete_tag_for_prompt_template('my_prompt', tags)
    end
  end

  describe '#test_prompt' do
    it 'constructs PromptTemplateTestRequest and delegates' do
      expect(prompt_api).to receive(:test_prompt) do |req|
        expect(req).to be_a(Conductor::Http::Models::PromptTemplateTestRequest)
        expect(req.prompt).to eq('Hello ${name}')
        expect(req.prompt_variables).to eq({ 'name' => 'World' })
        expect(req.llm_provider).to eq('openai')
        expect(req.model).to eq('gpt-4')
        expect(req.temperature).to eq(0.1)
        expect(req.top_p).to eq(0.9)
        expect(req.stop_words).to be_nil
      end

      client.test_prompt('Hello ${name}', { 'name' => 'World' }, 'openai', 'gpt-4')
    end

    it 'passes optional temperature, top_p, and stop_words' do
      expect(prompt_api).to receive(:test_prompt) do |req|
        expect(req.temperature).to eq(0.7)
        expect(req.top_p).to eq(0.5)
        expect(req.stop_words).to eq(['STOP', 'END'])
      end

      client.test_prompt('test', {}, 'openai', 'gpt-4',
                         temperature: 0.7, top_p: 0.5, stop_words: ['STOP', 'END'])
    end
  end
end
