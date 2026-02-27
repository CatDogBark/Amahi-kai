# Amahi-kai data and temp directories
AMAHI_DATA_DIR = if Rails.env.production?
  '/var/lib/amahi-kai'
else
  File.join(Rails.root, 'tmp/amahi-kai')
end

AMAHI_TMP_DIR = File.join(AMAHI_DATA_DIR, 'tmp')
FileUtils.mkdir_p(AMAHI_TMP_DIR)
