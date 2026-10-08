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

module SearchHelper

  # A result's icon: the file browser's, by kind (FileBrowserService).
  def search_result_icon(result)
    kind = result[:type] == 'directory' ? :folder : FileBrowserService.kind(FileBrowserService.detect_mime_type(result[:path].to_s), false)
    lucide_icon(FileBrowserService::KIND_ICONS[kind], size: 18)
  end

  # active class if the the controller matches
  def active(controller)
    action_name == controller ? 'active' : ''
  end

end
