require 'rails_helper'

# The logs Settings → Help shows and a problem's report quotes (HelpLogs): files read from their
# end, the helper's JSON lines made readable, the journal and the apps' through the root helper.
RSpec.describe HelpLogs do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(dir) }

  def file(name, text)
    path = File.join(dir, name)
    File.binwrite(path, text)
    path
  end

  describe 'reading a file from its end' do
    it 'gives its last lines, and none for a file not there yet' do
      path = file('a.log', (1..10).map { |n| "line #{n}" }.join("\n") << "\n")
      expect(described_class.tail(path, 3)).to eq(['line 8', 'line 9', 'line 10'])
      expect(described_class.tail(File.join(dir, 'missing.log'), 3)).to eq([])
    end

    it "reads only the file's end, leaving out the line it cuts" do
      stub_const('HelpLogs::TAIL_BYTES', 20)
      path = file('b.log', "a long first line that won't fit\nsecond\nthird\n")
      expect(described_class.tail(path, 10)).to eq(%w[second third])
    end

    it 'shows a line that is not UTF-8 instead of failing' do
      expect(described_class.tail(file('c.log', "ok\nbad \xFF byte\n".b), 5)).to eq(['ok', 'bad ? byte'])
    end
  end

  describe "the root helper's lines" do
    it 'says when, what, with what, and how it went' do
      ok = '{"time":"2026-10-29T03:40:58.120Z","op":"shares.create","args":{"name":"Downloads"},"result":null,"ms":41}'
      failed = '{"time":"2026-10-29T03:41:06.002Z","op":"apps.install","args":{"app":"transmission","shares":[{"name":"Downloads","write":true}]},' \
               '"error":"setfacl exited 1","ms":8143}'
      expect(described_class.helper_line(ok)).to eq('2026-10-29 03:40:58 shares.create name=Downloads → ok (41 ms)')
      expect(described_class.helper_line(failed))
        .to eq('2026-10-29 03:41:06 apps.install app=transmission shares=[{"name":"Downloads","write":true}] → failed: setfacl exited 1 (8143 ms)')
    end

    it 'cuts long arguments, and leaves a line that is not one of its entries as it is' do
      long = JSON.generate('time' => '2026-10-29T03:41:06Z', 'op' => 'network.apply', 'args' => { 'netplan' => 'x' * 500 })
      expect(described_class.helper_line(long)).to match(/netplan=x{290,}… → ok\z/)
      expect(described_class.helper_line('not json')).to eq('not json')
      expect(described_class.helper_line('[1, 2]')).to eq('[1, 2]')
    end
  end

  describe 'the logs there are' do
    let(:apps) { [instance_double(DockerApp, identifier: 'gitea', name: 'Gitea')] }

    it "lists the app's, the journal and each installed app's, and reads each" do
      expect(described_class.sources(apps).map(&:key)).to eq(%w[amahi helper update journal app:gitea])
      stub_const('HelpLogs::HELPER_LOG', file('helper.log', "#{JSON.generate('time' => '2026-10-29T01:00:00Z', 'op' => 'apps.status')}\n"))
      expect(described_class.lines('helper')).to eq(['2026-10-29 01:00:00 apps.status → ok'])

      allow(Privileged).to receive(:call).with('system.journal', lines: 150).and_return('lines' => ['Oct 29 started'])
      allow(Privileged).to receive(:call).with('apps.logs', app: 'gitea', lines: 150).and_return('lines' => ['up'])
      expect(described_class.lines('journal')).to eq(['Oct 29 started'])
      expect(described_class.lines('app:gitea')).to eq(['up'])
      allow(Privileged).to receive(:call).with('apps.logs', app: 'gitea', lines: 150).and_return('lines' => [], 'missing' => true)
      expect(described_class.lines('app:gitea')).to eq(['(no container: install it again)'])
    end

    it "refuses a log that isn't one of them, and says why one couldn't be read" do
      expect { described_class.lines('../../etc/shadow') }.to raise_error(HelpLogs::Unreadable, /there's no log/)
      expect { described_class.lines('app:../x') }.to raise_error(HelpLogs::Unreadable)
      allow(Privileged).to receive(:call).and_raise(Privileged::Error.new('system.journal', 'journalctl exited 1'))
      expect { described_class.lines('journal') }.to raise_error(HelpLogs::Unreadable, 'journalctl exited 1')
    end

    it 'puts every log under its name, saying which could not be read' do
      stub_const('HelpLogs::HELPER_LOG', file('helper.log', ''))
      stub_const('HelpLogs::UPDATE_LOG', file('update.log', "==> ✓ Amahi-kai updated and running!\n"))
      allow(described_class).to receive(:rails_log).and_return(file('app.log', "Started GET /\n"))
      allow(Privileged).to receive(:call).with('system.journal', lines: 5).and_raise(Privileged::Error.new('system.journal', 'no journal'))
      allow(Privileged).to receive(:call).with('apps.logs', app: 'gitea', lines: 5).and_return('lines' => ['up'])
      expect(described_class.text(5, apps)).to eq(<<~TEXT.chomp)
        ── Amahi-kai ──
        Started GET /

        ── Root helper ──
        (empty)

        ── System Update ──
        ==> ✓ Amahi-kai updated and running!

        ── System journal ──
        (couldn't be read: no journal)

        ── Gitea ──
        up
      TEXT
    end
  end
end
