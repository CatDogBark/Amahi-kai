# Amahi Home Server  encoding: utf-8
# Copyright (C) 2007-2013 Amahi
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License v3
# (29 June 2007), as published in the COPYING file.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# file COPYING for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Amahi
# team at http://www.amahi.org/ under "Contact Us."

require 'uri'
require 'net/http'

# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper

	# refactored

	def current_user_is_admin?
		current_user && current_user.admin?
	end

	def rtl?
		@locale_direction == 'rtl'
	end

	def theme
		@theme
	end

	def page_title
		@page_title
	end

	def amahi_plugins
		AmahiHDA::Application.config.amahi_plugins
	end

	def full_page_title
		page_title ? "Amahi Home Server &rsaquo; #{page_title}".html_safe : "Amahi Home Server"
	end

	def spinner(css_class = '')
		content_tag('span', '', class: "spinner #{css_class}", style: "display: none")
	end

	def formatted_date(date)
		date = date.localtime
		"#{date.to_formatted_s(:short)} (#{time_ago_in_words(date)})"
	rescue
		'-'
	end

	def path2uri(name)
		name = URI.encode_www_form_component(name)
		is_a_mac? ? "smb://hda/#{name}" : "file://///hda/#{name}"
	end

	def path2location(name)
		fwd = '\\'
		is_a_mac? ? '&raquo; '.html_safe + h(name.gsub(/\//, ' ▸ ')) : h('\\\\hda\\' + name.gsub(/\//, fwd))
	end

	# to verify ################################################

	def is_a_mac?
		(request.env["HTTP_USER_AGENT"] =~ /Macintosh/) ? true : false
	end

	def is_firefox?
		(request.env["HTTP_USER_AGENT"] =~ /Firefox/) ? true : false
	end




	def fw_rule_type(t)
		case t
		when 'port_filter'
			'Port Filter'
		when 'url_filter'
			'URL Filter'
		when 'mac_filter'
			'MAC Filter'
		when 'ip_filter'
			'IP Filter'
		when 'port_forward'
			'Port Forwarding'
		else
			raise "type #{rule.kind} unknown"
		end
	end

	def fw_rule_details(rule)
		case rule.kind
		when 'port_filter'
			"Ports: #{rule.range}, Protocol: #{fw_prot(rule.protocol)}"
		when 'ip_filter'
			"IP: #{@net}.#{rule.ip}, Protocol: #{fw_prot(rule.protocol)}"
		when 'mac_filter'
			"MAC: #{rule.mac}"
		when 'url_filter'
			"URL: #{rule.url}"
		when 'port_forward'
			"IP: #{@net}.#{rule.ip}, Ports: #{rule.range}"
		else
			raise "details for #{rule.kind} unknown"
		end
	end

	def fw_rule_state(rule)
		Setting.get(rule.kind) == '1'
	end

	def fw_prot(p)
		p == 'both' ? 'TCP &amp; UDP' : p.upcase
	end

	def msg_bad(s = "")
		theme_image_tag("stop") + " " + s
	end

	def msg_good(s = "")
		theme_image_tag("ok") + " " + s
	end

	def msg_warn(s = "")
		theme_image_tag("warning") + " " + s
	end

	def delete_icon(title = "")
		theme_image_tag("delete.png", :title => title)
	end






	# theme helpers
	def theme_stylesheet_link_tag(a)
		tag.link(
			href: File.join('/themes', @theme.path, 'stylesheets', "#{a}.css"),
			rel: "stylesheet",
			media: "screen"
		)
	end

	def theme_stylesheet_path(a, theme)
		File.join('/themes', theme, 'stylesheets', "#{a}.css")
	end

	def theme_image_tag(a, options = {})
		s = File.join('/themes', @theme.path, 'images', a)
		tag('img', {src: s}.merge(options))
	end

	def theme_image_path(a, theme=nil)
		File.join('/themes', theme || @theme.path, 'images', a)
	end
end
