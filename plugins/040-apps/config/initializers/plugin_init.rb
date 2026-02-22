# plugin initialization
t = Tab.new("apps", "apps", "/tab/apps")
# add any subtabs with what you need. params are controller and the label, for example
t.add("index", "available")
t.add("installed", "installed")
t.add("docker_apps", "docker_apps", true)
