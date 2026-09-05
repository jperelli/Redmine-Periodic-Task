Rails.application.routes.draw do
  #  this is like "resources :periodictask" but it has been
  #  replaced put with match for action 'update', allowing both http-verb options 'put'
  #  and the new verb 'patch' for compatibility with Redmine 3 and below

  match    'projects/:project_id/periodictask/customfields', to: 'periodictask#customfields',
                                                             as: 'periodictask_customfields', via: %i[post patch]
  get      'projects/:project_id/periodictask/tags',       to: 'periodictask#tags',   as: 'periodictask_tags'
  get      'projects/:project_id/periodictask',            to: 'periodictask#index',  as: 'periodictasks'
  get      'projects/:project_id/periodictask/new',        to: 'periodictask#new',    as: 'new_periodictask'
  post     'projects/:project_id/periodictask',            to: 'periodictask#create'
  get      'projects/:project_id/periodictask/:id',        to: 'periodictask#show',   as: 'periodictask'
  get      'projects/:project_id/periodictask/:id/edit',   to: 'periodictask#edit',   as: 'edit_periodictask'
  post     'projects/:project_id/periodictask/:id/run_now', to: 'periodictask#run_now', as: 'run_now_periodictask'
  match    'projects/:project_id/periodictask/:id',        to: 'periodictask#update', via: %i[put patch]
  delete   'projects/:project_id/periodictask/:id',        to: 'periodictask#destroy'
end

# Cron-less trigger for external schedulers, protected by Redmine's sys API key
Rails.application.routes.draw do
  match 'periodictask/check', to: 'periodictask_sys#check', as: 'periodictask_check', via: %i[get post]
end

# Admin-only "Run checker now" button on the plugin settings page
Rails.application.routes.draw do
  post 'admin/periodictask/run_checker', to: 'periodictask_admin#run_checker', as: 'periodictask_run_checker'
end
