# Installs used to be seeded with the domain amahi.net, the old Amahi project's real domain:
# dnsmasq would answer for it on the LAN (local=/amahi.net/), and Samba's lmhosts named the
# server under it. home.arpa is the name kept for home networks. A domain set to anything
# else is left alone; running this again changes nothing.
class MoveDomainOffAmahiNet < ActiveRecord::Migration[8.0]
  def up
    execute "UPDATE settings SET value = 'home.arpa' WHERE name = 'domain' AND value = 'amahi.net'"
  end

  def down
    # Nothing to undo: home.arpa works with the code from before.
  end
end
