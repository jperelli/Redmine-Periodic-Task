active_record_migration_class = ActiveRecord::Migration.respond_to?(:current_version) ? ActiveRecord::Migration[4.2] : ActiveRecord::Migration

class MigrateCustomFieldValuesToJson < active_record_migration_class
  # Bare model with no serialization, so we read the raw stored string and
  # convert it ourselves instead of letting the type caster choke on the old
  # YAML payload.
  class Row < ActiveRecord::Base
    self.table_name = 'periodictasks'
  end

  def self.up
    Row.where.not(custom_field_values: nil).find_each do |row|
      raw = row.read_attribute_before_type_cast(:custom_field_values)
      next if raw.blank?

      parsed = begin
        YAML.safe_load(raw, permitted_classes: [Symbol], aliases: true)
      rescue StandardError
        nil
      end
      next if parsed.nil?

      row.update_columns(custom_field_values: JSON.generate(parsed))
    end
  end

  def self.down
    Row.where.not(custom_field_values: nil).find_each do |row|
      raw = row.read_attribute_before_type_cast(:custom_field_values)
      next if raw.blank?

      parsed = begin
        JSON.parse(raw)
      rescue StandardError
        nil
      end
      next if parsed.nil?

      row.update_columns(custom_field_values: YAML.dump(parsed))
    end
  end
end
