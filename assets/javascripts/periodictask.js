/* Next occurrences: the chevron link shows and hides the month grids.
   Delegated, since the form replaces the block on every live preview. */
$(document).on('click', '.periodictask-calendar-toggle', function(event) {
  event.preventDefault();
  var link = $(this);
  var calendar = link.closest('.periodictask-upcoming-runs').find('.periodictask-calendar');
  var expanded = !calendar.is(':visible');
  calendar.toggle(expanded);
  link.attr('aria-expanded', expanded);
  link.toggleClass('icon-expanded', expanded).toggleClass('icon-collapsed', !expanded);
  if (typeof updateSVGIcon === 'function') {
    updateSVGIcon(link[0], expanded ? 'angle-down' : 'angle-right');
    link.find('svg').toggleClass('icon-rtl', !expanded);
  }
});

/* Calendar import: the toolbar select fills the project of every staged row
   that has none yet. */
$(document).on('change', '.periodictask-import-fill', function() {
  var projectId = $(this).val();
  if (projectId === '') { return; }
  $('#periodictask-import-form select.periodictask-import-project').each(function() {
    if ($(this).val() === '') { $(this).val(projectId); }
  });
  $(this).val('');
});
