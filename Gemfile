gem 'business_time', '= 0.13.0'

rails_gem = Bundler.rubygems.find_name('rails').first
rails_version = rails_gem.version unless rails_gem.nil?
gem 'protected_attributes_continued' if rails_gem.nil? || rails_version >= Gem::Version.new('4.0.0')
