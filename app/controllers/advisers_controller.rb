class AdvisersController < ApplicationController
  layout 'general_layout'

  def index
    not check_access(true, true) and return
    @advisers = Adviser.all
    respond_to do |format|
      format.html {render layout: 'admins'}
      format.csv {send_data Adviser.to_csv}
    end
  end

  def new
    not check_access(true, true) and return
    @adviser = Adviser.new
    render layout: 'admins', locals: {
                             users: User.all,
                             user: User.new
                           }
  end

  def create
    # create separate render template for create and use_existing
    not check_access(true, true) and return
    user_params = get_user_params
    user = User.new(user_params)
    if user.save
      create_adviser_for_user_and_respond(user)
    else
      render_new_template(user)
    end
  end

  def use_existing
    not check_access(true, true) and return
    user = User.find(params[:adviser][:user_id])
    if user
      create_adviser_for_user_and_respond(user)
    else
      render_new_template(user)
    end
  end

  def show
    @adviser = Adviser.find(params[:id])
    display_adviser_access_control_strategy = lambda {
      if @adviser.user_id == current_user.id
        return true
      else
        return false
      end
    }
    not check_access(true, false, display_adviser_access_control_strategy) and return
    milestones, teams_submissions, own_evaluations = get_data_for_adviser
    render locals: {
             milestones: milestones,
             teams_submissions: teams_submissions,
             own_evaluations: own_evaluations
           }
  end

  def edit
    not check_access(true, true) and return
    @adviser = Adviser.find(params[:id])
    render layout: get_layout_for_role
  end

  def update
    not check_access(true, true) and return
    @adviser = Adviser.find(params[:id])
    if update_user
      if admin?
        redirect_to advisers_path
      else
        redirect_to @adviser
      end
    else
      render layout: get_layout_for_role, template: 'advisers/edit'
    end
  end

  def destroy
    not check_access(true, true) and return
    @adviser = Adviser.find(params[:id])
    @adviser.destroy
    redirect_to advisers_path
  end

  def get_page_title
    @page_title = @page_title || 'Advisers | Orbital'
    super
  end

  private
    def get_user_params
      user_param = params.require(:user).permit(:user_name, :email, :uid, :provider)
    end

    def create_adviser_for_user_and_respond(user)
      @adviser = Adviser.new(user_id: user.id)
      if @adviser.save
        redirect_to advisers_path
      else
        render_new_template(nil)
      end
    end

    def update_user
      user = @adviser.user
      user_param = get_user_params
      user_param[:uid] = user.uid
      user_param[:provider] = user.provider
      user.update(user_param) ? user : nil
    end

    def get_data_for_adviser
      milestones = Milestone.all
      teams_submissions = {}
      own_evaluations = {}
      milestones.each do |milestone|
        teams_submissions[milestone.id] = {}
        own_evaluations[milestone.id] = {}
        @adviser.teams.each do |team|
          team_sub = Submission.find_by(milestone_id: milestone.id,
                                        team_id: team.id)
          teams_submissions[milestone.id][team.id] = team_sub
          if team_sub
            own_evaluations[milestone.id][team.id] =
              PeerEvaluation.find_by(submission_id: team_sub.id,
                                     adviser_id: @adviser.id)
          end
        end
      end
      return milestones, teams_submissions, own_evaluations
    end

    def render_new_template(user)
      render layout: 'admins', template: 'advisers/new', locals: {
                    users: User.all,
                    user: user || User.new
                  }
    end
end
