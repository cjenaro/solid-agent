require 'test_helper'
require 'solid_agent/tool/registry'
require 'solid_agent/tool/base'
require 'solid_agent/tool/inline_tool'

class RegistrySearchTool < SolidAgent::Tool::Base
  name :search
  description 'Search'
  parameter :query, type: :string, required: true

  def call(query:)
    "found: #{query}"
  end
end

class ToolRegistryTest < ActiveSupport::TestCase
  def setup
    @registry = SolidAgent::Tool::Registry.new
  end

  test 'register a standalone tool class' do
    @registry.register(RegistrySearchTool)
    assert @registry.registered?('search')
  end

  test 'register an inline tool' do
    tool = SolidAgent::Tool::InlineTool.new(
      name: :calc, description: 'Calculate', parameters: [],
      block: proc { 42 }
    )
    @registry.register(tool)
    assert @registry.registered?('calc')
  end

  test 'lookup returns tool instance' do
    @registry.register(RegistrySearchTool)
    tool = @registry.lookup('search')
    assert_instance_of RegistrySearchTool, tool
  end

  test 'lookup raises for unknown tool' do
    assert_raises(SolidAgent::Error) { @registry.lookup('nonexistent') }
  end

  test 'all_schemas returns array of schemas' do
    @registry.register(RegistrySearchTool)
    inline = SolidAgent::Tool::InlineTool.new(
      name: :ping, description: 'Ping', parameters: [], block: proc { 'pong' }
    )
    @registry.register(inline)
    schemas = @registry.all_schemas
    assert_equal 2, schemas.length
    assert_instance_of SolidAgent::Tool::Schema, schemas.first
  end

  test 'all_schemas_hashes returns MCP-compatible hashes' do
    @registry.register(RegistrySearchTool)
    hashes = @registry.all_schemas_hashes
    assert_equal 1, hashes.length
    assert hashes.first.key?(:inputSchema)
  end

  test 'tool_count' do
    assert_equal 0, @registry.tool_count
    @registry.register(RegistrySearchTool)
    assert_equal 1, @registry.tool_count
  end
end
