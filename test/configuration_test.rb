require 'test_helper'
require 'solid_agent/configuration'
require 'solid_agent/model'
require 'solid_agent/models/open_ai'
require 'solid_agent/telemetry/exporter'
require 'solid_agent/telemetry/null_exporter'
require 'solid_agent/telemetry/otlp_exporter'

module SolidAgent
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end

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

  test 'telemetry_exporters defaults to NullExporter' do
    SolidAgent.reset_configuration!
    assert_instance_of SolidAgent::Telemetry::NullExporter,
                       SolidAgent.configuration.telemetry_exporters.first
  end

  test 'telemetry_exporters can be set to custom exporters' do
    exporter = SolidAgent::Telemetry::OTLPExporter.new(endpoint: 'http://jaeger:4318/v1/traces')
    SolidAgent.configure do |config|
      config.telemetry_exporters = [exporter]
    end
    assert_equal 1, SolidAgent.configuration.telemetry_exporters.length
    assert_instance_of SolidAgent::Telemetry::OTLPExporter, SolidAgent.configuration.telemetry_exporters.first
  end

  test 'telemetry_exporters can have multiple exporters' do
    SolidAgent.configure do |config|
      config.telemetry_exporters = [
        SolidAgent::Telemetry::NullExporter.new,
        SolidAgent::Telemetry::OTLPExporter.new
      ]
    end
    assert_equal 2, SolidAgent.configuration.telemetry_exporters.length
  end
end
