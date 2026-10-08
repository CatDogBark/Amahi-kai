Rails.application.routes.draw do

  # Users (consolidated from plugin)
  resources :users, except: %i[new edit show] do
    member do
      put 'toggle_admin'
      put 'update_role'
      put 'update_password'
      put 'update_name'
    end
  end

  # Network (consolidated from plugin)
  scope '/network', controller: 'network', as: 'network' do
    get '/', action: 'index', as: 'index'
    get 'hosts', action: 'hosts'
    post 'hosts', action: 'create_host'
    delete 'host/:id', action: 'destroy_host', as: 'destroy_host'
    get 'dns_aliases', action: 'dns_aliases'
    post 'dns_aliases', action: 'create_dns_alias'
    delete 'dns_alias/:id', action: 'destroy_dns_alias', as: 'destroy_dns_alias'
    get 'settings', action: 'settings'
    put 'update_lease_time', action: 'update_lease_time'
    put 'update_gateway', action: 'update_gateway'
    put 'update_dns', action: 'update_dns'
    put 'update_dns_ips', action: 'update_dns_ips'
    put 'toggle_setting/:id', action: 'toggle_setting', as: 'toggle_setting'
    put 'update_dhcp_range/:id', action: 'update_dhcp_range', as: 'update_dhcp_range'
    get 'gateway', action: 'gateway'
    get 'install_dnsmasq_stream', action: 'install_dnsmasq_stream'
    post 'start_dnsmasq', action: 'start_dnsmasq'
    post 'stop_dnsmasq', action: 'stop_dnsmasq'
    put 'update_dnsmasq_config', action: 'update_dnsmasq_config'
  end

  # Remote Access (Cloudflare Tunnel) — split from network
  scope '/network/remote_access', controller: 'remote_access', as: 'remote_access' do
    get '/', action: 'index', as: 'index'
    post 'stage_tunnel_token', action: 'stage_tunnel_token'
    post 'start_tunnel', action: 'start_tunnel'
    post 'restart_tunnel', action: 'restart_tunnel'
    post 'stop_tunnel', action: 'stop_tunnel'
    get 'setup_tunnel_stream', action: 'setup_tunnel_stream'
    # Tailscale VPN
    get 'install_tailscale_stream', action: 'install_tailscale_stream'
    post 'start_tailscale', action: 'start_tailscale'
    post 'stop_tailscale', action: 'stop_tailscale'
    post 'logout_tailscale', action: 'logout_tailscale'
  end

  # Security Audit — split from network
  scope '/network/security', controller: 'security', as: 'security' do
    get '/', action: 'index', as: 'index'
    post 'fix', action: 'fix'
    get 'audit_stream', action: 'audit_stream'
    get 'fix_stream', action: 'fix_stream'
  end

  # Settings (consolidated from plugin)
  scope '/settings', controller: 'settings', as: 'settings' do
    get '/', action: 'index', as: 'index'
    # Actions that change something are POST-only, so a link can't trigger them.
    post 'reboot', action: 'reboot'
    post 'poweroff', action: 'poweroff'
    get 'servers', action: 'servers'
    post 'servers/:key/:verb', action: 'service_action', as: 'service_action',
         constraints: { verb: /start|stop|restart/ }
    get 'jobs', action: 'jobs'
    get 'dependencies', action: 'dependencies'
    get 'dependencies_refresh_stream', action: 'dependencies_refresh_stream'
    get 'dependencies_upgrade_stream', action: 'dependencies_upgrade_stream'
    post 'dependencies_hold', action: 'dependencies_hold'
    post 'dependencies_automatic', action: 'dependencies_automatic'
    get 'system_status', action: 'system_status'
    post 'update_system', action: 'update_system'
    post 'check_updates', action: 'check_updates'
    get 'update_system_stream', action: 'update_system_stream'
  end

  # Apps (consolidated from plugin)
  scope '/apps', controller: 'apps', as: 'apps' do
    get '/', action: 'docker_apps', as: 'index'
    get 'install_docker_stream', action: 'install_docker_stream'
    post 'start_docker', action: 'start_docker'
    post 'stop_docker', action: 'stop_docker'
    get 'docker_apps', action: 'docker_apps'
    get 'installed_apps', action: 'installed_apps'
    post 'refresh_catalog', action: 'refresh_catalog'
    get 'docker/install_stream/:id', action: 'docker_install_stream', as: 'docker_install_stream'
    get 'docker/update_stream/:id', action: 'docker_update_stream', as: 'docker_update_stream'
    get 'docker/undo_update_stream/:id', action: 'docker_undo_update_stream', as: 'docker_undo_update_stream'
    post 'docker/uninstall/:id', action: 'docker_uninstall', as: 'docker_uninstall'
    post 'docker/start/:id', action: 'docker_start', as: 'docker_start'
    post 'docker/stop/:id', action: 'docker_stop', as: 'docker_stop'
  end

  # Disks (consolidated from plugin)
  scope '/disks', controller: 'disks', as: 'disks' do
    get '/', action: 'index', as: 'index'
    get 'devices', action: 'devices'
    get 'mounts', action: 'mounts'
    get 'storage_pool', action: 'storage_pool'
    post 'format_disk', action: 'format_disk'
    post 'mount_disk', action: 'mount_disk'
    post 'unmount_disk', action: 'unmount_disk'
    post 'preview_disk', action: 'preview_disk'
    post 'mount_as_share', action: 'mount_as_share'
    put 'toggle_disk_pool_partition', action: 'toggle_disk_pool_partition'
    post 'accept_pool_drive', action: 'accept_pool_drive'
    post 'toggle_greyhole', action: 'toggle_greyhole'
    get 'install_greyhole_stream', action: 'install_greyhole_stream'
    get 'uninstall_greyhole_stream', action: 'uninstall_greyhole_stream'
    get 'pools', action: 'pools'
    post 'create_pool', action: 'create_pool'
    post 'scrub_pool', action: 'scrub_pool'
    post 'replace_pool_drive', action: 'replace_pool_drive'
    post 'add_pool_group', action: 'add_pool_group'
    post 'destroy_pool', action: 'destroy_pool'
    post 'pool_offline', action: 'pool_offline'
    post 'pool_online', action: 'pool_online'
    post 'snapshot_pool', action: 'snapshot_pool'
    post 'pool_snapshot_policy', action: 'pool_snapshot_policy'
    post 'destroy_pool_snapshot', action: 'destroy_pool_snapshot'
    post 'rollback_pool', action: 'rollback_pool'
    post 'check_health', action: 'check_health'
    get 'install_storage_tools_stream', action: 'install_storage_tools_stream'
    get 'uninstall_zfs_stream', action: 'uninstall_zfs_stream'
  end

  match 'login' => 'user_sessions#new', :as => :login, via: [:get]
  delete 'logout' => 'user_sessions#destroy', :as => :logout

  get '/tab/debug'=>'debug#index'
  post '/tab/debug'=>'debug#submit'
  get '/tab/debug/system'=>'debug#system'
  get '/tab/debug/logs'=>'debug#logs'

  resources :shares, except: %i[new edit show update] do
    collection do
      get 'settings'
    end

    member do
      put 'toggle_visible'
      put 'toggle_everyone'
      put 'toggle_readonly'
      put 'toggle_access'
      put 'toggle_write'
      put 'toggle_guest_access'
      put 'toggle_guest_writeable'
      put 'update_path'
      put 'update_workgroup'
      put 'update_disk_pool_copies'
      put 'update_extras'
      put 'clear_permissions'
      put 'update_size'
      put 'update_name'
    end
  end

  resources :user_sessions, only: %i[new create destroy]

  match 'search/files' => 'search#files', :as => :search_files, via: [:get,:post]
  match 'search/images' => 'search#images', :as => :search_images, via: [:get,:post]
  match 'search/audio' => 'search#audio', :as => :search_audio, via: [:get,:post]
  match 'search/video' => 'search#video', :as => :search_video, via: [:get,:post]

  # Setup wizard
  get  'setup/welcome'  => 'setup#welcome',       as: :setup_welcome
  get  'setup/create_swap' => 'setup#create_swap', as: :setup_create_swap
  get  'setup/admin'    => 'setup#admin',          as: :setup_admin
  post 'setup/admin'    => 'setup#update_admin',   as: :setup_update_admin
  get  'setup/network'  => 'setup#network',        as: :setup_network
  post 'setup/network'  => 'setup#update_network', as: :setup_update_network
  get  'setup/storage'  => 'setup#storage',            as: :setup_storage
  post 'setup/storage'  => 'setup#update_storage',   as: :setup_update_storage
  get  'setup/prepare_drives_stream' => 'setup#prepare_drives_stream', as: :setup_prepare_drives_stream
  post 'setup/preview_drive' => 'setup#preview_drive',  as: :setup_preview_drive
  get  'setup/greyhole' => 'setup#greyhole',          as: :setup_greyhole
  post 'setup/greyhole' => 'setup#install_greyhole',  as: :setup_install_greyhole
  get  'setup/install_greyhole_stream' => 'setup#install_greyhole_stream', as: :setup_install_greyhole_stream
  get  'setup/share'    => 'setup#share',              as: :setup_share
  post 'setup/share'    => 'setup#create_share',   as: :setup_create_share
  get  'setup/complete' => 'setup#complete',        as: :setup_complete
  post 'setup/finish'   => 'setup#finish',          as: :setup_finish

  # File Browser
  get  'files',                        to: 'file_browser#index',   as: :file_browser_index
  # Greyhole's trash, beside the shares (admins)
  get  'files/trash',                  to: 'trash#index',          as: :trash
  post 'files/trash/restore',          to: 'trash#restore',        as: :trash_restore
  post 'files/trash/delete',           to: 'trash#delete',         as: :trash_delete
  post 'files/trash/empty',            to: 'trash#empty',          as: :trash_empty
  post 'files/trash/keep',             to: 'trash#keep',           as: :trash_keep
  get  'files/:share_id/browse',       to: 'file_browser#browse',  as: :file_browser, defaults: { path: '' }
  get  'files/:share_id/browse/*path', to: 'file_browser#browse',  as: :file_browser_path
  get  'files/:share_id/download',       to: 'file_browser#download', as: :file_browser_download_root, defaults: { path: '' }
  get  'files/:share_id/download/*path', to: 'file_browser#download', as: :file_browser_download, format: false
  get  'files/:share_id/raw/*path',      to: 'file_browser#raw',      as: :file_browser_raw, format: false
  get  'files/:share_id/preview/*path',  to: 'file_browser#preview',  as: :file_browser_preview, format: false

  post 'toggle_advanced' => 'front#toggle_advanced', as: :toggle_advanced

  root :to => 'front#index'

end
