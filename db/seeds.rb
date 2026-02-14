# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).

# reset the whole app and initialize basic settings

[AppDependency,
App,
CapAccess,
CapWriter,
Db,
DnsAlias,
Host,
Server,
Share,
Theme,
User,
Setting,
WebappAlias,
Webapp].map {|c| c.destroy_all}

Setting.set('net', '192.168.1')
Setting.set('self-address', '10')
Setting.set('domain', 'amahi.net')
Setting.set('api-key', '1b6727c9170b11d6f80437eac13d7a2e143fd895')

# Authlogic 6.x no longer provides password_confirmation= as a virtual attribute
# by default. Set password directly and skip confirmation validation.
admin = User.new(
  login: 'admin',
  name: 'Admin User',
  admin: true,
  pin: nil
)
admin.password = 'secretpassword'
admin.save!(validate: false)

Setting.set('advanced', '1')
Setting.set('theme', 'default')
Setting.set('guest-dashboard', '0')
Setting.set('dns', 'opennic')
Setting.set('dns_ip_1', '173.230.156.28')
Setting.set('dns_ip_2', '23.90.4.6')
Setting.set('dnsmasq_dns', '1')
Setting.set('dnsmasq_dhcp', '1')
Setting.set('initialized', '1')
Setting.set('workgroup', 'WORKGROUP')
