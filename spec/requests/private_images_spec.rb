require 'spec_helper'

# Private images (PrivateImagesController): the tokens the NAS keeps for images their owners keep
# private, under Apps and under Setup → Settings → Tokens. The root helper keeps the tokens and
# writes their status (RegistryTokens' file here); the pages never hold or show a token.
describe 'Private images', type: :request do
  let(:status_file) { Rails.root.join("tmp/registry-tokens-#{Process.pid}.json").to_s }
  let(:token) { "ghp_#{'a' * 36}" }
  let(:digest) { "sha256:#{'d' * 64}" }

  before do
    allow(RegistryTokens).to receive(:status_file).and_return(status_file)
    allow(DockerService).to receive(:installed?).and_return(true)
    allow(DockerService).to receive(:running?).and_return(true)
    PrivateImagesController::PASSWORD_TRIES.clear
  end

  after { FileUtils.rm_f(status_file) }

  def keep_status(*rows)
    File.write(status_file, JSON.generate('tokens' => rows))
  end

  def ghcr_token(more = {})
    { 'place' => 'ghcr.io/catdogbark', 'username' => 'CatDogBark', 'note' => 'Amahi-kai NAS', 'added_at' => '2026-11-08T10:00:00Z',
      'checked_at' => 1.hour.ago.utc.iso8601, 'worked' => true, 'error' => nil }.merge(more)
  end

  def save_params(more = {})
    { registry: 'ghcr.io', owner: 'catdogbark', username: 'CatDogBark', token: token, note: 'Amahi-kai NAS', password: 'secretpassword' }.merge(more)
  end

  context 'as an admin' do
    before { login_as_admin }

    it 'says there are none yet, with the form for GitHub and how to make a token there' do
      get '/apps/private-images'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Private images', 'None yet', 'Add a token', 'How to make one on GitHub', 'read:packages',
                                       'Your password, to add a token')
      expect(response.body).to match(/<input checked=""[^>]*value="ghcr.io"/)
    end

    it 'lists each token, who it signs in as and the apps using it, and never the token' do
      keep_status(ghcr_token)
      DockerApp.create!(identifier: 'bitstream', name: 'bitStream', status: 'running', image: "ghcr.io/catdogbark/bitstream:0.2.1@#{digest}")
      DockerApp.create!(identifier: 'jellyfin', name: 'Jellyfin', status: 'running', image: "jellyfin/jellyfin:12.1@#{digest}")
      get '/apps/private-images'
      expect(response.body).to include('ghcr.io/catdogbark', 'GitHub&#39;s registry · signs in as CatDogBark', 'Kept on the NAS, never shown',
                                       'Amahi-kai NAS', 'Nov 8, 2026', 'href="/apps/bitstream"', '✓ Worked about 1 hour ago')
      expect(response.body).not_to include('href="/apps/jellyfin"')
      expect(response.body).not_to include(token)
    end

    it 'shows a token its registry refused, with Replace first' do
      keep_status(ghcr_token('worked' => false, 'error' => 'ghcr.io refused the token'))
      DockerApp.create!(identifier: 'bitstream', name: 'bitStream', status: 'running', image: "ghcr.io/catdogbark/bitstream:0.2.1@#{digest}")
      get '/apps/private-images'
      expect(response.body).to include('Refused about 1 hour ago', 'The last time it was used, ghcr.io refused the token. It may have expired or been deleted',
                                       'Until then, bitStream keeps running, but can&#39;t update or install again.')
    end

    it 'fills the form in from a link: a private image found on Review, or a token to replace' do
      get '/apps/private-images', params: { registry: 'registry.example.com', owner: 'team' }
      expect(response.body).to include('value="team"', 'registry.example.com/team/', 'value="registry.example.com"')
      get '/apps/private-images', params: { registry: 'ghcr.io', owner: 'catdogbark' }
      expect(response.body).to include('value="catdogbark"', 'ghcr.io/catdogbark/')
      keep_status(ghcr_token)
      get '/apps/private-images', params: { replace: 'ghcr.io/catdogbark' }
      expect(response.body).to include('Replace the token for ghcr.io/catdogbark', 'name="replacing" type="hidden" value="ghcr.io/catdogbark"',
                                       'value="CatDogBark"', 'Your password, to replace a token')
    end

    it 'saves a token once the helper has tried it with the registry' do
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('registry.save', any_args).and_return('ok' => true, 'place' => 'ghcr.io/catdogbark', 'replaced' => false)
      post '/apps/private-images/save', params: save_params(owner: ' CatDogBark/ ')
      expect(Privileged).to have_received(:call).with('registry.save', host: 'ghcr.io', owner: 'catdogbark', username: 'CatDogBark', token: token,
                                                                       note: 'Amahi-kai NAS')
      expect(response).to redirect_to('/apps/private-images')
      expect(flash[:notice]).to eq("The token for ghcr.io/catdogbark is saved: GitHub's registry took it.")
    end

    it 'takes another registry by its address, and a note left empty' do
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('registry.save', any_args).and_return('ok' => true, 'place' => 'registry.example.com/team', 'replaced' => true)
      post '/apps/private-images/save', params: save_params(registry: 'other', host: ' Registry.Example.com ', owner: 'registry.example.com/team', note: '')
      expect(Privileged).to have_received(:call).with('registry.save', host: 'registry.example.com', owner: 'team', username: 'CatDogBark', token: token, note: nil)
      expect(flash[:notice]).to eq('The token for registry.example.com/team is replaced: registry.example.com took it.')
    end

    it 'asks for the password again, and never puts a token back in the page' do
      post '/apps/private-images/save', params: save_params(password: 'wrong')
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That isn&#39;t your password", 'value="catdogbark"', 'value="Amahi-kai NAS"')
      expect(response.body).not_to include(token)
      expect(Privileged.calls.map(&:first)).not_to include('registry.save')
    end

    it 'says what the registry or the helper said when the token isn\'t kept' do
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('registry.save', any_args).and_raise(Privileged::Error.new('registry.save', 'ghcr.io refused the token'))
      post '/apps/private-images/save', params: save_params
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Not saved: ghcr.io refused the token.')
      expect(response.body).not_to include(token)
    end

    it 'checks a token again, and says if its registry refused it' do
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('registry.check', place: 'ghcr.io/catdogbark').and_return('worked' => true)
      post '/apps/private-images/check', params: { place: 'ghcr.io/catdogbark' }
      expect(flash[:notice]).to eq("GitHub's registry still takes the token for ghcr.io/catdogbark.")
      allow(Privileged).to receive(:call).with('registry.check', place: 'ghcr.io/catdogbark').and_return('worked' => false, 'error' => 'ghcr.io refused the token')
      post '/apps/private-images/check', params: { place: 'ghcr.io/catdogbark', from: 'settings' }
      expect(response).to redirect_to('/settings/tokens')
      expect(flash[:alert]).to eq("The token for ghcr.io/catdogbark didn't work: ghcr.io refused the token. It may have expired or been deleted: replace it with a new one.")
    end

    it 'removes a token, and says its registry still has it' do
      allow(Privileged).to receive(:call).and_call_original
      allow(Privileged).to receive(:call).with('registry.remove', place: 'ghcr.io/catdogbark').and_return('removed' => true)
      post '/apps/private-images/remove', params: { place: 'ghcr.io/catdogbark' }
      expect(Privileged).to have_received(:call).with('registry.remove', place: 'ghcr.io/catdogbark')
      expect(flash[:notice]).to eq("The token for ghcr.io/catdogbark is off the NAS. Its registry still has it: delete it there too if you're done with it.")
    end

    it 'lists them under Setup → Settings → Tokens too, with the Cloudflare Tunnel\'s' do
      keep_status(ghcr_token)
      get '/settings/tokens'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Tokens for private images', 'ghcr.io/catdogbark', 'Cloudflare Tunnel', 'Manage on Remote Access',
                                       'name="from" type="hidden" value="settings"')
      expect(response.body).to match(%r{class="text-capitalize active-subtab-link" href="/settings/tokens"})
      expect(response.body).to match(%r{aria-current="page"[^>]*>Setup|href="/users" aria-current="page"})
    end

    it 'shows a wrong password on the Settings page when it came from there' do
      post '/apps/private-images/save', params: save_params(password: 'wrong', from: 'settings')
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Cloudflare Tunnel', "That isn&#39;t your password")
    end

    it 'puts a line for them on the Apps page' do
      get '/apps'
      expect(response.body).to include('Private images: no tokens', 'href="/apps/private-images">Add one')
      keep_status(ghcr_token('worked' => false))
      get '/apps'
      expect(response.body).to include('Private images: 1 token, for ghcr.io/catdogbark', ' · 1 refused', '>Manage tokens')
    end

    it "says on an app's page that its image is private, and when its token was refused" do
      keep_status(ghcr_token)
      DockerApp.create!(identifier: 'bitstream', name: 'bitStream', status: 'running', image: "ghcr.io/catdogbark/bitstream:0.2.1@#{digest}")
      get '/apps/bitstream'
      expect(response.body).to include('Private: downloaded with', 'your token for ghcr.io/catdogbark')
      expect(response.body).not_to include('app-token-refused-bitstream')
      keep_status(ghcr_token('worked' => false))
      get '/apps/bitstream'
      expect(response.body).to include('id="app-token-refused-bitstream"', 'ghcr.io refused your token for catdogbark',
                                       'href="/apps/private-images?replace=ghcr.io%2Fcatdogbark#add-token"')
    end
  end

  it 'is for admins' do
    login_as_user
    get '/apps/private-images'
    expect(response).not_to have_http_status(:ok)
    post '/apps/private-images/remove', params: { place: 'ghcr.io/catdogbark' }
    expect(Privileged.calls.map(&:first)).not_to include('registry.remove')
  end
end
