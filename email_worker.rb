require 'logger'

class EmailWorker
  @queue = :send_grid
  extend ResqueHelper

  def self.perform(my_params)
    send(my_params)
  end
end
