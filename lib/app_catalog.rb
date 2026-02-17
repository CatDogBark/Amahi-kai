require "yaml"

class AppCatalog
  CATALOG_PATH = File.expand_path("../../config/docker_apps/catalog.yml", __FILE__)

  def self.all
    catalog.map { |id, attrs| symbolize(attrs).merge(identifier: id) }
  end

  def self.find(id)
    all.detect { |app| app[:identifier] == id.to_s }
  end

  def self.by_category(category)
    all.select { |app| app[:category] == category.to_s }
  end

  def self.search(query)
    q = query.to_s.downcase
    all.select do |app|
      app[:name].to_s.downcase.include?(q) ||
        app[:description].to_s.downcase.include?(q)
    end
  end

  def self.categories
    all.map { |app| app[:category] }.compact.uniq.sort
  end

  def self.reload!
    @catalog = nil
  end

  private

  def self.catalog
    @catalog ||= YAML.load_file(CATALOG_PATH).fetch("apps", {})
  end

  def self.symbolize(hash)
    hash.each_with_object({}) do |(k, v), h|
      h[k.to_sym] = v
    end
  end
end
