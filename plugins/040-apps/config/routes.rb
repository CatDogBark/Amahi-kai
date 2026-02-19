Apps::Engine.routes.draw do
	# root of the plugin
	root :to => 'apps#index'

	match 'installed' => 'apps#installed', via: [:get,:post]

	# Legacy app install/uninstall
	post 'install/:id' => 'apps#install', as: 'install'
	match 'install_progress/:id' => 'apps#install_progress', as: 'install_progress', via: [:get,:post]
	post 'uninstall/:id' => 'apps#uninstall', as: 'uninstall'
	match 'uninstall_progress/:id' => 'apps#uninstall_progress', as: 'uninstall_progress', via: [:get,:post]
	put 'toggle_in_dashboard/:id' => 'apps#toggle_in_dashboard', as: 'toggle_in_dashboard'

	# Docker engine installation
	get 'install_docker_stream' => 'apps#install_docker_stream', as: 'install_docker_stream'
	post 'start_docker' => 'apps#start_docker', as: 'start_docker'

	# Docker apps
	get 'docker_apps' => 'apps#docker_apps', as: 'docker_apps'
	post 'docker/install/:id' => 'apps#docker_install', as: 'docker_install'
	post 'docker/uninstall/:id' => 'apps#docker_uninstall', as: 'docker_uninstall'
	post 'docker/start/:id' => 'apps#docker_start', as: 'docker_start'
	post 'docker/stop/:id' => 'apps#docker_stop', as: 'docker_stop'
	post 'docker/restart/:id' => 'apps#docker_restart', as: 'docker_restart'
	get 'docker/status/:id' => 'apps#docker_status', as: 'docker_status'
end
