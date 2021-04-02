# TeamsController
class TeamsController < ApplicationController
  def index
    !authenticate_user(true, false, Adviser.all.map(&:user)) && return
    cohort = params[:cohort] || current_cohort
    @teams = Team.order(:team_name).where(cohort: cohort)
    @page_title = t('.page_title')
    respond_to do |format|
      format.html do
        render locals: {
          all_cohorts: all_cohorts,
          cohort: cohort
        }
      end
      format.csv { send_data Team.to_csv(cohort: cohort) }
    end
  end

  def new
    !authenticate_user(true, true) && return
    @team = Team.new
    cohort = params[:cohort] || current_cohort
    @page_title = t('.page_title')
    render locals: {
      advisers: Adviser.where(cohort: cohort),
      mentors: Mentor.where(cohort: cohort),
      cohort: cohort
    }
  end

  def create
    !authenticate_user(true, true) && return
    @team = Team.new(team_params)
    cohort = @team.cohort || current_cohort
    if @team.save
      redirect_to teams_path(cohort: cohort), flash: {
        success: t('.success_message', team_name: @team.team_name)
      }
    else
      redirect_to new_team_path(cohort: cohort), flash: {
        danger: t('.failure_message',
                  error_message: @team.errors.full_messages.join(', '))
      }
    end
  end

  def show
    @team = Team.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false,
                       @team.get_relevant_users(true, true)) && return
    @page_title = t('.page_title', team_name: @team.team_name)
    cohort = @team.cohort || current_cohort
    @teamsMentorMatchings = MentorMatching.where(:team_id => params[:id]).order(:choice_ranking);
    render locals: data_for_display
  end

  def edit
    @team = Team.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false,
                       @team.get_relevant_users(false, false)) && return
    @page_title = t('.page_title', team_name: @team.team_name)
    cohort = @team.cohort || current_cohort
    render locals: {
      advisers: Adviser.where(cohort: cohort),
      mentors: Mentor.where(cohort: cohort)
    }
  end

  def update
    @team = Team.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false,
                       @team.get_relevant_users(false, false)) && return
    if @team.update(team_params)
      redirect_to team_path(@team.id), flash: {
        success: t('.success_message', team_name: @team.team_name)
      }
    else
      redirect_to edit_team_path(params[:id]), flash: {
        danger: t('.failure_message',
                  team_name: @team.team_name,
                  error_message: @team.errors.full_messages.join(', '))
      }
    end
  end

  def upload_csv
    !authenticate_user(true, true) && return
    render locals: {
      team: Team.first
    }
  end

  def update_teams
    require 'csv'
    uploaded_io = params[:team][:uploaded_csv]
    File.open(File.join('public', uploaded_io.original_filename), 'wb') do |file|
      file.write(uploaded_io.read)
    end
    #to-do: error checking, check title and whether there is any parsing error
    csv_text = CSV.read(Rails.root.join('public', uploaded_io.original_filename))
    elements_per_row = 5
    rows = []
    count = 0
    row = []
    for i in 0..csv_text.length - 1
      if i == 0
        next
      end
      row = csv_text[i]
      rank = row[0]
      teamID = row[1]
      avg_rank = row[2]
      evaluators = row[3]
      evaluator_students = evaluators.split('\', \'')
      evaluator_students[0] = evaluator_students[0][2, -1]
      evaluator_students[-1] = evaluator_students[-1][0, -3]
      # puts '@@@@@@@@@'
      # puts evaluator_students.length
      application_status = row[5]
      team_to_update = Team.find_by(id: teamID)
      team_to_update.avg_rank = avg_rank.to_f
      team_to_update.evaluator_students = evaluator_students
      team_to_update.application_status = application_status
      team_to_update.save
    end
    msg = 'success'
    redirect_to applicant_admin_index_path(), flash: {
      success: msg
    }
  end

  def destroy
    !authenticate_user(true, true) && return
    @team = Team.find(params[:id])
    cohort = @team.cohort || current_cohort
    if @team.destroy
      redirect_to teams_path(cohort: cohort), flash: {
        success: t('.success_message', team_name: @team.team_name)
      }
    else
      redirect_to teams_path(cohort: cohort), flash: {
        danger: t('.failure_message', team_name: @team.team_name)
      }
    end
  end

  def match_mentor
    @team = Team.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false,
                       @team.get_relevant_users(true, true)) && return
    cohort = @team.cohort || current_cohort
    @teamsMentorMatchings = MentorMatching.where(:team_id => params[:id])
    render locals: {
      mentors: Mentor.where(cohort: cohort),
    }
  end

  def match_mentor_success
    @team = Team.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false,
                       @team.get_relevant_users(false, false)) && return
    cohort = @team.cohort || current_cohort
    choices = [ params[:team][:choice_1], params[:team][:choice_2], params[:team][:choice_3] ]
    teamsMentorMatchings = MentorMatching.where(:team_id => params[:id]).ids;

    if ((choices[0] == choices[2]) || (choices[0] == choices[1]) || (choices[1] == choices[2]))
      redirect_to match_mentor_team_path(), flash: {
        danger: t('.failure_message')
      }
      return
    end
    #See if can edit else create
    if teamsMentorMatchings.any?
      if MentorMatching.edit_mentor_preferences(@team, choices, cohort, teamsMentorMatchings)
        redirect_to team_path(@team.id), flash: {
          success: t('.success_message')
        }
        return
      else
        redirect_to match_mentor_team_path(), flash: {
          danger: t('.error_message',
                    error_message: @team.errors.full_messages.join(', ')
          )
        }
        return
      end
    elsif MentorMatching.match_mentor(@team, choices, cohort)
      redirect_to team_path(@team.id), flash: {
        success: t('.success_message')
      }
      return
    else
      redirect_to match_mentor_team_path(), flash: {
        danger: t('.error_message',
                  error_message: @team.errors.full_messages.join(', ')
        )
      }
      return
    end
  end

  def accept_mentor
    @team = Team.find(params[:id]) || (record_not_found && return)
    !authenticate_user(true, false,
                       @team.get_relevant_users(false, false)) && return
    #establish the mentorship
    @mentor = Mentor.find(params[:mentor_id])
    teamsMentorMatching = MentorMatching.find_by(:team_id => params[:id], :mentor_id => params[:mentor_id])
    if !@mentor.nil? && !teamsMentorMatching.nil? && teamsMentorMatching.mentor_accepted
      @team.update(mentor_id: @mentor.id)
      @mentor.teams << @team #to-do: what's this?
      redirect_to team_path(@team.id), flash: {
        success: t('.success_message',
                   mentor_name: @mentor.user.user_name)
      }
      return
    else
      redirect_to team_path(@team.id), flash: {
        danger: t('.error_message')
      }
      return
    end
  end

  def getEvaluatedTeams(beginI, endI, teamID, teamIDs, size)
    if beginI + size - 1 > endI
        teamsBack = teamIDs[beginI..teamIDs.length() - 1]
        teamsFront = teamIDs[0..endI]
        teams = teamsFront + teamsBack
    else
        teams = teamIDs[beginI..endI]
    end
    if teams.delete(teamID)
      if beginI > 0
        teams << teamIDs[beginI - 1]
      else
        teams << teamIDs[endI + 1]
      end
    end
    return teams
  end

  def applicant_eval_matching
    # authenticate users
    !authenticate_user(true, true) && return
    # if confirm false, return
    confirm_params = params.require(:team).permit(:confirm)
    if confirm_params[:confirm] == 'false'
      redirect_to applicant_admin_index_path(), flash: {
        success: 'cancelled'
      }
    else
      teams = Team.where("proposal_link != \'\'")
      teamIDs = []
      teams.each do |team|
        teamIDs << team.id
      end
      teamIDs = teamIDs.shuffle
      size = 4
      # to-do: 'Invalid size': < 2 * size + 1
      # fix self evaluate
      teamIDs.each_with_index do |teamID, i|
          team = Team.find_by(id: teamID)
          members = team.students
          # update params, shift the links to peer eval page
          member1 = members[0].id
          member2 = members[1].id
          member1Begin = i % teamIDs.length()
          member1End = (i + size - 1) % teamIDs.length()
          member2Begin = (i + size) % teamIDs.length()
          member2End = (i + size + size - 1) % teamIDs.length()
          teamsBy1 = getEvaluatedTeams(member1Begin, member1End, teamID, teamIDs, size)
          teamsBy2 = getEvaluatedTeams(member2Begin, member2End, teamID, teamIDs, size)
          members[0].evaluatee_ids = teamsBy1
          members[1].evaluatee_ids = teamsBy2
          members[0].save
          members[1].save
        end
      # update team attributes: for each member, evaluaters, evaluatees, application status   
      redirect_to applicant_admin_index_path(), flash: {
        success: 'success'
      }
    end
  end

  private

  def team_params
    team_ps = params.require(:team).permit(:team_name, :project_level,
                                           :adviser_id, :mentor_id,
                                           :has_dropped, :cohort, :poster_link, 
                                           :video_link, :status, :comment, :application_status)
    team_ps[:project_level] = Team.get_project_level_from_raw(
      team_ps[:project_level]) if team_ps[:project_level]
    team_ps
  end

  def data_for_display
    milestones = Milestone.order(:id).where(cohort: @team.cohort)
    survey_templates = []
    milestones.each do |milestone|
      survey_templates = survey_templates.concat(milestone.survey_templates)
    end
    teamsMentorMatchings = MentorMatching.where(:team_id => @team.id).order(:choice_ranking);
    basic_data = {
      milestones: milestones,
      survey_templates: survey_templates,
      teamsMentorMatchings: teamsMentorMatchings
    }
    basic_data.merge(team_related_data)
  end

  def team_related_data
    {
      evaluateds: @team.evaluateds,
      evaluators: @team.evaluators,
      team_submissions: @team.get_own_submissions,
      team_evaluateds_submissions: @team.get_others_submissions,
      team_evaluations: @team.get_own_evaluations_for_others,
      team_evaluators_evaluations: @team.get_evaluations_for_own_team,
      team_feedbacks: @team.get_feedbacks_for_others,
      adviser_feedbacks: @team.get_feedbacks_for_adviser
    }
  end
end
