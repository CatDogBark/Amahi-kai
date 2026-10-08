# Commands Amahi-kai runs to read the system's state, as its own user: argument lists run
# through Open3, never through a shell. Everything that changes the system, and everything
# that needs root, goes through the root helper (Privileged.call).
#
# Usage:
#   Shell.output('lsblk', '-J', '-o', 'NAME,SIZE')   # => what it prints
#   Shell.success?('mountpoint', '-q', '/mnt/storage-1')

require 'open3'

module Shell
  class << self
    # What a command prints, whatever its exit status, or "" if it can't run (not installed).
    # The command is an argument list, run without a shell. For reading the system's state, so
    # nothing is logged, and it runs in tests too (stub it).
    def output(*argv)
      stdout, _stderr, _status = Open3.capture3(*argv)
      stdout
    rescue SystemCallError
      ''
    end

    # Whether a command, as an argument list run without a shell, runs and succeeds.
    def success?(*argv)
      _stdout, _stderr, status = Open3.capture3(*argv)
      status.success?
    rescue SystemCallError
      false
    end

    # Outside production (development and tests) Privileged.call records root helper calls
    # instead of running the helper, so the specs and a laptop running Amahi-kai never change
    # the computer. Production always runs them: no setting can turn this on there (it used to
    # be "dummy mode", which a setting in amahi.env could switch on).
    def simulated?
      return @simulated unless @simulated.nil?
      !(defined?(Rails) && Rails.env.production?)
    end

    # For specs that test the real code paths with the system calls stubbed: false runs them,
    # nil goes back to the rule above.
    def simulated=(value)
      @simulated = value
    end
  end
end
