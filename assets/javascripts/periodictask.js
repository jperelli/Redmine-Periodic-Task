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

/* Import menu: each entry of the "Import" drop-down is a format and opens
   the file picker limited to it; the file is uploaded as that format. Only
   the file input of the chosen format is enabled, so only it is posted. */
$(document).on('click', '.periodictask-import-format', function(event) {
  event.preventDefault();
  var source = $(this).data('source');
  var form = $(this).closest('form');
  form.find('#periodictask-import-source').val(source);
  form.find('input.periodictask-import-file').each(function() {
    $(this).prop('disabled', $(this).data('source') !== source).val('');
  });
  form.find('.periodictask-import-chosen').text('');
  form.find('input[type=submit]').prop('disabled', true);
  $(this).closest('.drdn').removeClass('expanded');
  form.find('#periodictask-import-file-' + source)[0].click();
});
$(document).on('change', '.periodictask-import-upload input.periodictask-import-file', function() {
  var form = $(this).closest('form');
  var file = this.files[0];
  var format = form.find('.periodictask-import-format[data-source="' + $(this).data('source') + '"]').text();
  form.find('.periodictask-import-chosen').text(file ? file.name + ' (' + format + ')' : '');
  form.find('input[type=submit]').prop('disabled', !file);
});
