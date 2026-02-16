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

  factory :share do
    sequence(:path) { |n| "/path#{n}" }
    sequence(:name) { |n| "name#{n}" }
  end
end
