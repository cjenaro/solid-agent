require 'test_helper'
require 'solid_agent'

class ProviderRegistryTest < ActiveSupport::TestCase
  def setup
    @registry = SolidAgent::Provider::Registry.new
  end

  test 'registers a provider' do
    @registry.register(:test) { { api_key: 'key' } }
    assert @registry.registered?(:test)
  end

  test 'resolves registered provider' do
    @registry.register(:test) { { api_key: 'key' } }
    assert_instance_of Hash, @registry.resolve(:test)
  end

  test 'raises for unknown provider' do
    assert_raises(SolidAgent::Error) { @registry.resolve(:nonexistent) }
  end

  test 'lists registered providers' do
    @registry.register(:openai) { { api_key: 'key1' } }
    @registry.register(:anthropic) { { api_key: 'key2' } }
    assert_equal %i[openai anthropic], @registry.names
  end
end
