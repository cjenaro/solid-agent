class CreateSolidAgentMemoryEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :solid_agent_memory_entries do |t|
      t.references :conversation, foreign_key: { to_table: :solid_agent_conversations }
      t.string :agent_class
      t.string :entry_type, null: false
      t.text :content, null: false
      t.json :metadata, default: {}
      t.datetime :expires_at
      t.timestamps
    end

    add_index :solid_agent_memory_entries, :agent_class
    add_index :solid_agent_memory_entries, :entry_type
  end
end
