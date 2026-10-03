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
      before do
        allow(CloudflareService).to receive(:production?).and_return(true)
        allow(Shell).to receive(:run).and_return(true)
        allow(File).to receive(:write).and_call_original
      end

      it 'points cloudflared at the token file and keeps the token out of the unit' do
        CloudflareService.configure!('eyJsecret-token')
        expect(File).to have_received(:write).with(end_with('cloudflared.service'), satisfy { |unit|
          unit.include?("--token-file #{CloudflareService::TOKEN_FILE}") && !unit.include?('eyJsecret-token')
        })
      end

      it 'stages the token in a file only its owner can read' do
        CloudflareService.configure!('eyJsecret-token')
        expect(File).to have_received(:write).with(end_with('tunnel.token'), 'eyJsecret-token', perm: 0600)
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
