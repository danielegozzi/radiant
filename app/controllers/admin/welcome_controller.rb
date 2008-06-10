class Admin::WelcomeController < ApplicationController
  no_login_required
  
  def index
    redirect_to page_index_url
  end
  
  def login
    if request.post?
      login = params[:user][:login]
      password = params[:user][:password]
      announce_invalid_user unless self.current_user = User.authenticate(login, password)
    end
    if current_user
      redirect_to (session[:return_to] || welcome_url)
      session[:return_to] = nil
    end
  end
  
  def logout
    self.current_user = nil
    announce_logged_out
    redirect_to login_url
  end
  
  private
  
    def announce_logged_out
      flash[:notice] = 'You are now logged out.'
    end
    
    def announce_invalid_user
      flash[:error] = 'Invalid username or password.'
    end
    
end
