Rails.application.routes.draw do

  # Docker app reverse proxy — must be before plugin routes
  match '/app/:app_id', to: 'app_proxy#proxy', via: :all, defaults: { path: '/' }
  match '/app/:app_id/*path', to: 'app_proxy#proxy', via: :all, format: false

  # Legacy plugin routes (kept for future extensibility)
  amahi_plugin_routes

  # Users (consolidated from plugin)
  resources :users do
    member do
      put 'toggle_admin'
      put 'update_password'
      put 'update_name'
      put 'update_pubkey'
      put 'update_pin'
    end
  end

  # Network (consolidated from plugin)
  scope '/network', controller: 'network', as: 'network' do
    get '/', action: 'index', as: '_index'
    get 'leases', action: 'index'
    get 'hosts', action: 'hosts'
    post 'hosts', action: 'create_host'
    delete 'host/:id', action: 'destroy_host', as: '_destroy_host'
    get 'dns_aliases', action: 'dns_aliases'
    post 'dns_aliases', action: 'create_dns_alias'
    delete 'dns_alias/:id', action: 'destroy_dns_alias', as: '_destroy_dns_alias'
    get 'settings', action: 'settings'
    put 'update_lease_time', action: 'update_lease_time'
    put 'update_gateway', action: 'update_gateway'
    put 'update_dns', action: 'update_dns'
    put 'update_dns_ips', action: 'update_dns_ips'
    put 'toggle_setting/:id', action: 'toggle_setting', as: '_toggle_setting'
    put 'update_dhcp_range/:id', action: 'update_dhcp_range', as: '_update_dhcp_range'
    get 'gateway', action: 'gateway'
    post 'install_dnsmasq', action: 'install_dnsmasq'
    get 'install_dnsmasq_stream', action: 'install_dnsmasq_stream'
    post 'start_dnsmasq', action: 'start_dnsmasq'
    post 'stop_dnsmasq', action: 'stop_dnsmasq'
    put 'update_dnsmasq_config', action: 'update_dnsmasq_config'
    get 'remote_access', action: 'remote_access'
    post 'configure_tunnel', action: 'configure_tunnel'
    post 'start_tunnel', action: 'start_tunnel'
    post 'stop_tunnel', action: 'stop_tunnel'
    get 'install_cloudflared_stream', action: 'install_cloudflared_stream'
    get 'setup_tunnel_stream', action: 'setup_tunnel_stream'
    get 'security', action: 'security'
    post 'security_fix', action: 'security_fix'
    get 'security_audit_stream', action: 'security_audit_stream'
    get 'security_fix_stream', action: 'security_fix_stream'
  end

  # Settings (consolidated from plugin)
  scope '/settings', controller: 'settings', as: 'settings' do
    get '/', action: 'index', as: '_index'
    match 'change_language', action: 'change_language', via: %i[get post]
    match 'toggle_setting', action: 'toggle_setting', via: %i[get post]
    match 'reboot', action: 'reboot', via: %i[get post]
    match 'poweroff', action: 'poweroff', via: %i[get post]
    match 'servers', action: 'servers', via: %i[get post]
    match 'servers/:id/refresh', action: 'refresh', as: '_refresh', via: %i[get post]
    match 'servers/:id/start', action: 'start', as: '_start', via: %i[get post]
    match 'servers/:id/stop', action: 'stop', as: '_stop', via: %i[get post]
    match 'servers/:id/restart', action: 'restart', as: '_restart', via: %i[get post]
    match 'servers/:id/toggle_monitored', action: 'toggle_monitored', as: '_toggle_monitored', via: %i[get post put]
    match 'servers/:id/toggle_start_at_boot', action: 'toggle_start_at_boot', as: '_toggle_start_at_boot', via: %i[get post put]
    match 'themes', action: 'themes', via: %i[get post]
    match 'activate_theme', action: 'activate_theme', via: %i[get post]
    put 'revoke_app', action: 'revoke_app'
    get 'system_status', action: 'system_status'
    post 'update_system', action: 'update_system'
    get 'update_system_stream', action: 'update_system_stream'
  end

  # Apps (consolidated from plugin)
  scope '/apps', controller: 'apps', as: 'apps' do
    get '/', action: 'docker_apps', as: '_index'
    get 'install_docker_stream', action: 'install_docker_stream'
    post 'start_docker', action: 'start_docker'
    get 'docker_apps', action: 'docker_apps'
    get 'installed_apps', action: 'installed_apps'
    post 'docker/install/:id', action: 'docker_install', as: '_docker_install'
    get 'docker/install_stream/:id', action: 'docker_install_stream', as: '_docker_install_stream'
    post 'docker/uninstall/:id', action: 'docker_uninstall', as: '_docker_uninstall'
    post 'docker/start/:id', action: 'docker_start', as: '_docker_start'
    post 'docker/stop/:id', action: 'docker_stop', as: '_docker_stop'
    post 'docker/restart/:id', action: 'docker_restart', as: '_docker_restart'
    get 'docker/status/:id', action: 'docker_status', as: '_docker_status'
  end

  # Disks (consolidated from plugin)
  scope '/disks', controller: 'disks', as: 'disks' do
    get '/', action: 'index', as: '_index'
    get 'devices', action: 'devices'
    get 'mounts', action: 'mounts'
    get 'storage_pool', action: 'storage_pool'
    post 'format_disk', action: 'format_disk'
    post 'mount_disk', action: 'mount_disk'
    post 'unmount_disk', action: 'unmount_disk'
    post 'preview_disk', action: 'preview_disk'
    post 'mount_as_share', action: 'mount_as_share'
    put 'toggle_disk_pool_partition', action: 'toggle_disk_pool_partition'
    post 'toggle_greyhole', action: 'toggle_greyhole'
    post 'install_greyhole', action: 'install_greyhole'
    get 'install_greyhole_stream', action: 'install_greyhole_stream'
  end

  match 'login' => 'user_sessions#new', :as => :login, via: [:get]
  match 'logout' => 'user_sessions#destroy', :as => :logout, via: [:get]
  match 'start' => 'user_sessions#start', :as => :start, via: [:get]
  match 'user_sessions/initialize_system' => 'user_sessions#initialize_system', :as => :initialize_system, via: [:get,:post]

  get '/tab/debug'=>'debug#index'
  post '/tab/debug'=>'debug#submit'
  get '/tab/debug/system'=>'debug#system'
  get '/tab/debug/logs'=>'debug#logs'

  resources :shares do
    collection do
      get 'disk_pooling'
      get 'settings'
      put 'toggle_disk_pool_partition'
    end

    member do
      put 'toggle_visible'
      put 'toggle_everyone'
      put 'toggle_readonly'
      put 'toggle_access'
      put 'toggle_write'
      put 'toggle_guest_access'
      put 'toggle_guest_writeable'
      put 'update_tags'
      put 'update_path'
      put 'update_workgroup'
      put 'toggle_disk_pool_enabled'
      put 'update_disk_pool_copies'
      put 'update_extras'
      put 'clear_permissions'
      put 'update_size'
      put 'update_name'
    end
  end

  resources :user_sessions

  match 'search/hda' => 'search#hda', :as => :search_hda, via: [:get,:post]
  match 'search/images' => 'search#images', :as => :search_images, via: [:get,:post]
  match 'search/audio' => 'search#audio', :as => :search_audio, via: [:get,:post]
  match 'search/video' => 'search#video', :as => :search_video, via: [:get,:post]

  # Setup wizard
  get  'setup/welcome'  => 'setup#welcome',       as: :setup_welcome
  get  'setup/admin'    => 'setup#admin',          as: :setup_admin
  post 'setup/admin'    => 'setup#update_admin',   as: :setup_update_admin
  get  'setup/network'  => 'setup#network',        as: :setup_network
  post 'setup/network'  => 'setup#update_network', as: :setup_update_network
  get  'setup/storage'  => 'setup#storage',            as: :setup_storage
  post 'setup/storage'  => 'setup#update_storage',   as: :setup_update_storage
  post 'setup/preview_drive' => 'setup#preview_drive',  as: :setup_preview_drive
  get  'setup/greyhole' => 'setup#greyhole',          as: :setup_greyhole
  post 'setup/greyhole' => 'setup#install_greyhole',  as: :setup_install_greyhole
  get  'setup/share'    => 'setup#share',              as: :setup_share
  post 'setup/share'    => 'setup#create_share',   as: :setup_create_share
  get  'setup/complete' => 'setup#complete',        as: :setup_complete
  post 'setup/finish'   => 'setup#finish',          as: :setup_finish

  # File Browser
  get  'files/:share_id/browse',       to: 'file_browser#browse',  as: :file_browser, defaults: { path: '' }
  get  'files/:share_id/browse/*path', to: 'file_browser#browse',  as: :file_browser_path
  get  'files/:share_id/download',       to: 'file_browser#download', defaults: { path: '' }
  get  'files/:share_id/download/*path', to: 'file_browser#download', as: :file_browser_download, format: false
  get  'files/:share_id/raw/*path',      to: 'file_browser#raw',      as: :file_browser_raw, format: false
  get  'files/:share_id/preview/*path',  to: 'file_browser#preview',  as: :file_browser_preview, format: false
  post 'files/:share_id/upload',         to: 'file_browser#upload',   as: :file_browser_upload
  post 'files/:share_id/new_folder',     to: 'file_browser#new_folder', as: :file_browser_new_folder
  put  'files/:share_id/rename',         to: 'file_browser#rename',   as: :file_browser_rename
  delete 'files/:share_id/delete',       to: 'file_browser#delete',   as: :file_browser_delete

  post 'toggle_advanced' => 'front#toggle_advanced', as: :toggle_advanced

  root :to => 'front#index'

end
