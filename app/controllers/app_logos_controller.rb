# An app's logo, from the NAS (AppCatalog.logo): an app of your own's, or a catalog app's, which
# comes with the catalog's signed versions (docs/plans/apps.md, P4.10). For anyone signed in, as
# the dashboard shows them too. Under LOGO_POLICY, so a script in an SVG never runs; its address
# names the picture (v), so that one is cached.
class AppLogosController < ApplicationController
  LOGO_POLICY = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; sandbox".freeze

  before_action :login_required

  def show
    logo = AppCatalog.logo(params[:id]) or return head(:not_found)
    response.headers['Content-Security-Policy'] = LOGO_POLICY
    params[:v] == logo[:version] ? expires_in(1.year) : expires_now
    send_file logo[:path], type: logo[:type], disposition: 'inline'
  end
end
