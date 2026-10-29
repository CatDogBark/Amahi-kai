# An error that says whether something broke (failed?: the root helper failed, a command
# didn't run, a list couldn't be read) or the request needs changing (a refusal, a choice
# missing, a drive gone since the page loaded). A red flag for one that broke offers Report a
# problem (ApplicationController#flash_failure, toast.js); one that only needs changing doesn't.
module ReportableError
  def initialize(message = nil, failed: false)
    @failed = failed
    super(message)
  end

  def failed?
    @failed
  end

  # A root helper's error as this kind: broke unless the helper turned the request down.
  def self.from_privileged(klass, error)
    klass.new(error.message, failed: !error.refused?)
  end
end
