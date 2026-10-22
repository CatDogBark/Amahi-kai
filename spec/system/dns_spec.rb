require 'rails_helper'

# Network → DNS in a real browser: the (simulated) Unbound install, the custom server's fields
# showing when its card is picked, and saving with DNS off.
RSpec.describe 'DNS', type: :system do
  before do
    allow(DnsService).to receive(:installed?).and_return(false)
    allow(DnsmasqService).to receive(:rewrite_config!)
  end

  it 'installs Unbound in its window' do
    sign_in_as_admin
    visit '/network/dns'
    click_button 'Install Unbound'
    within('#unbound-install-modal') do
      expect(page).to have_css('#unbound-output', text: 'Unbound installed', wait: 15)
      expect(page).to have_button('Close & Refresh')
    end
  end

  it "shows the custom server's fields while it's picked, and saves with DNS off" do
    sign_in_as_admin
    visit '/network/dns'
    expect(page).to have_no_field('custom_tls_name')
    find('label.dns-choice', text: 'Another server').click
    expect(page).to have_field('custom_tls_name')
    find('label.dns-choice', text: 'Quad9').click
    expect(page).to have_no_field('custom_tls_name')
    click_button 'Save'
    expect(page).to have_text('DNS is off.')
  end
end
