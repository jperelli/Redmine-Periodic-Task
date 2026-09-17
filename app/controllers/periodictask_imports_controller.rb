# Import of recurring items from a calendar file (iCalendar or JSCalendar,
# see RedminePeriodictask::CalendarImport) as periodic tasks. Items are
# staged on upload and listed in a triage table where an administrator
# picks the project of each; "create" turns the rows with a project into
# periodic tasks and leaves the others staged for later. Administrators
# only: staged rows span projects.
class PeriodictaskImportsController < ApplicationController
  layout 'admin'
  self.main_menu = false

  before_action :require_admin
  before_action :find_import, only: :destroy

  helper :periodictask
  helper :projects

  MAX_FILE_SIZE = 5.megabytes

  def index
    @imports = PeriodictaskImport.sorted.preload(:project).to_a
    @projects = PeriodictaskImport.target_projects.to_a
  end

  # Parses the uploaded file as the format chosen in the import menu
  # (params[:source]) and stages its recurring items.
  def create
    importer = RedminePeriodictask::CalendarImport.for_source(params[:source])
    unless importer
      flash[:error] = l(:error_periodictask_import_no_format)
      return redirect_to periodictask_imports_path
    end
    file = params[:file]
    unless file.respond_to?(:read)
      flash[:error] = l(:error_periodictask_import_no_file)
      return redirect_to periodictask_imports_path
    end
    if file.size.to_i > MAX_FILE_SIZE
      flash[:error] = l(:error_periodictask_import_file_too_large, size: helpers.number_to_human_size(MAX_FILE_SIZE))
      return redirect_to periodictask_imports_path
    end

    text = file.read.to_s.force_encoding('UTF-8').scrub
    result = importer.parse(text, zone: User.current.time_zone)
    staged = PeriodictaskImport.stage(result.items, source: importer::SOURCE, user: User.current)
    flash[:notice] = upload_notice(result, staged)
    redirect_to periodictask_imports_path
  rescue RedminePeriodictask::CalendarImport::InvalidFile
    flash[:error] = l(:error_periodictask_import_invalid_file,
                      format_name: l(:"label_periodictask_import_format_#{importer::SOURCE}"))
    redirect_to periodictask_imports_path
  end

  # Creates a periodic task for every staged row a project was chosen for
  # (params[:project_ids] maps row id to project id); the rest stay staged.
  def import
    chosen = (params[:project_ids] || {}).to_unsafe_h.select { |_id, project_id| project_id.present? }
    imports = PeriodictaskImport.where(id: chosen.keys).sorted.to_a
    if imports.empty?
      flash[:warning] = l(:notice_periodictask_import_nothing_selected)
      return redirect_to periodictask_imports_path
    end

    projects = Project.where(id: chosen.values.uniq).index_by { |project| project.id.to_s }
    created = imports.count do |import|
      import.import(projects[chosen[import.id.to_s]], User.current).present?
    end
    failed = imports.size - created
    flash[:notice] = l(:notice_periodictask_import_created, count: created) if created.positive?
    flash[:error] = l(:error_periodictask_import_failed, count: failed) if failed.positive?
    redirect_to periodictask_imports_path
  end

  def destroy
    @import.destroy
    flash[:notice] = l(:notice_periodictask_import_discarded)
    redirect_to periodictask_imports_path
  end

  private

  def find_import
    @import = PeriodictaskImport.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def upload_notice(result, staged)
    parts = [l(:notice_periodictask_import_staged, count: staged)]
    duplicates = result.items.size - staged
    parts << l(:notice_periodictask_import_already_staged, count: duplicates) if duplicates.positive?
    parts << l(:notice_periodictask_import_not_recurring, count: result.not_recurring) if result.not_recurring.positive?
    if result.unsupported.any?
      parts << l(:notice_periodictask_import_unsupported, count: result.unsupported.size,
                                                          subjects: result.unsupported.join(', '))
    end
    if result.ended.any?
      parts << l(:notice_periodictask_import_ended, count: result.ended.size, subjects: result.ended.join(', '))
    end
    parts.join(' ')
  end
end
