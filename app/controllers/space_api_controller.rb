class SpaceApiController < ApplicationController
  # Individually remove authorizing stuff since there is no SpaceApi model
  authorize_resource :except => [:index, :access, :access_post]
  # User auth here happens via params, instead of form.
  before_filter :authenticate_user!, :except => [:index, :access, :access_post]

  def index
    @json = JSON.parse(Setting.space_api_json_template)
    door_status = DoorLog.show_status # Expect {:unlocked => boolean, :door_1_locked => boolean, :door_2_locked => boolean}

    @json["open"] = door_status[:unlocked]
    
    if( door_status[:unlocked] )
      @json["status"] = "doors_open=both"
    elsif( !door_status[:door_1_locked] )
      @json["status"] = "doors_open=door1"
    elsif( !door_status[:door_2_locked] )
      @json["status"] = "doors_open=door2"
    else
      @json["status"] = "doors_open=none"
    end

    respond_to do |format|
      format.html
      format.json { 
        response.headers["Cache-Control"] = "no-cache, no-store, max-age=0, must-revalidate"
        render :json => @json
      }
    end
  end

  def access
    @status = DoorLog.show_status

    # Nothing, just render form
    unless user_signed_in?
      @output =  "Invalid email or password. Please login with your Members DB email and password below."
    else
      unless can? :access_doors_remotely, :door_access
        @output =  "Sorry, your account isn't able to control doors remotely."
      end
    end
  end

  def access_post
    @output = ""

    #if params['cmd'] == "check-login" then
    #  if users[params['user']] && users[params['user']]['pass'].to_s == (Digest::SHA2.new(bitlen=512) << params['pass']).to_s then
    #    @output +=  '{ "login": "okay" }'
    #  else
    #    @output +=  '{ "login": "fail" }'
    #  end
    # 
    #  exit
    #end
    
    # Stop unless signed in already, OR if the supplied user/pass params are good.
    unless current_user || check_auth(params['user'],params['pass'])
      @output +=  "Invalid email or password."
    else
      # Stop unless the user can access the door system
      unless can? :access_doors_remotely, :door_access
        @output += "Sorry, your account isn't able to control doors remotely. Ask an admin if this is incorrect."
        Rails.logger.warn "----------\r\nWARNING: DOOR ACCESS ATTEMPT DENIED. USER #{current_user.inspect}\r\n----------"
      else
        # Stop unless we've got a command to run
        unless params['cmd']
          @output += "No command specified."
        else 
          # Log the access
          Rails.logger.info "Door access: user #{current_user.inspect}"
          DoorLog.create!({:key => "rem_"+DoorLog.parse_command(params['cmd'])[:url_param], :data => current_user.id})

          # Execute the access
          @output += DoorLog.execute_command(params['cmd'])
        end 
      end
    end

    # Render the form again
    render :access
  end

  def check_auth(email,password)
    resource = User.find_by_email(email)
    if resource && resource.valid_password?(password)
      resource.remember_me = true
      sign_in :user, resource
      return true
    else
      return false
    end
  end

end