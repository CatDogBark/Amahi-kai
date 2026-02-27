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

require 'system_utils'

class DebugController < ApplicationController

  before_action :admin_required
  layout 'debug'

  def index
    @page_title = t('debug')
  end

  def logs
    @page_title = t('debug')
  end

  def system
    @page_title = t('debug')
  end

  def submit
    report = SystemUtils.run "tail -200 #{Rails.root.join('log/production.log')}"
    render json: { status: 'ok', report_lines: report.to_s.lines.count }
  end

end
