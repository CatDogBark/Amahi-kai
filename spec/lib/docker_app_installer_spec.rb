require 'rails_helper'

RSpec.describe DockerAppInstaller do
  before do
    allow(Shell).to receive(:run).and_return(true)
  end

  describe '.create_init_files' do
    let(:reporter) { double('reporter', call: nil) }

    before do
      allow(FileUtils).to receive(:mkdir_p).and_call_original
      allow(FileUtils).to receive(:mkdir_p).with(DockerAppInstaller::STAGING_DIR)
      allow(File).to receive(:write).and_call_original
    end

    it 'creates init files via staging' do
      init_files = [{ host: '/opt/app/config.yml', content: 'key: value' }]

      allow(File).to receive(:write).with(anything, 'key: value')
      described_class.create_init_files(init_files, reporter: reporter)

      expect(Shell).to have_received(:run).with(/mkdir -p/)
      expect(Shell).to have_received(:run).with(/cp.*config\.yml/)
      expect(reporter).to have_received(:call).with(/Creating config/)
    end

    it 'handles string keys' do
      init_files = [{ 'host' => '/opt/app/config.yml', 'content' => 'data' }]
      allow(File).to receive(:write).with(anything, 'data')
      described_class.create_init_files(init_files)
    end

    it 'handles nil init_files' do
      expect { described_class.create_init_files(nil) }.not_to raise_error
    end
  end

  describe '.create_volumes' do
    let(:reporter) { double('reporter', call: nil) }

    it 'creates volume directories' do
      volumes = ['/opt/app/data:/data']
      described_class.create_volumes(volumes, reporter: reporter)
      expect(Shell).to have_received(:run).with(/mkdir -p.*\/opt\/app\/data/)
      expect(Shell).to have_received(:run).with(/chmod -R 777/)
    end

    it 'skips /var/run/ paths' do
      volumes = ['/var/run/docker.sock:/var/run/docker.sock']
      described_class.create_volumes(volumes, reporter: reporter)
      expect(Shell).not_to have_received(:run).with(/mkdir -p/)
    end

    it 'sets ownership when user provided' do
      volumes = ['/opt/app/data:/data']
      described_class.create_volumes(volumes, user: '1000', reporter: reporter)
      expect(Shell).to have_received(:run).with(/chown -R.*1000/)
    end

    it 'handles nil volumes' do
      expect { described_class.create_volumes(nil) }.not_to raise_error
    end
  end

  describe '.pull_image' do
    let(:reporter) { double('reporter', call: nil) }

    it 'pulls docker image' do
      io = StringIO.new("Pulling layer 1\nPulling layer 2\n")
      allow(IO).to receive(:popen).with(/docker pull myapp:latest/) { |&blk| blk.call(io); system("true") }

      described_class.pull_image('myapp:latest', reporter: reporter)
      expect(reporter).to have_received(:call).with('Pulling image myapp:latest...')
      expect(reporter).to have_received(:call).with('  ✓ Pull complete')
    end

    it 'raises on pull failure' do
      io = StringIO.new("Error\n")
      allow(IO).to receive(:popen) { |&blk| blk.call(io); system("false") }

      expect { described_class.pull_image('bad:image') }.to raise_error(/Failed to pull/)
    end
  end

  describe '.create_container' do
    let(:reporter) { double('reporter', call: nil) }
    let(:entry) { { ports: { '80' => '8080' }, volumes: ['/data:/data'], environment: { 'KEY' => 'val' }, docker_args: ['--network=host'] } }

    before do
      # Stub backtick and set $? via a real command
      allow(described_class).to receive(:`) { |_cmd| system("true"); "container_id\n" }
    end

    it 'builds and runs docker create command' do
      result = described_class.create_container(identifier: 'myapp', image: 'myapp:latest', entry: entry, reporter: reporter)
      expect(result).to eq('amahi-myapp')
      expect(Shell).to have_received(:run).with(/docker rm -f.*amahi-myapp/)
    end

    it 'raises on create failure' do
      allow(described_class).to receive(:`) { |_cmd| system("false"); "error\n" }
      expect {
        described_class.create_container(identifier: 'myapp', image: 'img', entry: {}, reporter: reporter)
      }.to raise_error('Failed to create container')
    end

    it 'handles init_files volumes' do
      entry_with_init = { init_files: [{ host: '/opt/config.yml', container: '/app/config.yml' }] }
      described_class.create_container(identifier: 'app', image: 'img', entry: entry_with_init, reporter: reporter)
    end

    it 'handles hash volume mappings' do
      entry_with_hash_vol = { volumes: [{ '/container/path' => '/host/path' }] }
      described_class.create_container(identifier: 'app', image: 'img', entry: entry_with_hash_vol, reporter: reporter)
    end
  end

  describe '.start_container' do
    it 'starts the container' do
      reporter = double('reporter', call: nil)
      described_class.start_container('amahi-myapp', reporter: reporter)
      expect(Shell).to have_received(:run).with('docker start amahi-myapp 2>/dev/null')
      expect(reporter).to have_received(:call).with('Starting container...')
    end
  end
end
