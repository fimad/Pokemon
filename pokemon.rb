require 'rubygems'
#require 'patron'
require 'rest_client'
require 'scrapi'

load 'config.rb'

#login info
username=PokemonConfig::USERNAME
password=PokemonConfig::PASSWORD
fbid=0
fb='https://www.facebook.com/'
headers={:user_agent=>"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_3) AppleWebKit/535.20 (KHTML, like Gecko) Chrome/19.0.1036.7 Safari/535.20"}

#min and max wait times for checking for pokes
max_wait = PokemonConfig::MAX_WAIT
min_wait = PokemonConfig::MIN_WAIT
cur_wait = max_wait/2
#cur_wait = 1

#Scrapes a pokes page for all outstanding pokes and grabs the poke back links
facebook_pokes = Scraper.define do
  array :code
  process "code.hidden_elem", :code=>:text
  process "h2.main_message", :login_check=>:text
  process 'input[name="fb_dtsg"]', :fb_dtsg=>"@value"
  process 'input[name="post_form_id"]', :post_form_id=>"@value"
  result :code, :login_check, :fb_dtsg, :post_form_id
end

#scrapes the hidden input values from the login page
facebook_login = Scraper.define do
  process 'input[name="post_form_id"]', :post_form_id=> "@value"
  process 'input[name="charset_test"]', :charset_test=> "@value"
  process 'input[name="lgnrnd"]', :lgnrnd=> "@value"
  process "input#lgnjs", :lgnjs=> "@value"
  result :post_form_id, :charset_test, :lgnrnd, :lgnjs
end

#calculate the phstamp for pokes
def phstamp(id,post_form_id,fb_dtsg,fbid)
  data="uid=#{id}&pokeback=1&nctr[_mod]=pagelet_pokes&post_form_id=#{post_form_id}&fb_dtsg=#{fb_dtsg}&lsd&post_form_id_source=AsyncRequest&__user=#{fbid}"
  input_len=data.length
  numeric_csrf_value=''
  fb_dtsg.chars{ |c| numeric_csrf_value += c.ord.to_s }
  phstamp='1'+numeric_csrf_value.to_s+input_len.to_s;
#return phstamp
  return data+"&phstamp=#{phstamp}&lsd"
end

def getFbId(content)
  id = content.scan(/envFlush\({"user":"([0-9]+)"/).flatten[0]
  return id
end

#RestClient.proxy = "http://localhost:8080"

while( true ) do #begin
  html_body = (RestClient.get "#{fb}pokes?", headers).body
  result = facebook_pokes.scrape( html_body )

  if( result.login_check == "You must log in to see this page." ) then
    puts "#{Time.now.strftime("[%m/%d/%Y %I:%M:%S%p]")} Logging in..."

#switch to the login page, seems to stop the frequent login errors
    html_body = (RestClient.get "#{fb}", headers).body
    result = facebook_pokes.scrape( html_body )
#send the login info
    formdata = {:email=>username, :pass=>password, :display=>"", :default_persistent=>"0", :locale=>"en_US"}
    facebook_login.scrape( html_body ).each_pair {|k,v| formdata[k] = v} #scrape the login info from the page
#formdata[:charset_test] = HTMLEntities.new.decode formdata[:charset_test]

    bad = false
    login_resp = RestClient.post(
      "#{fb}login.php?login_attempt=1",
      formdata,
      headers.merge(:referer=>"https://www.facebook.com/")
      ){ |response, request, result, &block|
        if [301, 302, 307].include? response.code
            headers[:cookies] = response.cookies
            RestClient.get response.headers[:location], headers
        else 
            puts "#{Time.now.strftime("[%m/%d/%Y %I:%M:%S%p]")} Cannot Login, bad password?"
            bad = true
            sleep max_wait
            response.return!(request, result, &block)
        end }
    if( not bad ) then
      login_result = facebook_pokes.scrape( login_resp.body )

      if( !login_result.login_check.nil? and login_result.login_check == "Please try again later" ) then
        puts "#{Time.now.strftime("[%m/%d/%Y %I:%M:%S%p]")} Logging in too often..."
        sleep max_wait
      end

      sleep min_wait #be nice to facebook and wait the min time after logging in
    end
  else

#grab our id if we don't already have it
    if( fbid == 0 ) then
      fbid = getFbId( html_body )
    end

    to_poke = []
#find the code block that contains the people who are going to poke us
    result.code.each do |code|
      if code =~ /poke_/ then
        to_poke = code.scan(/<li class="objectListItem uiListItem uiListLight uiListVerticalItemBorder" id="poke_([0-9]+)"/)
        to_poke.flatten!
      end
    end
    
    if( to_poke.size > 0 ) then
      #poke each victim
      to_poke.each do |id|
        puts "#{Time.now.strftime("[%m/%d/%Y %I:%M:%S%p]")} Poking #{id}"
        data = phstamp(id,result.post_form_id,result.fb_dtsg,fbid)
        RestClient.post("#{fb}ajax/pokes/poke_inline.php?__a=1",data,headers.merge({"X-SVN-Rev"=>"510544", "Referer"=>"https://www.facebook.com/pokes"})).body
      end
      #reduce the wait time 
      cur_wait = [cur_wait/2, min_wait].max
    else
      #no pokes, increase the wait time
      cur_wait = [cur_wait*2, max_wait].min
    end

    sleep cur_wait
  end
end

