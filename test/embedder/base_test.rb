require 'test_helper'

class EmbedderBaseTest < ActiveSupport::TestCase
  def setup
    @embedder = SolidAgent::Embedder::Base.new
  end

  test 'embed raises NotImplementedError' do
    assert_raises(NotImplementedError) do
      @embedder.embed('test text')
    end
  end
end
