require 'simplecov'

SimpleCov.start('rails') do
  # Give each CI job a unique command name so results can be merged
  command_name ENV.fetch('SIMPLECOV_COMMAND_NAME', 'default')

  # Filter out files we don't need coverage for
  %w(webapp.rb theme.rb system_utils.rb).each do |file|
    add_filter file
  end

  # Store results in a consistent location for CI artifact upload
  coverage_dir 'coverage'

  # Enable branch coverage (Ruby 2.5+)
  enable_coverage :branch if respond_to?(:enable_coverage)
end
