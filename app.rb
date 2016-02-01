require 'rubygems'
require 'sinatra'
require 'json' # required for .to_json
require 'net/https'
require 'uri'

OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

configure do
  set :sessions, true
  set :session_secret, '*&(^QQWW'
  # set :sessions, key: 'N&wedhSDF',
  #     domain: "localhost",
  #     path: '/',
  #     expire_after: 14400,
  #     secret: '*&(^QQWW'
  set :inline_templates, true
end


before do
  content_type :json
  headers 'Access-Control-Allow-Origin' => '*',
          'Access-Control-Allow-Methods' => ['OPTIONS', 'GET', 'POST'],
          'Access-Control-Allow-Headers' => ['Content-Type', 'Accept', 'X-Requested-With', 'access_token']
  halt 200 if request.request_method == 'OPTIONS'
end

get '/' do
  content_type :html
  erb "
    Sample fulfilment provider"
end

get '/pricing.html' do
  content_type :html
  erb "
    This is the pricing page"
end

get '/manage.html' do
  content_type :html
  erb "
    This is the manage page"
end

get '/shop.html' do
  content_type :html
  erb "
    <div>This is the shop page<div>
    <div>instanceId: <%= Wix.Utils.getInstanceId() %></div>"
end


__END__

@@ layout
<html>
<head>
<link href='http://twitter.github.com/bootstrap/1.4.0/bootstrap.min.css' rel='stylesheet' />
</head>
  <body>
    <div class='container'>
      <div class='content'>
        <%= yield %>
      </div>
</div>
  <script type="text/javascript" src="//static.parastorage.com/services/js-sdk/1.61.0/js/wix.min.js"></script>
  </body>
</html>