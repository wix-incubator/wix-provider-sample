require 'rubygems'
require 'sinatra'
require 'json' # required for .to_json
require 'net/https'
require 'uri'
require 'base64'
require 'httparty'

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
  set :protection, :except => :frame_options
end

configure :development do
  set :appDefId => '142e50c2-1d37-9c1d-812c-198426f8b757'
  set :appSecret => '9183fd33-76ef-4562-aef7-79d925136a0f'
end

configure :production do
  set :appDefId => '1430ec4e-bddf-8f9a-dee4-41cac6ef7cfa'
  set :appSecret => '7123eb4d-3124-4699-9d73-db8cf487eec2'
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
  erb 'Sample fulfilment provider'
end

get '/pricing.html' do
  content_type :html
  erb displayParams('pricing')
end

get '/manage.html' do
  content_type :html
  erb displayParams('manage')
end

get '/shop.html' do
  content_type :html
  erb "#{displayParams('shop')}
      <div><img id=\"img-holder\" src=\"<%=params['img']%>\" height=\"100px\"></div>
      <div>Message received from gallery:</div>
      <pre id=\"message-received\"></pre>
      <script>
        window.addEventListener('message', function(e) {
          if (e.data && e.data['itemId'] && e.data['img']) {
            document.getElementById('img-holder').src=e.data['img'];
            document.getElementById('message-received').innerHTML=JSON.stringify(e.data, null, 2);
          }
        }, false);
      </script>
      <div><a href=\"/payment_success.html?p_instance=<%=params['p_instance'] %>&galleryId=<%=params['galleryId'] %>&itemId=<%=params['itemId'] %>&purchaseNotify=<%=params['purchaseNotify'] %>\" target=\"_blank\">Simulate payment complete</a></div>
"
end

get '/banner.html' do
  content_type :html
  erb displayParams('banner')
end

get '/payment_success.html' do

  purchased = parse_instance_data(params['p_instance'])
  purchased['appDefId'] = settings.appDefId
  purchased['galleryId'] = params['galleryId']
  purchased['itemId'] = params['itemId']
  purchased['transactionId'] = Random.new.rand.to_s
  purchased['buyerName'] = 'some name'
  purchased['category'] = 'some category'
  purchased['product'] = 'some product'
  purchased['currency'] = 'usd'
  purchased['amount'] = '23.4'
  #contact the progallery server for with the purchased record
  res = HTTParty.get("#{params['purchaseNotify']}?signature=#{signJson(purchased)}&itemData=#{encodeJson(purchased)}",
                headers: { 'Content-Type' => 'application/json' } )
  #response will include the hi-res item
  res.body
end

def displayParams(pageName)
   "
    <div>This is the #{pageName} page<div>
    <div>Parameters received: <pre><%= JSON.pretty_generate(params)%></pre></div>
    <div>provider instance (after extraction from p_instance): <pre><%= JSON.pretty_generate(parse_instance_data(params['p_instance'])) %></pre></div>"

end

def parse_instance_data(signed_instance)
  signature, encoded_json = signed_instance.split('.', 2)
  # Need to add Base64 padding to make base64 decode work in Ruby. (ref: http://stackoverflow.com/questions/4987772/decoding-facebooks-signed-request-in-ruby-sinatra)
  encoded_json_hack = encoded_json.length.modulo(4) > 0 ? encoded_json + ('=' * (4 - encoded_json.length.modulo(4))) : encoded_json
  json_str = Base64.urlsafe_decode64(encoded_json_hack)
  hmac = OpenSSL::HMAC.digest(OpenSSL::Digest::SHA256.new, settings.appSecret, encoded_json)
  # bug in ruby. why are there '=' chars on urlsafe_encode ?!
  my_signature = Base64.urlsafe_encode64(hmac).gsub('=','')
  raise "the signatures do not match" if (signature != my_signature)
  JSON.parse(json_str)
end

def signJson(json)
  hmac = OpenSSL::HMAC.digest(OpenSSL::Digest::SHA256.new, settings.appSecret, encodeJson(json))
  Base64.urlsafe_encode64(hmac).gsub('=','')
end

def encodeJson(json)
  Base64.urlsafe_encode64(JSON.unparse(json).to_s).gsub('=','')
end

get '/test' do
  testJson = {'aa' => 'aa', 'bb' => 'bb'}

  resJson = parse_instance_data("#{signJson(testJson)}.#{encodeJson(testJson)}")
  "json is equal? #{ resJson == testJson}"
end

__END__

@@ layout
<html>
<head>
<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/css/bootstrap.min.css" integrity="sha384-1q8mTJOASx8j1Au+a5WDVnPi2lkFfwwEAa8hDDdjZlpLegxhjVME1fgjWPGmkzs7" crossorigin="anonymous">
</head>
  <body  style="background-color:lightyellow">
    <div class='container'>
      <div class='content'>
        <%= yield %>
      </div>
</div>
  <script type="text/javascript" src="//static.parastorage.com/services/js-sdk/1.61.0/js/wix.min.js"></script>
  </body>
</html>