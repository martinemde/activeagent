# spec/lib/active_agent/generation_provider/open_ai_provider_spec.rb
require "active_agent/generation_provider/open_ai_provider"

RSpec.describe ActiveAgent::GenerationProvider::OpenAIProvider do
  let(:api_key) { "test-api-key" }
  let(:model) { "gpt-4" }
  let(:temperature) { 0.5 }

  let(:config) do
    {
      "api_key" => api_key,
      "model" => model,
      "temperature" => temperature,
      "service" => "openai"
    }
  end

  let(:message) { instance_double(ActiveAgent::ActionPrompt::Message, content: "Hello", role: "user") }
  let(:messages) { [{role: "user", content: "Hello"}] }
  let(:actions) { [{name: "test_action", parameters: {}}] }

  let(:mock_prompt) do
    instance_double("ActiveAgent::ActionPrompt::Prompt",
      messages: messages,
      actions: actions,
      options: {stream: false},
      message: message).tap do |prompt|
      allow(prompt).to receive(:message=)
      allow(prompt.messages).to receive(:<<)
    end
  end

  let(:mock_client) { instance_double(OpenAI::Client) }

  before do
    allow(OpenAI::Client).to receive(:new).and_return(mock_client)
  end

  describe "#initialize" do
    it "sets default model name when not provided" do
      config.delete("model")
      provider = described_class.new(config)
      expect(provider.instance_variable_get(:@model_name)).to eq("gpt-4o-mini")
    end

    it "uses provided model name" do
      provider = described_class.new(config)
      expect(provider.instance_variable_get(:@model_name)).to eq(model)
    end

    it "initializes OpenAI client with API key" do
      expect(OpenAI::Client).to receive(:new).with(api_key: api_key)
      described_class.new(config)
    end
  end

  describe "#generate" do
    let(:provider) { described_class.new(config) }
    let(:expected_params) do
      {
        messages: messages,
        temperature: temperature,
        tools: actions,
        model: model
      }
    end

    let(:mock_response) do
      {
        "choices" => [{
          "message" => {
            "content" => "Test response",
            "role" => "assistant",
            "finish_reason" => "stop"
          }
        }]
      }
    end

    before do
      allow(mock_client).to receive(:chat).and_return(mock_response)
    end

    it "sends correct parameters to OpenAI" do
      expect(mock_client).to receive(:chat).with(parameters: hash_including(expected_params))
      provider.generate(mock_prompt)
    end

    it "excludes api_key, instructions, and service from parameters" do
      provider.generate(mock_prompt)
      expect(mock_client).to have_received(:chat) do |args|
        expect(args[:parameters].keys).not_to include("api_key", :instructions, "service")
      end
    end

    context "with streaming" do
      let(:stream_proc) { proc { |chunk| } }

      before do
        allow(mock_prompt).to receive(:options).and_return({stream: true})
      end

      it "includes stream parameter when streaming is enabled" do
        expect(mock_client).to receive(:chat).with(
          parameters: hash_including(stream: kind_of(Proc))
        )
        provider.generate(mock_prompt)
      end
    end

    context "with error handling" do
      it "wraps OpenAI errors in GenerationProviderError" do
        allow(mock_client).to receive(:chat).and_raise(StandardError, "API Error")
        expect {
          provider.generate(mock_prompt)
        }.to raise_error(ActiveAgent::GenerationProvider::Base::GenerationProviderError, "API Error")
      end
    end
  end

  describe "#prompt_parameters" do
    let(:provider) { described_class.new(config) }

    before do
      provider.instance_variable_set(:@prompt, mock_prompt)
    end

    it "includes messages from prompt" do
      expect(provider.send(:prompt_parameters)[:messages]).to eq(messages)
    end

    it "includes temperature from config" do
      expect(provider.send(:prompt_parameters)[:temperature]).to eq(temperature)
    end

    it "includes tools from prompt actions" do
      expect(provider.send(:prompt_parameters)[:tools]).to eq(actions)
    end
  end
  describe "#embed" do
    let(:provider) { described_class.new(config) }
    let(:embedding_response) do
      {
        "data" => [{
          "embedding" => [0.1, 0.2, 0.3]
        }]
      }
    end

    before do
      allow(mock_client).to receive(:embeddings).and_return(embedding_response)
    end

    it "calls embeddings with correct parameters" do
      expected_params = {
        model: "text-embedding-ada-002",
        input: "Hello"
      }
      expect(mock_client).to receive(:embeddings).with(parameters: expected_params)
      provider.embed(mock_prompt)
    end

    it "wraps response in Response object with embedding data" do
      response = provider.embed(mock_prompt)
      expect(response).to be_a(ActiveAgent::GenerationProvider::Response)
      expect(response.message.content).to eq([0.1, 0.2, 0.3])
    end

    it "handles errors appropriately" do
      allow(mock_client).to receive(:embeddings).and_raise(StandardError, "API Error")
      expect {
        provider.embed(mock_prompt)
      }.to raise_error(ActiveAgent::GenerationProvider::Base::GenerationProviderError, "API Error")
    end
  end

  describe "#embeddings_parameters" do
    let(:provider) { described_class.new(config) }

    before do
      provider.instance_variable_set(:@prompt, mock_prompt)
    end

    it "returns correct parameters structure" do
      params = provider.embeddings_parameters
      expect(params).to eq({
        model: "text-embedding-ada-002",
        input: "Hello"
      })
    end

    it "allows custom model override" do
      params = provider.embeddings_parameters(model: "custom-model")
      expect(params[:model]).to eq("custom-model")
    end

    it "allows custom input override" do
      params = provider.embeddings_parameters(input: "Custom input")
      expect(params[:input]).to eq("Custom input")
    end
  end

  describe "#embeddings_response" do
    let(:provider) { described_class.new(config) }
    let(:embedding_data) do
      {
        "data" => [{
          "embedding" => [0.1, 0.2, 0.3]
        }]
      }
    end

    before do
      provider.instance_variable_set(:@prompt, mock_prompt)
    end

    it "creates response with embedding data" do
      response = provider.embeddings_response(embedding_data)
      expect(response).to be_a(ActiveAgent::GenerationProvider::Response)
      expect(response.message.content).to eq([0.1, 0.2, 0.3])
      expect(response.message.role).to eq("assistant")
    end
  end
end
