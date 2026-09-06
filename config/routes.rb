Rails.application.routes.draw do
  #  this is like "resources :periodictask" but it has been
  #  replaced put with match for action 'update', allowing both http-verb options 'put'
  #  and the new verb 'patch' for compatibility with Redmine 3 and below
  #
  #  The CRUD and run_now routes also accept a .json / .xml format for the REST
  #  API. The static segments (customfields, tags, new) are declared first so
  #  they never resolve as an :id.

  match    'projects/:project_id/periodictask/customfields', to: 'periodictask#customfields',
                                                             as: 'periodictask_customfields', via: %i[post patch]
  match    'projects/:project_id/periodictask/preview',      to: 'periodictask#preview',
                                                             as: 'periodictask_preview', via: %i[post patch]
  get      'projects/:project_id/periodictask/tags',       to: 'periodictask#tags',   as: 'periodictask_tags'
  get      'projects/:project_id/periodictask/new',        to: 'periodictask#new',    as: 'new_periodictask'
  get      'projects/:project_id/periodictask(.:format)',  to: 'periodictask#index',  as: 'periodictasks'
  post     'projects/:project_id/periodictask(.:format)',  to: 'periodictask#create'
  get      'projects/:project_id/periodictask/:id/edit',   to: 'periodictask#edit',   as: 'edit_periodictask'
  get      'projects/:project_id/periodictask/:id/copy',   to: 'periodictask#copy',   as: 'copy_periodictask'
  post     'projects/:project_id/periodictask/:id/run_now(.:format)', to: 'periodictask#run_now',
                                                                      as: 'run_now_periodictask'
  get      'projects/:project_id/periodictask/:id(.:format)', to: 'periodictask#show', as: 'periodictask'
  match    'projects/:project_id/periodictask/:id(.:format)', to: 'periodictask#update', via: %i[put patch]
  delete   'projects/:project_id/periodictask/:id(.:format)', to: 'periodictask#destroy'
end

# Cron-less trigger for external schedulers, protected by Redmine's sys API key
Rails.application.routes.draw do
  match 'periodictask/check', to: 'periodictask_sys#check', as: 'periodictask_check', via: %i[get post]
end

# Administration page listing every project's periodic tasks (also as .json /
# .xml), and the admin-only "Run checker now" button on the plugin settings page
Rails.application.routes.draw do
  get  'admin/periodictasks(.:format)',  to: 'periodictask_admin#index',       as: 'admin_periodictasks'
  post 'admin/periodictask/run_checker', to: 'periodictask_admin#run_checker', as: 'periodictask_run_checker'
end
