module RedminePeriodictask
  # The "Export to ics" bulk action shared by the project list and the
  # administration list: the checked rows (ids[]) of +scope+ are sent as an
  # iCalendar download, in the current user's time zone. Without a checked
  # row that still exists in +scope+ the user is sent back to +list_path+.
  module IcalExportAction
    private

    def send_ical(scope, name, list_path)
      ids = Array(params[:ids]).map(&:to_i).select(&:positive?).uniq
      tasks = scope.where(id: ids).preload(:project).sort_by { |task| ids.index(task.id) }
      if tasks.empty?
        flash[:error] = l(:error_periodictask_export_no_selection)
        return redirect_to list_path
      end

      zone = User.current.time_zone || Time.zone
      send_data IcalExport.export(tasks, zone: zone),
                type: 'text/calendar; charset=utf-8', filename: "periodictasks-#{name}.ics"
    end
  end
end
