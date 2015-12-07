# Author: Gregory 'kalidor' Charbonneau
# Email: kalidor -AT- unixed -DOT- fr
# Published under the terms of the wtfPLv2

require 'net/http'
require 'net/https'
require 'uri'
require 'cgi' # unescape
require 'json'
require 'yaml'
require 'time'
$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__)))
require 'helpers'
$CONF = nil
DAYS = {
  "Monday" => "Lundi",
  "Tuesday" => "Mardi",
  "Wednesday" => "Mercredi",
  "Thursday" => "Jeudi",
  "Friday" => "Vendredi",
  "Saturday" => "Samedi",
  "Sunday" => "Dimanche"
}
MONTHS = {
  "Janvier" => "January",
  "Février" => "February",
  "Mars" => "March",
  "Avril" => "April",
  "Mai" => "May",
  "Juin" => "June",
  "Juillet" => "July",
  "Août" => "August",
  "Septembre" => "September",
  "Octobre" => "October",
  "Novembre" => "November",
  "Décembre" => "December"
}
REASON_REFUSE = {
  "refuse_no_longer_do_trip"=>
  "J'ai un imprévu, je n'effectue plus le voyage",
  "refuse_other"=>"Autre",
  "refuse_wanted_to_ask_question"=>
    "J'ai besoin de poser une question à ce membre avant d'accepter",
  "refuse_would_feel_uncomfortable"=>
    "Je ne me sentirais pas à l'aise en voyageant avec ce membre (ex: pas d'avis sur le profil)",
  "refuse_psgr_booked_too_short_distance"=>
    "Ce passager veut réserver pour une distance trop courte",
  "refuse_trip_full"=>"Mon trajet est complet",
  "refuse_modify_tripoffer"=>"Je dois modifier l'annonce",
  "refuse_psgr_profile_incomplete"=>
    "Le profil de ce membre est incomplet (pas de photo, mini bio, etc.)"
}

$tracking = {
  :method => Net::HTTP::Post,
  :url => "/tracking/cmkt",
  :data => "location=https://www.blablacar.fr/&originalData[site_language]=FR&originalData[media]=web&originalData[diplayed_currency]=EUR&originalData[current_route]=blablacar_security_security_login",
  :header => ["Content-Type" , "application/x-www-form-urlencoded; charset=UTF-8"],
}
$ident = {
  :method => Net::HTTP::Post,
  :url => "/login_check",
  :data => "_username=%{user}&_password=%{pass}&_submit=",
  :header => ["Content-Type", "application/x-www-form-urlencoded"],
}

$dashboard = {
  :method => Net::HTTP::Get,
  :url => "/dashboard",
}

$tripoffers = {
  :method => Net::HTTP::Get,
  :url => "/dashboard/trip-offers/active?page=%s",
}

$trip = {
  :method => Net::HTTP::Get,
  :url => "/dashboard/trip-offer/%s/passengers",
}

$trip_confirmation = {
  :method => Net::HTTP::Post,
  :url => "%s",
  :data => "confirm_booking[code]=%s&confirm_booking[_token]=%s",
  :header => ["Content-Type", "application/x-www-form-urlencoded"]
}

$messages = {
  :method => Net::HTTP::Get,
  :url => "/questions-answers",
}

$private_messages = {
  :method => Net::HTTP::Get,
  :url => "/messages/received",
}

$respond_to_message = {
  :method => Net::HTTP::Post,
  :url => "",
  :data => "message[content]=%s&message[_token]=%s",
  :header => ["Content-Type", "application/x-www-form-urlencoded"]
}

$money = {
  :method => Net::HTTP::Get,
  :url => "/dashboard/account/money-available",
}

$money_transfer = {
  :method => Net::HTTP::Get,
  :url => "/dashboard/ask-transfer",
}

$money_transfer_status = {
  :method => Net::HTTP::Get,
  :url => "/dashboard/account/archived-transfer",
}

$search_req = {
  :method => Net::HTTP::Get,
  :url => "/search_xhr?fn=%s&fcc=FR&tn=%s&tcc=FR&db=%s&sort=trip_date&order=asc&limit=50&page=1",
}

$proposer_req = {
  :method => Net::HTTP::Get,
  :url => "/proposer/1",
}

$avis_req_get = {
  :method => Net::HTTP::Get,
  :url => "",
}
$avis_req_post = {
  :method => Net::HTTP::Post,
  :url => "",
  :data => "rating[role]=%s&rating[global_rating]=%s&rating[comment]=%s&rating[driving_rating_optional]=1&rating[_token]=%s",
  :header => ["Content-Type", "application/x-www-form-urlencoded"]
}
$avis_req_post_confirm = {
  :method => Net::HTTP::Post,
  :url => "",
  :data => "rating_preview[confirm]=&rating_preview[_token]=%s",
  :header => ["Content-Type", "application/x-www-form-urlencoded"]
}
$rating_received = {
  :method => Net::HTTP::Get,
  :url => "/dashboard/ratings/received?page=%s",
}
$refuse_req = {
  :method => Net::HTTP::Post,
  :url => "",
  :data => "drvr_refuse_booking[_token]=%sdrvr_refuse_booking[reason]=%s&drvr_refuse_booking[comment]=%s&drvr_refuse_booking[agree]", # dernier peut être pas obligatoire ?
  :header => ["Content-Type", "application/x-www-form-urlencoded"]
}

