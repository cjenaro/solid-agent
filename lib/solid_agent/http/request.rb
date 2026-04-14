module SolidAgent
  module HTTP
    Request = Struct.new(:method, :url, :headers, :body, :stream, keyword_init: true)
  end
end
