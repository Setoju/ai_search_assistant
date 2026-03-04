class CreateUserMemories < ActiveRecord::Migration[8.0]
  def change
    create_table :user_memories do |t|
      t.references :user, null: false, foreign_key: true
      t.text :fact, null: false
      t.string :category, null: false
      t.float :embedding, array: true, default: []
      t.bigint :source_message_id
      t.datetime :source_message_at

      t.timestamps
    end

    add_index :user_memories, :category
    add_index :user_memories, [:user_id, :category]
  end
end
