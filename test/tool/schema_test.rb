require 'test_helper'
require 'solid_agent/tool/schema'

class ToolSchemaTest < ActiveSupport::TestCase
  test 'creates schema from hash' do
    schema = SolidAgent::Tool::Schema.new(
      name: 'web_search',
      description: 'Search the web',
      input_schema: {
        type: 'object',
        properties: { query: { type: 'string' } },
        required: ['query']
      }
    )
    assert_equal 'web_search', schema.name
    assert_equal 'Search the web', schema.description
    assert_equal 'string', schema.input_schema[:properties][:query][:type]
  end

  test 'to_hash returns MCP-compatible format' do
    schema = SolidAgent::Tool::Schema.new(
      name: 'search',
      description: 'Search',
      input_schema: { type: 'object', properties: { q: { type: 'string' } } }
    )
    h = schema.to_hash
    assert_equal 'search', h[:name]
    assert_equal 'Search', h[:description]
    assert h.key?(:inputSchema)
  end

  test 'validates required fields' do
    assert_raises(ArgumentError) do
      SolidAgent::Tool::Schema.new(name: nil, description: 'test', input_schema: {})
    end
  end
end
