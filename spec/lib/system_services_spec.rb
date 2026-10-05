require 'rails_helper'

RSpec.describe SystemServices do
  let(:ok) { instance_double(Process::Status, success?: true) }
  let(:failed) { instance_double(Process::Status, success?: false) }

  # What `systemctl show` prints for each catalog unit, in catalog order.
  def systemctl_blocks(overrides = {})
    described_class::CATALOG.map do |entry|
      props = overrides.fetch(entry[:unit], 'LoadState' => 'loaded', 'ActiveState' => 'inactive',
                                            'SubState' => 'dead', 'ActiveEnterTimestamp' => '',
                                            'MainPID' => '0', 'MemoryCurrent' => '[not set]',
                                            'Description' => "#{entry[:unit]}.service")
      props.map { |k, v| "#{k}=#{v}" }.join("\n")
    end.join("\n\n") + "\n"
  end

  before do
    allow(File).to receive(:exist?).and_call_original
    described_class::CATALOG.each { |e| allow(File).to receive(:exist?).with(e[:check]).and_return(true) if e[:check] }
    allow(Open3).to receive(:capture3).and_call_original
    allow(Open3).to receive(:capture3).with('systemctl', 'show', any_args).and_return([systemctl_blocks(
      'smbd' => { 'LoadState' => 'loaded', 'ActiveState' => 'active', 'SubState' => 'running',
                  'Description' => 'Samba SMB Daemon', 'ActiveEnterTimestamp' => "@#{(Time.now - 3600).to_i}",
                  'MainPID' => '4242', 'MemoryCurrent' => '8003584', 'UnitFileState' => 'enabled' },
      'tailscaled' => { 'LoadState' => 'not-found', 'ActiveState' => 'inactive', 'Description' => 'tailscaled.service' }
    ), '', ok])
    allow(Open3).to receive(:capture3).with('dpkg-query', any_args)
      .and_return(["samba\t2:4.19.5+dfsg-4ubuntu9.7\tii \nmariadb-server\t1:10.11.14-0ubuntu0.24.04.1\tii \ndocker.io\t24.0.7-0ubuntu4\trc \n", '', failed])
    allow(Open3).to receive(:capture3).with('pgrep', '-o', '-f', 'greyhole --daemon').and_return(['', '', failed])
  end

  describe '.all' do
    let(:services) { described_class.all(versions: true).index_by(&:key) }

    # smartd exits when no drive has SMART (virtual disks), which systemd counts as failed.
    it 'shows SMART monitoring as idle when the last health check found no drive with SMART' do
      allow(StorageHealth).to receive(:load).and_return(StorageHealth.new('checked_at' => Time.now.utc.iso8601, 'drives' => { '/dev/sda' => nil }))
      expect(described_class.all.index_by(&:key)['smartd']).to be_idle
      allow(StorageHealth).to receive(:load).and_return(StorageHealth.new('checked_at' => Time.now.utc.iso8601,
                                                                          'drives' => { '/dev/sdc' => { 'passed' => true } }))
      expect(described_class.all.index_by(&:key)['smartd']).not_to be_idle
      allow(StorageHealth).to receive(:load).and_return(StorageHealth.new({}))
      expect(described_class.all.index_by(&:key)['smartd']).not_to be_idle
      expect(services['mariadb']).not_to be_idle
    end

    it "lists ZFS's event daemon, SMART monitoring, Fail2ban and the VM guest agent when installed, without buttons" do
      %w[zfs-zed smartd fail2ban qemu-guest-agent].each do |key|
        expect(services[key]).to have_attributes(actions: [], note: be_present), key
      end
      expect(services['smartd'].unit).to eq('smartmontools')
      allow(File).to receive(:exist?).with('/usr/sbin/zed').and_return(false)
      expect(described_class.all.map(&:key)).not_to include('zfs-zed')
    end

    it 'reads state, start time, PID, memory and boot setting from systemd' do
      samba = services['smbd']
      expect(samba).to be_running
      expect(samba.description).to eq('Samba SMB Daemon')
      expect(samba.uptime).to be_within(5).of(3600)
      expect(samba.pid).to eq(4242)
      expect(samba.memory).to eq(8_003_584)
      expect(samba).to be_starts_at_boot
    end

    it 'shows the upstream package version, keeping the full one as detail' do
      expect(services['smbd'].version).to eq('4.19.5')
      expect(services['smbd'].version_detail).to eq('2:4.19.5+dfsg-4ubuntu9.7')
      expect(services['mariadb'].version).to eq('10.11.14')
    end

    it 'ignores packages that are removed but not purged' do
      expect(services['docker'].version).to be_nil
    end

    it 'treats an unknown memory figure, PID 0 and the fallback description as absent' do
      mariadb = services['mariadb']
      expect(mariadb).not_to be_running
      expect(mariadb.uptime).to be_nil
      expect(mariadb.pid).to be_nil
      expect(mariadb.memory).to be_nil
      expect(mariadb.description).to be_nil
    end

    it 'marks units systemd has never heard of as not installed' do
      expect(services['tailscaled']).not_to be_installed
      expect(services['smbd']).to be_installed
    end

    it 'leaves out optional services whose binary is missing' do
      allow(File).to receive(:exist?).with('/usr/bin/docker').and_return(false)
      expect(described_class.all.map(&:key)).not_to include('docker')
    end

    it 'shows the deployed commit and Rails version for Amahi-kai' do
      app = services['amahi-kai']
      expect(app.version_detail).to eq("Rails #{Rails::VERSION::STRING}, Ruby #{RUBY_VERSION}")
    end

    it 'skips dpkg when versions are not wanted' do
      described_class.all
      expect(Open3).not_to have_received(:capture3).with('dpkg-query', any_args)
    end

    it 'finds Greyhole by its process, which systemd cannot track' do
      allow(Open3).to receive(:capture3).with('pgrep', '-o', '-f', 'greyhole --daemon').and_return(["777\n", '', ok])
      allow(Open3).to receive(:capture3).with('ps', '-o', 'etimes=,rss=', '-p', '777').and_return(["  120  2048\n", '', ok])
      greyhole = described_class.find('greyhole')
      expect(greyhole).to be_running
      expect(greyhole.pid).to eq(777)
      expect(greyhole.uptime).to be_within(5).of(120)
      expect(greyhole.memory).to eq(2048 * 1024)
    end

    it 'copes with systemctl being missing' do
      allow(Open3).to receive(:capture3).with('systemctl', 'show', any_args).and_raise(Errno::ENOENT)
      # Greyhole's state comes from pgrep, not systemd
      states = described_class.all.reject { |s| s.key == 'greyhole' }.map(&:state)
      expect(states.uniq).to eq(['unknown'])
    end
  end

  describe 'Service#perform' do
    it 'runs the listed actions through the root helper' do
      expect(described_class.find('smbd').perform('restart')).to be true
      expect(described_class.find('docker').perform('stop')).to be true
      expect(Privileged.calls).to eq([['services.restart', { service: 'smbd' }], ['services.stop', { service: 'docker' }]])
    end

    it 'refuses actions the service does not list' do
      expect { described_class.find('mariadb').perform('stop') }.to raise_error(ArgumentError)
      expect { described_class.find('smbd').perform('disable') }.to raise_error(ArgumentError)
      expect(Privileged.calls).to be_empty
    end

    it 'reports a failure instead of raising' do
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('services.restart', 'exit 1'))
      expect(described_class.find('smbd').perform('restart')).to be false
    end
  end

  # The helper only controls the services this list gives actions to.
  describe 'the root helper' do
    it 'knows exactly the services that have actions' do
      Privileged.operations # loads libexec/amahi-helper
      with_actions = described_class::CATALOG.select { |e| e[:actions] }.map { |e| e[:key] }
      expect(AmahiHelper::SERVICES.keys).to match_array(with_actions)
    end
  end

  describe '.upstream_version' do
    it 'drops the epoch and Debian revision' do
      expect(described_class.upstream_version('5:27.3.1-1~ubuntu.24.04~noble')).to eq('27.3.1')
      expect(described_class.upstream_version('2026.2.0')).to eq('2026.2.0')
      expect(described_class.upstream_version('2.90-2build2')).to eq('2.90')
    end
  end
end
