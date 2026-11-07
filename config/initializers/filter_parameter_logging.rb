# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
Rails.application.config.filter_parameters += [:password, :password_confirmation, :pin, :secret_key_base, :authenticity_token,
  # Rails' standard list: anything whose name contains these is filtered too
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :otp,
  # An app of your own's file and settings' values (CustomAppsController) may hold a key typed in
  :manifest, /\Aapp\.settings\.[^.]+\.value\z/]
