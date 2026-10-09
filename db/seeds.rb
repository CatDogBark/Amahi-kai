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

# The admin's first password. bin/amahi-install makes a random one and passes it in a file
# only the app user can read (AMAHI_FIRST_PASSWORD_FILE), never on a command line, and prints
# it. Development and tests use User::SEED_ADMIN_PASSWORD; production won't seed with that
# one, since it's public. The setup wizard won't finish until the first password is changed.
# Deleting the file once it's read tells the installer the password was used (seeding is
# skipped when users exist, and then nothing should print it).
first_password = if (file = ENV['AMAHI_FIRST_PASSWORD_FILE'].presence)
                   File.read(file).strip.tap { File.delete(file) }
                 elsif Rails.env.production?
                   raise 'db:seed needs AMAHI_FIRST_PASSWORD_FILE in production (bin/amahi-install sets it)'
                 else
                   User::SEED_ADMIN_PASSWORD
                 end
raise "the first admin password in #{file} is shorter than 12 characters" if first_password.length < 12 && file

admin = User.new(
  login: User::SEED_ADMIN_LOGIN,
  name: 'Admin User',
  password: first_password,
  password_confirmation: first_password,
  admin: true,
  role: 'admin'
)
admin.save!(validate: false)
Setting.set(User::FIRST_PASSWORD_SETTING, admin.password_digest)

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
