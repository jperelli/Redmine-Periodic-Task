class ScheduledTasksChecker
  def self.checktasks!
     Periodictask.all(:conditions=> ["next_run_date <= ? ", Time.now]).each do |task| 
       print "assigning #{task.subject}"
         issue = Issue.new(:project_id=>task.project_id,  :tracker_id=>task.tracker_id, :assigned_to_id=>task.assigned_to_id, :author_id=>task.author_id, :subject=>task.subject);
         issue.save         
         interval = task.interval_number
         units = task.interval_units
         task.next_run_date =  interval.send(units.downcase).from_now
         task.save
     end
  end
end
