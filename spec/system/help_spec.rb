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
    expect(page).to have_css('#help-log-about', text: "Amahi-kai's services and the ones it runs")
    expect(page).to have_css('[data-log-source="journal"][aria-selected="true"]')
    click_button 'Amahi-kai'
    expect(page).to have_css('#help-log', text: 'Completed 200 OK')
    click_button 'System journal'
    expect(page).to have_css('#help-log', text: 'Started amahi-kai.service.')
    expect(HelpLogs).to have_received(:lines).with('journal').once # kept from the first time
    expect(page).to have_link('Download logs', href: '/settings/help/logs')
  end

  # An app's page links to its own output (one that keeps restarting)
  it 'opens on the log its address names, and fetches the others when their tab is opened' do
    create(:docker_app, identifier: 'gitea', name: 'Gitea', status: 'restarting')
    allow(HelpLogs).to receive(:lines).with('app:gitea').and_return(['panic: config not found'])
    sign_in_as_admin
    visit '/settings/help?log=app:gitea'
    expect(page).to have_css('[data-log-source="app:gitea"][aria-selected="true"]')
    expect(page).to have_css('#help-log', text: 'panic: config not found')
    click_button 'Amahi-kai'
    expect(page).to have_css('#help-log', text: 'Completed 200 OK')
    click_button 'Gitea'
    expect(page).to have_css('#help-log', text: 'panic: config not found')
    expect(HelpLogs).to have_received(:lines).with('app:gitea').once # in the page, and kept
  end
end
