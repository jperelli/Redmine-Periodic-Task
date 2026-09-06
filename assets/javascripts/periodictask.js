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
