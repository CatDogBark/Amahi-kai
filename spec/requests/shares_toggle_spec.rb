require 'rails_helper'

describe "Shares Toggle Actions", type: :request do

  describe "admin" do
    before do
      login_as_admin
      # Stub all system-level calls that share callbacks trigger
      allow(Share).to receive(:push_shares)
      allow(SambaService).to receive(:push_config)
      allow(Shell).to receive(:run).and_return(true)
    end

    let(:share) { create(:share, visible: true, rdonly: false) }

    describe "PUT /shares/:id/toggle_visible" do
      it "toggles visibility" do
        put toggle_visible_share_path(share), as: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
        expect(share.reload.visible).to eq(false)
      end
    end

    describe "PUT /shares/:id/toggle_readonly" do
      it "toggles readonly" do
        put toggle_readonly_share_path(share), as: :json
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("ok")
      end
    end

    describe "PUT /shares/:id/toggle_everyone" do
      it "toggles everyone access" do
        put toggle_everyone_share_path(share), as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PUT /shares/:id/toggle_guest_access" do
      it "toggles guest access" do
        put toggle_guest_access_share_path(share), as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PUT /shares/:id/toggle_guest_writeable" do
      it "toggles guest writeable" do
        put toggle_guest_writeable_share_path(share), as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PUT /shares/:id/update_extras" do
      it "updates extras" do
        put update_extras_share_path(share), params: { share: { extras: "vfs objects = recycle" } }, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq('status' => 'ok', 'message' => nil)
        expect(share.reload.extras).to eq("vfs objects = recycle")
      end

      it "refuses settings that open another section, and says so" do
        put update_extras_share_path(share), params: { share: { extras: "hide dot files = yes\n [global]\nx = y" } }, as: :json
        expect(response.parsed_body).to eq('status' => 'not_acceptable', 'message' => "Extras can't open another section ([global])")
        expect(share.reload.extras).to be_blank
      end

      it "puts the settings back when the root helper refuses the config, and says why" do
        allow(SambaService).to receive(:push_config).with(raise_refusal: true)
          .and_raise(Privileged::Error.new('samba.write_config', 'smb.conf refused: [test] made up is not allowed', refused: true))
        share.update_columns(extras: "hide dot files = yes")
        put update_extras_share_path(share), params: { share: { extras: "made up = x" } }, as: :json
        expect(response.parsed_body).to eq('status' => 'not_acceptable', 'message' => 'smb.conf refused: [test] made up is not allowed')
        expect(share.reload.extras).to eq("hide dot files = yes")
      end
    end

    describe "PUT /shares/:id/clear_permissions" do
      it "clears permissions" do
        put clear_permissions_share_path(share), as: :json
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /shares/settings" do
      it "redirects if not advanced" do
        Setting.find_by(name: "advanced")&.update!(value: "0")
        get "/shares/settings"
        expect(response).to have_http_status(:redirect)
      end

      it "shows settings page when advanced" do
        Setting.create!(name: "advanced", value: "1", kind: 0)
        get "/shares/settings"
        expect(response).to have_http_status(:ok)
      end
    end

    describe "a share's card" do
      it "is laid out by what it decides, with what each setting does, and Delete at the bottom" do
        Setting.set("advanced", "0")
        share = create(:share, name: "Docs", disk_pool_copies: 0)
        get shares_path
        card = Nokogiri::HTML(response.body).at_css("#whole_share_#{share.id} .share-card")
        expect(card.css("h6.share-section-title").map(&:text)).to eq(%w[Access Storage Trash])
        expect(card.css(".share-row-label").map(&:text)).to eq(["Who can use it", "Visible", "People", "Folder", "Size", "Pool copies", "Deleted files"])
        expect(card.at_css("#pool-help-#{share.id}").text.squish).to include("2 copies: each file is kept on two drives")
        expect(card.at_css("#share-section-trash-#{share.id}").text.squish).to include("for 30 days", "hidden .recycle folder")
        expect(card.at_css("#share-trash-#{share.id}")["href"]).to eq("/files/trash")
        expect(card.at_css(".share-card-footer").text.squish).to include("Delete Docs", "Its files stay in its folder")
        expect(card.text).not_to include("Features", "Tags", "Recycle Bin", "Time Machine")
        expect(card.at_css("#extras-textarea-#{share.id}")).to be_nil
      end

      it "has every switch show what's saved after a reload (no browser-restored state)" do
        share = create(:share, name: "Docs", everyone: false, guest_access: false)
        create(:user)
        get shares_path
        card = Nokogiri::HTML(response.body).at_css("#whole_share_#{share.id}")
        switches = card.css('input[type=checkbox]')
        expect(switches.size).to be >= 7 # visible, all users, writeable, a user's access and write, two guest
        expect(switches.map { |s| s['autocomplete'] }).to all(eq('off'))
      end

      it "has Samba settings under Advanced, in advanced mode" do
        Setting.set("advanced", "1")
        share = create(:share, name: "Docs", extras: "log level = 1")
        get shares_path
        card = Nokogiri::HTML(response.body).at_css("#whole_share_#{share.id} .share-card")
        expect(card.css("h6.share-section-title").map(&:text)).to eq(%w[Access Storage Trash Advanced])
        expect(card.at_css("#extras-textarea-#{share.id}").text).to eq("log level = 1")
      end

      it "says a pooled share's Trash is Greyhole's" do
        share = create(:share, name: "Photos", disk_pool_copies: 2)
        get shares_path
        expect(Nokogiri::HTML(response.body).at_css("#share-section-trash-#{share.id}").text).to include("Greyhole keeps them on the pool drives")
      end
    end
  end
end
