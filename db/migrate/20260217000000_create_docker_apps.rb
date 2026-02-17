class CreateDockerApps < ActiveRecord::Migration[5.1]
  def change
    create_table :docker_apps do |t|
      t.string :identifier, null: false
      t.string :name, null: false
      t.text :description
      t.string :image, null: false
      t.string :container_name
      t.string :status, default: 'available'
      t.string :category
      t.string :logo_url
      t.string :version
      t.integer :host_port
      t.text :port_mappings
      t.text :volume_mappings
      t.text :environment
      t.boolean :show_in_dashboard, default: true
      t.text :error_message
      t.timestamps
    end
    add_index :docker_apps, :identifier, unique: true
  end
end
