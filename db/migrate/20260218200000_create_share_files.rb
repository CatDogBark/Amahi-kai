class CreateShareFiles < ActiveRecord::Migration[8.0]
  def change
    create_table :share_files do |t|
      t.references :share, null: false, foreign_key: true, type: :integer
      t.string :name, null: false          # filename
      t.string :path, null: false           # full path on disk
      t.string :relative_path, null: false  # path relative to share root
      t.string :content_type               # mime type category: file, image, audio, video, document
      t.string :extension                  # file extension (lowercase, no dot)
      t.bigint :size, default: 0           # file size in bytes
      t.boolean :directory, default: false  # true if directory
      t.datetime :file_modified_at         # filesystem mtime
      t.timestamps
    end

    add_index :share_files, :name
    add_index :share_files, :extension
    add_index :share_files, :content_type
    add_index :share_files, [:share_id, :relative_path], unique: true
    add_index :share_files, :directory
  end
end
