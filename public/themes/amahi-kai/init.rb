def theme_init
	# Amahi-kai ocean theme colors
	teal = '#0a6e8a'
	light_teal = '#0d8aa8'
	amber = '#f0a030'
	navy = '#1a2332'
	success = '#27ae60'
	danger = '#c0392b'

	colors = [teal, navy, success, amber, danger, light_teal, '#7f8c9b']

	ret = {}

	ret[:name] = "Amahi-kai Ocean"
	ret[:version] = "1.0"
	ret[:theme_uri] = "https://github.com/CatDogBark/Amahi-kai"
	ret[:author] = "Kai & Troy, built on Amahi by Carlos Puchol"
	ret[:author_uri] = ""
	ret[:disable_inheritance] = false
	ret[:gruff_theme] = {
	  :colors => colors,
	  :marker_color => navy,
	  :font_color => navy,
	  :background_colors => ['#f4f7fa', '#ffffff']
	}

	ret
end
