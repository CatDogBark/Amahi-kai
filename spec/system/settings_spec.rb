require 'rails_helper'

# Settings in a real browser: System Status's Check now and a confirm's Cancel, and System
# Dependencies' install window (opens, streams, finishes, Close & Refresh reloads).
RSpec.describe 'Settings', type: :system do
  it 'checks for updates from System Status, and a cancelled confirm starts nothing' do
    sign_in_as_admin
    visit '/settings/system_status'
    click_button 'Check now'
    expect(page).to have_button('Check now', disabled: false) # the page came back after the check
    expect(Privileged.calls).to include(['system.check_update', {}])

    dismiss_confirm(/Repair runs every update step/) { click_button 'Repair' }
    expect(Privileged.calls.map(&:first)).not_to include('system.update')
  end

  # Their confirmations were inline onsubmit scripts, which the Content-Security-Policy refuses:
  # the forms went with no question asked (Servers' Restart and Stop too; no_inline_handlers_spec).
  it "asks before powering off or rebooting, and Cancel sends nothing" do
    sign_in_as_admin
    visit '/settings'
    dismiss_confirm(/This will power off your server/) { click_button 'Power off' }
    dismiss_confirm(/This will reboot your server/) { click_button 'Reboot' }
    expect(Privileged.calls.map(&:first)).not_to include('system.poweroff', 'system.reboot')
  end

  it "opens System Dependencies' window for Check now, streams to the end, and Close & Refresh reloads" do
    sign_in_as_admin
    visit '/settings/dependencies'
    click_button 'Check now'
    within('#deps-refresh-install-modal') do
      expect(page).to have_css('#deps-refresh-output', text: 'Refreshing the package lists')
      expect(page).to have_css('#deps-refresh-output', text: '✓ Package lists refreshed')
      expect(page).to have_css('#deps-refresh-status', text: '✓ Done')
      click_button 'Close & Refresh'
    end
    expect(page).to have_css('#deps-refresh-install-modal', visible: :hidden)
    expect(page).to have_css('#check-dependencies')
    expect(Privileged.calls).to include(['packages.refresh', {}])
  end
end
