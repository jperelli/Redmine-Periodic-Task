class ScheduledTasksChecker
    def self.checktasks!
        I18n.locale = ENV[ 'LOCALE' ] || I18n.default_locale
        puts Periodictask.INTERVAL_UNITS.inspect;
        
        now = Time.now
        Periodictask.where( "next_run_date <= ? ", now ).each do |task|

            # replace variables (set locale from shell)
            I18n.locale = ENV[ 'LOCALE' ] || I18n.default_locale
     
            issue = task.generate_issue( now )
            if issue
                begin
                    issue.save!
                    task.last_error = nil
                rescue ActiveRecord::RecordInvalid => e
                    Rails.logger.error "ScheduledTasksChecker: #{e.message}"
                    task.last_error = e.message
                end
                
                interval = task.interval_number
                units = task.interval_units.downcase
                #puts task.inspect
                
                if units == "business_day"
                
                    # puts "AA 1 " + BusinessTime::Config.default_config.inspect
                    c = BusinessTime::Config.default_config.clone
                    
                    BusinessTime::Config.beginning_of_workday = Time.parse( '0:0:0' )
                    BusinessTime::Config.end_of_workday = Time.parse( '23:59:0' )
                    
                    task.next_run_date = task.interval_number.business_day.after( task.next_run_date )
                else
                    interval_steps = ( ( now - task.next_run_date ) / interval.send( units ) ).ceil
                    task.next_run_date += ( interval * interval_steps ).send( units )
                end
                
                puts 'NEXT RUN DATE: ' + task.next_run_date.inspect
            else
                msg = "Project is missing or closed"
                Rails.logger.error "ScheduledTasksChecker: #{msg}"
                task.last_error = msg
            end
            
            task.save
        end
    end
end
