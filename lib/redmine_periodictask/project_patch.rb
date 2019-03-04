module RedminePeriodictask
  module ProjectPatch
    def self.included(base)
      base.class_eval do
        has_many :periodictasks, :dependent => :destroy
      end
    end
  end
end
