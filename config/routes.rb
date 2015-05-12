Rails.application.routes.draw do
#  resources :periodictask
#  es igual a las siguientes rutas

#  periodictask_index GET      /periodictask(.:format)            periodictask#index#                    POST     /periodictask(.:format)            periodictask#create
#  new_periodictask   GET      /periodictask/new(.:format)        periodictask#new
#  edit_periodictask  GET      /periodictask/:id/edit(.:format)   periodictask#edit
#       periodictask  GET      /periodictask/:id(.:format)        periodictask#show
#                     PUT      /periodictask/:id(.:format)        periodictask#update
#                     DELETE   /periodictask/:id(.:format)        periodictask#destroy
  
#  replaced put with match for action 'update', allowing both http-verb options 'put' 
#  and the new verb 'patch' for compatibility with Redmine 3 and below
  
  get      'projects/:project_id/periodictask',            :to => 'periodictask#index',  :as => 'periodictasks'
  get      'projects/:project_id/periodictask/new',        :to => 'periodictask#new',    :as => 'new_periodictask'
  post     'projects/:project_id/periodictask',            :to => 'periodictask#create'
  get      'projects/:project_id/periodictask/:id',        :to => 'periodictask#show',   :as => 'periodictask'
  get      'projects/:project_id/periodictask/:id/edit',   :to => 'periodictask#edit',   :as => 'edit_periodictask'
  match    'projects/:project_id/periodictask/:id',        :to => 'periodictask#update', :via => [:put, :patch]
  delete   'projects/:project_id/periodictask/:id',        :to => 'periodictask#destroy'
  
end
