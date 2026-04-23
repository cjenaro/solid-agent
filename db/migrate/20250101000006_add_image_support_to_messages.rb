class AddImageSupportToMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :solid_agent_messages, :image_url, :string
    add_column :solid_agent_messages, :image_data, :json
  end
end
