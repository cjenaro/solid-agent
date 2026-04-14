module SolidAgent
  module VectorStore
    class Base
      def upsert(id:, embedding:, metadata: {})
        raise NotImplementedError, "#{self.class}#upsert must be implemented"
      end

      def query(embedding:, limit: 10, threshold: 0.7)
        raise NotImplementedError, "#{self.class}#query must be implemented"
      end

      def delete(id:)
        raise NotImplementedError, "#{self.class}#delete must be implemented"
      end
    end
  end
end
