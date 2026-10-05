require 'rails_helper'
require 'scheduled_jobs'

RSpec.describe ScheduledJobs do
  let(:ok) { instance_double(Process::Status, success?: true) }
  let(:now) { Time.zone.parse('2026-10-04 12:00:00') }
  let(:usec) { ->(time) { time.to_i * 1_000_000 } }
  let(:timers) do
    [{ 'unit' => 'amahi-kai-storage-check.timer', 'last' => usec.call(now - 240), 'next' => usec.call(now + 660), 'activates' => 'x' },
     { 'unit' => 'amahi-kai-indexer.timer', 'last' => usec.call(now - 60), 'next' => usec.call(now + 540) },
     { 'unit' => 'amahi-kai-update-check.timer', 'last' => nil, 'next' => usec.call(now + 600) },
     { 'unit' => 'apt-daily-upgrade.timer', 'last' => usec.call(now - 3600), 'next' => usec.call(now + 80_000) }]
  end
  let(:services) do
    { 'amahi-kai-storage-check.service' => { 'LoadState' => 'loaded', 'ActiveState' => 'inactive', 'Result' => 'success' },
      'amahi-kai-indexer.service' => { 'LoadState' => 'loaded', 'ActiveState' => 'inactive', 'Result' => 'exit-code' },
      'amahi-kai-update-check.service' => { 'LoadState' => 'loaded', 'ActiveState' => 'inactive', 'Result' => 'success' },
      'apt-daily-upgrade.service' => { 'LoadState' => 'loaded', 'ActiveState' => 'activating', 'Result' => 'success' } }
  end
  let(:health) { StorageHealth.new({}) }

  before do
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with('/usr/bin/unattended-upgrade').and_return(true)
    allow(StoragePools).to receive(:next_scrub).and_return(nil)
    allow(Open3).to receive(:capture3).with('systemctl', 'list-timers', '--all', '--output=json', any_args)
                                      .and_return([timers.to_json, '', ok])
    allow(Open3).to receive(:capture3).with('systemctl', 'show', '--property=Id,LoadState,ActiveState,Result', any_args) do |*args|
      blocks = args.drop(3).map { |unit| { 'Id' => unit }.merge(services.fetch(unit, 'LoadState' => 'not-found')).map { |k, v| "#{k}=#{v}" }.join("\n") }
      ["#{blocks.join("\n\n")}\n", '', ok]
    end
  end

  it "lists each installed job with its last and next run (systemd's microseconds) and how the last run ended" do
    jobs = described_class.all(health: health).index_by(&:key)
    expect(jobs.keys).to eq(%w[storage-check indexer update-check security-updates])
    expect(jobs['storage-check']).to have_attributes(name: 'Storage health check', schedule: 'Every 15 minutes',
                                                     last_run: now - 240, next_run: now + 660, result: :ok)
    expect(jobs['indexer'].result).to eq(:failed)
    expect(jobs['update-check']).to have_attributes(last_run: nil, result: nil)
    expect(jobs['security-updates'].result).to eq(:running)
  end

  it 'lists the hourly pool snapshots once ZFS is installed' do
    allow(File).to receive(:exist?).with('/usr/sbin/zpool').and_return(true)
    timers << { 'unit' => 'amahi-kai-snapshots.timer', 'last' => usec.call(now - 300), 'next' => usec.call(now + 3300) }
    allow(Open3).to receive(:capture3).with('systemctl', 'list-timers', '--all', '--output=json', any_args).and_return([timers.to_json, '', ok])
    services['amahi-kai-snapshots.service'] = { 'LoadState' => 'loaded', 'ActiveState' => 'inactive', 'Result' => 'success' }
    jobs = described_class.all(health: health).index_by(&:key)
    expect(jobs['snapshots']).to have_attributes(name: 'Pool snapshots', schedule: 'Every hour', next_run: now + 3300, result: :ok)
    expect(jobs.keys.index('snapshots')).to eq(2)
  end

  it "leaves out jobs that aren't installed, and keeps the rest when list-timers can't be read" do
    services.delete('amahi-kai-indexer.service')
    allow(File).to receive(:exist?).with('/usr/bin/unattended-upgrade').and_return(false)
    allow(Open3).to receive(:capture3).with('systemctl', 'list-timers', any_args).and_return(['not json', '', ok])
    jobs = described_class.all(health: health)
    expect(jobs.map(&:key)).to eq(%w[storage-check update-check])
    expect(jobs.map(&:next_run).uniq).to eq([nil])
  end

  it "adds Ubuntu's pool scrub when ZFS is installed, from the pools' last scrubs" do
    allow(StoragePools).to receive(:next_scrub).and_return(Time.local(2026, 10, 11, 0, 24))
    pools = lambda do |*scans|
      StorageHealth.new('checked_at' => now.iso8601, 'pools' => scans.map.with_index { |scan, i| { 'name' => "p#{i}", 'scan' => scan, 'vdevs' => [] } })
    end
    scrub = ->(h) { described_class.all(health: h).find { |job| job.key == 'zfs-scrub' } }

    done = scrub.call(pools.call('scrub repaired 0B in 00:41:07 with 0 errors on Sun Oct  4 02:41:08 2026',
                                 'scrub repaired 0B in 00:10:00 with 0 errors on Sun Sep 13 00:34:00 2026'))
    expect(done).to have_attributes(name: 'Pool scrub', last_run: Time.parse('Sun Oct  4 02:41:08 2026'),
                                    next_run: Time.local(2026, 10, 11, 0, 24), result: :ok)
    expect(scrub.call(pools.call('scrub repaired 0B in 00:41:07 with 3 errors on Sun Oct  4 02:41:08 2026')).result).to eq(:failed)
    expect(scrub.call(pools.call('scrub in progress since Sun Oct  4 10:00:00 2026')).result).to eq(:running)
    empty = scrub.call(pools.call)
    expect(empty).to have_attributes(last_run: nil, result: nil)
    expect(empty.about).to end_with('(no pools yet)')
  end
end
