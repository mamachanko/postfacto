class RetrosController < ApplicationController
  before_action :load_retro_with_items, only: [:show]
  before_action :load_retro, :authenticate_retro
  before_action :authenticate_user, only: [:create, :index]
  before_action :authenticate_retro_admin, only: [:archive, :update]
  skip_before_action :load_retro, only: [:create, :index, :show]
  skip_before_action :authenticate_retro, only: [:create, :index, :show_login, :login]

  def create
    @retro = @user.retros.create(retro_params)
    if @retro.valid?
      @retro.create_instruction_cards! if first_retro_for @user
      render json: {
        retro: @retro.as_json(only: [:id, :name, :slug]),
        token: @retro.encrypted_password
      }, status: :created
    else
      render json: { errors: retro_errors_hash }, status: :unprocessable_entity
    end
  end

  def index
    render json: { retros: @user.retros }
  end

  def show_login
  end

  def login
    if password_matches?(retro_params.fetch(:password))
      render json: { token: @retro.encrypted_password }, status: :ok
    else
      render json: :no_content, status: :forbidden
    end
  end

  def update
    @retro.assign_attributes(retro_update_params.fetch(:retro))

    if @retro.save # TODO: no error handling
      broadcast_force_relogin if force_relogin_required?
      broadcast
      render json: { retro: @retro.as_json(only: [:id, :name, :slug, :is_private, :video_link]) }, status: :ok
    else
      render json: { errors: retro_errors_hash }, status: :unprocessable_entity
    end
  end

  def broadcast_force_relogin
    RetrosChannel.broadcast_force_relogin(@retro.reload, retro_update_params.fetch(:request_uuid))
  end

  def update_password
    if password_matches?(retro_update_password_params.fetch(:current_password))
      @retro.update!(password: retro_update_password_params.fetch(:new_password))
      RetrosChannel.broadcast_force_relogin(@retro.reload, retro_update_password_params.fetch(:request_uuid))
      render json: { token: @retro.encrypted_password }, status: :ok
    else
      render json: { errors: { 'current_password' => 'Sorry! That password does not match the current one.' } },
             status: :unprocessable_entity
    end
  end

  def archive
    RetroArchiveService.instance.call(@retro, Time.now, retro_archive_params.fetch(:send_archive_email, true))

    broadcast
    render 'show'
  end

  private

  def force_relogin_required?
    changes = @retro.previous_changes
    changed_to_private = [false, true]

    changes.key?(:is_private) && changes[:is_private] == changed_to_private
  end

  def retro_errors_hash
    errors_hash = @retro.errors.messages
    errors_hash.each { |k, v| errors_hash[k] = v.join(' ') }
    errors_hash
  end

  def password_matches?(value)
    @retro.validate_login?(value)
  end

  def authenticate_user
    @user = User.find_by_auth_token(request.headers['X-AUTH-TOKEN'])
    render json: :no_content, status: :unauthorized unless @user
  end

  def load_retro
    @retro = Retro.find_by_slug!(params.fetch(:id))
  end

  def broadcast
    RetrosChannel.broadcast(@retro)
  end

  def retro_params
    params.require(:retro).permit(:name, :slug, :password, :item_order, :is_private)
  end

  def retro_archive_params
    params.permit(:send_archive_email)
  end

  def retro_update_params
    params.permit({ retro: [:name, :slug, :is_private, :video_link] }, :request_uuid)
  end

  def retro_update_password_params
    params.permit(:id, :current_password, :new_password, :request_uuid)
  end

  def load_retro_with_items
    @retro = Retro.includes(:items, :action_items).find_by_slug!(params.fetch(:id))
  end

  def first_retro_for(user)
    user.retros.count == 1
  end
end