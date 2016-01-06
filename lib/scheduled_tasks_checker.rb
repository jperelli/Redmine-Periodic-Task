class ScheduledTasksChecker
  def self.checktasks!
    Periodictask.where("next_run_date <= ? ", Time.now).each do |task| 

      # replace variables (set locale from shell)
      I18n.locale = ENV['LOCALE'] || I18n.default_locale

      # Copy subject and description and replace variables
      subject = task.subject.dup
      description = task.description.dup
      subject.gsub!('**WEEK**', Time.now.strftime("%W"))
      subject.gsub!('**MONTH**', Time.now.strftime("%m"))
      subject.gsub!('**MONTHNAME**', I18n.localize(Time.now, :format => "%B"))
      subject.gsub!('**YEAR**', Time.now.strftime("%Y"))
      subject.gsub!('**PREVIOUS_MONTHNAME**', I18n.localize(Time.now - 2592000, :format => "%B"))
      description.gsub!('**WEEK**', Time.now.strftime("%W"))
      description.gsub!('**MONTH**', Time.now.strftime("%m"))
      description.gsub!('**MONTHNAME**', I18n.localize(Time.now, :format => "%B"))
      description.gsub!('**YEAR**', Time.now.strftime("%Y"))
      description.gsub!('**PREVIOUS_MONTHNAME**', I18n.localize(Time.now - 2592000, :format => "%B"))

      print "assigning #{subject}\n"
      issue = Issue.new(:project_id=>task.project_id,  :tracker_id=>task.tracker_id, :category_id=>task.issue_category_id, :assigned_to_id=>task.assigned_to_id, :author_id=>task.author_id, :subject=>subject, :description=>description);
      issue.start_date ||= Date.today if task.set_start_date?
      if task.due_date_number
        due_date = task.due_date_number
        due_date_units = task.due_date_units
        issue.due_date = due_date.send(due_date_units.downcase).from_now
      end
      issue.save
      interval = task.interval_number
      units = task.interval_units
      interval_steps = ((Time.now - task.next_run_date) / interval.send(units.downcase)).ceil
      task.next_run_date += (interval * interval_steps).send(units.downcase)
      task.save
    end
  end
end
