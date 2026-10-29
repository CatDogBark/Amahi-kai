require 'spec_helper'

# Settings → Help (SettingsController#help, help_log, help_logs): Report a problem, this server,
# and its logs, for admins. It replaced the old debug pages (/tab/debug).
describe 'Settings → Help', type: :request do
  let(:summary) { [['Amahi-kai', '1.4.4 (bc809de) · releases'], ['Storage', 'ZFS pool data: ONLINE']] }

  before do
    allow(ServerSummary).to receive_messages(rows: summary, text: "Amahi-kai: 1.4.4 (bc809de) · releases\nStorage: ZFS pool data: ONLINE")
    allow(HelpLogs).to receive(:lines).and_call_original
    allow(HelpLogs).to receive(:lines).with('amahi').and_return(['Started GET "/apps"', 'Completed 200 OK'])
  end

  it 'is for admins' do
    get '/settings/help'
    expect(response).to redirect_to(new_user_session_url)
    login_as(create(:user))
    get '/settings/help'
    expect(response).to redirect_to(root_url)
    get '/settings/help/log', params: { source: 'helper' }
    expect(response).to redirect_to(root_url)
  end

  describe 'as an admin' do
    before { login_as_admin }

    it 'offers Report a problem, says what this server is, and shows its own log with a tab for each' do
      create(:docker_app, identifier: 'gitea', name: 'Gitea', status: 'running')
      get '/settings/help'
      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css('a#report-a-problem')['href']).to eq('/settings/help/report')
      expect(page.css('.kai-help-summary dt').map(&:text)).to eq(%w[Amahi-kai Storage])
      expect(page.css('.kai-help-summary dd').map(&:text)).to eq(['1.4.4 (bc809de) · releases', 'ZFS pool data: ONLINE'])
      expect(page.css('[data-log-source]').map { |tab| tab['data-log-source'] }).to eq(%w[amahi helper update journal app:gitea])
      expect(page.at_css('[data-log-source="amahi"]')['aria-selected']).to eq('true')
      expect(page.at_css('#help-log').text.strip).to eq("Started GET \"/apps\"\nCompleted 200 OK")
      expect(page.at_css('.setup-subtab .active-subtab-link').text.strip).to eq('Help')
    end

    it 'gives one log at a time, and says when there is none by that name or it could not be read' do
      allow(HelpLogs).to receive(:lines).with('journal').and_return(['Oct 29 03:41:06 nas systemd[1]: Started x.'])
      get '/settings/help/log', params: { source: 'journal' }
      expect(response.parsed_body).to eq('lines' => ['Oct 29 03:41:06 nas systemd[1]: Started x.'])

      get '/settings/help/log', params: { source: '../../etc/shadow' }
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to include("there's no log")

      allow(HelpLogs).to receive(:lines).with('journal').and_raise(HelpLogs::Unreadable, 'journalctl exited 1')
      get '/settings/help/log', params: { source: 'journal' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq("Couldn't read it: journalctl exited 1")
    end

    it 'downloads the summary and every log as one text file' do
      allow(HelpLogs).to receive(:text).and_return("── Amahi-kai ──\nCompleted 200 OK")
      get '/settings/help/logs'
      expect(response.media_type).to eq('text/plain')
      expect(response.headers['Content-Disposition']).to match(/attachment; filename="amahi-kai-logs-\d{4}-\d{2}-\d{2}-\d{4}\.txt"/)
      expect(response.body).to eq("Amahi-kai: 1.4.4 (bc809de) · releases\nStorage: ZFS pool data: ONLINE\n\n── Amahi-kai ──\nCompleted 200 OK\n")
    end

    it 'takes the old debug pages there' do
      %w[/tab/debug /tab/debug/logs /tab/debug/system].each do |path|
        get path
        expect(response).to redirect_to('/settings/help')
      end
    end
  end
end
