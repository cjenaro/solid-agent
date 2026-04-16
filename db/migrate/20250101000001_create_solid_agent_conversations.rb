class CreateSolidAgentConversations < ActiveRecord::Migration[7.1]
  def change
    create_table :solid_agent_conversations do |t|
      t.string :agent_class, null: false
      t.string :status, default: 'active', null: false
      t.string :title
      t.json :metadata, default: {}
      t.timestamps
    end

    add_index :solid_agent_conversations, :agent_class
    add_index :solid_agent_conversations, :status
  end
end
