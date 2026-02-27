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

  def full_page_title
    page_title ? "Amahi-kai &rsaquo; #{page_title}".html_safe : "Amahi-kai Home Server"
  end

  def spinner(css_class = '')
    content_tag('span', '', class: "spinner #{css_class}", style: "display: none")
  end

  def formatted_date(date)
    date = date.localtime
    "#{date.to_formatted_s(:short)} (#{time_ago_in_words(date)})"
  rescue StandardError => e
    '-'
  end

  def netbios_name
    @netbios_name ||= (Setting.get('server-name') || 'amahi-kai').downcase
  end

  def path2uri(name)
    name = URI.encode_www_form_component(name)
    is_a_mac? ? "smb://#{netbios_name}/#{name}" : "file://///#{netbios_name}/#{name}"
  end

  def path2location(name)
    fwd = '\\'
    is_a_mac? ? '&raquo; '.html_safe + h(name.gsub(/\//, ' ▸ ')) : h("\\\\#{netbios_name}\\" + name.gsub(/\//, fwd))
  end

  def is_a_mac?
    (request.env["HTTP_USER_AGENT"] =~ /Macintosh/) ? true : false
  end

  # Firewall helpers removed — will be re-added when firewall plugin is built
  # (fw_rule_type, fw_rule_details, fw_rule_state, fw_prot, msg_bad, msg_good, msg_warn, delete_icon)






  # theme helpers
  def theme_stylesheet_link_tag(a)
    css_path = File.join('/themes', @theme.path, 'stylesheets', "#{a}.css")
    full_path = Rails.public_path.join('themes', @theme.path, 'stylesheets', "#{a}.css")
    mtime = File.exist?(full_path) ? File.mtime(full_path).to_i : AmahiKai::VERSION.tr('.', '')
    tag.link(
      href: "#{css_path}?v=#{mtime}",
      rel: "stylesheet",
      media: "screen"
    )
  end

  def theme_stylesheet_path(a, theme)
    css_path = File.join('/themes', theme, 'stylesheets', "#{a}.css")
    full_path = Rails.public_path.join('themes', theme, 'stylesheets', "#{a}.css")
    mtime = File.exist?(full_path) ? File.mtime(full_path).to_i : AmahiKai::VERSION.tr('.', '')
    "#{css_path}?v=#{mtime}"
  end

  def theme_image_tag(a, options = {})
    s = File.join('/themes', @theme.path, 'images', a)
    tag('img', {src: s}.merge(options))
  end

  def theme_image_path(a, theme=nil)
    File.join('/themes', theme || @theme.path, 'images', a)
  end

  def advanced?
    (s = Setting.where(:name=>'advanced').first) && s.set?
  end
end
