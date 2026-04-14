module SolidAgent
  module VectorStore
    class SqliteVecAdapter < Base
      DEFAULT_DIMENSIONS = 1536
      TABLE_NAME = 'solid_agent_vec_entries'

      attr_reader :dimensions

      def initialize(dimensions: DEFAULT_DIMENSIONS)
        @dimensions = dimensions
        @available = false
        @connection = nil
        setup_extension
      end

      def available?
        @available
      end

      def upsert(id:, embedding:, metadata: {})
        return nil unless @available

        true
      end

      def query(embedding:, limit: 10, threshold: 0.7)
        return [] unless @available

        []
      end

      def delete(id:)
        return nil unless @available

        true
      end

      private

      def setup_extension
        raw_conn = ActiveRecord::Base.connection.raw_connection
        return unless raw_conn.respond_to?(:enable_load_extension)

        raw_conn.enable_load_extension(true)
        raw_conn.load_extension('vec0')
        raw_conn.enable_load_extension(false)

        raw_conn.execute(<<~SQL)
          CREATE VIRTUAL TABLE IF NOT EXISTS #{TABLE_NAME}
          USING vec0(embedding float[#{@dimensions}])
        SQL

        @connection = raw_conn
        @available = true
      rescue StandardError
        @available = false
      end

      def serialize_embedding(embedding)
        embedding.pack('f*')
      end
    end
  end
end
