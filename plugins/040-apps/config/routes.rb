Apps::Engine.routes.draw do
	# Docker apps is the main view
	root :to => 'apps#docker_apps'

	# Docker engine installation
	get 'install_docker_stream' => 'apps#install_docker_stream', as: 'install_docker_stream'
	post 'start_docker' => 'apps#start_docker', as: 'start_docker'

	# Docker apps
	get 'docker_apps' => 'apps#docker_apps', as: 'docker_apps'
	get 'installed_apps' => 'apps#installed_apps', as: 'installed_apps'
	post 'docker/install/:id' => 'apps#docker_install', as: 'docker_install'
	get 'docker/install_stream/:id' => 'apps#docker_install_stream', as: 'docker_install_stream'
	post 'docker/uninstall/:id' => 'apps#docker_uninstall', as: 'docker_uninstall'
	post 'docker/start/:id' => 'apps#docker_start', as: 'docker_start'
	post 'docker/stop/:id' => 'apps#docker_stop', as: 'docker_stop'
	post 'docker/restart/:id' => 'apps#docker_restart', as: 'docker_restart'
	get 'docker/status/:id' => 'apps#docker_status', as: 'docker_status'
end
