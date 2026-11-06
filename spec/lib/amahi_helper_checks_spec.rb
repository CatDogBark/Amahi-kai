require 'rails_helper'
require 'tmpdir'

# Every argument of every root helper operation against values it mustn't take, with the helper's
# own checks running: only what they read from the machine stands in (a small NAS, in the before
# block), never a check itself. A request is altered one argument at a time, and each alteration
# must be refused, unless the table says the argument may hold it and why.
#
# A new operation or argument fails here until it's listed.
RSpec.describe 'AmahiHelper: the checks on every argument' do
  let(:helper) { AmahiHelper }

  fake = File.join(Dir.tmpdir, "amahi-helper-checks-#{Process.pid}")
  files = "#{fake}/files"
  mnt = "#{fake}/mnt"
  drive = "#{mnt}/storage-1"
  token = "eyJhIjoiYWJjIiwidCI6ImRlZiIsInMiOiJnaGkifQ#{'x' * 40}"
  smb_section = "[vault]\n\tpath = #{files}/vault"
  by_id = '/dev/disk/by-id/ata-SSD_9-part1'

  punctuation = %w[space comma equals semicolon hash_sign percent dollar backtick single_quote double_quote backslash].freeze
  letters = %w[non_ascii folds_to_k line_separator].freeze

  # A person's name is text, and reaches its command as one argument, after its option.
  name_may_hold = [*punctuation, *letters, 'leading_dash', 'leading_two_dashes', 'slash', 'dot_dot'].freeze
  # A password goes in on stdin, never on a command line: anything but a line break.
  password_may_hold = [*name_may_hold, 'colon', 'tab'].freeze
  # A folder's name is text, reached as one path; the checks are on the path's form and where it is.
  folder_may_hold = [*punctuation, *letters, 'colon', 'slash'].freeze
  # A blank line in a config, before or after what's checked. amahi_helper_real_tools_spec has the
  # tools read what the checks pass over.
  blank_lines = %w[line_break_end line_break_start].freeze
  # An argument left out, or null: the operation does without it.
  optional = ['null'].freeze
  # shares: a share given whole has no folder, and the argument can be left out.
  shares_may_hold = ['null', 'item folder null'].freeze

  # The operations with arguments: a request that's accepted, and what each argument may hold
  # beyond it.
  requests = {
    'users.create' => { good: { 'login' => 'newbie', 'name' => 'Ann Smith' }, may_hold: { 'name' => name_may_hold } },
    'users.set_password' => { good: { 'login' => 'ann', 'password' => 'hunter2hunter2' }, may_hold: { 'password' => password_may_hold } },
    'users.set_name' => { good: { 'login' => 'ann', 'name' => 'Ann B' }, may_hold: { 'name' => name_may_hold } },
    'users.normalize' => { good: { 'login' => 'ann' } },
    'users.delete' => { good: { 'login' => 'ann' } },

    # The text ends in a share's path, so what's added lands in a folder's name, which can hold it.
    # A line before the first section that isn't a parameter is one Samba passes over too.
    'samba.write_config' => { good: { 'content' => smb_section },
                              may_hold: { 'content' => [*blank_lines, *letters, 'space', 'comma', 'equals', 'semicolon', 'hash_sign', 'dollar', 'backtick', 'single_quote',
                                                        'double_quote', 'colon', 'slash', 'long', 'leading_dash', 'leading_two_dashes'] } },
    'samba.write_lmhosts' => { good: { 'content' => '192.168.1.5 nas' }, may_hold: { 'content' => blank_lines } },
    'shares.create_dir' => { good: { 'path' => "#{files}/photos" }, may_hold: { 'path' => folder_may_hold } },
    'shares.remove_dir' => { good: { 'path' => "#{files}/photos" }, may_hold: { 'path' => folder_may_hold } },
    'shares.set_guest_write' => { good: { 'path' => "#{files}/photos", 'writable' => true }, may_hold: { 'path' => folder_may_hold } },
    'trash.set_days' => { good: { 'days' => 14 } },

    'disks.format' => { good: { 'device' => '/dev/sdc1' } },
    'disks.mount' => { good: { 'device' => '/dev/sdc1', 'mount_point' => "#{mnt}/storage-2" } },
    'disks.unmount' => { good: { 'device' => '/dev/sdb1' } },
    'disks.preview' => { good: { 'device' => '/dev/sdc1' } },

    'pools.status' => { good: { 'scan' => true }, anything: ['scan'] }, # only true asks for a scan
    'pools.create' => { good: { 'name' => 'tank', 'layout' => 'mirror', 'devices' => ['/dev/sdd', '/dev/sde'] } },
    'pools.online_drive' => { good: { 'name' => 'old', 'drive' => by_id } },
    'pools.replace' => { good: { 'name' => 'old', 'old' => by_id, 'new' => '/dev/sdd' } },
    'pools.add_group' => { good: { 'name' => 'old', 'devices' => ['/dev/sdd', '/dev/sde'] } },
    'pools.destroy' => { good: { 'name' => 'old', 'confirm' => 'old' } },
    'pools.erase_drive' => { good: { 'device' => '/dev/sdh', 'confirm' => 'gone' } },
    'pools.export' => { good: { 'name' => 'old' } },
    'pools.shares_root' => { good: { 'name' => 'old' } },
    'pools.import' => { good: { 'name' => 'away' } },
    'pools.import_found' => { good: { 'id' => '5678' } },
    'pools.snapshot' => { good: { 'name' => 'old' } },
    'pools.snapshot_policy' => { good: { 'name' => 'old', 'hourly' => 3, 'daily' => 7 } },
    'pools.destroy_snapshot' => { good: { 'name' => 'old', 'snapshot' => 'amahi-daily-2026-10-03-0010' } },
    'pools.rollback' => { good: { 'name' => 'old', 'snapshot' => 'amahi-daily-2026-10-03-0010', 'confirm' => 'old' } },
    'pools.scrub' => { good: { 'name' => 'old' } },

    'greyhole.write_config' => { good: { 'content' => 'storage_pool_drive = /mnt/storage-1, min_free: 10gb' }, may_hold: { 'content' => blank_lines } },
    'greyhole.replace_drive' => { good: { 'path' => drive } },
    'greyhole.remove_drive' => { good: { 'path' => drive, 'available' => true } },
    'greyhole.remove_share' => { good: { 'share' => 'Photos' } },
    'greyhole.trash_restore' => { good: { 'share' => 'Photos', 'path' => 'a.jpg' } },
    'greyhole.trash_delete' => { good: { 'share' => 'Photos', 'path' => 'a.jpg' } },
    'greyhole.switch' => { good: { 'on' => true } },

    'dhcp.check_servers' => { good: { 'interface' => 'eth1' } },
    'dns.write_config' => { good: { 'content' => "server:\n  access-control: 10.0.0.0/8 allow" }, may_hold: { 'content' => blank_lines } },
    'dns.set_blocklists' => { good: { 'lists' => ['hagezi-normal'], 'allow' => ['example.com'] } },
    'dns.write_radvd_config' => { good: { 'content' => "interface eth1 {\n  AdvSendAdvert on;\n  AdvDefaultLifetime 0;\n};" }, may_hold: { 'content' => blank_lines } },
    'dns.set_own_address' => { good: { 'interface' => 'eth1', 'address' => 'fdab:cdef:1234::53' } },
    'dns.check_routers' => { good: { 'interface' => 'eth1' } },

    'network.set_hostname' => { good: { 'hostname' => 'amahi-kai' } },
    'network.write_dnsmasq_config' => { good: { 'content' => "port=0\nbind-interfaces" }, may_hold: { 'content' => blank_lines } },
    'network.router_on' => { good: { 'lan' => 'eth1', 'wan' => 'eth0', 'forwards' => [], 'dns' => '192.168.1.5', 'lan_only' => ['192.168.1.20'] },
                             may_hold: { 'dns' => optional, 'lan_only' => optional } },
    'network.router_off' => { good: { 'keep_lan' => true } },
    'network.set_address' => { good: { 'interface' => 'eth1', 'mode' => 'fixed', 'address' => '10.99.0.5/24', 'gateway' => '10.99.0.254',
                                       'dns' => ['9.9.9.9'], 'guard' => true },
                               may_hold: { 'gateway' => optional, 'dns' => optional, 'guard' => optional } },
    'network.blink_port' => { good: { 'interface' => 'eth1' } },
    # A token goes in a root-only file, never on a command line, and it's trimmed. Cloudflare's
    # alphabet holds these.
    'tunnel.configure' => { good: { 'token' => token }, may_hold: { 'token' => [*blank_lines, 'equals', 'slash', 'leading_dash', 'leading_two_dashes'] } },

    'apps.install' => { good: { 'app' => 'bitshare', 'shares' => [{ 'name' => 'vault', 'folder' => 'media', 'write' => false }], 'pool' => 'old' },
                        may_hold: { 'shares' => shares_may_hold } },
    'apps.start' => { good: { 'app' => 'gitea' } },
    'apps.stop' => { good: { 'app' => 'gitea' } },
    'apps.restart' => { good: { 'app' => 'gitea' } },
    'apps.update' => { good: { 'app' => 'gitea', 'shares' => [{ 'name' => 'vault', 'folder' => 'media', 'write' => true }] }, may_hold: { 'shares' => shares_may_hold } },
    'apps.undo_update' => { good: { 'app' => 'gitea', 'shares' => [{ 'name' => 'vault', 'folder' => 'media', 'write' => true }] }, may_hold: { 'shares' => shares_may_hold } },
    'apps.uninstall' => { good: { 'app' => 'gitea', 'delete_data' => true } },
    'apps.logs' => { good: { 'app' => 'gitea', 'lines' => 150 } },

    'services.start' => { good: { 'service' => 'smbd' } },
    'services.stop' => { good: { 'service' => 'smbd' } },
    'services.restart' => { good: { 'service' => 'smbd' } },
    'services.enable' => { good: { 'service' => 'smbd' } },
    'services.disable' => { good: { 'service' => 'smbd' } },

    'system.update' => { good: { 'repair' => true } },
    'system.journal' => { good: { 'lines' => 150 } },
    'system.set_update_channel' => { good: { 'channel' => 'candidates' } },
    'system.create_swap' => { good: { 'size_gb' => 2 } },
    'packages.add_repository' => { good: { 'repository' => 'greyhole' } },
    'packages.upgrade' => { good: { 'packages' => ['samba'] } },
    'packages.hold' => { good: { 'packages' => ['samba'], 'held' => true } },
    'updates.set_automatic' => { good: { 'enabled' => false } },
    'packages.install' => { good: { 'packages' => ['smartmontools'], 'recommends' => false } },
    'security.harden_ssh' => { good: { 'setting' => 'root_login' } }
  }.freeze

  text_changes = {
    'empty' => ->(_v) { '' },
    'line_break_end' => ->(v) { "#{v}\n" },
    'line_break_mid' => ->(v) { "#{v}\nmarker=1" },
    'line_break_start' => ->(v) { "\n#{v}" },
    'carriage_return' => ->(v) { "#{v}\rmarker" },
    'leading_dash' => ->(v) { "-#{v}" },
    'leading_two_dashes' => ->(v) { "--#{v}" },
    'space' => ->(v) { "#{v} marker" },
    'tab' => ->(v) { "#{v}\tmarker" },
    'comma' => ->(v) { "#{v},marker" },
    'equals' => ->(v) { "#{v}=marker" },
    'semicolon' => ->(v) { "#{v};marker" },
    'hash_sign' => ->(v) { "#{v}#marker" },
    'percent' => ->(v) { "#{v}%s" },
    'dollar' => ->(v) { "#{v}$marker" },
    'backtick' => ->(v) { "#{v}`marker`" },
    'single_quote' => ->(v) { "#{v}'" },
    'double_quote' => ->(v) { "#{v}\"" },
    'backslash' => ->(v) { "#{v}\\" },
    'colon' => ->(v) { "#{v}:marker" },
    'slash' => ->(v) { "#{v}/marker" },
    'dot_dot' => ->(v) { "#{v}/../marker" },
    'nul' => ->(v) { "#{v}\0marker" },
    'long' => ->(v) { "#{v}#{'a' * 5000}" },
    'non_ascii' => ->(v) { "#{v}é" },
    'folds_to_k' => ->(v) { "#{v}K" },
    'line_separator' => ->(v) { "#{v} marker" },
    'bad_utf8' => ->(v) { "#{v}\xFF".dup.force_encoding('UTF-8') }
  }.freeze

  wrong_types = { 'number' => 1, 'decimal' => 1.5, 'true' => true, 'null' => nil, 'list' => ['x'], 'object' => { 'x' => 'y' }, 'string' => 'x' }.freeze

  # [what changed, the altered value] for one argument's value; into lists and objects too.
  alterations = lambda do |value|
    wrong = wrong_types.reject { |_name, other| other.instance_of?(value.class) || ([true, false].include?(value) && other == true) }
    case value
    when String then wrong.reject { |name, _| name == 'string' }.to_a + text_changes.map { |name, change| [name, change.call(value)] }
    when Integer then wrong.to_a + [['negative', -1], ['huge', 2**40], ['number_as_text', value.to_s]]
    when Array
      items = value.empty? ? [] : alterations.call(value.first).map { |name, other| ["item #{name}", [other, *value.drop(1)]] }
      wrong.to_a + items
    when Hash
      fields = value.flat_map { |key, inner| alterations.call(inner).map { |name, other| ["#{key} #{name}", value.merge(key => other)] } }
      wrong.to_a + fields
    else wrong.to_a
    end
  end

  def account(uid, gid)
    Etc::Passwd.new('x', 'x', uid, gid, '', '/nonexistent', '/usr/sbin/nologin')
  end

  before(:all) do
    Privileged.operations # loads the helper's source once
    FileUtils.mkdir_p(["#{files}/vault/media", "#{mnt}/storage-1/.gh_trash/Photos", "#{fake}/definitions"])
    File.write("#{mnt}/storage-1/.gh_trash/Photos/a.jpg", 'x')
  end

  after(:all) { FileUtils.rm_rf(fake) }

  # A NAS: sda the system's disk, sdb1 a share drive mounted, sdc1 a formatted drive that isn't, sdd
  # and sde empty, sdh left over from a pool on the drives (gone), a pool (old) and one taken offline (away).
  before do
    stub_const('AmahiHelper::SHARE_ROOT', files)
    stub_const('AmahiHelper::DRIVES_ROOT', mnt)
    stub_const('AmahiHelper::MNT', mnt)
    stub_const('AmahiHelper::FSTAB', "#{fake}/fstab")
    stub_const('AmahiHelper::POOL_ROOT', "#{fake}/pools")
    stub_const('AmahiHelper::ROUTER_STATE', "#{fake}/router.json")
    stub_const('AmahiHelper::APP_STORAGE', "#{fake}/app-storage.json")
    stub_const('AmahiHelper::APP_DEFINITIONS', "#{fake}/definitions")
    stub_const('AmahiHelper::APP_CATALOG', "#{fake}/catalog")
    stub_const('AmahiHelper::APP_MANIFESTS', Rails.root.join('config/apps').to_s)
    File.write("#{fake}/fstab", "UUID=os / ext4 defaults 0 1\n")

    allow(helper).to receive(:installed!).and_return(true)
    allow(helper).to receive(:group_id).and_call_original
    allow(helper).to receive(:group_id).with('users').and_return(100)
    allow(helper).to receive(:passwd) { |login| account(1001, 100) if login == 'ann' }
    allow(helper).to receive(:old_home?).and_return(false)

    allow(helper).to receive(:samba_shares).and_return('vault' => { name: 'vault', path: "#{files}/vault", pooled: false },
                                                       'photos' => { name: 'Photos', path: "#{files}/photos", pooled: true })
    allow(helper).to receive(:real_root?).and_return(true)
    allow(helper).to receive(:capture).with(['/usr/bin/findmnt', '-n', '-o', 'FSTYPE', '-T', anything]).and_return("ext4\n")

    tree = [{ 'path' => '/dev/sda', 'type' => 'disk', 'mountpoints' => [nil],
              'children' => [{ 'path' => '/dev/sda2', 'type' => 'part', 'mountpoints' => ['/'] }] },
            { 'path' => '/dev/sdb', 'type' => 'disk', 'mountpoints' => [nil],
              'children' => [{ 'path' => '/dev/sdb1', 'type' => 'part', 'fstype' => 'ext4', 'mountpoints' => ["#{mnt}/storage-9"] }] },
            { 'path' => '/dev/sdc', 'type' => 'disk', 'mountpoints' => [nil],
              'children' => [{ 'path' => '/dev/sdc1', 'type' => 'part', 'fstype' => 'ext4', 'mountpoints' => [nil] }] },
            { 'path' => '/dev/sdd', 'type' => 'disk', 'mountpoints' => [nil] },
            { 'path' => '/dev/sde', 'type' => 'disk', 'mountpoints' => [nil] },
            { 'path' => '/dev/sdh', 'type' => 'disk', 'mountpoints' => [nil],
              'children' => [{ 'path' => '/dev/sdh1', 'type' => 'part', 'fstype' => 'zfs_member', 'mountpoints' => [nil] }] }]
    allow(helper).to receive(:block_tree).and_return(tree)
    allow(File).to receive(:blockdev?).and_call_original
    allow(File).to receive(:blockdev?).with(a_string_matching(%r{\A/dev/(?:sd[a-h]\d?)\z})).and_return(true)
    allow(helper).to receive(:probe).and_return('TYPE' => 'ext4', 'UUID' => 'u-1')
    allow(helper).to receive(:drive_holders).and_return([])
    allow(helper).to receive(:other_mount_views).and_return([])
    allow(helper).to receive(:stable_path) { |disk| "/dev/disk/by-id/ata-SSD_#{File.basename(disk)}" }
    allow(helper).to receive(:ssd?).and_return(true)

    allow(helper).to receive(:pool_names).and_return(['old'])
    allow(helper).to receive(:pool_mountpoint) { |name| "#{fake}/pools/#{name}" }
    allow(helper).to receive(:pooled_devices).and_return({})
    gone = { 'name' => 'gone', 'id' => '5678', 'state' => 'ONLINE', 'force' => false, 'devices' => ['/dev/sdh1'] }
    allow(helper).to receive(:importable_pools).and_return([gone])
    allow(helper).to receive(:found_pools).and_return([gone])
    allow(helper).to receive(:offline_records).and_return('away' => '1234')
    allow(helper).to receive(:pool_vdevs).and_return(
      [{ 'name' => 'mirror-0', 'children' => [{ 'name' => by_id, 'state' => 'OFFLINE', 'device' => '/dev/sdz1', 'children' => [] },
                                              { 'name' => '/dev/disk/by-id/ata-SSD_8-part1', 'state' => 'ONLINE', 'device' => '/dev/sdy1', 'children' => [] }] }]
    )
    allow(helper).to receive(:pool_drives).and_return([{ 'name' => '/dev/disk/by-id/ata-SSD_8-part1', 'state' => 'ONLINE', 'device' => '/dev/sdy1', 'children' => [] }])
    allow(helper).to receive(:pool_snapshots).and_return([{ 'name' => 'amahi-daily-2026-10-03-0010' }])
    allow(helper).to receive(:no_shares_on!)
    allow(helper).to receive(:no_apps_on!)
    allow(helper).to receive(:pool_not_held!)
    allow(helper).to receive(:apps_on_pool).and_return([])
    allow(helper).to receive(:capture).and_call_original
    allow(helper).to receive(:capture).with(['/usr/sbin/zpool', 'get', '-H', '-o', 'value', 'guid', 'old']).and_return("99\n")
    allow(helper).to receive(:whole_disk_of) { |path| path }
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(by_id).and_return(true)

    allow(helper).to receive(:greyhole_drives).and_return([drive])
    allow(helper).to receive(:greyhole_shares).and_return(['Photos'])
    allow(helper).to receive(:mount_point?).and_call_original
    allow(helper).to receive(:mount_point?).with(drive).and_return(true)
    allow(helper).to receive(:folder_size).and_return(1)
    allow(helper).to receive(:free_space).and_return(2)

    allow(File).to receive(:exist?).with(a_string_matching(%r{\A/sys/class/net/eth[01]\z})).and_return(true)
    allow(helper).to receive(:ufw_enabled?).and_return(true)
    allow(Socket).to receive(:getifaddrs).and_return([Struct.new(:addr).new(Addrinfo.ip('192.168.1.5'))])

    allow(helper).to receive(:app_job_running?).and_return(false)
    allow(helper).to receive(:docker_output).and_return('id')
    allow(helper).to receive(:engine_running!).and_return(true)
    allow(helper).to receive(:tailscale_https_name).and_return('nas.tail1234.ts.net')
    allow(helper).to receive(:app_backup_info).and_return(nil)

    allow(File).to receive(:exist?).with(AmahiHelper::UPDATE_UNIT).and_return(true)
    allow(helper).to receive(:update_channel).and_return('releases')
    allow(helper).to receive(:installed_package_names) { |names| names & ['samba'] }
    allow(helper).to receive(:upgradable_packages).and_return('samba' => '2')
    allow(helper).to receive(:held_packages).and_return([])
    allow(helper).to receive(:ssh_login_accounts).and_return(['ann'])
    allow(helper).to receive(:ssh_key_holders).and_return(['ann'])
  end

  it 'lists every operation with arguments, and all of its arguments' do
    with_arguments = AmahiHelper::OPERATIONS.select { |_name, spec| spec[:params].any? }
    expect(requests.keys).to match_array(with_arguments.keys)
    with_arguments.each { |name, spec| expect(requests.dig(name, :good)&.keys).to match_array(spec[:params]), name }
  end

  it 'refuses an argument no operation lists, and anything but an object' do
    AmahiHelper::OPERATIONS.each do |name, spec|
      expect { helper.validate(name, spec[:params].to_h { |param| [param, nil] }.merge('made_up' => 1)) }.to raise_error(AmahiHelper::Refused, 'unexpected argument made_up')
      ['x', 1, nil, []].each { |args| expect { helper.validate(name, args) }.to raise_error(AmahiHelper::Refused, 'arguments must be a JSON object') }
    end
  end

  it 'can log every one of these requests, and answer it' do
    requests.each do |op, request|
      request[:good].each do |param, value|
        alterations.call(value).each do |name, other|
          altered = request[:good].merge(param => other)
          expect { JSON.generate(helper.filtered(altered)) }.not_to raise_error, "#{op} #{param} #{name}"
        end
      end
    end
  end

  requests.each do |op, request|
    describe op do
      it 'takes the request the rest start from' do
        expect { helper.validate(op, request[:good]) }.not_to raise_error
      end

      request[:good].each do |param, value|
        next if request[:anything]&.include?(param)

        it "takes nothing else in #{param} that it mustn't" do
          taken = alterations.call(value).filter_map do |name, other|
            helper.validate(op, request[:good].merge(param => other))
            name
          rescue AmahiHelper::Refused, AmahiHelper::Failed
            nil
          rescue StandardError => e
            "#{name}: #{e.class}"
          end
          expect(taken).to match_array(request.dig(:may_hold, param) || [])
        end
      end
    end
  end
end
