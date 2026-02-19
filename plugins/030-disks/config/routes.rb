Disks::Engine.routes.draw do
  root to: 'disks#index'
  get 'mounts' => 'disks#mounts'
  get 'storage_pool' => 'disks#storage_pool'
  post 'toggle_greyhole' => 'disks#toggle_greyhole'
  post 'install_greyhole' => 'disks#install_greyhole'
  get 'install_greyhole_stream' => 'disks#install_greyhole_stream'
end
