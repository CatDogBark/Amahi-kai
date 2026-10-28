require 'open3'

# The root helper's code as it's installed: libexec/amahi-helper with each of its parts
# (libexec/amahi-helper.d) in place, as bin/amahi-join-helper puts them, for specs that read it.
module HelperSource
  def self.text
    @text ||= begin
      out, err, status = Bundler.with_unbundled_env do
        Open3.capture3(RbConfig.ruby, '--disable-gems', Rails.root.join('bin/amahi-join-helper').to_s)
      end
      raise "bin/amahi-join-helper failed: #{err}" unless status.success?

      out
    end
  end
end
