require 'test_helper'

class SqliteVecAdapterTest < ActiveSupport::TestCase
  def setup
    @adapter = SolidAgent::VectorStore::SqliteVecAdapter.new(dimensions: 8)
  end

  test 'initializes with dimensions' do
    assert_equal 8, @adapter.dimensions
  end

  test 'default dimensions is 1536' do
    adapter = SolidAgent::VectorStore::SqliteVecAdapter.new
    assert_equal 1536, adapter.dimensions
  end

  test 'available? returns boolean' do
    assert [true, false].include?(@adapter.available?)
  end

  test 'upsert returns nil when not available' do
    unless @adapter.available?
      result = @adapter.upsert(id: 1, embedding: [0.1] * 8, metadata: {})
      assert_nil result
    end
  end

  test 'query returns empty array when not available' do
    unless @adapter.available?
      result = @adapter.query(embedding: [0.1] * 8, limit: 5, threshold: 0.5)
      assert_equal [], result
    end
  end

  test 'delete returns nil when not available' do
    unless @adapter.available?
      result = @adapter.delete(id: 1)
      assert_nil result
    end
  end

  test 'serialize_embedding produces binary string' do
    embedding = [0.1, 0.2, 0.3]
    blob = @adapter.send(:serialize_embedding, embedding)
    assert_instance_of String, blob
    assert blob.bytesize > 0
  end

  test 'serialize_embedding round-trips correctly' do
    embedding = [0.1, 0.2, 0.3, 0.4]
    blob = @adapter.send(:serialize_embedding, embedding)
    restored = blob.unpack('f*')
    embedding.each_with_index do |val, i|
      assert_in_delta val, restored[i], 0.001
    end
  end
end
