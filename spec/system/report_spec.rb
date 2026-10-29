require 'rails_helper'

# Report a problem in the browser (report.js): the switch between the details without names and
# addresses and as they are, What happened needed first, and the issue's link GitHub opens with,
# cut when the report is too long for it (the whole report then saved as a file to attach).
# window.open and saving a file are caught, so the example sees what would go where.
RSpec.describe 'Report a problem', type: :system do
  let(:details) { "The flag said on /files/trash: Greyhole didn't start on nas\n\nStorage: Greyhole at 192.168.1.20" }

  before do
    allow(ProblemReport).to receive_messages(details: details, version: '1.4.4 (bc809de)', storage_choice: 'Greyhole (drives in a pool)')
    allow(ReportScrubber).to receive(:names).and_return('server-name' => ['nas'])
    sign_in_as_admin
  end

  # What window.open was asked to open, the email link, and the files the page saved, instead of
  # doing any of them.
  def catch_leaving
    page.execute_script(<<~JS)
      window.opened = [];
      window.open = function(url) { window.opened.push(url); return null; };
      window.saved = [];
      var click = HTMLAnchorElement.prototype.click;
      HTMLAnchorElement.prototype.click = function() {
        if (this.download) { window.saved.push(this.download); return; }
        if (this.href.indexOf('mailto:') === 0) { window.mailed = this.href; return; }
        click.call(this);
      };
    JS
  end

  def opened
    page.evaluate_script('window.opened').map { |url| URI(url) }
  end

  # The email link's address, and its subject and body.
  def mailed
    to, query = page.evaluate_script('window.mailed').delete_prefix('mailto:').split('?', 2)
    [to, URI.decode_www_form(query).to_h]
  end

  def fields(url)
    URI.decode_www_form(url.query).to_h
  end

  it 'switches the details between without names and as they are, each keeping what was changed in it' do
    visit "/settings/help/report?about=#{CGI.escape("Greyhole didn't start on nas")}&page=%2Ffiles%2Ftrash"
    expect(find('#report-details').value).to include('Greyhole at <lan-address-1>')
    fill_in 'report-details', with: "#{find('#report-details').value}\nMy note"
    find('#report-scrub').click
    expect(page).to have_css('#report-scrub[aria-checked="false"]')
    expect(find('#report-details').value).to include('Greyhole at 192.168.1.20')
    expect(page).to have_css('#report-scrub-note', text: 'Showing the real names and addresses')
    find('#report-scrub').click
    expect(find('#report-details').value).to end_with('My note')
  end

  it 'opens a new GitHub issue filled in, once What happened says something' do
    visit '/settings/help/report'
    catch_leaving
    click_button 'Open on GitHub'
    expect(page).to have_css('#report-what.is-invalid')
    expect(page.evaluate_script('window.opened')).to be_empty

    fill_in 'report-what', with: "Greyhole didn't start\nafter adding a drive"
    fill_in 'report-steps', with: '1. Disks → Storage Pool'
    click_button 'Open on GitHub'
    url = opened.sole
    expect("#{url.host}#{url.path}").to eq('github.com/CatDogBark/Amahi-kai/issues/new')
    expect(fields(url)).to eq(
      'template' => 'bug_report.yml', 'title' => "Greyhole didn't start", 'version' => '1.4.4 (bc809de)',
      'what-happened' => "Greyhole didn't start\nafter adding a drive", 'steps' => '1. Disks → Storage Pool',
      'storage' => 'Greyhole (drives in a pool)', 'report' => find('#report-details').value.strip
    )
    expect(page.evaluate_script('window.saved')).to be_empty
    expect(page).to have_css('#report-status', text: 'GitHub opened in a new tab')
  end

  it "cuts a report too long for the link, and saves the whole of it to attach" do
    allow(ProblemReport).to receive(:details).and_return((1..400).map { |n| "log line #{n} #{'x' * 40}" }.join("\n"))
    visit '/settings/help/report'
    catch_leaving
    fill_in 'report-what', with: 'It broke'
    click_button 'Open on GitHub'
    url = opened.sole
    expect(url.to_s.length).to be <= 7000
    expect(fields(url)['report']).to start_with('log line 1 ').and end_with('The rest is in the file saved with this report: attach it.')
    saved = page.evaluate_script('window.saved').sole
    expect(saved).to match(/\Aamahi-kai-report-\d{4}-\d{2}-\d{2}-\d{4}\.txt\z/)
    expect(page).to have_css('#report-status', text: "saved as #{saved}")
  end

  it 'opens an email to the maintainer, with the details in a file to attach when they are too long for it' do
    visit '/settings/help/report'
    catch_leaving
    fill_in 'report-what', with: 'It broke'
    click_button 'Send by email'
    to, query = mailed
    expect(to).to eq('catdogbark@pm.me')
    expect(query).to include('subject' => 'Amahi-kai: It broke')
    body = query['body']
    expect(body).to start_with("What happened\nIt broke\n\nAmahi-kai 1.4.4 (bc809de)")
    expect(body).to include('Greyhole at <lan-address-1>') # short enough: all of it, and no file
    expect(page.evaluate_script('window.saved')).to be_empty

    allow(ProblemReport).to receive(:details).and_return((1..100).map { |n| "log line #{n}" }.join("\n"))
    visit '/settings/help/report'
    catch_leaving
    fill_in 'report-what', with: 'It broke'
    click_button 'Send by email'
    body = mailed.last['body']
    saved = page.evaluate_script('window.saved').sole
    expect(body).to end_with("The system details and logs are in #{saved}, attached.")
    expect(body).not_to include('log line')
    expect(page).to have_css('#report-status', text: "saved as #{saved}")
  end

  it 'saves the report as a file, and copies it' do
    visit '/settings/help/report'
    catch_leaving
    fill_in 'report-what', with: 'It broke'
    click_button 'Download report'
    expect(page.evaluate_script('window.saved').sole).to start_with('amahi-kai-report-')
    click_button 'Copy'
    expect(page).to have_css('#report-copy', text: 'Copied')
  end
end
