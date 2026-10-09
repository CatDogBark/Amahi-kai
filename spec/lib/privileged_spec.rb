require 'rails_helper'

RSpec.describe Privileged do
  describe 'outside production (Shell.simulated?)' do
    it 'records the call and answers ok' do
      expect(described_class.call('users.set_name', login: 'ann', name: 'Ann')).to eq('ok' => true)
      expect(described_class.calls).to eq([['users.set_name', { login: 'ann', name: 'Ann' }]])
    end

    it 'refuses an operation the helper does not have' do
      expect { described_class.call('users.chmod', path: '/') }.to raise_error(ArgumentError, /unknown privileged operation/)
    end
  end

  describe 'running the helper' do
    let(:ok_status) { instance_double(Process::Status, success?: true, exitstatus: 0) }

    before { Shell.simulated = false }
    after { Shell.simulated = nil }

    def status(code)
      instance_double(Process::Status, success?: code.zero?, exitstatus: code)
    end

    it 'runs it through sudo -n with the arguments as JSON on stdin and a clean environment' do
      allow(Process).to receive(:uid).and_return(1000)
      allow(Open3).to receive(:capture3).and_return(["{\"ok\":true}\n", '', status(0)])

      expect(described_class.call('users.set_password', login: 'ann', password: 'hunter2hunter2')).to eq('ok' => true)

      expect(Open3).to have_received(:capture3).with(
        { 'PATH' => '/usr/sbin:/usr/bin:/sbin:/bin' }, '/usr/bin/sudo', '-n', '/usr/local/sbin/amahi-helper', 'users.set_password',
        stdin_data: '{"login":"ann","password":"hunter2hunter2"}', unsetenv_others: true, chdir: '/'
      )
    end

    it 'runs it directly when already root' do
      allow(Process).to receive(:uid).and_return(0)
      allow(Open3).to receive(:capture3).and_return(["{\"ok\":true}\n", '', status(0)])

      described_class.call('samba.reload')

      expect(Open3).to have_received(:capture3)
        .with(anything, '/usr/local/sbin/amahi-helper', 'samba.reload', stdin_data: '{}', unsetenv_others: true, chdir: '/')
    end

    it "raises with the helper's reason, marked as a refusal for exit status 1" do
      allow(Open3).to receive(:capture3).and_return(["{\"ok\":false,\"error\":\"login root is reserved\"}\n", '', status(1)])

      expect { described_class.call('users.create', login: 'root', name: 'x') }.to raise_error(Privileged::Error) { |e|
        expect(e.message).to eq('login root is reserved')
        expect(e).to be_refused
        expect(e.operation).to eq('users.create')
      }
    end

    it 'raises with stderr when the helper gives no answer (sudo refused, for example)' do
      allow(Open3).to receive(:capture3).and_return(['', "sudo: a password is required\n", status(1)])

      expect { described_class.call('samba.reload') }.to raise_error(Privileged::Error, 'sudo: a password is required')
    end

    it 'raises a failure (not a refusal) when a step failed' do
      allow(Open3).to receive(:capture3).and_return(["{\"ok\":false,\"error\":\"useradd exited 1: boom\"}\n", '', status(2)])

      expect { described_class.call('users.create', login: 'ann', name: 'A') }
        .to raise_error(Privileged::Error) { |e| expect(e).not_to be_refused }
    end

    describe 'with a progress block' do
      # A stand-in helper: echoes its arguments, writes progress to stderr, then replies.
      def fake_helper(script)
        allow(described_class).to receive(:command).and_return(['/bin/sh', '-c', script])
      end

      it "yields the helper's stderr lines as they come and returns its reply" do
        fake_helper('read args; echo "got $args" >&2; echo "Unpacking greyhole ..." >&2; echo \'{"ok":true}\'')
        lines = []
        expect(described_class.call('packages.install', packages: ['greyhole']) { |line| lines << line }).to eq('ok' => true)
        expect(lines).to eq(['got {"packages":["greyhole"]}', 'Unpacking greyhole ...'])
      end

      it 'keeps reading when the block fails, so the helper runs to the end' do
        fake_helper('cat >/dev/null; for i in 1 2 3; do echo "line $i" >&2; done; echo \'{"ok":true,"done":3}\'')
        seen = []
        reply = described_class.call('packages.install', packages: ['greyhole']) do |line|
          seen << line
          raise IOError, 'stream closed'
        end
        expect(reply).to eq('ok' => true, 'done' => 3)
        expect(seen).to eq(['line 1'])
      end

      it "raises with the helper's reason" do
        fake_helper('cat >/dev/null; echo "E: Unable to locate package" >&2; echo \'{"ok":false,"error":"apt-get exited 100"}\'; exit 2')
        expect { described_class.call('packages.install', packages: ['greyhole']) { |_line| nil } }
          .to raise_error(Privileged::Error, 'apt-get exited 100')
      end
    end

    it 'raises when the helper is missing' do
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, '/usr/local/sbin/amahi-helper')

      expect { described_class.call('samba.reload') }.to raise_error(Privileged::Error, /couldn't be run/)
    end
  end

  # Every operation name the app uses is one the helper has, and every operation is
  # used: the helper shouldn't keep root abilities nothing asks for. Operation names are
  # found as quoted strings in the helper's namespaces, so names kept in a table (as in
  # SystemServices::ACTION_OPERATIONS) count too, and so do the systemd units that run one
  # (ExecStart=/usr/local/sbin/amahi-helper pools.run_snapshots, or ExecStart=-/usr/... for one
  # whose failure the unit ignores).
  describe 'contract with libexec/amahi-helper' do
    let(:called) do
      namespaces = described_class.operations.map { |op| op.split('.').first }.uniq
      pattern = /['"]((?:#{namespaces.join('|')})\.[a-z_]+)['"]/
      in_code = Dir[Rails.root.join('{app,lib}/**/*.rb')].flat_map { |file| File.read(file).scan(pattern).flatten }
      in_units = Dir[Rails.root.join('config/systemd/*.service')].flat_map do |file|
        File.read(file).scan(%r{^ExecStart=-?/usr/local/sbin/amahi-helper ([a-z]+\.[a-z_]+)$}).flatten
      end
      in_scripts = Dir[Rails.root.join('bin/amahi-*')].flat_map do |file|
        File.read(file).scan(%r{/usr/local/sbin/amahi-helper ([a-z]+\.[a-z_]+)}).flatten
      end
      (in_code + in_units + in_scripts).uniq
    end

    it 'only calls operations the helper has' do
      expect(called - described_class.operations).to eq([])
    end

    it 'has no operation nothing calls' do
      expect(described_class.operations - called).to eq([])
    end
  end
end