def save_cookie(cookie)
  dputs __method__.to_s
  File.open($CONF['cookie'], "w") do |fc|
    fc.write(cookie)
  end
end

def local_cookie?
  if File.exist?($CONF['cookie'])
    return true
  end
  false
end

def look_for_day(day)
  diff = DAYS.keys.index(DAYS.find{|k,v| v==day}.first) - DAYS.keys.index(Time.now.strftime("%A"))
  return diff.abs
end

def parse_time(tt)
  MONTHS.map{|k,v|
    tt.gsub!(/\<k.downcase\>/, v.downcase)
  }
  case tt
    when /Aujourd'hui\s*à.*/
      t = Time.parse(tt)
    when /Demain\s*à.*/
      t = Time.parse(tt)+60*60*24
    when /(?:Lundi)?(?:Mardi)?(?:Mercredi)?(?:Jeudi)?(?:Vendredi)?(?:Samedi)?(?:Dimanche)?\s*\d{1,2}\s*.*\s*à.*/
      t = Time.parse(tt)
    when /(?:Lundi)?(?:Mardi)?(?:Mercredi)?(?:Jeudi)?(?:Vendredi)?(?:Samedi)?(?:Dimanche)?\s*à.*/
      #diff = look_for_day(tt.split(" ").first)
      t = Time.parse(tt)
    else
      t = Time.parse(tt)
  end
  return t
end

