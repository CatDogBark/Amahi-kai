require 'rails_helper'
require 'tmpdir'

# What the root helper's config checks approve, read by the tools that will read it on a server. A
# difference between the check and the tool is how a line gets in unchecked: dnsmasq takes the
# end of a long comment as a line of its own, and Samba takes the line after a comment ending in
# a backslash as live. So each tool gets text with a meaningless word in whatever the check
# passes over, and must pass over it too.
#
# They run where the tools are installed. CI's Real Tools job has Ubuntu 24.04's versions, and
# sets REAL_TOOLS=required, so a tool that went missing there fails instead of skipping.
RSpec.describe 'AmahiHelper: what its checks approve, read by the real tools' do
  let(:helper) { AmahiHelper }
  let(:word) { 'notarealword' }

  before(:all) { Privileged.operations } # loads the helper's source once

  def tool!(path)
    return if File.executable?(path)
    raise "#{path} isn't installed" if ENV['REAL_TOOLS'] == 'required'

    skip "#{path} isn't installed"
  end

  def in_a_file(text)
    Dir.mktmpdir do |dir|
      path = "#{dir}/conf"
      File.write(path, text)
      yield path
    end
  end

  describe 'dnsmasq' do
    before { tool!(AmahiHelper::DNSMASQ) }

    def approved(text)
      helper.dnsmasq_conf(text, AmahiHelper::DNSMASQ_LINES)
    end

    def read_by_dnsmasq(text)
      in_a_file(text) { |path| helper.check_dnsmasq_conf(path) }
    end

    it 'reads the config the app writes' do
      text = DnsmasqService.config_text(net: '192.168.1', first: 100, last: 254, router: 1, lease_time: 14_400, interface: 'lo', dhcp_enabled: true)
      expect { approved(text) }.not_to raise_error
      expect { read_by_dnsmasq(text) }.not_to raise_error
    end

    it 'passes over each comment the check passes over, up to the longest line it approves' do
      ["# #{word}", "   # #{word}", "\t# #{word}", "# #{word}\r", "# \\ #{word}", "# \" #{word}", "# #{'é' * 200}#{word}",
       "# #{'a' * (AmahiHelper::DNSMASQ_LINE_MAX - 3 - word.size)}#{word}"].each do |line|
        text = "port=0\n#{line}\n"
        expect { approved(text) }.not_to raise_error, line.inspect
        expect { read_by_dnsmasq(text) }.not_to raise_error, line.inspect
      end
    end

    it 'reads a line the same with space around it' do
      ['port=0 ', "\tport=0", "port=0\r"].each do |line|
        expect { approved("#{line}\n") }.not_to raise_error, line.inspect
        expect { read_by_dnsmasq("#{line}\n") }.not_to raise_error, line.inspect
      end
    end

    it 'refuses a comment or a line after anything but a space or a tab' do
      ["\f# #{word}", "\v# #{word}", "\r# #{word}", "\fport=0", "\vbind-interfaces"].each do |line|
        expect { approved("port=0\n#{line}\n") }.to raise_error(AmahiHelper::Refused), line.inspect
      end
    end
  end

  describe 'Samba' do
    before { tool!(AmahiHelper::TESTPARM) }

    let(:base) do
      "[global]\n\tworkgroup = WORKGROUP\n\tunix extensions = no\n\tload printers = no\n\tprinting = bsd\n\t" \
        "printcap name = /dev/null\n\tdisable spoolss = yes\n"
    end

    def testparm(text)
      in_a_file(text) { |path| Open3.capture3(AmahiHelper::TESTPARM, '-s', path).first }
    end

    # A parameter that follows the line: testparm shows it if Samba would use it, and then the
    # check must have read it as well.
    it 'reads every parameter Samba would use, whatever line comes before it' do
      lines = ['# a note', '; a note', '#', ';', "\t# a note", "\f# a note", "\r# a note", "# a note\r", 'junk', '-[x]', '=', '= x', '[vault] # a note',
               "# #{'a' * 70_000}", "#{'#' * 3} \\ a note", '# a note \\\\ here',
               '# a note \\', '; a note \\', '# a note \\ ', "# a note \\\t", "# a note \\\r", '\\', 'workgroup = A \\', '# a note \\\\']
      read = lines.count do |line|
        text = "#{base}#{line}\n\tnetbios name = MARKERNAME\n"
        next false unless helper.samba_problems(text).empty?

        if testparm(text).include?('MARKERNAME')
          expect(helper.samba_params(text).map(&:last)).to include('MARKERNAME'), line.inspect
        end
        true
      end
      expect(read).to be >= 10 # the check approved a good part of them, so this tried something
    end

    it 'refuses every line ending in a backslash, which is where the two read differently' do
      ['# a note \\', '; a note \\', '# a note \\ ', "# a note \\\t", "# a note \\\r", '\\', 'workgroup = A \\', '# a note \\\\'].each do |line|
        expect(helper.samba_problems("#{base}#{line}\n\tnetbios name = MARKERNAME\n").first).to include('ends in a backslash'), line.inspect
      end
    end

    it 'reads a config in its second pass the way testparm shows it' do
      in_a_file("#{base}\tnetbios name = MARKERNAME\n") do |path|
        expect { helper.check_smb_conf(path) }.not_to raise_error
      end
    end
  end

  describe 'Unbound' do
    before { tool!(AmahiHelper::UNBOUND_CHECKCONF) }

    it 'passes over each comment the check passes over, however long' do
      ["# #{word}", "  # #{word}", "\t# #{word}", "# #{word}\r", "# \" #{word}", "# ' #{word}", "# \\ #{word}", "# #{'a' * 5000} #{word}"].each do |line|
        text = "server:\n#{line}\n  access-control: 10.0.0.0/8 allow\n"
        expect { helper.unbound_conf(text) }.not_to raise_error, line.inspect
        expect { in_a_file(text) { |path| helper.check_unbound_conf(path) } }.not_to raise_error, line.inspect
      end
    end

    # Unbound takes a form feed as text, so "\f#" isn't a comment to it.
    it 'refuses a comment after anything but a space or a tab, as Unbound would read it' do
      ["\f# #{word}", "\v# #{word}"].each do |line|
        text = "server:\n#{line}\n  access-control: 10.0.0.0/8 allow\n"
        expect { helper.unbound_conf(text) }.to raise_error(AmahiHelper::Refused), line.inspect
        expect { in_a_file(text) { |path| helper.check_unbound_conf(path) } }.to raise_error(AmahiHelper::Refused), line.inspect
      end
    end
  end

  describe 'radvd' do
    before { tool!(AmahiHelper::RADVD) }

    it 'passes over each comment the check passes over, however long' do
      ["# #{word}", "  # #{word}", "\t# #{word}", "# #{word}\r", "# \" #{word}", "# \\ #{word}", "# #{'a' * 3000} #{word}"].each do |line|
        text = "#{line}\ninterface lo {\n  AdvSendAdvert on;\n  AdvDefaultLifetime 0;\n};\n"
        expect { helper.radvd_conf(text) }.not_to raise_error, line.inspect
        expect { in_a_file(text) { |path| helper.check_radvd_conf(path) } }.not_to raise_error, line.inspect
      end
    end

    it 'refuses a comment after anything but a space or a tab' do
      ["\f# #{word}", "\v# #{word}", "\r# #{word}"].each do |line|
        text = "#{line}\ninterface lo {\n  AdvSendAdvert on;\n  AdvDefaultLifetime 0;\n};\n"
        expect { helper.radvd_conf(text) }.to raise_error(AmahiHelper::Refused), line.inspect
      end
    end
  end
end
