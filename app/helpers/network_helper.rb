module NetworkHelper
  # A port wherever it's named: "Modem (ens20)" once the admin named it (Network → Devices,
  # This NAS), or "ens20".
  def port_display(name)
    NetworkPorts.display(name.to_s)
  end

  def confirm_host_destroy_message(host)
    t('are_you_sure_host', :fixed_ip => host)
  end

  def confirm_dns_alias_destroy_message(dns_alias)
    t('are_you_sure_dns_alias', :dns_alias => dns_alias)
  end

  def alias_ip(dns_alias)
    addr = dns_alias.address
    net = Setting.get('net')
    if addr.nil? || addr.blank?
      # empty -- alias to this server
      net + '.' + Setting.get('self-address')
    elsif addr =~ /\A\d+\z/
      # just a number, same network
      net + '.' + addr
    else
      addr
    end
  end

end
