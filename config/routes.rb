SolidAgent::Engine.routes.draw do
  root 'dashboard#index'

  resources :traces, only: %i[index show] do
    resources :spans, only: %i[show], controller: 'spans'
  end

  resources :conversations, only: %i[index show]

  resources :agents, only: %i[index]
  resources :tools, only: %i[index]

  get 'mcp', to: 'mcp#index', as: :mcp_status
end