# Set up the HTTP request object to avoir duplicated code
def setup_http_request(obj, cookie=nil, args={})
  if args.has_key?(:url)
    if args[:url].scan("%s").length > 0
      if args[:url].scan("%s").length != args[:arg].length
        aputs "URL contains %d '%%s' argument... Fix your code" % args[:url].scan("%s").length
        aputs __callee__
        exit 2
      end
      req = obj[:method].new(args[:url] % args[:arg])
    else
      req = obj[:method].new(args[:url])
    end
  else
    if args.has_key?(:arg)
      if obj[:url].scan("%s").length != args[:arg].length
        aputs "URL contains %d '%%s' argument... Fix your code" % args[:url].scan("%s").length
        aputs __callee__
        exit 2
      end
      req = obj[:method].new(obj[:url] % args[:arg])
    else
      req = obj[:method].new(obj[:url])
    end
  end
  req.add_field("Host", "www.blablacar.fr")
  req["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64; rv:18.0) Gecko/20100101 Firefox/18.0"
  req["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
  req.add_field("Referer", "https://www.blablacar.fr/dashboard")
  req.add_field("Connection", "keep-alive")
  if cookie
    req.add_field("Cookie", cookie)
  end
  if obj.has_key?(:header)
    req.add_field(obj[:header][0], obj[:header][1])
  end
  if obj.has_key?(:data)
    if obj[:data].scan("%s").length > 0
      if obj[:data].scan("%s").length != args[:arg].length
        aputs "URL contains %d '%%s' argument... Fix your code" % args[:url].scan("%s").length
        aputs __callee__
        exit 2
      else
      req.body = obj[:data] % args[:arg]
      end
    else
      req.body = obj[:data]
    end
  end
  req
end

class AuthenticationFailed < StandardError
end

class SendReponseMessageFailed < StandardError
end

class AcceptationError < StandardError
end

# Generic Notification class
# All notification will heritated from it
class Notification
  attr_reader :desc
  def initialize(http, cookie, data)
    @http = http
    @cookie = cookie
    @desc = data.first
    @url = data.last
    prepare(data)
  end
end

# AcceptationNotification
# When you have to accept a passenger for a trip
class AcceptationNotification < Notification
  attr_reader :user, :end_date, :trip, :trip_date
  def prepare(data)
    @user = data.first.scan(/Demande de réservation de (.*)/).flatten.first
    parse()
  end
  def parse
    get_req = setup_http_request($dashboard, @cookie,{:url=>@url})
    res = @http.request(get_req)
    # res.code == 302
    next_ = res['location']
    get_form_confirm_req = setup_http_request($dashboard, @cookie,{:url=>next_})
    res = @http.request(get_form_confirm_req)
    body = res.body.force_encoding('utf-8')
    # @cancel_url is present only if someone reserved a seat (already valid)
    @cancel_url = body.scan(/data-url="(\/seat-driver-action.*)"\s*data-show-modal="(?:driverCancel)?"/).flatten.first
    @refuse_url, @accept_url = body.scan(/data-url="(\/seat-driver-action.*)"\s*data-show-modal="(?:pendingRefuse)?(?:pendingAccept)?"/).flatten
    @end_date = body.scan(/strong data-date="([^"]*)"/).flatten.first
    @trip = body.scan(/<h2 class="pull-left">\s(.*)\s*<\/h2>/).flatten.first.strip.gsub("&rarr;", "->")
    @trip_date = body.scan(/<p class="my-trip-elements size16 push-left no-clear my-trip-date">\s*(.*)\s*<\/p>/).flatten.first
    if @user != user
      raise AcceptationError, "User unknown", caller
    end
    if @trip_date != date
      raise AcceptationError, "Date doesn't match", caller
    end
    if not @trip
      raise AcceptationError, "Can't get trip", caller
    end
    if not @end_date
      raise AcceptationError, "Can't get end_date", caller
    end
    if not @accept_url
      raise AcceptationError, "Can't get accept_url ", caller
    end
    if not @refuse_url
      raise AcceptationError, "Can't get refuse_url", caller
    end
  end

  def accept(user, date)
    accept_req = setup_http_request($dashboard, @cookie,{:url=>@accept_url})
    res = @http.request(accept_req)
    if res.code.to_i == 302
      r = res['location'].match(/\/dashboard\/trip-offer\/\d+\/passengers/)
      if r.length == 1 # success
        return true
      end
    end
    return false
  end

  def refuse(user, date, reason, comment)
    accept_req = setup_http_request($dashboard, @cookie,{:url=>@refuse_url, :arg => [@token, reason, comment]})
    res = @http.request(accept_req)
    if res.code.to_i == 302
      r = res['location'].match(/\/dashboard\/trip-offer\/\d+\/passengers/)
      if r.length == 1 # success
        return true
      end
    end
    return false
  end
end

# ValidationNotification
# When you have to confirm the trip with this person
class ValidationNotification < Notification
  attr_reader :user
  def prepare(data)
    @user = data.first.scan(/renseignez le code passager de (.*) pour recevoir/).flatten.first
  end

  def find_user_need_confirm(data)
    m = data.scan(/Vous avez voyag/)
    while t = m.shift do
      i = data.index(t)
      res = data[i..i+1000]
      if res.include?(@user)
        return res
      end
      data = data[i+1000..-1]
    end
  end

  def get_validation_confirmation(loc)
    get_form_confirm_req = setup_http_request($dashboard, @cookie,{:url=>loc})
    res = @http.request(get_form_confirm_req)
    body = res.body.force_encoding('utf-8')
    confirmed = body.scan(/<div class="pull-right bold green size16 uppercase">Confirm.e<\/div>\s*<span class="passenger-fullname">([^<]*)<\/span>/).flatten
    return confirmed.include?(@user)
  end

  # Confirm
  # if return true => success
  # if return false => wrong validation code
  # if return nil => the post request fails somewhere
  def confirm(code)
    dputs __method__.to_s
    get_confirm_req = setup_http_request($dashboard, @cookie, {:url=>@url})
    res = @http.request(get_confirm_req)
    loc = res['location']
    if res.code.to_i != 302 and not loc.start_with?("/dashboard/trip-offer/")
      eputs "Can't valid the trip.. Error somewhere."
      return nil
    end
    get_form_confirm_req = setup_http_request($dashboard, @cookie,{:url=>loc})
    res = @http.request(get_form_confirm_req)
    body = find_user_need_confirm(res.body.force_encoding('utf-8'))
    form_url = body.scan(/<form method="post" action="(\/seat-driver[^"]*)">/).flatten.first
    token = body.scan(/name="confirm_booking\[_token\]" value="([^"]*)" \/>/).flatten.first
    confirm_req = setup_http_request($trip_confirmation, @cookie, {:url => form_url, :arg => [code, token]})
    res = @http.request(confirm_req)
    # We get 302 code, and we have to request the first page in order to check if
    # the validation is "Confirmée"
    if res.code.to_i == 302
      return get_validation_confirmation(loc)
    end
    return nil
  end
end

