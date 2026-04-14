require 'test_helper'
require 'solid_agent/model'
require 'solid_agent/models/open_ai'
require 'solid_agent/models/anthropic'
require 'solid_agent/models/google'
require 'solid_agent/models/mistral'
require 'solid_agent/models/ollama'

class ModelTest < ActiveSupport::TestCase
  test 'Model stores id, context_window, max_output' do
    model = SolidAgent::Model.new('test-model', context_window: 128_000, max_output: 16_384)
    assert_equal 'test-model', model.id
    assert_equal 128_000, model.context_window
    assert_equal 16_384, model.max_output
  end

  test 'Model stores pricing' do
    model = SolidAgent::Model.new('test', context_window: 128_000, max_output: 16_384, input_price_per_million: 2.5,
                                          output_price_per_million: 10.0)
    assert_equal 2.5, model.input_price_per_million
    assert_equal 10.0, model.output_price_per_million
  end

  test 'Model is frozen' do
    assert SolidAgent::Models::OpenAi::GPT_4O.frozen?
  end

  test 'Model to_s returns id' do
    assert_equal 'gpt-4o', SolidAgent::Models::OpenAi::GPT_4O.to_s
  end

  test 'OpenAI constants' do
    assert_equal 'gpt-4o', SolidAgent::Models::OpenAi::GPT_4O.id
    assert_equal 128_000, SolidAgent::Models::OpenAi::GPT_4O.context_window
    assert_equal 2.5, SolidAgent::Models::OpenAi::GPT_4O.input_price_per_million
  end

  test 'Anthropic constants' do
    assert_equal 'claude-sonnet-4-0', SolidAgent::Models::Anthropic::CLAUDE_SONNET_4.id
    assert_equal 200_000, SolidAgent::Models::Anthropic::CLAUDE_SONNET_4.context_window
  end

  test 'Google constants' do
    assert_equal 'gemini-2.5-pro', SolidAgent::Models::Google::GEMINI_2_5_PRO.id
    assert_equal 1_048_576, SolidAgent::Models::Google::GEMINI_2_5_PRO.context_window
  end

  test 'Mistral constants' do
    assert_equal 'mistral-large-2512', SolidAgent::Models::Mistral::MISTRAL_LARGE.id
    assert_equal 262_144, SolidAgent::Models::Mistral::MISTRAL_LARGE.context_window
  end

  test 'Ollama constants have no pricing' do
    assert_equal 0, SolidAgent::Models::Ollama::LLAMA_3_3_70B.input_price_per_million
  end
end
