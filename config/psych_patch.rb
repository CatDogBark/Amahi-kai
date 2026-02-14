# Psych 5.x on Ruby 2.7 requires explicit aliases: true for YAML anchors.
# The yettings gem (and other old code) calls YAML.load without this option.
# This patch makes YAML.load use unsafe_load when called without options,
# matching the pre-Psych-4 behavior.
#
# TODO: Remove when either:
# - yettings gem is replaced with Rails credentials/custom config
# - Ruby + Psych versions are properly matched
require 'psych'

module Psych
  class << self
    alias_method :_strict_load, :load

    def load(yaml, *args, **kwargs)
      if args.empty? && kwargs.empty?
        unsafe_load(yaml)
      else
        _strict_load(yaml, *args, **kwargs)
      end
    end
  end
end
