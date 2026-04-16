class CreateSolidAgentTraces < ActiveRecord::Migration[7.1]
  def change
    create_table :solid_agent_traces do |t|
      t.references :conversation, null: false, foreign_key: { to_table: :solid_agent_conversations }
      t.references :parent_trace, foreign_key: { to_table: :solid_agent_traces }
      t.string :agent_class, null: false
      t.string :trace_type, null: false, default: 'agent_run'
      t.string :status, null: false, default: 'pending'
      t.text :input
      t.text :output
      t.json :usage, default: {}
      t.integer :iteration_count, default: 0
      t.text :error
      t.string :otel_trace_id
      t.string :otel_span_id
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :solid_agent_traces, :status
    add_index :solid_agent_traces, :agent_class
    add_index :solid_agent_traces, :otel_trace_id
  end
end
