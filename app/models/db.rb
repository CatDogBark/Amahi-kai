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

require 'shellwords'

class Db < ApplicationRecord

	DB_BACKUPS_DIR = "/var/hda/dbs"

	after_create :after_create_hook
	after_destroy :after_destroy_hook

	# stubs for name, password and hostname, in case they need changed later

	def username
		name
	end

	def password
		name
	end

	def hostname
		"localhost"
	end

private

	def after_create_hook
		return unless Rails.env.production?
		c = self.class.connection
		password = name
		user = name
		host = 'localhost'
		quoted_db = c.quote_column_name(name)
		quoted_user = c.quote(user)
		quoted_host = c.quote(host)
		quoted_pass = c.quote(password)
		c.execute "DROP DATABASE IF EXISTS #{quoted_db};" rescue nil
		c.execute "CREATE DATABASE IF NOT EXISTS #{quoted_db} DEFAULT CHARACTER SET utf8;"
		# Drop user first to ensure clean state (CREATE USER fails if user exists)
		c.execute("DROP USER #{quoted_user}@#{quoted_host};") rescue nil
		c.execute "CREATE USER #{quoted_user}@#{quoted_host} IDENTIFIED BY #{quoted_pass};"
		c.execute "GRANT ALL PRIVILEGES ON #{quoted_db}.* TO #{quoted_user}@#{quoted_host};"
	end

	def after_destroy_hook
		return unless Rails.env.production?
		user = name
		filename = Time.now.strftime("#{DB_BACKUPS_DIR}/%y%m%d-%H%M%S-#{name}.sql.bz2")
		safe_user = Shellwords.escape(user)
		safe_name = Shellwords.escape(name)
		safe_filename = Shellwords.escape(filename)
		system("mysqldump --add-drop-table -u#{safe_user} -p#{safe_user} #{safe_name} | bzip2 > #{safe_filename}")
		Dir.chdir(DB_BACKUPS_DIR) do
			system("ln -sf #{safe_filename} #{Shellwords.escape("latest-#{name}.bz2")}")
		end
		c = self.class.connection
		host = 'localhost'
		quoted_user = c.quote(user)
		quoted_host = c.quote(host)
		quoted_db = c.quote_column_name(name)
		c.execute "DROP USER #{quoted_user}@#{quoted_host};"
		c.execute "DROP DATABASE IF EXISTS #{quoted_db};"
	end
end
