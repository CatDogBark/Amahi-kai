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

require 'rubygems'
require 'active_support/all'
require 'active_resource'

# Amahi cloud API client.
#
# NOTE: The original api.amahi.org service is no longer available.
# This module is preserved for structural compatibility but all API calls
# are stubbed to return empty results rather than hanging/crashing.
#
# Set the api key (preserved for compatibility):
#    AmahiApi.api_key = 'abcxyz123'

module AmahiApi
	class Error < StandardError; end

	# Track whether the API is available
	@@api_available = false
	@@last_check = nil

	class << self
		attr_accessor :host_format, :domain_format, :protocol
		attr_reader :api_key

		def api_key=(value)
			@api_key = value
			# Don't attempt to configure resources — API is dead
			Rails.logger.info("AmahiApi: API key set but api.amahi.org is no longer available") if defined?(Rails)
		end

		def resources
			@resources ||= []
		end

		def available?
			@@api_available
		end
	end

	self.host_format   = '%s://%s'
	self.domain_format = 'api.amahi.org/api2'
	self.protocol      = 'https'

	# Stub base class that returns empty results instead of hitting a dead API
	class Base < ActiveResource::Base
		self.site = 'https://api.amahi.org/api2'

		def self.inherited(base)
			AmahiApi.resources << base
			class << base
				attr_accessor :site_format
			end
			base.site_format = '%s'
			base.site = 'https://api.amahi.org/api2'
			super
		end

		# Override find to return empty results instead of hitting dead API
		def self.find(*args)
			Rails.logger.warn("AmahiApi: Skipping API call to dead api.amahi.org (#{self.name}.find)") if defined?(Rails)
			raise ActiveResource::ResourceNotFound.new(nil)
		rescue => e
			raise AmahiApi::Error, "Amahi cloud API is not available: #{e.message}"
		end

		# Override create/save to no-op
		def save
			Rails.logger.warn("AmahiApi: Skipping API call to dead api.amahi.org (#{self.class.name}#save)") if defined?(Rails)
			false
		end
	end

	# Preserved class definitions for structural compatibility

	class ErrorReport < Base
	end

	class App < Base
	end

	class AppInstaller < Base
	end

	class AppUninstaller < Base
	end

	class TimelineEvent < Base
	end
end
