require 'rails_helper'

# What Settings → Help says about the server, and a problem's report quotes (ServerSummary).
# Every source is stubbed: the machine running the specs isn't the one described.
RSpec.describe ServerSummary do
  let(:dir) { Dir.mktmpdir }
  let(:pool) { StoragePools::Pool.new(name: 'data', health: 'ONLINE', used: '1.4T', available: '2.0T', managed: true) }
  let(:service) { Struct.new(:name, :running, :idle) { def running? = running; def idle? = idle } }

  after { FileUtils.rm_rf(dir) }

  before do
    cpuinfo = File.join(dir, 'cpuinfo')
    File.write(cpuinfo, "processor\t: 0\nmodel name\t: Intel(R) Core(TM)  i5-12400\nprocessor\t: 1\nmodel name\t: Intel(R) Core(TM)  i5-12400\n")
    stub_const('ServerSummary::CPUINFO', cpuinfo)
    allow(SystemServices).to receive(:app_commit).and_return('bc809de')
    allow(UpdateStatus).to receive(:load).and_return(instance_double(UpdateStatus, channel: 'releases'))
    allow(SystemInfo).to receive_messages(os_name: 'Ubuntu 24.04.3 LTS', kernel: '6.8.0-87-generic',
                                          memory: { total: 16_252_928, used: 9_856_000, percent: 60 },
                                          root_disk: { size: '98G', used: '40G', free: '58G', percent: 41 })
    allow(StoragePools).to receive(:status).and_return(pools: [pool], offline: [], found: [], installed: true)
    allow(Greyhole).to receive(:installed?).and_return(false)
    allow(SystemServices).to receive(:all).and_return([service.new('Samba', true, false), service.new('Greyhole', false, true)])
    create(:docker_app, identifier: 'gitea', name: 'Gitea', status: 'running')
    create(:docker_app, identifier: 'transmission', name: 'Transmission', status: 'error', error_message: 'setfacl exited 1')
  end

  it 'says in a line each what this server runs, on what, and how it is' do
    expect(described_class.rows.to_h).to eq(
      'Amahi-kai' => "#{Rails.root.join('VERSION').read.strip} (bc809de) · releases",
      'System' => 'Ubuntu 24.04.3 LTS · kernel 6.8.0-87-generic',
      'Hardware' => 'Intel(R) Core(TM) i5-12400 (2 threads) · 15.5 GB RAM, 6.1 GB free',
      'System disk' => '58 GB free of 98 GB',
      'Storage' => 'ZFS pool data: ONLINE, 1.4T used, 2.0T free',
      'Apps' => '1 running · 1 needs attention',
      'Services' => 'all running' # Greyhole is idle (nothing pooled), not down
    )
  end

  it 'adds each app on a line of its own for a report, with why one needs attention' do
    expect(described_class.text.lines(chomp: true).last(2)).to eq(['  Gitea: running', '  Transmission: needs attention (setfacl exited 1)'])
  end

  it 'names a service that should run and does not, Greyhole and storage on the system disk' do
    allow(SystemServices).to receive(:all).and_return([service.new('Samba', false, false)])
    allow(StoragePools).to receive(:status).and_return(pools: [], offline: [], found: [], installed: false)
    allow(Greyhole).to receive_messages(installed?: true, running?: true)
    allow(DiskPoolPartition).to receive(:count).and_return(2)
    expect(described_class.services_summary).to eq('not running: Samba')
    expect(described_class.storage).to eq('Greyhole running, 2 drives')
    allow(Greyhole).to receive(:installed?).and_return(false)
    expect(described_class.storage).to eq('shares on the system disk')
  end
end
