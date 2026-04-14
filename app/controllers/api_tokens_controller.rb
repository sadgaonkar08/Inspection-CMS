class ApiTokensController < ApplicationController
  before_action :authenticate_user!

  def create
    token = current_user.generate_api_token!
    render json: { token: token, email: current_user.email }
  end
end
