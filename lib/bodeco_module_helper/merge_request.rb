require "gitlab"
require "json"
require "git"
require 'uri'

class MergeRequest
  attr_accessor :client, :git, :mr
  attr_reader :project_id

  UPSTREAM_NAME='upstream'

  def git
    @git ||= Git.open(Dir.pwd)
  end

  def client
    @client ||= Gitlab.client
  end

  def target_project_id
    remote_url = git.config["remote.#{UPSTREAM_NAME}.url"]
    abort("Unable to lookup project id, must have the remote named #{UPSTREAM_NAME}") if remote_url.nil?
    gitlab_project_id(remote_url)
  end


  def project_id
    remote_url = git.config["remote.origin.url"]
    abort("Unable to lookup project id, must have the remote named origin") if remote_url.nil?
    gitlab_project_id(remote_url, 'owned')
  end

  def create_mr
    # we need to check if the branch has been pushed yet
    unless mr_exists?(git.current_branch,git.branch.full)
      abort('Must not be on master branch to create merge request') if git.current_branch == 'master'
      title = "#{git.current_branch} → #{git.branch.full}"
      begin
        @mr = client.create_merge_request(project_id, title, :source_branch => git.current_branch,
                                          :target_branch => git.branch.full, :target_project_id => target_project_id)
      rescue Exception => e
        raise "Merge request already created"
      end
    end
    @mr
  end

  def self.create_mr
    newmr = MergeRequest.new
    begin
      request = newmr.create_mr
    rescue Exception =>e
      puts e.message
      exit(1)
    end
    # output the merge request url
  end

  private
  # get author email from current git repo
  def author_email
    client.config["user.email"]
  end

  # mr_exists? returns a boolean true when the merge request already exists
  # currently this does not work so we just return false
  def mr_exists?(src,dst)
    return false
    merge_request(src,dst).nil?
  end

  # merge_request fetches all the available merge requests with given state
  # this is supposed to work but the data being returned is not correct
  def merge_request(src,dst, email=author_email)
    merge_requests.find_all { |mr| mr.target_branch == dst and mr.source_branch == src and mr.author.email == email }

  end

  #retrives all the current merge requests with the state filtered
  def merge_requests(id=project_id, state='active')
    client.merge_requests(id).find_all {|mr| mr.state == state }
  end

  # lets make a rule that the project id is the project from the remote named upstream
  def gitlab_project_id(remote_url, scope=nil)
    if remote_url =~ /^git@/
      project = client.projects(:scope => scope).find { |p| p.ssh_url_to_repo == remote_url }
    else
      project = client.projects(:scope => scope).find { |p| p.http_url_to_repo == remote_url }
    end
    if project
      project.id
    else
      nil
    end
  end

end
