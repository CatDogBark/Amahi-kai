Disks::Engine.routes.draw do
  root to: 'disks#index'
  get 'devices' => 'disks#devices'
  get 'mounts' => 'disks#mounts'
  get 'storage_pool' => 'disks#storage_pool'
  post 'format_disk' => 'disks#format_disk'
  post 'mount_disk' => 'disks#mount_disk'
  post 'unmount_disk' => 'disks#unmount_disk'
  post 'toggle_greyhole' => 'disks#toggle_greyhole'
  post 'install_greyhole' => 'disks#install_greyhole'
  get 'install_greyhole_stream' => 'disks#install_greyhole_stream'
end
