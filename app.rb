require 'rubygems'
require 'mongo'
require 'sinatra'
require 'bson'
require 'json' # required for .to_json
require 'net/https'
require 'uri'

require 'omniauth'
require 'omniauth-facebook'
require 'omniauth-twitter'
require 'omniauth-google-oauth2'
require 'omniauth-windowslive'
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

configure do
  if RUBY_PLATFORM.downcase.include?("x64-mingw32") || RUBY_PLATFORM.downcase.include?("x86_64-darwin14")
    db = Mongo::Client.new('mongodb://127.0.0.1:27017/test2')
  else
    db = Mongo::Client.new('mongodb://wix1:wix1@ds033145.mongolab.com:33145/heroku_cswwb7rd')
  end
  set :mongo_db, db[:test]

  set :sessions, true
  set :inline_templates, true
end

use OmniAuth::Builder do
  #provider :github, 'ece9da5a3cff23b3475f','eb81c6098ba5d08e3c2dbd263bf11de5f3382d55'
  provider :facebook, '500367060145352','fc7f89e3da290c1188f3dbbf9e36efcb', {
    strategy_class: OmniAuth::Strategies::Facebook,
        provider_ignores_state: true,
    auth_type: 'reauthenticate'
  }
  provider :twitter, 'GZlE06pMkuGU6i5CIzwnjhokr', '9rtGaasYH8aPAD5Oa1Wy7EF9okxAABqgBelgW9xMZyxH327GIE'
  #provider :att, 'client_id', 'client_secret', :callback_url => (ENV['BASE_DOMAIN']
  provider :google_oauth2, '408793461511-sb2j37tdr95mrfnfe3b9dnsb1hqt71im.apps.googleusercontent.com', 'ZtFVrWuJplQ8tbny1NchoPkG', {:scope => "https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile",approval_prompt: "auto", prompt: 'consent'}
           # {
           #                   :client_options => {:ssl => {:ca_file => '/etc/pki/tls/certs/ca-bundle.crt'}, :scope => 'userinfo.profile,userinfo.email'},
           #                   provider_ignores_state: true}
  provider "windowslive", '000000004017CC47', 'kWkjBmaEg07ZgdXhVHyYqpQkAY5e-Ojj',  :scope => 'wl.basic,wl.emails'

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
    <a href='/auth/google_oauth2'>Login with Google</a><br>
    <a href='/auth/facebook'>Login with facebook</a><br>
    <a href='/auth/twitter'>Login with twitter</a>"
end
get '/auth/:provider/callback' do
  content_type :html
  email = request.env['omniauth.auth']['info']['email'] || (request.env['omniauth.auth']['info']['emails'] && request.env['omniauth.auth']['info']['emails'][0] && request.env['omniauth.auth']['info']['emails'][0]['value'] ? request.env['omniauth.auth']['info']['emails'][0]['value'] : nil)
  res={res: true, provider: params[:provider], uid: request.env['omniauth.auth']['uid'], name: request.env['omniauth.auth']['info']['name'], email: email, image: request.env['omniauth.auth']['info']['image']}
  if(params[:provider]=='facebook' && res['image'])
    res['image'] = "#{res['image']}?type=large"
  end
  erb "<h1>#{params[:provider]}</h1>
         <pre>#{JSON.pretty_generate(request.env['omniauth.auth'])}</pre>
      <script>
      window.opener.postMessage('#{res.to_json}', '*');
</script>
"
end

get '/auth/failure' do
  content_type :html
  res={res: false, provider: params[:provider], message: params}
  erb "<h1>Authentication Failed:</h1><h3>message:<h3> <pre>#{params}</pre>
      <script>
      window.opener.postMessage('#{res.to_json}', '*');
</script>
"
end

get '/auth/:provider/deauthorized' do
  content_type :html
  erb "#{params[:provider]} has deauthorized this app."
end

