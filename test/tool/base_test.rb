require 'test_helper'
require 'solid_agent/tool/base'

class WebSearchTool < SolidAgent::Tool::Base
  name :web_search
  description 'Search the web for information'

  parameter :query, type: :string, required: true, description: 'Search query'
  parameter :max_results, type: :integer, default: 5, description: 'Max results'

  def call(query:, max_results: 5)
    "Results for: #{query} (max #{max_results})"
  end
end

class ToolBaseTest < ActiveSupport::TestCase
  test 'tool has name' do
    assert_equal 'web_search', WebSearchTool.tool_name
  end

  test 'tool has description' do
    assert_equal 'Search the web for information', WebSearchTool.tool_description
  end

  test 'tool has parameters' do
    params = WebSearchTool.tool_parameters
    assert_equal 2, params.length
    query_param = params.find { |p| p[:name] == :query }
    assert_equal :string, query_param[:type]
    assert query_param[:required]
  end

  test 'tool generates JSON Schema from parameters' do
    schema = WebSearchTool.to_schema
    assert_instance_of SolidAgent::Tool::Schema, schema
    assert_equal 'web_search', schema.name
    assert_equal 'string', schema.input_schema[:properties][:query][:type]
    assert_includes schema.input_schema[:required], 'query'
  end

  test 'tool execute calls the call method' do
    tool = WebSearchTool.new
    result = tool.execute({ 'query' => 'test search' })
    assert_equal 'Results for: test search (max 5)', result
  end

  test 'tool execute uses defaults for missing optional params' do
    tool = WebSearchTool.new
    result = tool.execute({ 'query' => 'test' })
    assert_includes result, 'max 5'
  end

  test 'tool execute raises on missing required params' do
    tool = WebSearchTool.new
    assert_raises(ArgumentError) { tool.execute({}) }
  end
end
