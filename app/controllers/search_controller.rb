# encoding: UTF-8
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

class SearchController < ApplicationController

  before_action :login_required
  layout 'basic'

  RESULTS_PER_PAGE = 20

  def hda
    @page_title = 'Search Results'
    @search_value = 'HDA'

    if params[:button] && params[:button] == "Web"
      require 'uri'
      redirect_to "http://www.google.com/search?q=#{URI.encode_www_form_component(params[:query])}", allow_other_host: true
    else
      @query = params[:query]
      @page = (params[:page] && params[:page].to_i.abs) || 1
      @rpp = (params[:per_page] && params[:per_page].to_i.abs) || RESULTS_PER_PAGE

      unless use_sample_data?
        @results = search_share_files(@query, nil, @page, @rpp)
      else
        @results = SampleData.load('search')
      end
    end
  end

  def images
    @query = params[:query]
    @page = (params[:page] && params[:page].to_i.abs) || 1
    @rpp = (params[:per_page] && params[:per_page].to_i.abs) || RESULTS_PER_PAGE
    @results = search_share_files(@query, 'image', @page, @rpp)
    render 'hda'
  end

  def audio
    @query = params[:query]
    @page = (params[:page] && params[:page].to_i.abs) || 1
    @rpp = (params[:per_page] && params[:per_page].to_i.abs) || RESULTS_PER_PAGE
    @results = search_share_files(@query, 'audio', @page, @rpp)
    render 'hda'
  end

  def video
    @query = params[:query]
    @page = (params[:page] && params[:page].to_i.abs) || 1
    @rpp = (params[:per_page] && params[:per_page].to_i.abs) || RESULTS_PER_PAGE
    @results = search_share_files(@query, 'video', @page, @rpp)
    render 'hda'
  end

  def web
  end

  protected

  def search_share_files(query, content_type, page, rpp = RESULTS_PER_PAGE)
    scope = ShareFile.files_only
    scope = scope.search(query) if query.present?
    scope = scope.by_type(content_type) if content_type.present?
    scope = scope.recent

    # Paginate
    offset = (page - 1) * rpp
    files = scope.offset(offset).limit(rpp).includes(:share)

    files.map do |sf|
      # path format: "sharename/relative/path/to/file" — matches what path2uri and path2location expect
      rel = sf.relative_path
      full_share_path = rel == sf.name ? sf.share.name : File.join(sf.share.name, rel)
      {
        title: sf.name,
        path: full_share_path,
        size: sf.size,
        owner: sf.share.name,
        type: sf.directory? ? 'directory' : 'file'
      }
    end
  end
end
