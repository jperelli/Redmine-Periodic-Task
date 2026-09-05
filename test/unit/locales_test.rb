require "#{File.dirname(__FILE__)}/../test_helper"

class LocalesTest < ActiveSupport::TestCase
  LOCALE_DIR = File.expand_path('../../config/locales', __dir__)
  REFERENCE = 'en'.freeze
  PLURALIZED_KEYS = %w[
    label_recurrence_every_day label_recurrence_every_business_day
    label_recurrence_every_week label_recurrence_every_month label_recurrence_every_year
  ].freeze

  def test_every_locale_defines_the_same_keys_as_english
    expected = load_locale(REFERENCE).keys.sort

    each_translation_locale do |locale, translations|
      assert_equal expected, translations.keys.sort,
                   "#{locale}.yml does not define the same keys as #{REFERENCE}.yml"
    end
  end

  # Interpolations (%{name}) and subject macros (**MACRO**) must survive
  # translation. Pluralized entries are compared as a whole, since which plural
  # categories a language needs (one/few/other) is up to the language.
  def test_every_locale_keeps_interpolations_and_macros
    reference = load_locale(REFERENCE)

    each_translation_locale do |locale, translations|
      translations.each do |key, value|
        assert_equal tokens(reference[key]), tokens(value),
                     "#{locale}.yml: #{key} does not use the same variables as #{REFERENCE}.yml"
      end
    end
  end

  def test_pluralized_keys_resolve_for_every_locale
    each_translation_locale do |locale, _translations|
      PLURALIZED_KEYS.each do |key|
        [1, 3].each do |count|
          value = I18n.t(key, count: count, locale: locale, raise: true)
          assert_kind_of String, value, "#{locale}.yml: #{key} has no plural form for count #{count}"
        end
      end
    end
  end

  private

  def each_translation_locale
    locales = Dir.glob("#{LOCALE_DIR}/*.yml").map { |path| File.basename(path, '.yml') } - [REFERENCE]
    assert_not_empty locales
    locales.each { |locale| yield locale, load_locale(locale) }
  end

  def load_locale(locale)
    YAML.safe_load_file("#{LOCALE_DIR}/#{locale}.yml").fetch(locale)
  end

  def tokens(value)
    values = value.is_a?(Hash) ? value.values : [value]
    values.flat_map { |v| v.to_s.scan(/%\{\w+\}|\*\*[A-Z_]+\*\*/) }.uniq.sort
  end
end
