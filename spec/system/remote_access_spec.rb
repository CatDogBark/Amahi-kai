require 'rails_helper'

# Tailscale's Connect in a real browser (remote_access.js). Its sign-in page is a link to click,
# never a tab the page opens: one opened seconds after the click was blocked as a pop-up
# (Firefox), and the page then reloaded to Connect as if it had failed. It waits for the sign-in
# and shows the NAS connected once it is.
RSpec.describe 'Remote Access', type: :system do
  let(:sign_in_url) { 'https://login.tailscale.com/a/abc123' }
  let(:waiting) { { installed: true, running: false, state: 'NeedsLogin' } }
  let(:connected) do
    { installed: true, running: true, state: 'Running', tailscale_ip: '100.64.0.7', hostname: 'amahi-kai.tail1234.ts.net',
      magic_dns: 'amahi-kai.tail1234.ts.net', peers: 1, magic_dns_on: true, https_certificates: true }
  end

  it 'shows Tailscale sign-in page as a link, opens no window, and shows the NAS connected once signed in' do
    allow(TailscaleService).to receive_messages(status: waiting, running?: false, start!: { success: true, auth_url: sign_in_url })
    sign_in_as_admin
    visit '/network/remote_access'
    page.execute_script('window.opened = 0; window.open = function() { window.opened++; return null; }')
    find('button[data-call="startTailscale"]', text: 'Connect').click # Cloudflare's card has a Connect too

    link = find_link('Sign in to Tailscale to finish')
    expect(link[:href]).to eq(sign_in_url)
    expect(link[:target]).to eq('_blank')
    expect(page).to have_text('Waiting for you to sign in…')
    expect(page.evaluate_script('window.opened')).to eq(0)

    # Signed in on Tailscale's page: the next check finds it connected, and the page shows it
    allow(TailscaleService).to receive_messages(status: connected, running?: true)
    expect(page).to have_text('Connected', wait: 10)
    expect(page).to have_no_link('Sign in to Tailscale to finish')
  end
end
