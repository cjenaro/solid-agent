require 'test_helper'
require 'solid_agent/tool/inline_tool'

class InlineToolTest < ActiveSupport::TestCase
  test 'creates inline tool from block' do
    tool = SolidAgent::Tool::InlineTool.new(
      name: :greet,
      description: 'Say hello',
      parameters: [{ name: :name, type: :string, required: true, description: 'Person name' }],
      block: proc { |name:| "Hello, #{name}!" }
    )
    assert_equal 'greet', tool.schema.name
    assert_equal 'Hello, World!', tool.execute({ 'name' => 'World' })
  end

  test 'generates schema from parameters' do
    tool = SolidAgent::Tool::InlineTool.new(
      name: :add,
      description: 'Add numbers',
      parameters: [
        { name: :a, type: :integer, required: true },
        { name: :b, type: :integer, required: true }
      ],
      block: proc { |a:, b:| a + b }
    )
    schema = tool.schema
    assert_equal 'add', schema.name
    assert_equal 2, schema.input_schema[:required].length
  end

  test 'inline tool without parameters' do
    tool = SolidAgent::Tool::InlineTool.new(
      name: :ping,
      description: 'Ping',
      parameters: [],
      block: proc { 'pong' }
    )
    assert_equal 'pong', tool.execute({})
  end
end