get '/protected' do
  content_type :html
  throw(:halt, [401, "Not authorized\n"]) unless session[:authenticated]
  erb "<pre>#{request.env['omniauth.auth'].to_json}</pre><hr>
         <a href='/logout'>Logout</a>"
end

get '/logout' do
  session[:authenticated] = false
  redirect '/'
end

get "/getUser/:id" do
  db = settings.mongo_db
  result = db.find(id: params[:id]);
  result.first[:data].to_json
end

get "/getVisitor" do
  db = settings.mongo_db
  result = db.find(visitor: 1).first;
  {time: result[:time], name: result['name'], image: result['image']}.to_json
end
post "/saveVisitor" do
  db = settings.mongo_db
  result = db.delete_many(visitor: 1);
  data = request.body.read
  data = JSON.parse(data)
  result = db.insert_one({visitor: 1, time: Time.now, name: data['label'], image: data['value']})
  '{"status":"ok"}'
end

post "/saveUser/:id" do
  db = settings.mongo_db
  result = db.find(id: params[:id]);
  if result.first
    result.delete_one
  end
  data = request.body.read
  data = JSON.parse(data)
  result = db.insert_one({id: params[:id], data: data})
  '{"status":"ok"}'
end


get "/getRecent/:site/:user/:category" do
  db = settings.mongo_db
  db.find(site: params[:site], user: params[:user], category: params[:category]).sort({time: -1})
      .collect { |doc| {count: doc[:count], time: doc[:time], data: doc[:data]} }.to_json
end

get "/getRecommendations/:site/:user/:category" do
  db = settings.mongo_db
  actionIds = db.find({site: params[:site], user: params[:user], category: params[:category]},:fields=>{:actionId=>true}).
      collect { |doc| doc[:actionId] }.to_a
  similarUsers = {}
  db.find({site: params[:site], category: params[:category], actionId: {:$in=>actionIds}, user: {:$ne => params[:user]}}, fields: {user: true}).each do |rec|
    similarUsers[rec['user']] ||= 0
    similarUsers[rec['user']] +=1
  end
  similarUsersSorted = similarUsers.sort_by{|_key, value| -value}.map{ |item| item[0] }.reject{|v| v==params[:user]}

  #get the items these users had and sort them by populatity
  listOfItemsSimilarUsersHad = {}
  items={}
  db.find({site: params[:site], category: params[:category], user: {:$in=>similarUsersSorted}})
                           .sort(count: -1).each do |rec|

    if(listOfItemsSimilarUsersHad[rec[:actionId]])
      listOfItemsSimilarUsersHad[rec[:actionId]]['popularityCount'] +=1
    else
      rec['popularityCount'] =1
      listOfItemsSimilarUsersHad[rec[:actionId]]=rec
    end
  end
  if(listOfItemsSimilarUsersHad.length<20)
    similarUsersSorted << params[:user]
    puts "we have only #{listOfItemsSimilarUsersHad.length} items - need more"
    db.find({site: params[:site], category: params[:category], user: {:$nin=>similarUsersSorted}})
        .sort(count: -1).each do |rec|

      if(listOfItemsSimilarUsersHad[rec[:actionId]])
        listOfItemsSimilarUsersHad[rec[:actionId]]['popularityCount'] +=1
      else
        rec['popularityCount'] =1
        listOfItemsSimilarUsersHad[rec[:actionId]]=rec
      end
    end
  end
  listOfItemsSimilarUsersHadSorted = listOfItemsSimilarUsersHad.sort_by {|_key, value| -value['popularityCount']}.map{ |item| item[1] }[0..8]


  listOfItemsSimilarUsersHadSorted.to_json
end


get "/delete/:site/:user/:category" do
  db = settings.mongo_db
  db.delete_many(site: params[:site], user: params[:user], category: params[:category]).n.to_s
end

