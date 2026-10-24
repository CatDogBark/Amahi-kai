# LAN only (Network → Devices): a device with a fixed address that keeps the LAN but can't reach
# the internet through the NAS while it's the router. Safe to run again.
class AddLanOnlyToHosts < ActiveRecord::Migration[8.1]
  def change
    add_column :hosts, :lan_only, :boolean, null: false, default: false unless column_exists?(:hosts, :lan_only)
  end
end