# I choosed to set up a single Virement class, because I don't want to request multiple money transfer
# if I can do it in one time. "One request to get the all money baby"
class Virement < Notification
  attr_reader :total
  def prepare(data)
  end

  def initialize(http, cookie)
    super(http, cookie, ["",""])
    total_and_current
  end

  def available?
    @current
  end

  # Get money_ transfer status
  def status?
    dputs __method__.to_s
    money_req = setup_http_request($money_transfer_status, @cookie)
    res = @http.request(money_req)
    body = CGI.unescapeHTML(res.body.force_encoding('utf-8').gsub("<br />", ""))
    m = {}
    m[:who] = body.scan(/<li>([^<]*)<\/li>/).flatten
    m[:trip] = body.scan(/(.* &rarr; .*)<br\/>/).flatten.map{|c| c.gsub('&rarr;', '->').strip!}
    m[:status] = body.scan(/<td class="vertical-middle align-center .* span3">\s*(.*)\s*/).flatten.map{|c| c.gsub('<br/>','')}
    data = []
    0.step(m[:who].length-1,3) do |i|
      data << [m[:who][i], m[:who][i+1], m[:trip][i/3], m[:status][i/3]]
    end
    data
  end

  # Ask for the money transfer on my account
  def transfer
    dputs __method__.to_s
    money_req = setup_http_request($money_transfer, @cookie)
    res = @http.request(money_req)
    body = CGI.unescapeHTML(res.body.force_encoding('utf-8').gsub("<br />", ""))
    if body.scan(/<meta http-equiv="refresh" content="1;url=(\/dashboard\/account\/archived-transfer)" \/>/).flatten.first == "/dashboard/account/archived-transfer"
      return true
    end
    return false
  end

private
  def total_and_current
    dputs __method__.to_s
    money_req = setup_http_request($money, @cookie)
    res = @http.request(money_req)
    body = CGI.unescapeHTML(res.body.force_encoding('utf-8').gsub("<br />", ""))
    @total = body.scan(/Montant total reversé <span class="money-highlight size24 bold">(.*)<\/span>/).flatten.first
    @current = body.scan(/<p class="RequestMoney-available">Vous avez <strong>(.*)<\/strong> disponible.<\/p>/).flatten.first
  end
end

# AvisNotification
# When you have to send a comment about a person, if he/she was nice, etc.
class AvisNotification < Notification
  attr_reader :user
  def prepare(data)
    @user = data.first.scan(/laissez un avis . votre passager (.*)/).flatten.first
  end
  def send(status, note, comment, driver=nil)
    # click call_to_action
    req = setup_http_request($avis_req_get, @cookie, {:url => @url})
    res = @http.request(req)
    if not res['location']
      puts "Uh I'm not being redirected?... What a failure!"
      return nil
    end
    # on est redirigé
    loc = res['location']
    req = setup_http_request($avis_req_get, @cookie, {:url => loc})
    res = @http.request(req)
    url = res.body.scan(/<form class="[^"]*" action="(\/dashboard\/ratings\/.*)" method="POST"/).flatten.first
    token = res.body.scan(/<input type="hidden" id="rating__token" name="rating\[_token\]" value="([^"]*)" \/>/).flatten.first
    # post for previsualisation
    req = setup_http_request($avis_req_post, @cookie, {:url => url, :arg => [status, note, comment, token]})
    res = @http.request(req)
    if not res['location']
      puts "Uh I'm not being redirected?... What a failure!"
      return nil
    end
    req = setup_http_request($avis_req_get, @cookie, {:url => res['location']})
    res = @http.request(req)
    url = res.body.scan(/<form class="[^"]*" action="(\/dashboard\/ratings\/.*)" method="POST"/).flatten.first
    token = res.body.scan(/<input type="hidden" id="rating_preview__token" name="rating_preview\[_token\]" value="([^"]*)" \/>/).flatten.first
    req = setup_http_request($avis_req_post_confirm, @cookie, {:url => url, :arg => [token]})
    res = @http.request(req)
    File.open("/tmp/last.html", "w") do |f| f.write(res.body); end
    if not res['location']
      puts "Uh I'm not being redirected?... What a failure!"
      return nil
    end
    if res['location'].match(/\/dashboard\/ratings\/saved\/([^\/]+)/) or
      res['location'] == "/dashboard/ratings/hints"
      return true
    else
      eputs res['location']
      return false
    end
  end
  def send_as_driver(status, note, avis)
    send(status, note, avis)
  end
  def send_as_passenger(status, note, drive, avis)
    send(status, note, avis, drive)
  end
end

