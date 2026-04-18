class CreateSolidAgentSpans < ActiveRecord::Migration[7.1]
  def change
    create_table :solid_agent_spans do |t|
      t.references :trace, null: false, foreign_key: { to_table: :solid_agent_traces }
      t.references :parent_span, foreign_key: { to_table: :solid_agent_spans }
      t.string :span_type, null: false
      t.string :name, null: false
      t.string :status, null: false, default: 'pending'
      t.text :input
      t.text :output
      t.json :metadata, default: {}
      t.integer :tokens_in, default: 0
      t.integer :tokens_out, default: 0
      t.string :otel_span_id
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :solid_agent_spans, :span_type
  end
end
