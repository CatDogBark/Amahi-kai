require 'app_versions'

# Request and browser specs never ask a registry, as the update check, Check now and an install's
# newest version would (P4.9, AppUpdateCheck): every app's image is the newest one, unless a spec
# says otherwise with its own allow_any_instance_of(AppVersions).to receive(:check_image).
RSpec.configure do |config|
  %i[request system].each do |type|
    config.before(:each, type: type) do
      allow_any_instance_of(AppVersions).to receive(:check_image) do |_versions, image, **_options|
        match = image.to_s.match(AppVersions::IMAGE)
        AppVersions::Result.new(repo: match&.[](:repo), tag: match&.[](:tag), latest: match&.[](:tag), image: image, kind: :current)
      end
    end
  end
end
