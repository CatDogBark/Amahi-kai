require 'file_browser_service'
require 'zip_kit'

# The web file browser: browse, preview and download. It changes nothing. Files are added,
# renamed and deleted over the SMB shares, so Samba, and Greyhole on pooled shares, sees
# every change (docs/plans/storage.md, S5).
class FileBrowserController < ApplicationController
  include ZipKit::RailsStreaming

  before_action :browse_required
  before_action { @no_tabs = true } # Files is its own section; Setup is in the header
  before_action :set_share, except: :index
  before_action :check_share_access, except: :index
  before_action :resolve_path, except: :index

  # A name or path the service refuses gets a clear error, not a 500. (Handlers are
  # matched last-declared first, so InvalidName, a SecurityError, is checked first.)
  rescue_from SecurityError, with: :access_denied
  rescue_from FileBrowserService::InvalidName, with: :invalid_name

  # GET /files: the shares this person can open, to browse (the header's Shares link).
  def index
    @page_title = t('shares')
    @shares = Share.by_name.select { |share| current_user.can_access_share?(share) }
    # How many things each share holds at its top, for its card
    @counts = @shares.to_h { |share| [share.id, (Dir.children(share.path).count { |e| !e.start_with?('.') } rescue nil)] }
    # Admins also get the Trash, below the shares
    @trash = Trash.contents if current_user.admin?
  end

  # GET /files/:share_id/browse/*path
  def browse
    unless File.directory?(@full_path)
      # If it's a file, send it
      if File.file?(@full_path)
        return send_file_download
      end
      flash[:error] = "Path not found"
      return redirect_to file_browser_path(@share)
    end

    # Its heading is the breadcrumbs (Shares › the share › its folders), under Files
    @page_title = @share.name
    @page_heading = false
    @entries = FileBrowserService.list_directory(@full_path)
    @breadcrumbs = FileBrowserService.build_breadcrumbs(@share.name, @relative_path)
  end

  # GET /files/:share_id/download/*path
  def download
    unless File.exist?(@full_path)
      flash[:error] = "File not found"
      parent = File.dirname(@relative_path.to_s)
      return redirect_to helpers.browse_path(@share, parent == '.' ? nil : parent) # the folder it was in
    end

    if File.directory?(@full_path)
      send_directory_as_zip
    else
      send_file_download
    end
  end

  # GET /files/:share_id/preview/*path
  def preview
    unless File.file?(@full_path)
      return render json: { error: "Not a file" }, status: :not_found
    end

    @filename = File.basename(@full_path)
    @file_size = File.size(@full_path)
    @mime_type = FileBrowserService.detect_mime_type(@full_path)
    @previewable = FileBrowserService.previewable?(@mime_type, @file_size)

    if request.format.json?
      render json: {
        name: @filename,
        size: @file_size,
        mime: @mime_type,
        previewable: @previewable
      }
    end
    # Otherwise renders preview.html.erb
  end

  # Types a browser would run as a page on the Amahi origin if the raw URL were
  # opened directly. They are served as plain text, so the browser shows the source.
  ACTIVE_TYPES = %w[text/html application/xhtml+xml text/javascript application/javascript
                    application/xml text/xml].freeze

  # GET /files/:share_id/raw/*path — serves file content for preview embeds
  def raw
    unless File.file?(@full_path)
      return head :not_found
    end

    mime = FileBrowserService.detect_mime_type(@full_path)
    mime = 'text/plain' if ACTIVE_TYPES.include?(mime)
    # Files from a share open in a sandbox: no scripts, and no access to the Amahi
    # origin, so an SVG (still served as an image for previews) can't run code either.
    # PDFs are left out because browsers' built-in PDF viewers won't load sandboxed.
    response.headers['Content-Security-Policy'] = 'sandbox' unless mime == 'application/pdf'
    send_file @full_path,
      type: mime,
      disposition: 'inline',
      filename: File.basename(@full_path)
  end

  private

  def invalid_name(error)
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def access_denied(_error)
    render json: { error: "Access denied" }, status: :forbidden
  end

  def set_share
    @share = Share.find_by!(name: params[:share_id])
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Share not found"
    redirect_to root_path
  end

  def check_share_access
    unless current_user.can_access_share?(@share)
      flash[:error] = "You don't have access to this share"
      redirect_to root_path
    end
  end

  # Where the share's files may really be: its folder and, when it's pooled, its folder on
  # each Greyhole pool drive (a pooled share holds links to the copies there).
  def share_roots
    @share_roots ||= begin
      pooled = @share.disk_pool_copies.to_i.positive? ? DiskPoolPartition.pluck(:path) : []
      [@share.path, *pooled.map { |drive| File.join(drive, @share.name) }]
    end
  end

  def resolve_path
    @relative_path, @full_path = FileBrowserService.resolve_path(share_roots, params[:path])
  rescue Errno::ENOENT, Errno::EACCES, Errno::EPERM, SecurityError
    flash[:error] = "Access denied"
    redirect_to file_browser_path(@share)
  end

  def send_file_download
    mime = FileBrowserService.detect_mime_type(@full_path)
    send_file @full_path,
      type: mime,
      disposition: 'attachment',
      filename: File.basename(@full_path)
  end

  # The folder as a zip, sent as it's made: the download starts at once, and nothing is
  # written to the system disk first. The page's token comes back in a cookie, which tells
  # it the download has started (file_browser_controller.js).
  def send_directory_as_zip
    token = params[:token].to_s
    cookies[:fb_download] = { value: token, path: '/', httponly: false, same_site: :lax } if token.match?(/\A[a-z0-9]{8,40}\z/)
    full_path = @full_path
    roots = share_roots
    zip_kit_stream(filename: "#{File.basename(full_path)}.zip") do |zip|
      FileBrowserService.write_zip(zip, full_path, roots)
    end
  end
end
