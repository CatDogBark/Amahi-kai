Rails.application.routes.draw do

  amahi_plugin_routes

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
  get  'setup/storage'  => 'setup#storage',        as: :setup_storage
  post 'setup/storage'  => 'setup#update_storage', as: :setup_update_storage
  get  'setup/share'    => 'setup#share',          as: :setup_share
  post 'setup/share'    => 'setup#create_share',   as: :setup_create_share
  get  'setup/complete' => 'setup#complete',        as: :setup_complete
  post 'setup/finish'   => 'setup#finish',          as: :setup_finish

  root :to => 'front#index'

end
