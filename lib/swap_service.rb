# Manages swap file creation.
# Extracted from SetupController to keep Shell.run out of controllers.

module SwapService
  SWAP_PATH = '/swapfile'

  class << self
    # Create, enable, and persist a swap file of +size+ ("1G", "2G" or "4G").
    # The root helper (system.create_swap) creates /swapfile (mode 600), turns it on and
    # adds it to /etc/fstab. Yields status messages via the block.
    # Returns true on success, false on failure.
    def create!(size, &block)
      report = block || ->(msg) {}

      report.call("Creating a #{size} swap file at #{SWAP_PATH}, turning it on and adding it to /etc/fstab...")
      Privileged.call('system.create_swap', size_gb: size.to_i)
      true
    rescue Privileged::Error => e
      report.call("  #{e.message}")
      false
    end
  end
end
