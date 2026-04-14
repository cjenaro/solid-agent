module SolidAgent
  module Embedder
    class Base
      def embed(text)
        raise NotImplementedError, "#{self.class}#embed must be implemented"
      end
    end
  end
end
