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

  it "shows This NAS on Devices, with a port's form behind Change" do
    rows = [NetworkAddress::Interface.new(name: 'ens18', addresses: [NetworkInterfaces::Address.new(ip: IPAddr.new('192.168.1.13'), prefix: 24)],
                                          automatic: true, gateway: '192.168.1.1', part: :lan)]
    allow(NetworkAddress).to receive_messages(interfaces: rows, nameservers: ['192.168.1.1'], state: nil)
    allow(Leases).to receive(:all).and_return([])
    sign_in_as_admin
    visit '/network'
    expect(page).to have_text('This NAS')
    expect(page).to have_text('192.168.1.13/24')
    expect(page).to have_no_field('address-ens18')
    click_link 'Change'
    expect(page).to have_field('address-ens18', with: '192.168.1.13')
    expect(page).to have_field('dns-ens18', with: '192.168.1.1')
    expect(page).to have_checked_field('mode-automatic-ens18')
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
    expect(page).to have_text('DNS is off.')
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

  it 'has its own DHCP page, offering dnsmasq until it is installed' do
    allow(DnsService).to receive(:installed?).and_return(true)
    sign_in_as_admin
    visit '/network/dhcp'
    expect(page).to have_button('Install dnsmasq')
    expect(page).to have_no_field('dhcp_first')

    allow(DnsmasqService).to receive(:installed?).and_return(true)
    visit '/network/dhcp'
    expect(page).to have_field('dhcp_first', with: '100')
    expect(page).to have_select('lease_time', selected: '4 hours')
    within('.setup-subtab') { click_link 'Internet' }
    expect(page).to have_text('The NAS as your router')
  end
end
