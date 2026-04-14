require 'test_helper'
require 'solid_agent/configuration'
require 'solid_agent/model'
require 'solid_agent/models/open_ai'

class ConfigurationTest < ActiveSupport::TestCase
  def setup
    @config = SolidAgent::Configuration.new
  end

  test 'has default provider' do
    assert_equal :openai, @config.default_provider
  end

  test 'has default model' do
    assert_equal SolidAgent::Models::OpenAi::GPT_4O, @config.default_model
  end

  test 'dashboard is enabled by default' do
    assert_equal true, @config.dashboard_enabled
  end

  test 'default dashboard route prefix' do
    assert_equal 'solid_agent', @config.dashboard_route_prefix
  end

  test 'default vector store is sqlite_vec' do
    assert_equal :sqlite_vec, @config.vector_store
  end

  test 'default http adapter is net_http' do
    assert_equal :net_http, @config.http_adapter
  end

  test 'default trace retention is 30 days' do
    assert_equal 30.days, @config.trace_retention
  end

  test 'providers config is a hash' do
    assert_instance_of Hash, @config.providers
  end

  test 'mcp_clients config is a hash' do
    assert_instance_of Hash, @config.mcp_clients
  end

  test 'embedding configuration defaults' do
    assert_equal :openai, @config.embedding_provider
    assert_equal 'text-embedding-3-small', @config.embedding_model
  end

  test 'validates with valid config' do
    @config.default_provider = :openai
    assert_nil @config.validate!
  end

  test 'accepts custom http adapter class' do
    custom_adapter = Class.new { def call(req); end }
    @config.http_adapter = custom_adapter
    assert_equal custom_adapter, @config.http_adapter
  end

  test 'accepts custom vector store class' do
    custom_store = Class.new { def upsert(**); end }
    @config.vector_store = custom_store
    assert_equal custom_store, @config.vector_store
  end
end
