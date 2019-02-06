class FakeCredential
  def login
    'dev'
  end

  def current_user_id
    3
  end

  def ok?
    true
  end

  def logged_in?
    true
  end

  def expired?
    false
  end

  def admin?
    true
  end

  def accessible_workflow?(workflow_id)
    workflow_id
  end

  def accessible_project?(id)
    true
  end
end