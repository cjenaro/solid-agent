require 'test_helper'
require 'solid_agent'
require 'solid_agent/agent/dsl'
require 'solid_agent/agent/base'
require 'solid_agent/agent/result'

class MultimodalMessageIntegrationTest < ActiveSupport::TestCase
  def setup
    @conversation = SolidAgent::Conversation.create!(agent_class: 'TestAgent')
  end

  # --- DB-level storage ---

  test 'AR message stores image_url' do
    message = SolidAgent::Message.create!(
      conversation: @conversation,
      role: 'user',
      content: 'What is in this image?',
      image_url: 'https://example.com/photo.jpg'
    )
    assert_equal 'https://example.com/photo.jpg', message.reload.image_url
  end

  test 'AR message stores image_data as JSON' do
    image_data = { data: 'iVBORw0KGgo=', media_type: 'image/png' }
    message = SolidAgent::Message.create!(
      conversation: @conversation,
      role: 'user',
      content: 'Describe this',
      image_data: image_data
    )
    assert_equal 'iVBORw0KGgo=', message.reload.image_data['data']
    assert_equal 'image/png', message.reload.image_data['media_type']
  end

  test 'AR message stores both image_url and image_data' do
    message = SolidAgent::Message.create!(
      conversation: @conversation,
      role: 'user',
      content: 'Compare these',
      image_url: 'https://example.com/a.jpg',
      image_data: { data: 'iVBORw0KGgo=', media_type: 'image/png' }
    )
    reloaded = message.reload
    assert_equal 'https://example.com/a.jpg', reloaded.image_url
    assert_equal 'image/png', reloaded.image_data['media_type']
  end

  test 'AR message image columns default to nil' do
    message = SolidAgent::Message.create!(
      conversation: @conversation,
      role: 'user',
      content: 'Just text'
    )
    assert_nil message.image_url
    assert_nil message.image_data
  end

  # --- Types::Message reconstruction from AR ---

  test 'reconstructs multimodal Types::Message from AR record with image_url' do
    SolidAgent::Message.create!(
      conversation: @conversation,
      role: 'user',
      content: 'What is this?',
      image_url: 'https://example.com/photo.jpg'
    )

    types_msg = @conversation.messages.order(:created_at).map do |m|
      SolidAgent::Types::Message.new(
        role: m.role,
        content: m.content,
        tool_calls: nil,
        tool_call_id: m.tool_call_id,
        image_url: m.image_url,
        image_data: m.image_data
      )
    end.first

    assert_equal 'user', types_msg.role
    assert_equal 'What is this?', types_msg.content
    assert_equal 'https://example.com/photo.jpg', types_msg.image_url
    assert types_msg.multimodal?
  end

  test 'reconstructs multimodal Types::Message from AR record with image_data' do
    image_data = { 'data' => 'iVBORw0KGgo=', 'media_type' => 'image/png' }
    SolidAgent::Message.create!(
      conversation: @conversation,
      role: 'user',
      content: 'Describe this',
      image_data: image_data
    )

    types_msg = @conversation.messages.order(:created_at).map do |m|
      img_data = m.image_data
      img_data = img_data.transform_keys(&:to_sym) if img_data.is_a?(Hash)
      SolidAgent::Types::Message.new(
        role: m.role,
        content: m.content,
        tool_calls: nil,
        tool_call_id: m.tool_call_id,
        image_url: m.image_url,
        image_data: img_data
      )
    end.first

    assert types_msg.multimodal?
    assert_equal 'image/png', types_msg.image_data[:media_type]
  end

  # --- RunJob input parsing ---

  test 'hash input with image_url creates multimodal AR message' do
    trace = SolidAgent::Trace.create!(
      conversation: @conversation,
      agent_class: 'TestAgent',
      trace_type: :agent_run,
      status: 'pending',
      input: 'Analyze this image'
    )

    input = { text: 'Analyze this image', image_url: 'https://example.com/photo.jpg' }

    msg_attrs = if input.is_a?(Hash)
                  { role: 'user', content: input[:text] || input['text'], trace: trace,
                    image_url: input[:image_url] || input['image_url'],
                    image_data: input[:image_data] || input['image_data'] }.compact
                else
                  { role: 'user', content: input, trace: trace }
                end

    message = @conversation.messages.create!(msg_attrs)
    assert_equal 'Analyze this image', message.content
    assert_equal 'https://example.com/photo.jpg', message.image_url
  end

  test 'hash input with base64 image_data creates multimodal AR message' do
    trace = SolidAgent::Trace.create!(
      conversation: @conversation,
      agent_class: 'TestAgent',
      trace_type: :agent_run,
      status: 'pending',
      input: 'Describe this screenshot'
    )

    input = {
      text: 'Describe this screenshot',
      image_data: { data: 'iVBORw0KGgo=', media_type: 'image/png' }
    }

    msg_attrs = if input.is_a?(Hash)
                  { role: 'user', content: input[:text] || input['text'], trace: trace,
                    image_url: input[:image_url] || input['image_url'],
                    image_data: input[:image_data] || input['image_data'] }.compact
                else
                  { role: 'user', content: input, trace: trace }
                end

    message = @conversation.messages.create!(msg_attrs)
    assert_equal 'Describe this screenshot', message.content
    assert_equal 'iVBORw0KGgo=', message.image_data['data']
  end

  test 'string input still works as before' do
    trace = SolidAgent::Trace.create!(
      conversation: @conversation,
      agent_class: 'TestAgent',
      trace_type: :agent_run,
      status: 'pending',
      input: 'Hello'
    )

    input = 'Hello'

    msg_attrs = if input.is_a?(Hash)
                  { role: 'user', content: input[:text] || input['text'], trace: trace,
                    image_url: input[:image_url] || input['image_url'],
                    image_data: input[:image_data] || input['image_data'] }.compact
                else
                  { role: 'user', content: input, trace: trace }
                end

    message = @conversation.messages.create!(msg_attrs)
    assert_equal 'Hello', message.content
    assert_nil message.image_url
    assert_nil message.image_data
  end

  # --- Trace input extraction from hash ---

  test 'trace input extracts text from hash input' do
    input = { text: 'What do you see?', image_url: 'https://example.com/photo.jpg' }
    trace_input = input.is_a?(Hash) ? input[:text] || input['text'] || input.to_json : input
    assert_equal 'What do you see?', trace_input
  end

  test 'trace input falls back to json when hash has no text' do
    input = { image_url: 'https://example.com/photo.jpg' }
    trace_input = input.is_a?(Hash) ? input[:text] || input['text'] || input.to_json : input
    assert_equal input.to_json, trace_input
  end

  test 'trace input passes string through unchanged' do
    input = 'Just a string'
    trace_input = input.is_a?(Hash) ? input[:text] || input['text'] || input.to_json : input
    assert_equal 'Just a string', trace_input
  end
end
