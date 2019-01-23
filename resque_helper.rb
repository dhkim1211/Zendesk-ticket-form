require 'dotenv'
Dotenv.load
require 'logger'
require 'sendgrid-ruby'

module ResqueHelper
  def send(params)
    sg_ticket_body = params['ticket_body']
    sg_from = SendGrid::Email.new(email: params['email'])
    sg_to = SendGrid::Email.new(email: params['email_to'])
    sg_subject = "Ellie Contact Form Submission: #{ params['subject'] }"
    sg_content = SendGrid::Content.new(type: 'text/plain', value: sg_ticket_body)
    sg_mail = SendGrid::Mail.new(sg_from, sg_subject, sg_to, sg_content)

    sg = SendGrid::API.new(api_key: ENV['SENDGRID_API_KEY'])
    response = sg.client.mail._('send').post(request_body: sg_mail.to_json)
    Resque.logger.info response.status_code
  end
end
