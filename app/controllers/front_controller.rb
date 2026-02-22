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

require 'amahi_news'

class FrontController < ApplicationController

	before_action :login_required
	layout 'basic'

	def index
		@page_title = t('dashboard')
		@apps = App.in_dashboard
		@stats = DashboardStats.summary
	end

	def toggle_advanced
		return head(:forbidden) unless current_user&.admin?
		s = Setting.where(name: 'advanced').first
		if s
			s.value = (1 - s.value.to_i).to_s
			s.save
		end
		render json: { status: 'ok', advanced: s&.value == '1' }
	end
end
