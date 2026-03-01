require 'rails_helper'

RSpec.describe NetworkHelper, type: :helper do
  describe '#alias_ip' do
    before do
      Setting.find_or_create_by!(name: 'net', kind: Setting::NETWORK).update!(value: '192.168.1')
      Setting.find_or_create_by!(name: 'self-address', kind: Setting::NETWORK).update!(value: '100')
    end

    it 'returns server IP for blank address' do
      dns_alias = double('dns_alias', address: '')
      expect(helper.alias_ip(dns_alias)).to eq('192.168.1.100')
    end

    it 'returns server IP for nil address' do
      dns_alias = double('dns_alias', address: nil)
      expect(helper.alias_ip(dns_alias)).to eq('192.168.1.100')
    end

    it 'prepends network for numeric address' do
      dns_alias = double('dns_alias', address: '50')
      expect(helper.alias_ip(dns_alias)).to eq('192.168.1.50')
    end

    it 'returns full IP for complete address' do
      dns_alias = double('dns_alias', address: '10.0.0.5')
      expect(helper.alias_ip(dns_alias)).to eq('10.0.0.5')
    end
  end

  describe '#dns_select_options' do
    it 'returns options for cloudflare, google, and custom' do
      options = helper.dns_select_options
      expect(options.map(&:first)).to eq(%w[cloudflare google custom])
    end

    it 'returns arrays of [provider, label]' do
      options = helper.dns_select_options
      options.each do |opt|
        expect(opt).to be_an(Array)
        expect(opt.length).to eq(2)
      end
    end
  end
end
