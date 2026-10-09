require 'rails_helper'

RSpec.describe SystemInfo do
  def proc_file(text)
    file = Tempfile.new('proc')
    file.write(text)
    file.close
    @files = [*@files, file]
    file.path
  end

  after { @files&.each(&:unlink) }

  describe '.uptime' do
    it 'says it as uptime -p does, without "up"' do
      expect(described_class.uptime(proc_file("273960.52 1000.00\n"))).to eq('3 days, 4 hours, 6 minutes')
      expect(described_class.uptime(proc_file("3660.0 1.0\n"))).to eq('1 hour, 1 minute')
      expect(described_class.uptime(proc_file("30.0 1.0\n"))).to eq('0 minutes')
    end

    it 'is unknown without /proc' do
      expect(described_class.uptime('/nonexistent/uptime')).to eq('unknown')
    end
  end

  describe '.swaps' do
    it 'lists the swap in use, in bytes' do
      swaps = proc_file(<<~SWAPS)
        Filename                                Type            Size            Used            Priority
        /swap.img                               file            2097148         0               -2
      SWAPS
      expect(described_class.swaps(swaps)).to eq([{ name: '/swap.img', bytes: 2_097_148 * 1024 }])
      expect(described_class.swaps(proc_file("Filename\tType\tSize\tUsed\tPriority\n"))).to eq([])
    end
  end

  describe '.root_disk' do
    it "reads df's line for /" do
      allow(Shell).to receive(:output).with('df', '-h', '/').and_return(
        "Filesystem                         Size  Used Avail Use% Mounted on\n" \
        "/dev/mapper/ubuntu--vg-ubuntu--lv   98G   24G   70G  26% /\n"
      )
      expect(described_class.root_disk).to eq(size: '98G', used: '24G', free: '70G', percent: 26)
    end

    it 'is nil when df gives nothing' do
      allow(Shell).to receive(:output).with('df', '-h', '/').and_return('')
      expect(described_class.root_disk).to be_nil
    end
  end

  describe '.package_installed?' do
    it "asks dpkg-query for the package's status, as an argument list" do
      allow(Shell).to receive(:output).with('dpkg-query', '-W', '-f=${Status}', 'greyhole').and_return('install ok installed')
      allow(Shell).to receive(:output).with('dpkg-query', '-W', '-f=${Status}', 'fail2ban').and_return('')
      expect(described_class.package_installed?('greyhole')).to be true
      expect(described_class.package_installed?('fail2ban')).to be false
    end
  end

  describe '.os_name, .load and .memory' do
    it "reads the distribution's name, or says Linux" do
      expect(described_class.os_name(proc_file("NAME=\"Ubuntu\"\nPRETTY_NAME=\"Ubuntu 24.04.3 LTS\"\n"))).to eq('Ubuntu 24.04.3 LTS')
      expect(described_class.os_name(proc_file("NAME=\"Ubuntu\"\n"))).to eq('Linux')
      expect(described_class.os_name('/nonexistent/os-release')).to eq('Linux')
    end

    it 'reads the load averages against the cores, capped at 100%' do
      allow(described_class).to receive(:cores).and_return(4)
      expect(described_class.load(proc_file("1.50 0.75 0.25 2/345 6789\n"))).to eq(one: 1.5, five: 0.75, fifteen: 0.25, cores: 4, percent: 38)
      expect(described_class.load(proc_file("9.0 1.0 1.0 1/2 3\n"))[:percent]).to eq(100)
      expect(described_class.load('/nonexistent/loadavg')).to be_nil
    end

    it 'reads memory in kB with the share in use' do
      meminfo = proc_file("MemTotal:        8000000 kB\nMemFree:         1000000 kB\nMemAvailable:    6000000 kB\n")
      expect(described_class.memory(meminfo)).to eq(total: 8_000_000, available: 6_000_000, used: 2_000_000, percent: 25)
      expect(described_class.memory(proc_file("MemFree: 1 kB\n"))).to be_nil
      expect(described_class.memory('/nonexistent/meminfo')).to be_nil
    end
  end

  it 'reads the hostname, the first address, the kernel and the cores' do
    allow(Shell).to receive(:output).with('hostname', '-I').and_return("192.168.1.111 100.64.0.5 \n")
    expect(described_class.ip_address).to eq('192.168.1.111')
    expect(described_class.hostname).to eq(Socket.gethostname)
    expect(described_class.kernel).to eq(Etc.uname[:release])
    expect(described_class.cores).to be >= 1
  end
end
