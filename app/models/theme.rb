# Amahi Home Server
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

class Theme < ApplicationRecord

  before_destroy :before_destroy_hook

  # Themes installed under public/themes. Uses full paths rather than Dir.chdir,
  # which changes the working directory for every thread in the server.
  def self.available
    tl = all.to_a
    Dir.glob(File.join(Rails.root, THEME_ROOT, "*")).sort.each do |dir|
      theme_dir = File.basename(dir)
      next if where(:css=>theme_dir).first
      next unless SetTheme.valid_theme?(theme_dir)
      begin
        theme = SetTheme.info(theme_dir)
        tl << Theme.new(:name => theme[:name], :css => theme_dir) if theme[:name]
      rescue LoadError, NameError => e # NameError includes NoMethodError
        # there were issues in the theme init file!!
        logger.error("=================== Amahi Theme Error BEGIN ===========================")
        logger.error(e)
        logger.error("=================== Amahi Theme Error END   ===========================")
      end
    end
    tl
  end

  # Is +name+ one of the installed themes?
  def self.installed?(name)
    available.any? { |t| t.css == name.to_s }
  end

  def self.dir2theme(dir)
    theme = nil
    Dir.chdir(File.join(Rails.root, THEME_ROOT)) do
      theme_init_file = File.join(dir, "init.rb")
      if File.exist? theme_init_file
        load theme_init_file
        if defined?(theme_init) == "method"
          begin
            ti = theme_init
            theme = Theme.new(:name => ti[:name], :css => dir)
          rescue LoadError, NameError => e # NameError includes NoMethodError
            # there were issues in the theme init file!!
            raise "There were issues loading file '#{theme_init_file}'"
          end
        end
      else
        raise "That file '#{theme_init_file}' does not exist!"
      end
    end
    theme.save! if theme
    theme
  end

  def before_destroy_hook
    Dir.chdir(File.join(Rails.root, THEME_ROOT)) do
      FileUtils.rm_rf self.css
    end
  end
end
