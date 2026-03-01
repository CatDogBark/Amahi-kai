require 'rails_helper'

RSpec.describe DiskUtils do
  describe '.stats' do
    let(:lsblk_json) do
      '{"blockdevices": [{"name":"sda","model":"Samsung SSD","size":"500G","type":"disk"},{"name":"sr0","model":null,"size":"1024M","type":"rom"}]}'
    end

    before do
      allow(described_class).to receive(:`).and_call_original
      allow(described_class).to receive(:`).with(/lsblk -dno NAME,MODEL,SIZE,TYPE -J/).and_return(lsblk_json)
      allow(described_class).to receive(:`).with(/smartctl/).and_return("Temperature_Celsius     0x0022   070   040   000    Old_age   Always       -       30\n")
    end

    it 'returns an array of disk hashes with temperature info' do
      result = described_class.stats
      expect(result).to be_an(Array)
      expect(result.first[:device]).to eq('/dev/sda')
      expect(result.first[:model]).to eq('Samsung SSD')
      expect(result.first[:temp_c]).to eq('30')
      expect(result.first[:temp_f]).to eq('86')
      expect(result.first[:tempcolor]).to eq('cool')
    end

    it 'excludes non-disk devices' do
      result = described_class.stats
      expect(result.map { |d| d[:device] }).not_to include('/dev/sr0')
    end

    context 'when smartctl returns no temperature' do
      before do
        allow(described_class).to receive(:`).with(/smartctl/).and_return("")
      end

      it 'returns dash for temps' do
        result = described_class.stats
        expect(result.first[:temp_c]).to eq('-')
        expect(result.first[:temp_f]).to eq('-')
      end
    end

    context 'when lsblk returns empty output' do
      before do
        allow(described_class).to receive(:`).with(/lsblk -dno NAME,MODEL,SIZE,TYPE -J/).and_return("")
        allow(described_class).to receive(:`).with(/lsblk -dno NAME,TYPE/).and_return("")
      end

      it 'returns empty array' do
        expect(described_class.stats).to eq([])
      end
    end

    context 'when model is nil (virtual disk)' do
      let(:lsblk_json) do
        '{"blockdevices": [{"name":"vda","model":null,"size":"50G","type":"disk"}]}'
      end

      it 'defaults to Virtual Disk' do
        result = described_class.stats
        expect(result.first[:model]).to eq('Virtual Disk')
      end
    end

    context 'on error' do
      before do
        allow(described_class).to receive(:`).and_raise(StandardError, 'fail')
        allow(Rails.logger).to receive(:error)
      end

      it 'returns empty array' do
        expect(described_class.stats).to eq([])
      end
    end
  end

  describe '.mounts' do
    let(:df_output) do
      "Filesystem     1K-blocks    Used Available Use% Mounted on\n" \
      "/dev/sda1      50000000 20000000  30000000  40% /\n" \
      "tmpfs           4000000        0   4000000   0% /dev/shm\n" \
      "/dev/sdb1      100000000 50000000  50000000  50% /mnt/data\n"
    end

    before do
      allow(described_class).to receive(:`).with("df -BK 2>/dev/null").and_return(df_output)
    end

    it 'returns mount info excluding tmpfs' do
      result = described_class.mounts
      expect(result.map { |m| m[:filesystem] }).to contain_exactly('/dev/sda1', '/dev/sdb1')
    end

    it 'converts sizes to bytes' do
      result = described_class.mounts
      sda = result.find { |m| m[:filesystem] == '/dev/sda1' }
      expect(sda[:bytes]).to eq(50000000 * 1024)
      expect(sda[:mount]).to eq('/')
    end

    it 'sorts by filesystem' do
      result = described_class.mounts
      expect(result.first[:filesystem]).to eq('/dev/sda1')
    end
  end

  describe 'temp_color (private)' do
    it 'returns cool for 0 or below' do
      expect(described_class.send(:temp_color, 0)).to eq('cool')
      expect(described_class.send(:temp_color, -5)).to eq('cool')
    end

    it 'returns cool for normal temps' do
      expect(described_class.send(:temp_color, 35)).to eq('cool')
    end

    it 'returns warm for 40-49' do
      expect(described_class.send(:temp_color, 45)).to eq('warm')
    end

    it 'returns hot for 50+' do
      expect(described_class.send(:temp_color, 50)).to eq('hot')
    end
  end
end
