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

  # What the last check for updates found, read once per page (admins' header and dashboard).
  def update_status
    @update_status ||= UpdateStatus.load
  end

  # Amahi-kai's own address on +host+ (the web UI's port). Every address of Amahi-kai is made
  # here, as every address of an app is made by DockerApp#url, so HTTPS (an optional front
  # door, later: docs/plans/roadmap.md) can change them in one place. A spec checks.
  def amahi_url(host)
    "http://#{host}:#{ENV.fetch('PORT', '3000')}/"
  end

  # Installed apps the catalog has a newer version of, for the admins who can update them
  # (by name, case aside, so SQLite and MariaDB agree).
  def app_updates
    @app_updates ||= current_user&.admin? ? DockerApp.all.select(&:update_available?).sort_by { |app| app.name.downcase } : []
  end

  def theme
    @theme
  end

  def page_title
    @page_title
  end

  # The header's section for this page, whose link is marked current, and the line above the
  # page title: the dashboard, Files (the file browser, the Trash and search), Apps, or Setup.
  def page_section
    case controller_name
    when 'front' then :dashboard
    when 'file_browser', 'trash', 'search' then :files
    when 'apps' then :apps
    else :setup
    end
  end

  # A folder in a share's file browser: the share's top for an empty path. (The share's own
  # route takes no path, and quietly drops one given to it.)
  def browse_path(share, path = nil)
    path.present? ? file_browser_path_path(share, path: path) : file_browser_path(share)
  end

  def full_page_title
    page_title ? "Amahi-kai › #{page_title}" : "Amahi-kai Home Server"
  end

  def spinner(css_class = '')
    content_tag('span', '', class: "spinner #{css_class}", style: "display: none")
  end

  # "bitTube 0.1.2 → 0.1.3", for the dashboard's app update notice (just the name when either
  # version isn't known).
  def app_update_label(app)
    from, to = app.version, app.catalog_version
    from.present? && to.present? ? "#{app.name} #{from} → #{to}" : app.name
  end

  # A time shown as "3 hours ago", or "in 2 hours" when +future+ ("any moment" once it's
  # passed). time_ago.js works it out again every minute, when a dialog opens and when the page
  # comes back into view: written only when the page loads, a page left open would keep saying
  # "less than a minute ago". +clock+ adds the time of day in the viewer's time zone.
  def relative_time_tag(time, future: false, capitalize: false, clock: false)
    text = if !future then "#{time_ago_in_words(time)} ago"
           elsif time > Time.current then "in #{distance_of_time_in_words(Time.current, time)}"
           else 'any moment'
           end
    content_tag(:time, capitalize ? text.upcase_first : text, datetime: time.utc.iso8601,
                data: { relative: future ? 'in' : 'ago', capitalize: (true if capitalize), clock: (true if clock) })
  end

  def formatted_date(date)
    date = date.localtime
    "#{date.to_formatted_s(:short)} (#{time_ago_in_words(date)})"
  rescue NoMethodError, ArgumentError, RangeError
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
