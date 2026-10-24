# The NAS's network ports as hardware (Network → Devices, This NAS): what each one is (its
# driver, and over PCI the model lspci names; a virtual port in a VM), whether a cable is in
# and at what speed, its MAC, and the name the admin gives it (a setting), shown wherever a
# port is named. A real port's light can be made to blink through the helper (ethtool), to
# find the socket. Everything but the blink is read from sysfs, which needs no root.

require 'privileged'
require 'shell'

module NetworkPorts
  SYS = '/sys/class/net'
  ETHTOOL = '/usr/sbin/ethtool'
  LABEL_SETTING = 'port-label:'
  LABEL_MAX = 32
  # Drivers of ports a hypervisor gives a VM: there's no socket behind them.
  VIRTUAL_DRIVERS = %w[virtio_net vmxnet3 hv_netvsc xen_netfront veth].freeze
  PCI_SLOT = /\A[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]\z/

  Port = Data.define(:name, :label, :driver, :model, :virtual, :link, :speed, :mac) do
    # What it is, in a few words: "Intel I350 Gigabit Network Connection", "virtual port
    # (virtio)", "igb port".
    def kind
      return "virtual port#{" (#{driver.delete_suffix('_net').delete_suffix('_netfront')})" if driver}" if virtual
      model || (driver ? "#{driver} port" : 'port')
    end

    # "link up, 1000 Mb/s", "link up", "no link".
    def link_text
      return 'no link' unless link
      speed ? "link up, #{speed} Mb/s" : 'link up'
    end
  end

  class << self
    def info(name, sys: SYS)
      dir = File.join(sys, name)
      driver = link_basename(File.join(dir, 'device', 'driver'))
      device = real(File.join(dir, 'device'))
      virtual = driver.nil? || VIRTUAL_DRIVERS.include?(driver)
      slot = device && File.basename(device)[PCI_SLOT]
      Port.new(name: name, label: label(name), driver: driver, model: !virtual && slot ? model(slot) : nil, virtual: virtual,
               link: read(dir, 'carrier') == '1', speed: speed(dir), mac: read(dir, 'address').presence)
    end

    # { "ens18" => Port, ... }
    def all(names, sys: SYS)
      names.index_with { |name| info(name, sys: sys) }
    end

    def label(name)
      Setting.get(LABEL_SETTING + name).to_s.strip.presence
    end

    # "Modem (ens20)", or the name alone.
    def display(name)
      (text = label(name)) ? "#{text} (#{name})" : name
    end

    # Keeps the name given (empty drops it); returns it. Raises ArgumentError with the reason
    # for one that won't do.
    def set_label!(name, label)
      label = label.to_s.strip
      raise ArgumentError, "a port's name is up to #{LABEL_MAX} characters" if label.length > LABEL_MAX
      raise ArgumentError, "a port's name is letters, digits, spaces and punctuation" unless label.empty? || label.match?(/\A[[:print:]]+\z/)
      Setting.set(LABEL_SETTING + name, label)
      label.presence
    end

    # A real port with ethtool here: its light can be made to blink.
    def blinkable?(port)
      !port.virtual && File.executable?(ETHTOOL)
    end

    def blink!(name)
      Privileged.call('network.blink_port', interface: name)
    end

    private

    def read(dir, file)
      File.read(File.join(dir, file)).strip
    rescue SystemCallError
      nil
    end

    # The port's speed in Mb/s, when it has a link and says.
    def speed(dir)
      value = read(dir, 'speed').to_i
      value.positive? ? value : nil
    end

    def link_basename(path)
      File.basename(File.readlink(path))
    rescue SystemCallError
      nil
    end

    def real(path)
      File.realpath(path)
    rescue SystemCallError
      nil
    end

    # "Intel I350 Gigabit Network Connection": lspci's vendor (its first word) and device names
    # for the PCI slot, or nil.
    def model(slot)
      fields = Shell.output('lspci', '-mm', '-s', slot).scan(/"([^"]*)"/).flatten
      vendor, device = fields[1], fields[2]
      vendor.present? && device.present? ? "#{vendor.split.first} #{device}" : nil
    end
  end
end
