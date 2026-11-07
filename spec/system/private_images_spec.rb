require 'rails_helper'

# Private images in a real browser: the way in from the Apps page, the form's script (the address
# only for another registry, GitHub's how-to only for GitHub's, the place as it's typed), a token
# saved, Remove asking first, and the same list under Setup → Settings → Tokens.
RSpec.describe 'Private images', type: :system do
  let(:status_file) { Rails.root.join("tmp/registry-browser-#{Process.pid}.json").to_s }

  before do
    allow(RegistryTokens).to receive(:status_file).and_return(status_file)
    allow(DockerService).to receive(:installed?).and_return(true)
    allow(DockerService).to receive(:running?).and_return(true)
    allow(Privileged).to receive(:call).and_call_original
    # The helper keeps the token and writes its status
    allow(Privileged).to receive(:call).with('registry.save', any_args) do |_op, host:, owner:, username:, token:, note:|
      expect(token).to eq("ghp_#{'a' * 36}")
      File.write(status_file, JSON.generate('tokens' => [{ 'place' => "#{host}/#{owner}", 'username' => username, 'note' => note,
                                                           'added_at' => Time.now.utc.iso8601, 'checked_at' => Time.now.utc.iso8601, 'worked' => true }]))
      { 'ok' => true, 'place' => "#{host}/#{owner}", 'replaced' => false }
    end
  end

  after { FileUtils.rm_f(status_file) }

  it 'adds a token from the Apps page, and asks before removing it' do
    sign_in_as_admin
    visit '/apps'
    within('#private-images-line') { click_link 'Add one' }
    expect(page).to have_css('h2', text: 'Add a token')
    expect(page).to have_css('[data-token-howto]', visible: :visible)
    expect(page).to have_field('Its address', visible: :hidden)

    choose 'registry', option: 'other'
    expect(page).to have_field('Its address', visible: :visible)
    expect(page).to have_css('[data-token-howto]', visible: :hidden)
    fill_in 'Its address', with: 'registry.example.com'
    fill_in 'Whose images', with: 'Team'
    expect(page).to have_css('[data-token-where] code', text: 'registry.example.com/team/')
    choose 'registry', option: 'ghcr.io'
    expect(page).to have_field('Its address', visible: :hidden)
    expect(page).to have_css('[data-token-where] code', text: 'ghcr.io/team/')

    fill_in 'Whose images', with: 'catdogbark'
    fill_in 'It signs in as', with: 'CatDogBark'
    fill_in 'The token', with: "ghp_#{'a' * 36}"
    fill_in 'Your note', with: 'Amahi-kai NAS'
    fill_in 'Your password, to add a token', with: User::SEED_ADMIN_PASSWORD
    click_button 'Check and save it'

    expect(page).to have_text("The token for ghcr.io/catdogbark is saved: GitHub's registry took it.")
    expect(page).to have_css('#token-ghcr-io-catdogbark', text: 'Kept on the NAS, never shown')
    expect(page).to have_no_field('The token', with: /ghp_/)

    dismiss_confirm(/Remove the token for ghcr.io\/catdogbark\?/) { within('#token-ghcr-io-catdogbark') { click_button 'Remove' } }
    expect(Privileged.calls.map(&:first)).not_to include('registry.remove')
  end

  it 'lists them under Setup → Settings → Tokens' do
    File.write(status_file, JSON.generate('tokens' => [{ 'place' => 'ghcr.io/catdogbark', 'username' => 'CatDogBark', 'worked' => true }]))
    sign_in_as_admin
    visit '/settings'
    click_link 'Tokens'
    expect(page).to have_css('h2', text: 'Tokens for private images')
    expect(page).to have_css('#token-ghcr-io-catdogbark')
    expect(page).to have_css('#token-cloudflare-tunnel', text: 'Cloudflare Tunnel')
    click_link 'Replace'
    expect(page).to have_css('h2', text: 'Replace the token for ghcr.io/catdogbark')
    expect(page).to have_current_path('/settings/tokens?replace=ghcr.io%2Fcatdogbark')
  end
end
