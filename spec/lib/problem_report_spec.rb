require 'rails_helper'

# A problem's report (ProblemReport): what the flag said and where, this server, the newest lines
# of the logs most likely to show the fault, and an app's own when it needs attention.
RSpec.describe ProblemReport do
  before do
    allow(ServerSummary).to receive(:text).and_return("Amahi-kai: 1.4.4 (bc809de) · releases\nApps: 1 needs attention")
    allow(HelpLogs).to receive(:lines) { |key, count| ["#{key} line (#{count})"] }
  end

  it 'starts with what the flag said and where, then the server, then each log by name' do
    create(:docker_app, identifier: 'transmission', name: 'Transmission', status: 'error', error_message: 'setfacl exited 1')
    create(:docker_app, identifier: 'gitea', name: 'Gitea', status: 'running')
    expect(described_class.details(about: "Transmission's install failed", page: '/apps')).to eq(<<~TEXT.chomp)
      The flag said on /apps: Transmission's install failed

      Amahi-kai: 1.4.4 (bc809de) · releases
      Apps: 1 needs attention

      ── Root helper, last 30 lines ──
      helper line (30)

      ── Amahi-kai, last 30 lines ──
      amahi line (30)

      ── System Update, last 15 lines ──
      update line (15)

      ── System journal, last 30 lines ──
      journal line (30)

      ── Transmission (needs attention), last 20 lines ──
      app:transmission line (20)
    TEXT
  end

  it "says when a log couldn't be read, and leaves the flag out when there was none" do
    allow(HelpLogs).to receive(:lines).with('journal', 30).and_raise(HelpLogs::Unreadable, 'journalctl exited 1')
    details = described_class.details
    expect(details).to start_with('Amahi-kai: 1.4.4')
    expect(details).to include("── System journal, last 30 lines ──\n(couldn't be read: journalctl exited 1)")
  end

  it "answers the bug form's Storage with one of its choices" do
    zfs = StoragePools::Pool.new(name: 'data', managed: true)
    allow(StoragePools).to receive(:status).and_return(pools: [zfs])
    allow(Greyhole).to receive(:installed?).and_return(false)
    expect(described_class.storage_choice).to eq('A ZFS pool')
    allow(Greyhole).to receive(:installed?).and_return(true)
    allow(DiskPoolPartition).to receive(:exists?).and_return(true)
    expect(described_class.storage_choice).to eq('Both')
    allow(StoragePools).to receive(:status).and_return(pools: [])
    expect(described_class.storage_choice).to eq('Greyhole (drives in a pool)')
    allow(Greyhole).to receive(:installed?).and_return(false)
    expect(described_class.storage_choice).to eq('Neither, or not sure')
    form = YAML.safe_load(Rails.root.join('.github/ISSUE_TEMPLATE/bug_report.yml').read)
    choices = form['body'].find { |field| field['id'] == 'storage' }.dig('attributes', 'options')
    expect(described_class::STORAGE.values).to match_array(choices) # word for word, or GitHub leaves it unset
  end
end
