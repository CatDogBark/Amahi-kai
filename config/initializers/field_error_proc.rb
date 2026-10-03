
# Uncomment the following block if you want each input field to have the validation messages attached.
ActionView::Base.field_error_proc = Proc.new do |html_tag, instance|
  label = ''
  unless html_tag =~ /^<label/
    label = %{<label for="#{ERB::Util.html_escape(instance.send(:tag_id))}" class="messages">#{ERB::Util.html_escape(instance.error_message.first)}</label>}
  end
  # Safe: html_tag is Rails' own field markup and the label's values are escaped above.
  %{<span class="field_with_errors">#{html_tag}#{label}</span>}.html_safe # rubocop:disable Rails/OutputSafety
end

