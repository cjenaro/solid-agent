require 'test_helper'

class VectorStoreBaseTest < ActiveSupport::TestCase
  def setup
    @store = SolidAgent::VectorStore::Base.new
  end

  test 'upsert raises NotImplementedError' do
    assert_raises(NotImplementedError) do
      @store.upsert(id: 1, embedding: [0.1, 0.2], metadata: {})
    end
  end

  test 'query raises NotImplementedError' do
    assert_raises(NotImplementedError) do
      @store.query(embedding: [0.1, 0.2], limit: 5, threshold: 0.7)
    end
  end

  test 'delete raises NotImplementedError' do
    assert_raises(NotImplementedError) do
      @store.delete(id: 1)
    end
  end
end
