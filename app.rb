require 'sinatra'
require 'sinatra/reloader'
require 'httparty'
require 'bundler'
require 'base64'
require 'dotenv'
require 'shopify_api'
require 'sinatra/cross_origin'
require 'sendgrid-ruby'
include SendGrid
Dotenv.load

class ZendeskTicket < Sinatra::Base
  attr_reader :tokens
  API_KEY = ENV['API_KEY']
  API_SECRET = ENV['API_SECRET']
  APP_URL = "5901b96c.ngrok.io"

  set :bind, '0.0.0.0'
  configure do
    enable :cross_origin
  end
  before do
    response.headers['Access-Control-Allow-Origin'] = '*'
  end

  # routes...
  options "*" do
    response.headers["Allow"] = "GET, POST, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, Accept, X-User-Email, X-Auth-Token"
    response.headers["Access-Control-Allow-Origin"] = "*"
    200
  end

  def initialize
    @tokens = {}
    super
    # @shop_url = "https://#{ENV['API_KEY']}:#{ENV['API_SECRET']}@elliestaging.myshopify.com/admin"
    # ShopifyAPI::Base.site = @shop_url
  end

  get '/sinatra-zendesk/install' do
    shop = request.params['shop']
    scopes = "read_orders,read_products,write_products"

    # construct the installation URL and redirect the merchant
    install_url = "http://elliestaging.myshopify.com/admin/oauth/authorize?client_id=#{API_KEY}"\
                "&scope=#{scopes}&redirect_uri=https://#{APP_URL}/sinatra-zendesk/auth"

    # redirect to the install_url
    redirect install_url
  end

  get '/sinatra-zendesk/auth' do
    # extract shop data from request parameters
    # shop = request.params['shop']
    shop = 'elliestaging.myshopify.com'
    code = request.params['code']
    hmac = request.params['hmac']

    # perform hmac validation to determine if the request is coming from Shopify
    validate_hmac(hmac,request)

    # if no access token for this particular shop exist,
    # POST the OAuth request and receive the token in the response
    get_shop_access_token(shop,API_KEY,API_SECRET,code)

    # now that the session is activated, redirect to the bulk edit page
    redirect bulk_edit_url
  end

  post '/create_ticket' do
    puts params.inspect
    #Get form data
    subject = params['subject']
    description = params['description']
    topic = params['topic']
    name = params['name']
    order_number = params['order_number']
    ticket_body = "Name: #{name} \n Order Number: #{order_number} \n Description: #{description}"
    email = params['email']

    #Package the data for API
    data = {'request': {'subject': subject, 'comment': {'body': ticket_body}, 'tags': [topic], 'custom_fields': [{"id": 81584948, 'value': topic}] }}
    ticket = data.to_json

    #Make the API request
    user = email
    api_token = 'swb47Vl8FF6AN3H8w1zu5vawk0iieduTBNyvCJnd'
    url = 'https://ellieactive.zendesk.com/api/v2/requests.json'
    # encoded_user = Base64.encode64(user)
    encoded = Base64.encode64("#{user}/token:#{api_token}")
    encoded.slice! "\n"
    encoded_auth = "Basic #{encoded}"
    puts encoded_auth
    # auth = 'Basic #{encoded_user}/token:#{api_token}'
    headers = {'content-type' => 'application/json', 'Authorization' => encoded_auth}
    puts headers

    create_a_ticket = HTTParty.post(url, :headers => headers, :body => ticket)

    puts create_a_ticket.inspect

    @default_headers = { 'Content-Type' => 'application/json' }

    if create_a_ticket.code == 200 || create_a_ticket.code == 201
      puts "Success! No Errors!"
      # @feedback = 'Ticket was created. Look for an email notification.'
      # return 200
      return [200, @default_headers, {message: "Success"}.to_json]
    else
      puts "Error! #{create_a_ticket.code}"
      ################################################# Send email:
      sg_ticket_body = "Name: #{name} \n Email: #{email} \n Order Number: #{order_number} \n Description: #{description}"
      sg_from = SendGrid::Email.new(email: 'dkim@fambrands.com')
      sg_to = SendGrid::Email.new(email: 'dkim@fambrands.com')
      sg_subject = "Ellie Contact Form Submission: #{subject}"
      sg_content = SendGrid::Content.new(type: 'text/plain', value: sg_ticket_body)
      sg_mail = SendGrid::Mail.new(sg_from, sg_subject, sg_to, sg_content)

      sg = SendGrid::API.new(api_key: ENV['SENDGRID_API_KEY'])
      response = sg.client.mail._('send').post(request_body: sg_mail.to_json)
      puts response.status_code

      if response.status_code.to_i == 202 || response.status_code.to_i == 200
        puts "success! Sent thru sendgrid"
        puts response.status_code
        return [200, @default_headers, {message: "Success"}.to_json]
      else
        puts "error with sendgrid!"
        puts response.status_code
        return [400, @default_headers, {message: "Problem with the request"}.to_json]
      end

      # if create_a_ticket.code == 401 || create_a_ticket.code == 422
      #   # @feedback = 'Could not authenticate you. Check your email address or register.'
      #   return [create_a_ticket.code, @default_headers, {message: "User could not be authenticated. Check email address or register."}.to_json]
      # else
      #   # @feedback = "Problem with the request. Status #{create_a_ticket.code}"
      #   return [create_a_ticket.code, @default_headers, {message: "Problem with the request."}.to_json]
      # end
    end
    # erb :default
  end

  helpers do
      def get_shop_access_token(shop,client_id,client_secret,code)
        if @tokens[shop].nil?
          url = "https://#{shop}/admin/oauth/access_token"

          payload = {
            client_id: client_id,
            client_secret: client_secret,
            code: code}

          response = HTTParty.post(url, body: payload)
          # if the response is successful, obtain the token and store it in a hash
          if response.code == 200
            @tokens[shop] = response['access_token']
          else
            return [500, "Something went wrong."]
          end

          instantiate_session(shop)
        end
      end

      def instantiate_session(shop)
        # now that the token is available, instantiate a session
        session = ShopifyAPI::Session.new(shop, @tokens[shop])
        ShopifyAPI::Base.activate_session(session)
      end

      def validate_hmac(hmac,request)
        h = request.params.reject{|k,_| k == 'hmac' || k == 'signature'}
        query = URI.escape(h.sort.collect{|k,v| "#{k}=#{v}"}.join('&'))
        digest = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), API_SECRET, query)

        unless (hmac == digest)
          return [403, "Authentication failed. Digest provided was: #{digest}"]
        end
      end

      def bulk_edit_url
        bulk_edit_url = "https://www.shopify.com/admin/bulk"\
                      "?resource_name=ProductVariant"\
                      "&edit=metafields.test.ingredients:string"
        return bulk_edit_url
      end

    end
end



run ZendeskTicket.run!