post "/putValue/:site/:user/:category/:actionId" do
  db = settings.mongo_db
  result = db.find(site: params[:site], user: params[:user], category: params[:category],
                        actionId: params[:actionId]);
  count = 1
  if result.first
    count = result.first[:count] + 1
    result.delete_one
  end
  # request.body.rewind  # in case someone already read it
  data = request.body.read
  data = JSON.parse(data)
  #lets check if we need to parse the data
  if(data['productLink']  )
    product = getProductFromPage(data['productLink'])
    data['image'] = "https://static.wixstatic.com/media/#{product['media'][0]['url']}/v1/fit/w_1000,h_1000,q_90/file.jpg"
    data['description'] = product['formattedPrice']
    data['title'] = product['name']
    data['id'] = product['id']
    data['type'] = 'productView'
    puts "Found product #{data}"
  end
  record = {site: params[:site], user: params[:user], category: params[:category],
          actionId: params[:actionId], time: Time.now,
          count: count, data: data}
  result = db.insert_one(record)
  if(data['type'] == 'productView' && params[:category] != 'ecom')
    #add this as an ecom data also
    recordEcom = {site: params[:site], user: params[:user], category: 'ecom',
                  actionId: "productView_#{data['id']}", time: Time.now,
                  count: count, data: data}
    result = db.insert_one(recordEcom)
  end

  #lets also insert a productView action

  record.to_json
end

def fetch(uri_str, limit = 10,header={})
  # You should choose a better exception.
  raise ArgumentError, 'too many HTTP redirects' if limit == 0
  uri=URI.parse(uri_str)
  puts( "Fetching: "+uri_str)
  header={}#addParamsToHeader(uri,header)
  retryCount=0
  response=nil
  max_retries = 3
  until response or retryCount > max_retries
    begin
      http = Net::HTTP.new(uri.host, uri.port)
      #http.use_ssl = true
      #http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      #header=@cookies.
      request = Net::HTTP::Get.new(uri.request_uri,header)

      response = http.request(request)#Net::HTTP.get_response(URI(uri_str),params)
      #saveCookieFromResponse(response,uri)
      case response
        when Net::HTTPSuccess then
          return response
        when Net::HTTPRedirection then
          location = response['location']
          puts( "redirected to #{location}")
          return fetch(location, limit - 1)
        else
          puts( "Unexpected response #{response.value.to_s}. Retry count #{retryCount}")
          response=nil
          retryCount+=1
      end
    rescue
      logMsg = "Error in retry #{retryCount}, #{$!.inspect} #{$@}"
      (retryCount == max_retries) ? puts(logMsg) : puts(logMsg)
      retryCount+=1
    end
  end
  return response
end
def addParamsToHeader(uri,header)
  if(header==nil)
    header=Hash.new
  end
  header["Referer"]=@lastUri if @lastUri
  @lastUri=uri.to_s
  header['User-Agent'] = @userAgent


  #c=@cookies.get_cookie_header(uri)
  # $write_mutex.synchronize do
  #   c=$cookie.get_cookie_header(uri)
  #   #Params::Log.debug( "cookie: "+c)
  #   header['Cookie']=c
  # end
  return header
end

def getProductFromPage(url)
  puts "getting an image from url #{url}"
  res= fetch url
  if(res==nil)
    puts "can't find data from url #{url}"
  end
  ecom={}
  res.body.scan(/eCom.eComAppConfig\('productPageApp', (.+), '\/\/static.parastorage.com\/services\/wix-ecommerce-product-page/) do |ecomJson|

    begin
      ecom=JSON.parse(ecomJson[0]) #return result
    rescue
      puts( "Error while parsing ecom on #{url} #{$!.inspect} #{$@.to_s}")
    end
  end
  if(ecom['appData'] && ecom['appData']['productPageData'] && ecom['appData']['productPageData']['product'])
    return ecom['appData']['productPageData']['product']
  else
    return {}
  end
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
  </body>
</html>