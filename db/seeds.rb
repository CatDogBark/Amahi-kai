# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).

# reset the whole app and initialize basic settings

[CapAccess,
CapWriter,
Db,
DnsAlias,
DockerApp,
Host,
Server,
Share,
Theme,
User,
Setting].map {|c| c.destroy_all}

Setting.set('net', '192.168.1')
Setting.set('self-address', '10')
Setting.set('domain', 'amahi.net')
Setting.set('api-key', '1b6727c9170b11d6f80437eac13d7a2e143fd895')

admin = User.new(
  login: 'admin',
  name: 'Admin User',
  password: 'secretpassword',
  password_confirmation: 'secretpassword',
  admin: true,
  role: 'admin',
  pin: nil
)
admin.save!(validate: false)

Setting.set('advanced', '1')
Setting.set('theme', 'amahi-kai')
Setting.set('guest-dashboard', '0')
Setting.set('dns', 'cloudflare')
Setting.set('dns_ip_1', '1.1.1.1')
Setting.set('dns_ip_2', '1.0.0.1')
Setting.set('dnsmasq_dns', '1')
Setting.set('dnsmasq_dhcp', '1')
Setting.set('initialized', '1')
Setting.set('workgroup', 'WORKGROUP')
Setting.set('setup_completed', 'false')
