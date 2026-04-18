class CreateSolidAgentMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :solid_agent_messages do |t|
      t.references :conversation, null: false, foreign_key: { to_table: :solid_agent_conversations }
      t.references :trace, foreign_key: { to_table: :solid_agent_traces }
      t.string :role, null: false
      t.text :content
      t.string :tool_call_id
      t.json :metadata, default: {}
      t.timestamps
    end

    add_index :solid_agent_messages, :role
  end
end
