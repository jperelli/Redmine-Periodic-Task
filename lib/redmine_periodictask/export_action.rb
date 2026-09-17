module RedminePeriodictask
  # The "Export to ..." bulk actions shared by the project list and the
  # administration list: the checked rows (ids[]) of +scope+ are sent as a
  # download in the format named by params[:export] (a CalendarExport
  # FORMAT, iCalendar by default), in the current user's time zone. Without
  # a checked row that still exists in +scope+ the user is sent back to
  # +list_path+.
  module ExportAction
    private

    def send_export(scope, name, list_path)
      exporter = CalendarExport.for_format(params[:export].presence || IcalExport::FORMAT)
      return render_404 unless exporter

      ids = Array(params[:ids]).map(&:to_i).select(&:positive?).uniq
      tasks = scope.where(id: ids).preload(:project).sort_by { |task| ids.index(task.id) }
      if tasks.empty?
        flash[:error] = l(:error_periodictask_export_no_selection)
        return redirect_to list_path
      end

      zone = User.current.time_zone || Time.zone
      send_data exporter.export(tasks, zone: zone), type: exporter::CONTENT_TYPE, filename: exporter.filename(name)
    end
  end
end
