class UserNotExistInSystemValidator < ActiveModel::EachValidator
  def validate_each(object, attribute, value)
    unless User.is_valid_name?(value)
      # errors[:login] << message stopped adding errors in Rails 7, so this check
      # silently passed and a web user could take an existing Linux login.
      object.errors.add(:login, options[:message] || 'already exists in system')
    end
  end
end
