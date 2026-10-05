require 'rails_helper'

# The dashboard's Jobs card and Settings → Jobs (ScheduledJobs), and services that are idle
# rather than stopped.
RSpec.describe 'Scheduled jobs', type: :request do
  let(:jobs) do
    [ScheduledJobs::Job.new(key: 'storage-check', name: 'Storage health check', about: "Reads the pools and every drive's SMART data",
                            schedule: 'Every 15 minutes', last_run: 4.minutes.ago, next_run: 11.minutes.from_now, result: :ok),
     ScheduledJobs::Job.new(key: 'indexer', name: 'File search index', about: 'Adds new files', schedule: 'Every 10 minutes',
                            last_run: 1.minute.ago, next_run: 9.minutes.from_now, result: :failed),
     ScheduledJobs::Job.new(key: 'update-check', name: 'Check for updates', about: 'Asks GitHub', schedule: 'Every 6 hours',
                            last_run: nil, next_run: 10.minutes.from_now, result: nil)]
  end

  def page
    Nokogiri::HTML(response.body)
  end

  before { allow(ScheduledJobs).to receive(:all).and_return(jobs) }

  context 'as an admin' do
    before { login_as_admin }

    it 'puts a Jobs card next to System and Services on the dashboard, a third of the row each' do
      get root_path
      card = page.at_css('#jobs-card')
      rows = card.css('tbody tr').map { |tr| tr.text.squish }
      expect(rows).to eq(['Storage health check Last 4 minutes ago · next in 11 minutes OK',
                          'File search index Last 1 minute ago · next in 9 minutes Failed',
                          'Check for updates Last not yet · next in 10 minutes Not run yet'])
      expect(card.at_css('a')['href']).to eq('/settings/jobs')
      expect(card.ancestors('.col-lg-4').size).to eq(1)
      expect(page.css('.row.mb-4.g-3 > .col-lg-4').size).to eq(3)
    end

    it 'lists the jobs on Settings → Jobs, with what each does and its schedule' do
      get '/settings/jobs'
      expect(response).to have_http_status(:ok)
      rows = page.css('#jobs-table tbody tr')
      expect(rows.map { |tr| tr['id'] }).to eq(%w[job-storage-check job-indexer job-update-check])
      first = rows.first.css('td').map { |td| td.text.squish }
      expect(rows.first.at_css('.fw-bold').text).to eq('Storage health check')
      expect(rows.first.at_css('.small').text).to eq("Reads the pools and every drive's SMART data")
      expect(first[1..3]).to eq(['Every 15 minutes', '4 minutes ago', 'OK'])
      expect(first[4]).to end_with('in 11 minutes')
      expect(rows[2].css('td')[2].text.strip).to eq('Not yet')
    end

    it 'shows an idle service as Idle, with why, on the dashboard, System Status and Servers' do
      smartd = SystemServices::Service.new({ key: 'smartd', name: 'SMART monitoring', unit: 'smartmontools', note: 'x' },
                                           { 'LoadState' => 'loaded', 'ActiveState' => 'failed' })
      smartd.idle!('Nothing to watch')
      allow(SystemServices).to receive(:all).and_return([smartd])
      get root_path
      expect(page.at_xpath("//tr[td[contains(., 'SMART monitoring')]]//span[@class='badge bg-info text-dark']")['title']).to eq('Nothing to watch')
      get '/settings/system_status'
      expect(page.at_xpath("//tr[td[contains(., 'SMART monitoring')]]").css('td').map { |td| td.text.strip }).to eq(['SMART monitoring', 'Idle', 'Nothing to watch'])
      Setting.set('advanced', '1')
      get '/settings/servers'
      expect(page.at_css('#service-smartd .badge').text).to eq('Idle')
    end
  end

  it "keeps the Jobs card from users who aren't admins, who get System and Services side by side" do
    ensure_setup_completed!
    login_as(create(:user))
    get root_path
    expect(page.at_css('#jobs-card')).to be_nil
    expect(page.css('.row.mb-4.g-3 > .col-md-6').size).to eq(2)
  end
end
