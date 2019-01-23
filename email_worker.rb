require 'logger'

class EmailWorker
  @queue = :send_grid
  extend ResqueHelper
  Resque.logger = Logger.new('logs/email_jobs.log', 5, 10240000)

  def self.perform(my_params)
    send(my_params)
  end
end
