require 'rails_helper'
require 'open3'

# libexec/amahi-dfree, Samba's free-space answer for pooled shares: what greyhole-dfree answers,
# from the root helper's copy of greyhole.conf without the database password.
RSpec.describe 'amahi-dfree' do
  let(:dir) { Dir.mktmpdir }
  let(:script) { Rails.root.join('libexec/amahi-dfree').to_s }

  after { FileUtils.rm_rf(dir) }

  def answer(cwd, arg = '.')
    env = { 'AMAHI_DFREE_POOL' => "#{dir}/pool.conf", 'AMAHI_DFREE_SMB_CONF' => "#{dir}/smb.conf" }
    out, status = Open3.capture2(env, '/bin/sh', script, arg, chdir: cwd)
    expect(status).to be_success
    out.split.map(&:to_i)
  end

  it "gives the pool's size and its free space divided by the share's copies, leaving out folders with no drive" do
    FileUtils.mkdir_p(["#{dir}/share/sub", "#{dir}/not-mounted"])
    File.write("#{dir}/pool.conf", "storage_pool_drive = /, min_free: 10gb\n" \
                                   "storage_pool_drive = #{dir}/not-mounted, min_free: 10gb\n" \
                                   "num_copies[Test] = 2\nnum_copies[All] = max\n")
    File.write("#{dir}/smb.conf", "[global]\n\tworkgroup = HOME\n[Test]\n\tpath = #{dir}/share\n[All]\n\tpath = #{dir}/all\n")
    skip "/ isn't a mount point here" unless system('mountpoint', '-q', '/')
    total, free = `df -Pk /`.lines.last.split.values_at(1, 3).map(&:to_i)

    size, room, unit = answer("#{dir}/share/sub")
    expect([size, unit]).to eq([total, 1024])
    expect(room).to be_within(10 * 1024).of(free / 2) # 2 copies; the disk's free space moves a little
    FileUtils.mkdir_p("#{dir}/all")
    expect(answer("#{dir}/all").first(1)).to eq([total]) # max copies: one per drive found (here 1)
    expect(answer(dir, '/srv')[0]).to eq(total) # not a pooled share: the whole free space
    FileUtils.rm("#{dir}/pool.conf")
    expect(answer(dir)).to eq([0, 0, 1024])
  end
end
