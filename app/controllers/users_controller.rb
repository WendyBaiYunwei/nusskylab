# UsersController: manage actions related to user  
class UsersController < ApplicationController

  def index
    !authenticate_user(true, true) && return
    @page_title = t('.page_title')
    @users = User.order(:user_name).all
  end

  def new
    !authenticate_user(true, true) && return
    @page_title = t('.page_title')
    @user = User.new
  end

  def create
    !authenticate_user(true, true) && return
    user_ps = user_params(true)
    @user = User.new(user_ps)
    if @user.save
      UserMailer.welcome_email(@user, user_ps[:password]).deliver_now
      redirect_to users_path, flash: {
        success: t('.success_message')
      }
    else
      redirect_to new_user_path, flash: {
        danger: t('.failure_message',
                  error_message: @user.errors.full_messages.join(', '))
      }
    end
  end

  def preview_as
    !authenticate_user(true, true) && return
    user = User.find(params[:id]) || (record_not_found && return)
    sign_out(current_user)
    sign_in(user)
    redirect_to user_path(user.id)
  end

  def register_as_student
    @user = User.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false, [@user]) && return
    milestone = Milestone.find_by(name: 'Milestone 1', cohort: current_cohort)
    survey_template = SurveyTemplate.find_by(
      milestone_id: milestone.id,
      survey_type: SurveyTemplate.survey_types[:survey_type_registration])
    registration = Registration.find_by(
      survey_template_id: survey_template.id, user_id: @user.id) ||
                   Registration.new(survey_template_id: survey_template.id,
                                    user_id: @user.id)
    @page_title = t('.page_title')
    render locals: {
      survey_template: survey_template,
      questions: survey_template.questions.order('questions.order ASC'),
      registration: registration
    }
  end

  def register
    @user = User.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false, [@user]) && return
    milestone = Milestone.find_by(name: 'Milestone 1', cohort: current_cohort)
    survey_template = SurveyTemplate.find_by(
      milestone_id: milestone.id,
      survey_type: SurveyTemplate.survey_types[:survey_type_registration])
    registration = Registration.find_by(
      survey_template_id: survey_template.id, user_id: @user.id) ||
                   Registration.new(survey_template_id: survey_template.id,
                                    user_id: @user.id)
    registration.response_content = registration_params.to_json
    registration.save
    student = Student.student?(@user.id, cohort: current_cohort) ||
              Student.new(user_id: @user.id, cohort: current_cohort,
                          application_status: 'a')
    student.save
    redirect_to user_path(@user.id)
  end

  def register_as_team
    @user = User.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false, [@user]) && return
    student = Student.student?(@user.id, cohort: current_cohort)
    return redirect_to user_path(@user.id), flash: {
      danger: t('.register_as_student_message')
    } unless student
    student_team = student.team || Team.new
    @page_title = t('.page_title')
    render locals: {
      student: student,
      student_team: student_team
    }
  end

  def register_team
    @user = User.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false, [@user]) && return
    team_params = params.require(:team).permit(:email)
    invited_user = User.find_by(email: team_params[:email])
    return redirect_to user_path(@user.id), flash: {
      danger: t('.no_user_found_message')
    } unless invited_user
    return redirect_to user_path(@user.id), flash: {
      danger: t('.cannot_invite_self_message')
    } if invited_user.id == @user.id
    invited_student = Student.student?(invited_user.id, cohort: current_cohort)
    return redirect_to user_path(@user.id), flash: {
      danger: t('.no_registered_student_found_message')
    } if !invited_student
    # return redirect_to user_path(@user.id), flash: {
    #   danger: t('.student_invited_by_others')
    # } if invited_student.team_id
    return redirect_to user_path(@user.id), flash: {
      danger: t('.student_found_team_message')
    } if invited_student.team
    invitor_student = Student.student?(@user.id, cohort: current_cohort)
    return redirect_to user_path(@user.id), flash: {
      danger: t('.cannot_register_team_message')
    } if !invitor_student || invitor_student.team
    team = Team.new(
      # team_name: ("I am team temp"), application_status: 'a',
      # to-do: fix
      team_name: ("I am team #{Team.order('id').last.id + 1}"), application_status: 'a',
      cohort: current_cohort, invitor_student_id: invitor_student.id,
      project_level: Team.get_project_level_from_raw("Project Gemini"))
    team.save
    invited_student.team_id = team.id
    invited_student.save
    invitor_student.team_id = team.id
    invitor_student.save
    redirect_to user_path(@user.id), flash: {
      success: t('.team_invitation_success_message')
    }
  end

  def submit_proposal
    @user = User.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false, [@user]) && return
    student = Student.student?(@user.id, cohort: current_cohort)
    return redirect_to user_path(@user.id), flash: {
      danger: t('.register_as_student_message') #to-do
    } unless student
    student_team = student.team
    # @page_title = t('.page_title') # to-do: what's this?
    # team_params = params.require(:team).permit(:proposal_link)
    render locals: {
      student_team: student_team
    }
  end

  def upload_proposal
    # authenticate (to-do: why?)
    @user = User.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false, [@user]) && return
    student = Student.student?(@user.id, cohort: current_cohort)
    return redirect_to user_path(@user.id), flash: {
      danger: t('.register_as_student_message') #to-do
    } unless student
    team_id = student.team.id
    # update the teams
    team = Team.find(team_id)
    team.update_attributes(application_params)
    team.application_status = 'c'
    team.save
    # redirect to-do: en.yml, stay on the previous page
    flash_message = 'proposal link submitted successfully'
    redirect_to user_path(@user.id), flash: {
      success: flash_message
    }
    #to-do: error conditions
  end

  def withdraw_invitation
    @user = User.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false, [@user]) && return
    student = Student.student?(@user.id, cohort: current_cohort)
    student_team = student.team
    if !student_team
      msg = 'Your invitation has already been rejected.'
      redirect_to user_path(@user.id), flash: {
        success: msg
      }
    end
    @page_title = t('.page_title')
    render locals: {
      student_team: student_team
    }
  end

  def confirm_withdraw
    @user = User.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false, [@user]) && return
    team_params = params.require(:team).permit(:withdraw)
    student_user = Student.student?(@user.id, cohort: current_cohort)
    return redirect_to user_path(@user.id), flash: {
      danger: t('.cannot_withdraw_invitation_message')
    } if !student_user || !student_user.team
    team = student_user.team
    if team_params[:withdraw] == 'false'
      flash_message = t('.withdrawal_cancelled_message')
    else
      team.destroy
      flash_message = t('.invitation_withdrawn_message')
    end
    redirect_to user_path(@user.id), flash: {
      success: flash_message
    }
  end

  def remove_proposal
    @user = User.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false, [@user]) && return
    student = Student.student?(@user.id, cohort: current_cohort)
    student_team = student.team
    @page_title = t('.page_title')
    render locals: {
      student_team: student_team
    }
  end

  #to-do: link and proposal (wording)
  def confirm_remove_proposal
    @user = User.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false, [@user]) && return
    team_params = params.require(:team).permit(:remove_link)
    student_user = Student.student?(@user.id, cohort: current_cohort)
    #to-do
    return redirect_to user_path(@user.id), flash: {
      danger: t('.cannot_withdraw_invitation_message')
    } if !student_user || !student_user.team
    team = student_user.team
    if team_params[:remove_link] == 'false'
      flash_message = "Removal of proposal cancelled"
    else
      team.update_attribute(:proposal_link, nil)
      flash_message = "Removal of proposal successful"
    end
    redirect_to user_path(@user.id), flash: {
      success: flash_message
    }
  end

  def confirm_team
    @user = User.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false, [@user]) && return
    team_params = params.require(:team).permit(:confirm)
    student_user = Student.student?(@user.id, cohort: current_cohort)
    return redirect_to user_path(@user.id), flash: {
      danger: t('.cannot_confirm_team_message')
    } if !student_user || !student_user.team
    team = student_user.team
    if team_params[:confirm] == 'true'
      team.update_attribute(:application_status, 'b')
      team.save
      flash_message = t('.team_invitation_accepted_message')
    else
      team.destroy
      flash_message = t('.team_invitation_rejected_message')
    end
    redirect_to user_path(@user.id), flash: {
      success: flash_message
    }
  end

  def do_evaluation
    @user = User.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false, [@user]) && return
    student = Student.student?(@user.id, cohort: current_cohort)
    evaluatee_links = []
    evaluatee_ids = student.evaluatee_ids
    evaluatee_ids.each do |id|
      evaluatee = Team.find_by(id: id)
      evaluatee_link = evaluatee.proposal_link
      evaluatee_links << evaluatee_link
    end
    @page_title = t('.page_title')
    render locals:{
      links: evaluatee_links
    }
  end

  def show
    @user = User.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false, [@user]) && return
    @page_title = t('.page_title', user_name: @user.user_name)
    form_team_ddl = ApplicationDeadlines.find_by(name: 'form team deadline').submission_deadline
    submit_proposal_ddl = ApplicationDeadlines.find_by(name: 'submit proposal deadline').submission_deadline
    peer_evaluation_open_date = ApplicationDeadlines.find_by(name: 'peer evaluation open date').submission_deadline
    peer_evaluation_ddl = ApplicationDeadlines.find_by(name: 'peer evaluation deadline').submission_deadline
    result_release_date = ApplicationDeadlines.find_by(name: 'result release date').submission_deadline
    portal_open_date = ApplicationDeadlines.find_by(name: 'portal open date').submission_deadline
    render locals:{
      form_team_ddl: form_team_ddl,
      submit_proposal_ddl: submit_proposal_ddl,
      peer_evaluation_open_date: peer_evaluation_open_date,
      peer_evaluation_ddl: peer_evaluation_ddl,
      result_release_date: result_release_date,
      portal_open_date: portal_open_date
    }
  end

  def edit
    @user = User.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false, [@user]) && return
    @page_title = t('.page_title', user_name: @user.user_name)
  end

  def update
    @user = User.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false, [@user]) && return
    user_ps = user_params
    user_ps.except!(:provider)
    if @user.update(user_ps)
      redirect_to @user, flash: {
        success: t('.success_message')
      }
    else
      redirect_to @user, flash: {
        danger: t('.failure_message',
                  error_message: @user.errors.full_messages.join(', '))
      }
    end
  end

  def destroy
    !authenticate_user(true, true) && return
    @user = User.find(params[:id])
    @user.destroy
    redirect_to users_path, flash: {
      success: t('.success_message')
    }
  end

  private

  def user_params(generate_pswd = false)
    user_ps = params.require(:user).permit(
      :user_name, :email, :uid, :provider, :slack_id, :github_link, :linkedin_link,
      :blog_link, :program_of_study, :matric_number, :self_introduction)
    user_ps[:password] = Devise.friendly_token.first(8) if generate_pswd
    user_ps[:provider] = user_ps[:provider].to_i
    user_ps[:program_of_study] = user_ps[:program_of_study].to_i
    unless(user_ps[:matric_number].blank?)
      user_ps[:matric_number] = calculate_matric_number(user_ps[:matric_number])
    end
    user_ps
  end
 
  def calculate_matric_number(num)
  matric_regex = /^A\d{7}|U\d{6,7}/

  if (num.present? && matric_regex.match(num.upcase))
  matches = matric_regex.match(num.upcase)
  match = matches[0]

    if (match[0].eql?('U') && match.length === 8)
      match = match[0, 3] + match[4]
    end

    weights = {
      U: [0, 1, 3, 1, 2, 7],
      A: [1, 1, 1, 1, 1, 1]
    }

    weights = weights[:"#{match[0]}"]

    sum = 0
    digits = match[2, 7]

      for i in 0..6 do
        sum += weights[i].to_i * digits[i].to_i
      end
    calculated_id = match.to_s + 'YXWURNMLJHEAB' [sum % 13]
        if(num.upcase == calculated_id)
          return (match.to_s + 'YXWURNMLJHEAB' [sum % 13])
        end
  end
      #trigger invalid matric number warning if its not correct
      return "invalid matric number" 
end

  def registration_params
    params.require(:questions).permit!
  end

  def application_params
    params.require(:team).permit(:proposal_link)
  end
end
