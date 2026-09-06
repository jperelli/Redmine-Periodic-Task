module RedminePeriodictask
  # Optional "Periodic task" column of the issue list: the task that generated
  # the issue, or blank. Sorting and grouping use correlated subqueries on the
  # periodictask_issues join table so the base issue query is never multiplied.
  class PeriodictaskQueryColumn < QueryColumn
    def initialize
      super(:periodictask,
            sortable: [self.class.subject_sql, self.class.id_sql],
            groupable: true,
            caption: :field_periodictask)
    end

    def group_by_statement
      self.class.id_sql
    end

    def self.id_sql
      links = PeriodictaskIssue.table_name
      "(SELECT MAX(#{links}.periodictask_id) FROM #{links} WHERE #{links}.issue_id = #{Issue.table_name}.id)"
    end

    def self.subject_sql
      links = PeriodictaskIssue.table_name
      tasks = Periodictask.table_name
      "(SELECT MAX(#{tasks}.subject) FROM #{tasks} " \
        "INNER JOIN #{links} ON #{links}.periodictask_id = #{tasks}.id " \
        "WHERE #{links}.issue_id = #{Issue.table_name}.id)"
    end
  end
end
