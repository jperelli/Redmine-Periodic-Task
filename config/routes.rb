Rails.application.routes.draw do

#  resources :periodictask
#  es igual a las siguientes rutas
# periodictask_index GET      /periodictask(.:format)            periodictask#index
#                    POST     /periodictask(.:format)            periodictask#create
#   new_periodictask GET      /periodictask/new(.:format)        periodictask#new
#  edit_periodictask GET      /periodictask/:id/edit(.:format)   periodictask#edit
#       periodictask GET      /periodictask/:id(.:format)        periodictask#show
#                    PUT      /periodictask/:id(.:format)        periodictask#update
#                    DELETE   /periodictask/:id(.:format)        periodictask#destroy


  get    'projects/:project_id/periodictask',             :to => 'periodictask#index', :as => 'periodictasks'
  post   'projects/:project_id/periodictask',             :to => 'periodictask#create'
  get    'projects/:project_id/periodictask/new',         :to => 'periodictask#new',   :as => 'new_periodictask'
  get    'projects/:project_id/periodictask/:id/edit',    :to => 'periodictask#edit',  :as => 'edit_periodictask'
  get    'projects/:project_id/periodictask/:id',         :to => 'periodictask#show',  :as => 'periodictask'
  put    'projects/:project_id/periodictask/:id',         :to => 'periodictask#update'
  post   'projects/:project_id/periodictask/:id',         :to => 'periodictask#destroy'
end
