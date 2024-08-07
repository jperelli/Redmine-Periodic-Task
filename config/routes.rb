Rails.application.routes.draw do
#  this is like "resources :periodictask" but it has been
#  replaced put with match for action 'update', allowing both http-verb options 'put' 
#  and the new verb 'patch' for compatibility with Redmine 3 and below
  
  match    'projects/:project_id/periodictask/customfields', :to => 'periodictask#customfields', :as => 'periodictask_customfields', :via => [:post, :patch]
  match    'projects/:project_id/periodictask/facility', :to => 'periodictask#facility', :as => 'periodictask_facility', :via => [:post, :patch]
  
  get      'projects/:project_id/periodictask',            :to => 'periodictask#index',  :as => 'periodictasks'
  get      'projects/:project_id/periodictask/new',        :to => 'periodictask#new',    :as => 'new_periodictask'
  post     'projects/:project_id/periodictask',            :to => 'periodictask#create'
  get      'projects/:project_id/periodictask/:id',        :to => 'periodictask#show',   :as => 'periodictask'
  get      'projects/:project_id/periodictask/:id/edit',   :to => 'periodictask#edit',   :as => 'edit_periodictask'
  match    'projects/:project_id/periodictask/:id',        :to => 'periodictask#update', :via => [:put, :patch]
  delete   'projects/:project_id/periodictask/:id',        :to => 'periodictask#destroy'
  
end
