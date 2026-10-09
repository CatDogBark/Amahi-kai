require 'rails_helper'

# Shares on a ZFS pool (Shares → New Share → Where): a share whose folder is in the pool's shares
# dataset, with no Greyhole copies, labelled on Shares and listed on the pool's card; the pool
# isn't taken offline or deleted under it.
RSpec.describe 'Shares on ZFS pools', type: :request do
  let(:pool) do
    StoragePools::Pool.new(name: 'tank', health: 'ONLINE', used: 1, available: 100, mountpoint: '/srv/pools/tank', state: 'ONLINE',
                           scan: 'none requested', vdevs: [{ 'name' => 'mirror-0', 'state' => 'ONLINE', 'children' => [] }])
  end

  before do
    login_as_admin
    allow(StoragePools).to receive(:zfs_installed?).and_return(true)
    allow(StoragePools).to receive(:status).and_return(installed: true, pools: [pool], offline: [], error: nil)
    allow(StoragePools).to receive(:drives).and_return([])
    allow(SambaService).to receive(:push_config)
  end

  def page
    Nokogiri::HTML(response.body)
  end

  it "offers the system disk and each ZFS pool under Where, and makes the share in the pool's shares folder" do
    get shares_path
    options = page.css('#share_where option').map { |option| [option.text, option['value']] }
    expect(options).to include(['System disk', 'disk'], ['ZFS pool tank (Mirror)', 'zfs:tank'])

    post shares_path, params: { share: { name: 'Photos', where: 'zfs:tank' } }
    share = Share.find_by(name: 'Photos')
    expect(share).to have_attributes(zfs_pool: 'tank', path: '/srv/pools/tank/shares/photos', disk_pool_copies: 0)
    expect(Privileged.calls.map(&:first).first(2)).to eq(%w[pools.shares_root shares.create_dir])
    expect(Privileged.calls.first).to eq(['pools.shares_root', { name: 'tank' }])
    expect(Privileged.calls.second).to eq(['shares.create_dir', { path: '/srv/pools/tank/shares/photos' }])
  end

  it "makes a share in the Greyhole pool with 2 copies, and one on the system disk without" do
    allow(Greyhole).to receive(:configure!)
    post shares_path, params: { share: { name: 'Music', where: 'greyhole' } }
    expect(Share.find_by(name: 'Music')).to have_attributes(disk_pool_copies: 2, zfs_pool: nil, path: Share.default_full_path('Music'))
    expect(Greyhole).to have_received(:configure!)
    post shares_path, params: { share: { name: 'Plain', where: 'disk' } }
    expect(Share.find_by(name: 'Plain')).to have_attributes(disk_pool_copies: 0, zfs_pool: nil)
  end

  it "labels each share by where it lives, and a pool share's card shows its pool, not copies" do
    zfs = create(:share, name: 'Photos', zfs_pool: 'tank', path: '/srv/pools/tank/shares/photos')
    grey = create(:share, name: 'Music', disk_pool_copies: 2)
    plain = create(:share, name: 'Docs')
    get shares_path
    expect(page.at_css("#share-storage-#{zfs.id}").text).to eq('ZFS · tank')
    expect(page.at_css("#share-storage-#{grey.id}").text).to eq('Greyhole · 2 copies')
    expect(page.at_css("#share-storage-#{plain.id}").text).to eq('System disk')
    card = page.at_css("#whole_share_#{zfs.id}")
    expect(card.at_css("#share-zfs-pool-#{zfs.id}").text).to eq('tank')
    expect(card.at_css("#pool-controls-#{zfs.id}")).to be_nil
    expect(card.at_css('.update-path-form')).to be_nil # its folder stays on the pool
    expect(page.at_css("#whole_share_#{plain.id} #pool-controls-#{plain.id}")).not_to be_nil
  end

  it "refuses Greyhole copies for a share on a ZFS pool" do
    zfs = create(:share, name: 'Photos', zfs_pool: 'tank', path: '/srv/pools/tank/shares/photos')
    put update_disk_pool_copies_share_path(zfs), params: { copies: 2 }, as: :json
    expect(response.parsed_body).to include('status' => 'error', 'message' => a_string_including('on the ZFS pool tank'))
    expect(zfs.reload.disk_pool_copies).to eq(0)
  end

  it "lists a pool's shares on its card, and won't take it offline or delete it under them" do
    create(:share, name: 'Photos', zfs_pool: 'tank', path: '/srv/pools/tank/shares/photos')
    get '/disks/pools'
    expect(page.at_css('#pool-shares-tank').text.squish).to include('Shares on this pool: Photos.', "can't be taken offline or deleted")

    expect { StoragePools.take_offline!('tank') }.to raise_error(StoragePools::Error, 'Photos is on this pool: delete that share on Shares first.')
    expect { StoragePools.destroy!(name: 'tank', confirm: 'tank') }.to raise_error(StoragePools::Error, /Photos is on this pool/)
    expect(Privileged.calls.map(&:first)).not_to include('pools.export', 'pools.destroy')
  end
end
