require 'rails_helper'

# Network → DNS & DHCP in a real browser: the (simulated) Unbound install, the custom server's
# fields and the DHCP settings showing while they're picked, blocking's lists, and saving with
# DNS off.
RSpec.describe 'DNS & DHCP', type: :system do
  before do
    Setting.set('advanced', '1')
    allow(DnsService).to receive(:installed?).and_return(false)
    allow(DnsmasqService).to receive_messages(installed?: false, running?: false)
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
    within('#dns-settings') { click_button 'Save' }
    expect(page).to have_text('DNS and DHCP are off.')
  end

  it 'offers blocking with the recommended lists ticked' do
    sign_in_as_admin
    visit '/network/dns'
    within('#dns-blocking') do
      expect(page).to have_unchecked_field('Block ads, trackers and malware')
      expect(page).to have_checked_field('lists[]', with: 'hagezi-normal')
      expect(page).to have_checked_field('lists[]', with: 'hagezi-tif-mini')
      expect(page).to have_unchecked_field('lists[]', with: 'oisd-big')
      check 'Block ads, trackers and malware'
      fill_in 'allowlist', with: 'example.com'
      click_button 'Save'
    end
    expect(page).to have_text('Saved. Blocking starts when DNS is on.')
  end

  it 'shows the DHCP settings while DNS + DHCP is picked, and offers dnsmasq until it is installed' do
    allow(DnsService).to receive(:installed?).and_return(true)
    sign_in_as_admin
    visit '/network/dns'
    expect(page).to have_no_button('Install dnsmasq')
    find('label.dns-choice', text: /\ADNS \+ DHCP/).click
    expect(page).to have_button('Install dnsmasq')

    allow(DnsmasqService).to receive(:installed?).and_return(true)
    visit '/network/dns'
    find('label.dns-choice', text: /\ADNS \+ DHCP/).click
    expect(page).to have_field('dhcp_first', with: '100')
    expect(page).to have_select('lease_time', selected: '4 hours')
    find('label.dns-choice', text: 'DNS for my network').click
    expect(page).to have_no_field('dhcp_first')
  end
end
