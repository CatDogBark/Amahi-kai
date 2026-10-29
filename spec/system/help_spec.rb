require 'rails_helper'

# Settings → Help in the browser: its logs' tabs (help.js) show Amahi-kai's own at first, fetch
# the journal's the first time its tab is opened, and keep it.
RSpec.describe 'Settings → Help', type: :system do
  before do
    allow(ServerSummary).to receive(:rows).and_return([['Amahi-kai', '1.4.4 (bc809de) · releases']])
    allow(HelpLogs).to receive(:lines).and_call_original
    allow(HelpLogs).to receive(:lines).with('amahi').and_return(['Completed 200 OK'])
    allow(HelpLogs).to receive(:lines).with('journal').and_return(['Oct 29 03:41:06 nas systemd[1]: Started amahi-kai.service.'])
  end

  it "switches between the logs, fetching each the first time it's opened" do
    sign_in_as_admin
    visit '/settings/help'
    expect(page).to have_css('#help-log', text: 'Completed 200 OK')
    click_button 'System journal'
    expect(page).to have_css('#help-log', text: 'Started amahi-kai.service.')
    expect(page).to have_css('#help-log-about', text: "The system's own log")
    expect(page).to have_css('[data-log-source="journal"][aria-selected="true"]')
    click_button 'Amahi-kai'
    expect(page).to have_css('#help-log', text: 'Completed 200 OK')
    click_button 'System journal'
    expect(page).to have_css('#help-log', text: 'Started amahi-kai.service.')
    expect(HelpLogs).to have_received(:lines).with('journal').once # kept from the first time
    expect(page).to have_link('Download logs', href: '/settings/help/logs')
  end
end