class Blablacar
  attr_reader :cookie, :messages, :notifications, :virement
  def initialize(verbose=nil, debug=nil)
    url = URI.parse("https://www.blablacar.fr/")
    if debug
      proxy = Net::HTTP::Proxy("127.0.0.1", 8080)
      @http = proxy.start(url.host, url.port, :use_ssl => true,
                          :verify_mode => OpenSSL::SSL::VERIFY_NONE)
    else
      @http = Net::HTTP.new(url.host, url.port)
      @http.use_ssl = true
    end
    @cookie = nil
    @messages = 0
    @notifications = []
    @virement = nil
    $VERBOSE = verbose
    $DDEBUG = debug
    @authenticated = nil
    @dashboard = nil
  end

  def authenticated?
    @authenticated
  end

  def messages?
    return @messages
  end

  def notifications?
    return true if @notifications.length > 0
    return false
  end

  # return array : ["msg", "URL to request"]
  def notifications
     @notifications
  end

  # Parse header in order to get the cookie
  def get_cookie(data)
    if data['Set-Cookie']
      # don't by shy, let's take every cookie...
      t = data['Set-Cookie'].scan(/([a-zA-Z0-9_\-\.]*=[^;]*)/).flatten
      t.delete_if{|c| c.start_with?("path")}
      t.delete_if{|c| c.start_with?("expires")}
      if t.length == 1
        @cookie = @cookie + t.first
      else
        #if @cookie
        #  puts "coin"
        #  c = @cookie.split(";").map{|c| c.strip}
        #  puts "+"*20
        #  @cookie = (c | t).join("; ")
        #else
          @cookie = t.join("; ")
        #end
      end
      #puts @cookie
    end
  end

  # (Step1) Get tracking cookie don't know why it's so important
  def get_cookie_tracking
    dputs __method__.to_s
    track_req = setup_http_request($tracking, @cookie)
    res = @http.request(track_req)
    get_cookie(res)
  end

  # (Step2) Post id/passwd to the send_credentials web page
  def send_credentials
    dputs __method__.to_s
    $ident[:data] = $ident[:data] % {:user => $CONF['user'], :pass => $CONF['pass']}
    login_req = setup_http_request($ident, @cookie)
    res = @http.request(login_req)
    get_cookie(res)
  end

  def check_conf
    ['user', 'pass', 'cookie'].map{|i|
      if not $CONF.keys.include?(i)
        aputs "Configuration error: key #{i} not found"
        exit 2
      end
      if not $CONF[i]
        aputs "Configuration error: key #{i} is empty"
        exit 2
      end
    }
  end

  def load_conf(file=nil)
    f = file || File.join(ENV['HOME'], '.blablacar.rc')
    begin
      $CONF = YAML.load_file(f)
    rescue Errno::ENOENT => e
      eputs(e.message)
      exit 2
    end
  end

  # Let's get authenticated
  def authentication
    # Step 1: We need cookie tracking :(
    get_cookie_tracking
    (aputs "Can't get Cookie tracking"; exit 1) if not @cookie
    dputs "Get the cookie tracking: (#@cookie)"
    # Step 2: Post send_credentials id/passwd and get authenticated cookie
    # the cookie is the same name as previous, but the value is updated
    send_credentials()
    (aputs "Can't get Cookie send_credentials"; exit 2) if not @cookie
  end


  # Step 3: Access to the dashboard
  def get_dashboard
    dashboard_req = setup_http_request($dashboard, @cookie)
    res = @http.request(dashboard_req)
    if res.code=='400' or res['location'] == "https://www.blablacar.fr/identification"
      raise AuthenticationFailed, "Can't get logged in"
    end
    res.body.force_encoding('utf-8')
  end

  def list_trip_offers(body, ind=0)
    trips = {}
    ts = body.scan(/"\/dashboard\/trip-offer\/(\d*)\/passengers" class=/).flatten
    stats = body.scan(/visit-stats">Annonce vue (\d+) fois<\/span>/).flatten
    ts.each_with_index do |v, i|
      trips[ind + i] = {:trip => v, :stats => stats[i]}
    end
    trips
  end

  # Get all trip's offers id
  def get_trip_offers
    dputs __method__.to_s
    trip_offer_req = setup_http_request($tripoffers, @cookie, {:arg => [1]})
    res = @http.request(trip_offer_req)
    trips = {}
    trips = list_trip_offers(res.body)
    pages = res.body.scan(/<a href="\/dashboard\/trip-offers\/active\?page=(\d*)/).flatten.uniq
    pages.map{|p|
      trip_offer_req = setup_http_request($tripoffers, @cookie, {:arg => [p]})
      res = @http.request(trip_offer_req)
      trips = trips.merge(list_trip_offers(res.body, trips.length))
    }
    trips
  end

  def parse_trip(data)
    res = CGI.unescapeHTML(data.force_encoding('utf-8'))
    t={}
    t[:trip] = res.scan(/<h2 class="pull-left">\s(.*)\s*<\/h2>/).flatten.map{|c| c.strip!}.first.gsub("&rarr;", "->")
    t[:when] = parse_time(res.scan(/<p class="my-trip-elements size16 push-left no-clear my-trip-date">\s(.*)\s*<\/p>/).flatten.map{|c| c.strip!}.first)
    t[:who] = res.scan(/<a href="\/membre\/profil\/.*" class="blue">\s*(.*)\s*<\/a>/).flatten.map{|c| c.strip!}
    t[:note] = res.scan(/<span class="bold dark-gray">(.*)<\/span><span class="fade-gray">/).flatten
    t[:phone] = res.scan(/<span class="mobile*">(.*)<\/span>/).flatten
    t[:place] = res.scan(/<li class="passenger-seat">(\d) place[s]?<\/li>/).flatten
    t[:status] = res.scan(/<div class="pull-right bold (?:green|dark-gray) size16 uppercase">(.*)<\/div>/).flatten
    t[:actual_trip] = res.scan(/<ul class="unstyled passenger-trip size17">\s*<li>\s([a-zA-Zé\ \-]*)\s*<\/li>/).flatten.map{|c| c.strip!;c.gsub!(" - ", " -> ")}

    # Insert blanck phone number
    tmp = t[:status].dup
    1.upto(t[:status].count("annulée")).map do |x|
      i = tmp.find_index("annulée")
      tmp = t[:status][i+1..-1].dup
      t[:phone].insert(i, nil)
    end
    t
  end

  # Display all passengers for all the future trips
  def get_planned_passengers
    dputs __method__.to_s
    _trips = get_trip_offers()
    m="Parsing (on #{_trips.length}): "
    print m
    trips = {}
    _trips.map{|i, t|
      id = t[:trip]
      print i
      trip_req = setup_http_request($trip, @cookie, {:arg => [id]})
      res = @http.request(trip_req)
      p = parse_trip(res.body)
      trips[id] = p
      trips[id][:stats] = t[:stats]
      print 0x08.chr * i.to_s.length
    }
    print 0x08.chr * m.length
    # Sort by date
    trips = Hash[trips.sort_by{|k, v| v[:when]}]
    trips
  end

  # Get private messages from link
  def get_private_conversations(url, check=nil)
    dputs __method__.to_s
    messages_req = setup_http_request($messages, @cookie, {:url => url})
    res = @http.request(messages_req)
    body = CGI.unescapeHTML(res.body.force_encoding('utf-8').gsub("<br />", ""))
    urls = body.scan(/<form id="qa"\s*class="[^"]*"\s*action="(\/messages\/respond\/[^"]*)"\s*method="POST"/).flatten
    trip = body.scan(/<a href="\/trajet-[^"]*" rel="nofollow">\s*(.*)\s*<\/a>/).flatten.first # PRIVATE
    trip, trip_date = trip.split(",") # PRIVATE
    ret = Array.new
    u = 0
    urls.map{|t|
      ind = body.index(t)+2000
      body_ = body[u..ind]
      u = ind
      token = body_.scan(/message\[_token\]" value="([^"]*)" \/>/).flatten.first
      users = body_.scan(/<h4>\s*<strong>\s*([^:]*) :\s*<\/strong>\s*<\/h4>/).flatten # PRIVATE
      msgs = body_.scan(/<\/h4>\s*<p>"([^"]*)"<\/p>/).flatten # PRIVATE
      msg_hours = body_.scan(/<p class="msg-date clearfix">\s*([^<]*)\s*</).flatten.map{|m| m.strip.chomp} # PRIVATE
      tmp = {:msg_user => users.first, :url => t, :token => token, :trip_date => trip_date, :trip => trip}
      tmp[:msgs] = []
      0.upto(msgs.length-1).map{|id|
        if users[id].include?("Greg C")
          # When I have already responded
          #  d = "[%s] %s" % [msg_hours[id], msgs[id].split(":").first]
          #  d.strip!
          if check
             m = msgs[id].split(":")[1..-1].join(":")
            ret << m.strip!
          end
        else
          if not check
            #ret << {:msg_user => users[id], :msg => {:msg_date => msg_hours[id], :msg => msgs[id].gsub("\r\n", ' ').gsub("\n", " "), :trip => trip, :trip_date => trip_date, :url => t, :token => token}
            next if msgs[id] == nil
            tmp[:msgs] << {:msg_date => msg_hours[id], :msg => msgs[id].gsub("\r\n", ' ').gsub("\n", " ")}
          end
        end
      }
      ret << tmp
    }
    ret
  end

  # Get public messages from link
  def get_public_conversations(url, check=nil)
    dputs __method__.to_s
    messages_req = setup_http_request($messages, @cookie, {:url => url})
    res = @http.request(messages_req)
    body = CGI.unescapeHTML(res.body.force_encoding('utf-8').gsub("<br />", ""))
    lastindex = body.index('Questions sur les autres portions du trajet')
    if lastindex
      body = body[0..lastindex]
    end
    # looking for uniq value for each discussion (url to respond to)
    urls = body.scan(/<form id="qa"\s*class="[^"]*"\s*action="(\/messages\/respond\/[^"]*)"\s*method="POST"/).flatten
    trip_date = body.scan(/<strong class="RideDetails-infoValue">\s*<i class="bbc-icon2-calendar" aria-hidden="true"><\/i>\s*<span>\s*(.*)\s*<\/span>\s*<\/strong>/).flatten.first
    ret = Array.new
    u = 0
    urls.map{|t|
      ind = body.index(t)+2000
      body_ = body[u..ind]
      u = ind
      token = body_.scan(/message\[_token\]" value="([^"]*)" \/>/).flatten.first
      users = body_.scan(/<a href="\/membre\/profil\/[^"]*" class="u-(?:darkGray)?(?:blue)?">([^<]*)<\/a>/).flatten
      msgs = body_.scan(/<\/span><\/span>\)<\/span>\s*<\/h3>\s*<p>([^<]*)<\/p>/).flatten
      msg_hours = body_.scan(/<time class="Speech-date" datetime="[^"]*">([^<]*)<\/time>/).flatten
      trips = body_.scan(/<span class="Ridename RideName--small">\(<span class="RideName-mainTrip"><span class="RideName-location RideName-location--arrowAfter">(.*)<\/span><span class="RideName-location">(.*)<\/span><\/span>\)/).flatten
      trip = (0..trips.length-1).step(2).map{|c| "#{trips[c]}->#{trips[c+1]}"}.first
      tmp = {:msg_user => users.first, :url => t, :token => token, :trip_date => trip_date, :trip => trip}
      tmp[:msgs] = []
      0.upto(msgs.length-1).map{|id|
        if users[id].include?("Greg C")
          # When I have already responded
          #  d = "[%s] %s" % [msg_hours[id], msgs[id].split(":").first]
          #  d.strip!
          if check
             m = msgs[id].split(":")[1..-1].join(":")
            ret << m.strip!
          end
        else
          if not check
            #ret << {:msg_user => users[id], :msg => {:msg_date => msg_hours[id], :msg => msgs[id].gsub("\r\n", ' ').gsub("\n", " "), :trip => trip, :trip_date => trip_date, :url => t, :token => token}
            next if msgs[id] == nil
            tmp[:msgs] << {:msg_date => msg_hours[id], :msg => msgs[id].gsub("\r\n", ' ').gsub("\n", " ")}
          end
        end
      }
      ret << tmp
    }
    ret
  end

  def respond_to_question(url, token, resp)
    dputs __method__.to_s
    messages_req = setup_http_request($respond_to_message, @cookie, {:url => url, :arg => [resp, token]})
    res = @http.request(messages_req)
    body = CGI.unescapeHTML(res.body.force_encoding('utf-8'))
    # Checking...
    if res.code == "302"
      found = false
      # Should not be a problem calling public instead private or other way
      get_public_conversations(res['location']).map{|m|
        m[:msgs].map{|c| found = true if c[:msg].include?(resp)}
        if found
          return true
        end
      }
      return false
    end
    raise SendReponseMessageFailed, "Cannot received expected 302 code..."
  end

  # body: current HTML code
  # _private: look for private message
  # all: look for every messages, not only unread messages
  def messages_parsing(body, _private=nil, all=nil)
    term = "/trajet-"
    term = "\\/messages\\/private" if _private
    File.open("/tmp/body_#{_private.to_s}_#{rand(0..12)}.html", "w") do |f| f.write body; end
    if not all
      unread = nil
      index = body.index(/<li class="unread">\s*<a href="#{term}/)
      return [] if not index # means no unread message
      body = CGI.unescapeHTML(body[0..index+200])
    else
      body = CGI.unescapeHTML(body)
    end
    urls = body.scan(/<a href="(#{term}[^"]*)"/).flatten
    urls
  end

  # Get public/private message link
  #
  def get_messages_link_and_content(all=nil)
    dputs __method__.to_s
    urls = {:public => [], :private => []}
    # public messages
    message_req = setup_http_request($messages, @cookie)
    res = @http.request(message_req)
    urls[:public] = messages_parsing(res.body.force_encoding('utf-8'), nil, all)
    # private messages
    message_req = setup_http_request($private_messages, @cookie)
    res = @http.request(message_req)
    urls[:private] = messages_parsing(res.body.force_encoding('utf-8'), true, all)
    msgs = {:public => [], :private => []}
    until urls.empty?
      k, uu = urls.shift
      next if uu == nil
      # Set get_public_conversations / get_private_conversations dynamically
      f = self.method("get_#{k.to_s}_conversations")
      uu.map{|u|
        f.call(u).map do |m|
          next if not m
          msgs[k] << m
        end
      }
    end
    # ex: {:public => [{:msg=>["[Aujourd'hui à 09h48] Miguel  L : \"BONJOUR  GREG  vous  arrive jusque  a la  gare pardieu\"", "..."], :url=>"/messages/respond/kAxP4rA...", :token => "XazeAFsdf..."}], :private => [{:msg => ...}]
    return msgs
  end

  def get_new_messages
    get_messages_link_and_content
  end

  # TODO ?
  def get_all_messages
    get_messages_link_and_content(true)
  end

  def get_opinion(page=1)
    if page.empty?
      page=1
    end
    dputs __method__.to_s
    req = setup_http_request($rating_received, @cookie, {:arg => [page]})
    res = @http.request(req)
    ret = CGI.unescapeHTML(res.body.force_encoding('utf-8')).scan(/<h3 class="Rating-grade Rating-grade--\d">(.*)<\/h3>\s*<p class="Rating-text"><strong>(.*): <\/strong>(.*)<\/p>\s*<\/div>\s*<footer class="Speech-info">\s*<time class="Speech-date" datetime="[^"]*">(.*)<\/time>/)
    ret
  end

  def search_trip(city_start, city_end, date)
    dputs __method__.to_s
    req = setup_http_request($search_req, @cookie, {:arg => [city_start, city_end, date]})
    res = @http.request(req)
    res=JSON.parse(res.body)['html']['results'].force_encoding('utf-8')
    results = []
    url = res.scan(/<meta itemprop="url" content="([^>]*)">/)
    user = res.scan(/<div class="user-info">\s*<h2 class="username">(.*)<\/h2>\s*/)#(.*)<br \/>\s*<\/div>/)
    prefs = res.scan(/ <div class=\"preferences-container\">\s*((?:<span class="[^ ]* prefs tip" title=".*"><\/span>)*)\s*((?:<span class="[^ ]* prefs tip" title=".*"><\/span>)*)\s*((?:<span class="[^ ]* prefs tip" title=".*"><\/span>)*)\s*((?:<span class="[^ ]* prefs tip" title=".*"><\/span>)*)/)
    trip_time = res.scan(/<h3 class="time light-gray" itemprop="startDate" content="([^"]*)">(.*)<\/h3>/)
    trip = res.scan(/<span class="from trip-roads-stop">(.*)<\/span>\s*<span class="arrow-ie">.*<\/span>\s*<span class="trip-roads-stop">([^<]*)<\/span>/)
    start = res.scan(/<dd class="tip" title="D.part">\s*(.*)\s*<\/dd>/)
    stop = res.scan(/<dd class="tip" title="Arriv.e">\s*(.*)\s*<\/dd>/)
    car = res.scan(/<dd class="tip" title="Arriv.e">\s*.*\s*<\/dd>\s*<\/dl>\s*((?:<dl class="car-type" [^>]*>\s*<dt>V.hicule : <strong>.*<\/strong><\/dt>)){0,1}/)
    #car = res.scan(/Véhicule : <strong>(.*)<\/strong><\/dt>/)
    place = res.scan(/<div class="availability">\s*<strong>(.*)<\/strong>((?: <span>.*<\/span>){0,1})/)
    url.each_with_index{|u, ind|
      results[ind] = {
        :url => u.first,
        :user => user[ind].first,
        :preferences => prefs[ind].map{|p| p.scan(/<span class=".*" title="(.*)"><\/span>/)}.flatten,
        :time => trip_time[ind].join(" "),
        :trip => trip[ind].join(" -> "),
        :start => start[ind].first,
        :stop => stop[ind].first,
        :car => car[ind].first ==nil ? "no info" : car[ind].first.scan(/hicule : <strong>(.*)<\/strong>/).flatten.first,
        :place => place[ind].first=="Complet" ? "Complet" : "%s disponible(s)"%place[ind].first
      }
    }
    results
  end

  def parse_dashboard
    dputs __method__.to_s
    # Don't need to parse the all page to get message received...
    msg = @dashboard[0..35000].scan(/"\/messages\/received" rel="nofollow">\s*<span class="badge-notification">(\d+)<\/span>\s*<span class="visually-hidden">[^<]*<\/span>/).flatten.first
    tmp =@dashboard.scan(/class="text-notification-container">\s*<p>\s*(?:<strong>)?(.*)(?:<\/strong>\s*<br\/>)?\s*.*\s*<\/p>\s*<\/div>\s*<div class="btn-notification-container">\s*<a href="(\/dashboard\/notifications\/.*)" class="btn-validation">\s*.*\s*<\/a>/).map{|c| c if not c[1].include?("virement")}.delete_if{|c| c==nil}.map{|c| [c[0],c[1]]}
    tmp.map{|t|
      ret = parse_notifications(t)
      @notifications << ret if ret
    }
    @virement = Virement.new(@http, @cookie)
    if msg == "Aucun message"
      @messages = 0
    else
      @messages = msg.to_i
    end
  end

  def parse_notifications(data)
    if data.first.include?("renseignez le code passager de")
      return ValidationNotification.new(@http, @cookie, data)
    end
    if data.first.include?("laissez un avis")
      return AvisNotification.new(@http, @cookie, data)
    end
    if data.first.include?("argent disponible")
      return nil
    end
    if data.first.include?("Demande de réservation de")
      return AcceptationNotification.new(@http, @cookie, data)
    end
  end


  # Main function
  def run(conf=nil)
    load_conf(conf)
    check_conf()
    if local_cookie?
      vputs "Using existing cookie"
      @cookie = File.read($CONF['cookie'])
    else
      authentication()
    end

    @dashboard = nil
    begin
      @dashboard = get_dashboard
      save_cookie(@cookie)
    rescue AuthenticationFailed
      vputs "Cookie no more valid. Get a new one"
      @cookie = nil
      authentication()
      retry
    end
    @authenticated = true
  end
end
