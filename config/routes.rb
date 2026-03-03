Rails.application.routes.draw do
  devise_for :users

  get "up" => "rails/health#show", as: :rails_health_check

  root "conversations#index"
  resources :conversations, only: [ :index, :show, :create, :destroy ] do
    resources :messages, only: [ :create ]
  end
end
