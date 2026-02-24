Network::Engine.routes.draw do
	# root of the plugin
	root :to => 'network#index'
	get 'leases' => 'network#index'

	get 'hosts' => 'network#hosts'
	post 'hosts' => 'network#create_host'
	delete 'host/:id' => 'network#destroy_host', as: 'destroy_host'

	get 'dns_aliases' => 'network#dns_aliases'
	post 'dns_aliases' => 'network#create_dns_alias'
	delete 'dns_alias/:id' => 'network#destroy_dns_alias', as: 'destroy_dns_alias'

	get 'settings' => 'network#settings'
	put 'update_lease_time' => 'network#update_lease_time'
	put 'update_gateway' => 'network#update_gateway'
	put 'update_dns' => 'network#update_dns'
	put 'update_dns_ips' => 'network#update_dns_ips'
	put 'toggle_setting/:id' => 'network#toggle_setting', as: 'toggle_setting'
	put 'update_dhcp_range/:id' => 'network#update_dhcp_range', as: 'update_dhcp_range'

	# Gateway (dnsmasq DHCP/DNS)
	get 'gateway' => 'network#gateway'
	post 'install_dnsmasq' => 'network#install_dnsmasq'
	get 'install_dnsmasq_stream' => 'network#install_dnsmasq_stream'
	post 'start_dnsmasq' => 'network#start_dnsmasq'
	post 'stop_dnsmasq' => 'network#stop_dnsmasq'
	put 'update_dnsmasq_config' => 'network#update_dnsmasq_config'

	# Remote Access (Cloudflare Tunnel)
	get 'remote_access' => 'network#remote_access'
	post 'configure_tunnel' => 'network#configure_tunnel'
	post 'start_tunnel' => 'network#start_tunnel'
	post 'stop_tunnel' => 'network#stop_tunnel'
	get 'install_cloudflared_stream' => 'network#install_cloudflared_stream'
	get 'setup_tunnel_stream' => 'network#setup_tunnel_stream'

	# Security
	get 'security' => 'network#security'
	post 'security_fix' => 'network#security_fix'
	get 'security_audit_stream' => 'network#security_audit_stream'
	get 'security_fix_stream' => 'network#security_fix_stream'
end
