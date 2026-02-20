def theme_init
	# Colors — Classic neutral palette (steel blue + warm grays)
	primary = '#4a6fa5'
	secondary = '#5d8ac4'
	accent = '#d4a03c'
	success = '#38a169'
	danger = '#e53e3e'
	warning = '#dd6b20'
	dark = '#2d3748'
	muted = '#718096'
	# for disk usage pie charts
	colors = [danger, dark, success, warning, accent, primary, muted]

	ret = {}

	ret[:name] = "Classic"
	ret[:version] = "2.0"
	ret[:theme_uri] = "https://github.com/CatDogBark/Amahi-kai"
	ret[:author] = "Originally by Carlos Puchol for Amahi, updated for Amahi-kai"
	ret[:author_uri] = ""
	ret[:disable_inheritance] = true
	ret[:gruff_theme] = {
	  :colors => colors,
	  :marker_color => dark,
	  :font_color => dark,
	  :background_colors => ['#f7fafc', '#ffffff']
	}

	ret
end
