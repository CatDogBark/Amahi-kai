require 'rails_helper'

RSpec.describe CloudflareService do
  describe '.status' do
    it 'returns dummy status in non-production' do
      status = CloudflareService.status
      expect(status).to be_a(Hash)
      expect(status[:installed]).to eq(false)
      expect(status[:running]).to eq(false)
      expect(status[:token_configured]).to eq(false)
    end
  end

  describe '.installed?' do
    it 'returns false in non-production' do
      expect(CloudflareService.installed?).to eq(false)
    end
  end

  describe '.running?' do
    it 'returns false in non-production' do
      expect(CloudflareService.running?).to eq(false)
    end
  end

  describe '.enabled?' do
    it 'returns false when not installed or running' do
      expect(CloudflareService.enabled?).to eq(false)
    end
  end

  describe '.token_configured?' do
    it 'returns true in non-production' do
      expect(CloudflareService.token_configured?).to eq(true)
    end
  end

  describe '.install!' do
    it 'returns true in non-production' do
      expect(CloudflareService.install!).to eq(true)
    end
  end

  describe '.configure!' do
    it 'returns true in non-production' do
      expect(CloudflareService.configure!('test-token')).to eq(true)
    end

    context 'in production' do
      before { allow(CloudflareService).to receive(:production?).and_return(true) }

      it 'hands the token to the root helper, which saves it and (re)starts the tunnel' do
        expect(CloudflareService.configure!(" eyJsecret-token \n")).to be true
        expect(Privileged.calls).to eq([['tunnel.configure', { token: 'eyJsecret-token' }]])
      end

      it "raises the helper's reason" do
        allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('tunnel.configure', 'cloudflared isn\'t installed'))
        expect { CloudflareService.configure!('eyJx') }.to raise_error(CloudflareService::CloudflareError, "cloudflared isn't installed")
      end

      it "installs cloudflared from Cloudflare's repository, passing apt's output on" do
        allow(Privileged).to receive(:call).and_call_original
        allow(Privileged).to receive(:call).with('packages.install', packages: ['cloudflared']) do |*_args, &block|
          block.call('Setting up cloudflared (2026.9.0) ...')
          { 'ok' => true }
        end
        lines = []
        CloudflareService.install! { |line| lines << line }
        expect(Privileged.calls).to eq([['packages.add_repository', { repository: 'cloudflared' }]])
        expect(lines).to eq(['Setting up cloudflared (2026.9.0) ...'])
      end

      it 'starts, stops and restarts through the helper, reporting failure as false' do
        expect([CloudflareService.start!, CloudflareService.stop!, CloudflareService.restart!]).to all(be true)
        expect(Privileged.calls.map(&:first)).to eq(%w[tunnel.start tunnel.stop tunnel.restart])
        allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('tunnel.start', 'systemctl exited 1'))
        expect(CloudflareService.start!).to be false
      end
    end
  end

  describe 'token staging' do
    after { FileUtils.rm_f(CloudflareService.staged_token_path) }

    it 'hands the staged token over once, then forgets it' do
      CloudflareService.stage_token(" eyJabc \n")
      expect(File.stat(CloudflareService.staged_token_path).mode & 0o777).to eq(0o600)
      expect(CloudflareService.take_staged_token).to eq('eyJabc')
      expect(CloudflareService.take_staged_token).to be_nil
    end
  end

  describe 'log filtering' do
    it 'filters the tunnel token and similar parameters' do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      filtered = filter.filter('token' => 'a', 'tunnel_token' => 'b', 'api_key' => 'c', 'name' => 'd')
      expect(filtered).to eq('token' => '[FILTERED]', 'tunnel_token' => '[FILTERED]', 'api_key' => '[FILTERED]', 'name' => 'd')
    end
  end

  describe '.start!' do
    it 'returns true in non-production' do
      expect(CloudflareService.start!).to eq(true)
    end
  end

  describe '.stop!' do
    it 'returns true in non-production' do
      expect(CloudflareService.stop!).to eq(true)
    end
  end

  describe '.restart!' do
    it 'returns true in non-production' do
      expect(CloudflareService.restart!).to eq(true)
    end
  end
end
