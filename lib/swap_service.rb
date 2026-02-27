# Manages swap file creation.
# Extracted from SetupController to keep Shell.run out of controllers.

require 'shell'

module SwapService
  SWAP_PATH = '/swapfile'

  class << self
    # Create, enable, and persist a swap file.
    # Yields status messages via the block.
    # Returns true on success, false on failure.
    def create!(size, &block)
      report = block || ->(msg) {}

      report.call("Creating #{size} swap file...")
      result = Shell.run("fallocate -l #{size} #{SWAP_PATH} 2>/dev/null || sudo dd if=/dev/zero of=#{SWAP_PATH} bs=1M count=#{size.to_i * 1024} status=none")
      return false unless result

      report.call("Setting permissions...")
      Shell.run("chmod 600 #{SWAP_PATH}")

      report.call("Setting up swap space...")
      Shell.run("mkswap #{SWAP_PATH} > /dev/null 2>&1")

      report.call("Enabling swap...")
      Shell.run("swapon #{SWAP_PATH}")

      report.call("Adding to /etc/fstab for persistence...")
      fstab = File.read('/etc/fstab') rescue ''
      unless fstab.include?(SWAP_PATH)
        Shell.run("sh -c \"echo '#{SWAP_PATH} none swap sw 0 0' >> /etc/fstab\"")
      end

      true
    end
  end
end
