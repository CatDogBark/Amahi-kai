# Port forwards (Network → DNS & DHCP, router mode): a port on the internet side let in to a
# device on the LAN. The address is the last part of the device's address on DHCP's network, as
# a fixed host's is. Safe to run again.
class CreatePortForwards < ActiveRecord::Migration[8.1]
  def change
    create_table :port_forwards, if_not_exists: true do |t|
      t.string :name, null: false, default: ''
      t.string :protocol, null: false, default: 'tcp'
      t.integer :port, null: false
      t.string :address, null: false
      t.integer :to_port, null: false
      t.index %i[protocol port], unique: true
    end
  end
end
