class AddTitleToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :title, :string
  end
end
