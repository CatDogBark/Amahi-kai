FactoryBot.define do

  factory :user do
    sequence(:login) { |n| "user#{n}" }
    sequence(:name) { |n| "Name #{n}" }
    password { "secretpassword" }

    # Stub system hooks to avoid calling hda-ctl, useradd, etc.
    # Using transient + to_create instead of allow() which is not
    # available in FactoryBot 6.x callbacks
    transient do
      skip_system_hooks { true }
    end

    before(:create) do |user, evaluator|
      if evaluator.skip_system_hooks
        def user.before_create_hook; end
        def user.after_save_hook; end
        def user.after_create_hook; end
        def user.before_save_hook; end
        def user.before_destroy_hook; end
      end
    end

    factory :admin do
      admin { true }
    end
  end

  factory :setting

  factory :host do
    sequence(:name) { |n| "host#{n}" }
    sequence(:mac) { |n| "aa:bb:cc:dd:ee:%02x" % (n % 256) }
    sequence(:address) { |n| (n % 253) + 1 }

    before(:create) do |host|
      def host.restart; end
    end
  end

  factory :dns_alias do
    sequence(:name) { |n| "alias#{n}" }
    address { "192.168.1.100" }

    before(:create) do |dns_alias|
      def dns_alias.restart; end
    end
  end

  factory :docker_app do
    sequence(:identifier) { |n| "app#{n}" }
    sequence(:name) { |n| "App #{n}" }
    image { 'nginx:latest' }
    status { 'available' }
  end

  factory :disk_pool_partition do
    sequence(:path) { |n| "/mnt/data#{n}" }
    minimum_free { 10 }
  end

  factory :share do
    sequence(:path) { |n| "/path#{n}" }
    sequence(:name) { |n| "name#{n}" }

    before(:create) do |share|
      # Stub filesystem service with no-op to avoid shell commands in tests
      null_fs = ShareFileSystem.new(share)
      def null_fs.setup_directory; end
      def null_fs.update_guest_permissions; end
      def null_fs.cleanup_directory; end
      def null_fs.make_guest_writeable; end
      def null_fs.make_guest_non_writeable; end
      def null_fs.clear_permissions; end
      share.instance_variable_set(:@file_system, null_fs)

      # Stub access manager sync (after_save)
      null_am = ShareAccessManager.new(share)
      def null_am.sync_everyone_access; end
      share.instance_variable_set(:@access_manager, null_am)

      # Stub other callbacks
      def share.normalize_tags; end
      def share.push_samba_config; end
      def share.index_share_files; end
    end
  end
end
