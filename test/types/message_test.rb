require 'test_helper'
require 'solid_agent'

class MessageTest < ActiveSupport::TestCase
  test 'creates text-only message' do
    msg = SolidAgent::Types::Message.new(role: 'user', content: 'Hello')
    assert_equal 'user', msg.role
    assert_equal 'Hello', msg.content
    assert_nil msg.image_url
    assert_nil msg.image_data
  end

  test 'creates message with image URL' do
    msg = SolidAgent::Types::Message.new(
      role: 'user',
      content: 'What is in this image?',
      image_url: 'https://example.com/photo.jpg'
    )
    assert_equal 'What is in this image?', msg.content
    assert_equal 'https://example.com/photo.jpg', msg.image_url
  end

  test 'creates message with base64 image data' do
    msg = SolidAgent::Types::Message.new(
      role: 'user',
      content: 'Describe this',
      image_data: { data: 'iVBORw0KGgo=', media_type: 'image/png' }
    )
    assert_equal 'Describe this', msg.content
    assert_equal 'image/png', msg.image_data[:media_type]
  end

  test 'multimodal? returns false for text-only' do
    msg = SolidAgent::Types::Message.new(role: 'user', content: 'Hello')
    refute msg.multimodal?
  end

  test 'multimodal? returns true with image_url' do
    msg = SolidAgent::Types::Message.new(role: 'user', content: 'Hi', image_url: 'https://example.com/photo.jpg')
    assert msg.multimodal?
  end

  test 'to_hash includes content as array when image_url present' do
    msg = SolidAgent::Types::Message.new(
      role: 'user',
      content: 'What is this?',
      image_url: 'https://example.com/photo.jpg'
    )
    h = msg.to_hash
    assert_equal 'user', h[:role]
    content_parts = h[:content]
    assert content_parts.is_a?(Array)
    assert_equal 2, content_parts.length
    text_part = content_parts.find { |p| p[:type] == 'text' }
    image_part = content_parts.find { |p| p[:type] == 'image_url' }
    assert_equal 'What is this?', text_part[:text]
    assert_equal 'https://example.com/photo.jpg', image_part.dig(:image_url, :url)
  end

  test 'to_hash returns plain string content when no images' do
    msg = SolidAgent::Types::Message.new(role: 'user', content: 'Just text')
    h = msg.to_hash
    assert_equal 'Just text', h[:content]
  end
end
