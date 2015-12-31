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
require 'consts'
require 'requests'
require 'errors'
$CONF = nil

# Save authenticated cookie on disk
#
# @param cookie [String] Cookie's content
def save_cookie(cookie)
  dputs __method__.to_s
  File.open($CONF['cookie'], "w") do |fc|
    fc.write(cookie)
  end
end

# Check if there is cookie on disk
#
# @return [Boolean] true if success false if not
def local_cookie?
  if File.exist?($CONF['cookie'])
    return true
  end
  false
end

# Parse given time into Time object (specially when 'Demain' is used)
#
# @param tt [String] time of a trip generally
# @return [Time] Parsed time
def parse_time(tt)
  tt = tt.force_encoding('utf-8')
  MONTHS.map{|k,v|
    tt.gsub!(/ #{k}/i, " #{v.downcase}")
  }
  case tt
    when /Demain.*/
      t = Time.parse(tt)+60*60*24
    else
      t = Time.parse(tt)
  end
  return t
end

# Set up the HTTP request object to avoid duplicated code
#
# @param obj [Variable] Variable containing Net::HTTP object
# @param cookie [String] Cookie's content to use for this request
# @param args [Hash] Data to add to the request (to the url or in POST request)
# @return [Net] The complete Net::HTTP object
def setup_http_request(obj, cookie=nil, args={})
  if args.has_key?(:url)
    if args[:url].scan(/%[s|d]/).length > 0
      if args[:url].scan(/%[s|d]/).length != args[:arg].length
        aputs "URL contains %d '%%s' or '%%d' argument... Fix your code" % args[:url].scan(/%[s|d]/).length
        aputs __callee__
        exit 2
      end
      req = obj[:method].new(args[:url] % args[:arg])
    else
      req = obj[:method].new(args[:url])
    end
  else
    if args.has_key?(:arg)
      if obj[:url].scan(/%[s|d]/).length > 0
        if obj[:url].scan(/%[s|d]/).length != args[:arg].length
          aputs "URL contains %d '%%s' or '%%d' argument... Fix your code" % obj[:url].scan(/%[s|d]/).length
          aputs __callee__
          exit 2
        end
        req = obj[:method].new(obj[:url] % args[:arg])
      else
        req = obj[:method].new(obj[:url])
      end
    else
      req = obj[:method].new(obj[:url])
    end
  end
  req["Host"] = "www.blablacar.fr"
  req["origin"] = "https://www.blablacar.fr"
  req["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64; rv:18.0) Gecko/20100101 Firefox/18.0"
  req["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
  if obj.has_key?(:referer)
    req['Referer'] = obj[:referer]
  else
    req["Referer"] = "https://www.blablacar.fr/dashboard"
  end
  req.add_field("Connection", "keep-alive")
  if cookie
    req.add_field("Cookie", cookie)
  end
  if obj.has_key?(:header)
    req.add_field(obj[:header][0], obj[:header][1])
  end
  if obj.has_key?(:data)
    if obj[:data].scan(/%[s|d]/).length > 0
      if obj[:data].scan(/%[s|d]/).length != args[:arg].length
        aputs "URL contains %d '%%s' or '%%d' argument... Fix your code" % args[:url].scan(/%[s|d]/).length
        aputs __callee__
        exit 2
      else
        req.body = obj[:data] % args[:arg]
      end
    else
      req.body = obj[:data]
    end
    req['Content-Length'] = req.body.length
  end
  req
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
  # Get the name of the user who get the reservation
  #
  # @param data [String] HTTP response body 
  def prepare(data)
    @user = data.first.scan(/Demande de réservation de (.*)/).flatten.first
    parse()
  end

  # Parse the HTTP response body to get some links like cancellation, acceptation, etc.
  #
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

  # Accept the user for a trip
  #
  def accept
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

  # Refuse the user for a trip
  #
  # @param reason [String] Reason why you refuse the user (between defined reasons)
  # @param comment [String] More precise comment (free)
  # @return [Boolean] True if success or Else if failed
  def refuse(reason, comment)
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
  # Save the user who made the trip with us
  #
  # @param data [String] HTTP response body 
  def prepare(data)
    @user = data.first.scan(/renseignez le code passager de (.*) pour recevoir/).flatten.first
  end

  # Get the list of all user we drove with
  #
  # @param data [String] HTTP response body
  # @return [String] Stripped HTTP response body
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

  # Confirm the validation
  #
  # @param loc [String] URL
  # @return [Boolean] Return true if the confirmation includes the username
  def get_validation_confirmation(loc)
    get_form_confirm_req = setup_http_request($dashboard, @cookie,{:url=>loc})
    res = @http.request(get_form_confirm_req)
    body = res.body.force_encoding('utf-8')
    confirmed = body.scan(/<div class="pull-right bold green size16 uppercase">Confirm.e<\/div>\s*<span class="passenger-fullname">([^<]*)<\/span>/).flatten
    return confirmed.include?(@user)
  end

  # Validate the trip
  #
  # @param code [String] Validation code given by the passenger after the trip
  # @return [Boolean] true if succeed, false if validation code if bad, nil if the request failed
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
    if not body
      raise ValidateTripError, "User not found"
    end
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

  # Get money transfer status
  #
  # @return [String] Who
  # @return [String] Seats taken
  # @return [String] Trip
  # @return [String] Transfer status
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

  # Request the money transfer on my account
  #
  # @return [Boolean] true if succeed, false either
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
  # Get the total amount of money already transfer and the current amount available
  #
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

  # Get the name of the person who made a trip with us
  #
  # @param data [String] HTTP response body
  def prepare(data)
    @user = data.first.scan(/laissez un avis . votre passager (.*)/).flatten.first
  end

  # Generic method to send an avis about the driver/passenger
  #
  # @param status [String] P for passenger, D for Driver
  # @param note [String] The note we gave him (recommendation)
  # @param comment [String] The comment we want to left him
  # @param driver [Boolean] # to complete, how this driver drives ?
  # @return [Boolean] true if everything was fine, false either. nil if something was wrong.
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

  # Send an avis about the passenger
  #
  # @param status [String] P for passenger, D for Driver
  # @param note [String] The note we gave him (recommendation)
  # @param avis [String] The comment we want to left about how he was during the trip
  # @return [Boolean] true if everything was fine, false either. nil if something was wrong.
  def send_as_driver(status, note, avis)
    send(status, note, avis)
  end
  
  # Send an avis about the driver
  #
  # @param status [String] P for passenger, D for Driver
  # @param note [String] The note we gave him (recommendation)
  # @param drive [String] The comment we want to left about how he drove
  # @param avis [String] The comment we want to left about how he was during the trip
  # @return [Boolean] true if everything was fine, false either. nil if something was wrong.
  def send_as_passenger(status, note, drive, avis)
    send(status, note, avis, drive)
  end
end

# Main class, everything is in here \o/
class Blablacar
  attr_reader :cookie, :messages, :notifications, :virement
  # Initialize the Blablacar class
  #
  # @param verbose [Boolean] Activate the verbose mode (need improvement)
  # @param debug [Boolean] Activate the debug mode (proxify all requests through 127.0.0.1:8080)
  def initialize(verbose=nil, debug=nil)
    url = URI.parse("https://www.blablacar.fr/")
    if debug
      proxy = Net::HTTP::Proxy("127.0.0.1", 8080)
      @http = proxy.start(
                  url.host,
                  url.port,
                  :use_ssl => true,
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
    @messages
  end

  def notifications?
    return (@notifications.length > 0) ? true : false
  end

  def notifications
     @notifications
  end

  # Update current cookie
  def update_cookie(data)
    if data['set-cookie']
      # don't by shy, let's take every cookie...
      t = data['set-cookie'].scan(/([a-zA-Z0-9_\-\.]*=[^;]*;)/).flatten
      t.delete_if{|c| c.start_with?("path=")}
      t.delete_if{|c| c.start_with?("expires=")}
      t.map{|tt|
        if not @cookie.include?(tt)
          @cookie = @cookie + tt
        end
      }
    end
  end

  # Parse header in order to get the cookie and save it for the next futures requests
  #
  # @param data [Net::HTTPResponse] Net::HTTPResponse object containing HTTP headers
  def get_cookie(data)
    if data['set-cookie']
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

  # (Authentication Step1) Get tracking cookie don't know why it's so important
  def get_cookie_tracking
    dputs __method__.to_s
    track_req = setup_http_request($tracking, @cookie)
    res = @http.request(track_req)
    get_cookie(res)
  end

  # (Authentication Step2) Post id/passwd to the send_credentials web page
  def send_credentials
    dputs __method__.to_s
    $ident[:data] = $ident[:data] % {:user => $CONF['user'], :pass => $CONF['pass']}
    login_req = setup_http_request($ident, @cookie)
    res = @http.request(login_req)
    get_cookie(res)
  end

  # Check the configuration file and set up constants
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

  # Load the configuration file into $CONF constant
  #
  # @param file [String] Path to the configuration file
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

  # (Authentication Step 3) Try to access to the dashboard
  def get_dashboard
    dashboard_req = setup_http_request($dashboard, @cookie)
    res = @http.request(dashboard_req)
    if res.code=='400' or res['location'] == "https://www.blablacar.fr/identification"
      raise AuthenticationError, "Can't get logged in"
    end
    res.body.force_encoding('utf-8')
  end

  # List all trip we created
  #
  # @param body [String] Net::HTTPResponse body
  # @return [Hash] Hash with those keys: :trip, :stats, :date, :duplicate
  def list_trip_offers(body)
    trips = {}
    ts = body.scan(/"\/dashboard\/trip-offer\/(\d*)\/passengers" class=/).flatten
    stats = body.scan(/visit-stats">Annonce vue (\d+) fois<\/span>/).flatten
    dates = body.scan(/<p class="my-trip-elements size16 push-left no-clear my-trip-date">\s*(.*)\s*<\/p>/).flatten
    duplicate = body.scan(/<input type="hidden" id="publication_duplicate_\d+__token" name="publication_duplicate_\d+\[_token\]" value="([^"]+)" \/>/).flatten
    ts.each_with_index do |v, i|
      trips[v] = {:trip => v, :stats => stats[i], :date => dates[i], :duplicate => duplicate[i]}
    end
    trips
  end

  # Get all trip's offers id
  #
  # @param active [Boolean] If true get only future trips, if not, get old passed trip too
  # @return (see #list_trip_offers)
  def get_trip_offers(active=true)
    dputs __method__.to_s
    if active
      trip_offer_req = setup_http_request($active_trip_offers, @cookie, {:arg => [1]})
    else
      trip_offer_req = setup_http_request($inactive_trip_offers, @cookie, {:arg => [1]})
    end
    res = @http.request(trip_offer_req)
    #update_cookie(res)
    trips = {}
    trips = list_trip_offers(CGI.unescapeHTML(res.body.force_encoding("utf-8")))
    pages = res.body.scan(/<a href="\/dashboard\/trip-offers\/active\?page=(\d*)/).flatten.uniq
    pages.map{|p|
      trip_offer_req = setup_http_request($active_trip_offers, @cookie, {:arg => [p]})
      res = @http.request(trip_offer_req)
      trips = trips.merge(list_trip_offers(res.body))
    }
    trips
  end

  # Get all trip's offers id
  #
  # @return (see #get_trip_offers)
  def get_active_trip_offers
    get_trip_offers(active=true)
  end

  # Get all trip's offers id
  #
  # @return (see #get_trip_offers)
  def get_inactive_trip_offers
    get_trip_offers(active=false)
  end

  # Parse trip Web page in order to extract every needed information
  #
  # @param data [String] Net::HTTPResponse body
  # @return [Hash] Hash with those keys: :trip, :when, :seat_url, :seats, :who, :note, :phone, :seat_taken, :status, :actual_trip
  def parse_trip(data)
    res = CGI.unescapeHTML(data.force_encoding('utf-8'))
    t={}
    t[:trip] = res.scan(/<h2 class="pull-left">\s(.*)\s*<\/h2>/).flatten.map{|c| c.strip!}.first.gsub("&rarr;", "->")
    t[:when] = parse_time(res.scan(/<p class="my-trip-elements size16 push-left no-clear my-trip-date">\s(.*)\s*<\/p>/).flatten.map{|c| c.strip!}.first)
    t[:seat_url] = res.scan(/<form action="(\/dashboard\/trip\/\d+\/_seatCount\?token=[^"]+)/).flatten.first
    t[:seats] = res.scan(/(?:<input type="text" name="count" class="nb-seats" data-booking-enabled="\d+" data-value-warning="\d+" data-number-min="\d+" data-number-max="\d+" value="(\d+)")/).flatten.first
    t[:who] = res.scan(/<a href="\/membre\/profil\/.*" class="blue">\s*(.*)\s*<\/a>/).flatten.map{|c| c.strip!}
    t[:note] = res.scan(/<span class="bold dark-gray">(.*)<\/span><span class="fade-gray">/).flatten
    t[:phone] = res.scan(/<span class="mobile*">(.*)<\/span>/).flatten
    t[:seat_taken] = res.scan(/<li class="passenger-seat">(\d) place[s]?<\/li>/).flatten
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

  # Get all passengers for all the future trips
  #
  # @return (see #parse_trip)
  def get_planned_passengers
    dputs __method__.to_s
    _trips = get_active_trip_offers()
    m="Parsing (on #{_trips.length}): "
    print m
    trips = {}
    _trips.each_with_index{|t,i|
      id = t.first
      t = t[1]
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
  # @todo Maybe could be merged with get_public_conversations
  # @param url [String] URL to request
  # @todo -> check [Boolean] ? Get our response too ?
  # @return [Array] Array of Hash. Hash containing those keys: :msgs_user, :url, :token, :trip_date, :trip, :msgs
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
  # @todo Maybe could be merged with get_private_conversations
  # @param (see #get_private_conversations)
  # @return (see #get_private_conversations)
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
    trip_date = body.scan(/<strong class="RideDetails-infoValue">\s*<i class="bbc-icon2-calendar" aria-hidden="true"><\/i>\s*<span>\s*(.*)\s*/).flatten.first
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

  # Reponse back to a question
  #
  # @param url [String] URL to response to
  # @param token [String] Uniq token to use in order to response to the question
  # @param resp [String] The response message
  # @return [Boolean] true if succeed, false if failed. Could raise on error if something wrong on the network
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
    raise SendReponseMessageError, "Cannot received expected 302 code..."
  end

  # Parse the message web page to get unread message
  #
  # @param body [String] Net::HTTPResponse body
  # @param _private [Boolean] If true, look for private message
  # @param all [Boolean] If true, look for every messages, not only unread messages
  # @return [Array] Array of URL
  def messages_parsing(body, _private=nil, all=nil)
    term = "/trajet-"
    term = "\\/messages\\/private" if _private
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
  # @param all [Boolean] If true get our response too 
  # @return [Hash] Hash of Array. Keys are :public, :private. Each contains an array of Hash (see #get_private_conversations)
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

  # Get ony new messages
  #
  # @return (see #get_messages_link_and_content)
  def get_new_messages
    get_messages_link_and_content
  end

  # @todo try it, test it, commit it (Get all messages (unread or not))
  #
  # @return (see #get_messages_link_and_content)
  def get_all_messages
    get_messages_link_and_content(true)
  end

  # Get opinion people left us
  #
  # @param page [FixNum] Target page
  # @return [Array] Array of Array
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

  # Search for a trip # Need work on it...
  #
  # @param city_start [String] Where do you wanna to get pickup ?
  # @param city_end [String] Where do you wanna go ?
  # @param date [String] When do you wanna leave ?
  # @return [Array] Array of array
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

  # Parse the dashboard web page
  #
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

  # Get the notifications
  #
  # @param data [String] Net::HTTPResponse body
  # @return [Notification] Could be ValidationNotification, AvisNotification, AcceptationNotification or nil
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
  #
  # @param conf [String] This is the configuration file .rc
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
    rescue AuthenticationError
      vputs "Cookie no more valid. Get a new one"
      @cookie = nil
      authentication()
      retry
    end
    @authenticated = true
  end

  # Update the total seats for a trip
  #
  # @param trip_date [Time] The trip you wanna update
  # @param seat [FixNum] The number of seats in the car
  # @return [Boolean] If succeed true, false either
  def update_seat(trip_date, seat)
    dputs __method__.to_s
    trips = get_trip_offers()
    d = parse_time(trip_date)
    t_id = nil
    trips.keys.map{|k|
      if d == parse_time(trips[k][:date])
        t_id = trips[k][:trip]
        break
      end
    }
    #We did not find the trip
    if not t_id
      raise UpdateSeatError, "Trip not found"
    end
    trip_req = setup_http_request($trip, @cookie, {:arg => [t_id]})
    res = @http.request(trip_req)
    p = parse_trip(res.body)
    req = setup_http_request($update_seat_req, @cookie, {:url => p[:seat_url], :arg => [seat.to_i]})
    res = @http.request(req)
    # json return
    body = JSON.parse(res.body) #{"status":"OK","value":0}
    if body['status'] == "OK" and body["value"] == seat.to_i
      return true
    else
      return false
    end
  end

  # Duplicate a trip (city start, city end, hour and description)
  #
  # @param date_src [Time] The trip you wanna duplicate
  # @param date_dst_departure [Time] The date you wanna set up the trip
  # @param date_dst_return [Time] The date of the return # need working on it
  # @return [Boolean] truf if succeed, else raise DuplicateTripError
  def duplicate(date_src, date_dst_departure, date_dst_return=nil)
    match = nil
    indx = nil
    [get_active_trip_offers, get_inactive_trip_offers].each_with_index{|results, ind|
      res = results.select{|t_id, t_values| parse_time(t_values[:date]) == parse_time(date_src)}
      if res.length > 0
        match = res[res.keys.first]
        indx = ind
        break
      end
    }
    if not match
      raise DuplicateTripError, "Trip to duplicate not found"
    end
    data = []
    data << CGI.escape("publication_duplicate_#{match[:trip]}[departureDate][date]") + "=" + parse_time(date_dst_departure).strftime("%d/%m/%Y")
    data << CGI.escape("publication_duplicate_#{match[:trip]}[departureDate][time][hour]") + "=" + parse_time(date_dst_departure).strftime("%H").to_i.to_s
    data << CGI.escape("publication_duplicate_#{match[:trip]}[departureDate][time][minute]") + "=" + parse_time(date_dst_departure).strftime("%M").to_i.to_s
    data << CGI.escape("publication_duplicate_#{match[:trip]}[returnDate][date]") + "=" + (date_dst_return ? parse_time(date_dst_return).strftime("%d/%m/%Y") : "")
    data << CGI.escape("publication_duplicate_#{match[:trip]}[returnDate][time][hour]") + "=" + (date_dst_return ? parse_time(date_dst_return).strftime("%H").to_i.to_s : "")
    data << CGI.escape("publication_duplicate_#{match[:trip]}[returnDate][time][minute]") + "=" + (date_dst_return ? parse_time(date_dst_return).strftime("%M").to_i.to_s : "")
    data << CGI.escape("publication_duplicate_#{match[:trip]}[_token]") + "=" + match[:duplicate]
    if indx == 0
      $duplicate_active_trip_offers[:data] = data.join("&")
      trip_dupl_req = setup_http_request($duplicate_active_trip_offers, @cookie)
    else
      $duplicate_inactive_trip_offers[:data] = data.join("&")
      trip_dupl_req = setup_http_request($duplicate_inactive_trip_offers, @cookie)
    end
    res = @http.request(trip_dupl_req)
    if res.code != "302" # Failed
      raise DuplicateTripError, "HTTP code should be 302 after [step 1 requesting]"
    end
    to_req = res['location'] # should be /trip/<start>-<end>-<id>/compute
    req = setup_http_request($dashboard, @cookie, {:url => to_req}) # $dashboard for Get method
    res = @http.request(req)
    if res.code != "302"
      raise DuplicateTripError, "HTTP code should be 302 after [step 2] computing"
    end
    to_req = res['location'] # should be /trip/publish
    req = setup_http_request($dashboard, @cookie, {:url => to_req}) # $dashboard for Get method
    res = @http.request(req)
    if res.code != "302"
      raise DuplicateTripError, "HTTP code should be 302 after [step 3 publishing]"
    end
    to_req = res['location'] #should be /publication/processing
    req = setup_http_request($dashboard, @cookie, {:url => to_req}) # $dashboard for Get method
    res = @http.request(req)
    if res.code != "200"
      raise DuplicateTripError, "HTTP code should be 302 after [step 4 processing]"
    end
    return true
  end

  # Check if the previous duplicated trip is published
  # @return [Boolean] true if succeed, false either
  def check_trip_published
    req = setup_http_request($check_publication, @cookie)
    puts "Waiting 1 seconde before checking if trip is published"
    sleep(1)
    while true
      res = @http.request(req)
      res.each_header do |k, v|
        puts "#{k}: #{v}\n"
      end
      puts res.body[0..1000]
      if gets.chomp == "q"
        break
      end
    end
    if res.code != "200"
      raise CheckPublishedTripError, "HTTP code should be 200 here [step 1 getting status]"
    end
    # should be JSON data like {"published":true,"encrypted_offer_id":"<sort of hash here>"}
    puts res.body
    jres = JSON.parse(res.body)
    req = setup_http_request($publication_processed, @cookie, {:arg => [jres['encrypted_offer_id']]})
    res = @http.request(req)
    if res.code != "200"
      raise CheckPublishedTripError, "HTTP code should be 200 here [step 2 checking]"
    end
    if res.body.force_encoding('utf-8').include?("Votre annonce a bien été publiée")
      return true
    else
      return false
    end
  end
end
