class Periodictask < ActiveRecord::Base
  unloadable
  belongs_to :project
  belongs_to :assigned_to, :class_name => 'Principal', :foreign_key => 'assigned_to_id'
  belongs_to :issue_category, :class_name => 'IssueCategory', :foreign_key => 'issue_category_id'
  belongs_to :issue_facility, :class_name => 'KpiFacility', :foreign_key => 'facility_id'
  
  serialize :custom_field_values
  # adapted to changes concerning mass-assigning values to attributes
  #attr_accessible *column_names
  # the above (attr_accessible *column_names) does not work for some reason
  attr_protected

  after_initialize do |task|
    if task.new_record?
      task.interval_number ||= 1
      task.interval_units ||= Periodictask.INTERVAL_UNITS.first[1];
    end
  end

  validates :interval_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :interval_units, presence: true

  scope :accessible, lambda {
    if User.current.allowed_to?(:periodictask, nil, global: true)
      all
    else
      where('1 = 0')
    end
  }

    #** INTERVAL_UNITS
    def self.INTERVAL_UNITS()
        [
            [ l(:label_unit_day), 'day' ],
            [ l(:label_unit_business_day ), 'business_day' ],
            [ l(:label_unit_week), 'week' ],
            [ l(:label_unit_month), 'month' ],
            [ l(:label_unit_year), 'year' ]
        ]
    end
    
    #** trimTimeZone
    def self.trimTimeZone( aDateTime )
    puts 'AAAAAAAAAAAAAAAAAAAA 0 ' + aDateTime.inspect
        t = aDateTime.to_s.dup
        t.delete_suffix!( ' UTC' )
        t.gsub!( / \+[0-8]+/, '' )
    puts 'AAAAAAAAAAAAAAAAAAAA 1 ' + t        
        return t
    end    
    
    #** generate_issue
    def generate_issue(now = Time.now)
        return unless project.try( :active? )
        # puts "AAAAAAAAAAAAAAAAAAAAAAAAAA " + inspect
        # Copy subject and description and replace variables
        subj = parse_macro( subject.try( :dup ), now )
        desc = parse_macro( description.try( :dup ), now )
        
        issue = Issue.new(:project_id => project_id, :tracker_id => tracker_id || project.trackers.first.try(:id), :category_id => issue_category_id,
                          :assigned_to_id => assigned_to_id, :author_id => author_id,
                          :subject => subj, :description => desc, :facility_id => facility_id )
                          
        issue.start_date ||= now.to_date if set_start_date?
        if due_date_number
            due_date = due_date_number
            due_date_units = due_date_units || 'day'
            issue.due_date = due_date.send(due_date_units.downcase).from_now
        end
        
        issue.estimated_hours = estimated_hours
        
        fill_checklists issue
        fill_custom_fields issue
        
        issue
    end

    #** filterFacilityByTrackerId
    def filterFacilityByTrackerId( aTrackerId )  
        # puts "LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL " + aTrackerId.to_s
        acl.filterFacilityByTrackerId( aTrackerId )  
    end
  
    # acl
    def acl
        RedmineDitKpi::Acl
    end
            
  private
  def parse_macro(str, now)
    if str.respond_to?(:gsub!) && str.present?
      str.gsub!('**DAY**', now.strftime("%d"))
      str.gsub!('**WEEK**', now.strftime("%W"))
      str.gsub!('**MONTH**', now.strftime("%m"))
      str.gsub!('**MONTHNAME**', I18n.localize(now, :format => "%B"))
      str.gsub!('**YEAR**', now.strftime("%Y"))
      str.gsub!('**PREVIOUS_MONTHNAME**', I18n.localize(now - 2592000, :format => "%B"))
      str.gsub!('**PREVIOUS_MONTH**', I18n.localize(now - 2592000, :format => "%m"))
    end
    str
  end

  def fill_checklists(issue)
    if checklists_template_id && Redmine::Plugin.all.any? {|p| p.id == :redmine_checklists} && Object.const_defined?('ChecklistTemplate')
      template = ChecklistTemplate.find(checklists_template_id)
      if template
        items = template.template_items.split("\n")
        checklists = items.each_with_index.map { |x, i| {
          :is_done => false,
          :subject => x,
          :position => i
        }}
        issue.checklists_attributes = checklists
      end
    end
  end

  def fill_custom_fields(issue)
    issue.custom_field_values = custom_field_values.to_unsafe_hash if custom_field_values.respond_to?(:to_unsafe_hash)
  end
  

end
