# Minimum data for a new install: the admin account and default settings.
#
# Seeds only run on an empty database. bin/amahi-install runs db:seed on every
# install, including a re-run on a live system, and this file used to start by
# calling destroy_all on users, shares, apps and settings; User.destroy_all also
# ran `userdel -r` for every user. Nothing here deletes data any more.
if User.exists?
  puts "Database already has users; not seeding." unless Rails.env.test?
  return
end

Setting.set('net', '192.168.1')
Setting.set('self-address', '10')
Setting.set('domain', 'amahi.net')

# The setup wizard won't finish until this password is changed.
admin = User.new(
  login: User::SEED_ADMIN_LOGIN,
  name: 'Admin User',
  password: User::SEED_ADMIN_PASSWORD,
  password_confirmation: User::SEED_ADMIN_PASSWORD,
  admin: true,
  role: 'admin'
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
