require 'spec_helper'

# Report a problem (SettingsController#report): for admins; it starts with what a red flag said
# and where, and the details with the names and addresses taken out (and as they are, for the
# switch); the page sends nothing, so it carries where it goes.
describe 'Report a problem', type: :request do
  let(:details) { "The flag said on /files/trash: Greyhole didn't start on nas\n\nStorage: Greyhole at 192.168.1.20" }

  before do
    allow(ProblemReport).to receive_messages(details: details, version: '1.4.4 (bc809de)', storage_choice: 'Greyhole (drives in a pool)')
    allow(ReportScrubber).to receive(:names).and_return('server-name' => ['nas'])
  end

  it 'is for admins' do
    get '/settings/help/report'
    expect(response).to redirect_to(new_user_session_url)
    login_as(create(:user))
    get '/settings/help/report'
    expect(response).to redirect_to(root_url)
  end

  describe 'as an admin' do
    before { login_as_admin }

    it "starts with what the flag said, and this server's details without its names and addresses" do
      get '/settings/help/report', params: { about: "Greyhole didn't start on nas", page: '/files/trash' }
      expect(ProblemReport).to have_received(:details).with(about: "Greyhole didn't start on nas", page: '/files/trash')
      page = Nokogiri::HTML(response.body)
      expect(page.at_css('#report-what').text).to eq("Greyhole didn't start on <server-name>")
      expect(page.at_css('#report-details').text)
        .to eq("The flag said on /files/trash: Greyhole didn't start on <server-name>\n\nStorage: Greyhole at <lan-address-1>")
      expect(page.at_css('#report-details-as-is').text).to eq(details) # for the switch, hidden
      expect(page.at_css('#report-details-as-is')['hidden']).not_to be_nil
      expect(page.at_css('#report-scrub')['aria-checked']).to eq('true')
      report = page.at_css('.kai-report')
      expect(report['data-issues-url']).to eq('https://github.com/CatDogBark/Amahi-kai/issues/new')
      expect(report['data-email']).to eq('catdogbark@pm.me')
      expect(report['data-version']).to eq('1.4.4 (bc809de)')
      expect(report['data-storage']).to eq('Greyhole (drives in a pool)')
      expect(page.at_css('.setup-subtab .active-subtab-link').text.strip).to eq('Help')
    end

    it 'starts empty from Help, and takes only a path as the page it came from' do
      get '/settings/help/report'
      expect(ProblemReport).to have_received(:details).with(about: nil, page: nil)
      expect(Nokogiri::HTML(response.body).at_css('#report-what').text).to eq('')
      get '/settings/help/report', params: { about: 'x', page: 'https://elsewhere.example/' }
      expect(ProblemReport).to have_received(:details).with(about: 'x', page: nil)
    end
  end
end
