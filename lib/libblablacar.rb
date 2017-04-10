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
require 'libblablacar/helpers'
require 'libblablacar/consts'
require 'libblablacar/requests'
require 'libblablacar/errors'
require 'libblablacar/notifications'
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
      if args[:url].scan(/%[s|d]/).length != args[:url_arg].length
        aputs "URL contains %d '%%s' or '%%d' argument... Fix your code" % args[:url].scan(/%[s|d]/).length
        aputs __callee__
        exit 2
      end
      req = obj[:method].new(args[:url] % args[:url_arg])
    else
      req = obj[:method].new(args[:url])
    end
  else
    if args.has_key?(:url_arg)
      if obj[:url].scan(/%[s|d]/).length > 0
        if obj[:url].scan(/%[s|d]/).length != args[:url_arg].length
          aputs "URL contains %d '%%s' or '%%d' argument... Fix your code" % obj[:url].scan(/%[s|d]/).length
          aputs __callee__
          exit 2
        end
        req = obj[:method].new(obj[:url] % args[:url_arg])
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
    obj[:header].each_slice(2).map{|h|
      req.add_field(h[0], h[1])
    }
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
    @current_user = nil
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

  # Get cookie key=value and save it for the next futures requests
  #
  # @param data [Net::HTTPResponse] Net::HTTPResponse object containing HTTP headers
  def get_cookie(data)
    if data['set-cookie']
      t = []
      data['Set-Cookie'].split(", ").map{|c|
        tmp = c.scan(/([a-zA-Z0-9_\-\.]*=[^;]*)/).flatten
        tmp.delete_if{|cc| cc.downcase.include?("path")}
        tmp.delete_if{|cc| cc.downcase.include?("expires")}
        tmp.delete_if{|cc| cc.downcase.include?("domain")}
        t << tmp
      }
      if t.length == 1
        @cookie = @cookie + t.join("; ")
      else
        @cookie = t.join("; ")
      end
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
    if $ident[:data].include?("%{user}")
      $ident[:data] = $ident[:data] % {:user => $CONF['user'], :pass => CGI.escape($CONF['pass'])}
    end
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

  # Load the where I save validated requests from people asked me directly
  def load_local_requests(file=nil)
    file ||= File.join(ENV['HOME'], '.blablacar', 'direct.rc')
    begin
      $DIRECT = YAML.load_file(file)
    rescue Errno::ENOENT => e
      eputs(e.message)
      exit 2
    end
  end

  # Load the configuration file into $CONF constant
  #
  # @param file [String] Path to the configuration file
  def load_conf(file=nil)
    file ||= File.join(ENV['HOME'], '.blablacar', 'conf.rc')
    begin
      $CONF = YAML.load_file(file)
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
    vputs "Get the cookie tracking: (#{@cookie})"
    # Step 2: Post send_credentials id/passwd and get authenticated cookie
    # the cookie is the same name as previous, but the value is updated
    send_credentials()
    (aputs "Can't get Cookie send_credentials"; exit 2) if not @cookie
  end

  # Let's try if we can access the dashboard
  def get_dashboard
    # Setp 3: Try to access to the dashboard
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
    dates = body.scan(/<p class="my-trip-elements size16 u-left no-clear my-trip-date">\s*(.*)\s*<\/p>/).flatten
    duplicate = body.scan(/<input type="hidden" id="publication_duplicate_\d+__token" name="publication_duplicate_\d+\[_token\]" value="([^"]+)" \/>/).flatten
    ts.each_with_index do |v, i|
      trips[v] = {:trip => v, :stats => stats[i], :date => dates[i], :duplicate => duplicate[i]}
    end
    trips
  end

  # Get all trip's offers id
  #
  # @param active [Boolean] If true get only future trips, if not, get old passed trip too
  # @param limit [FixNum] Limit of the page parsed (1 req/page)
  # @return (see #list_trip_offers)
  def get_trip_offers(active=true, limit=3)
    dputs __method__.to_s
    if active
      trip_offer_req = setup_http_request($active_trip_offers, @cookie, {:url_arg => [1]})
      obj_ = $active_trip_offers
      page_regex = $active_trip_offers[:url].gsub("?","\\?").gsub("/", "\\/") % ""
      page_url = $active_trip_offers[:url]
    else
      trip_offer_req = setup_http_request($inactive_trip_offers, @cookie, {:url_arg => [1]})
      obj_ = $inactive_trip_offers
      page_regex = $inactive_trip_offers[:url].gsub("?","\\?").gsub("/", "\\/") % ""
      page_url = $inactive_trip_offers[:url]
    end
    res = @http.request(trip_offer_req)
    trips = {}
    trips = list_trip_offers(CGI.unescapeHTML(res.body.force_encoding("utf-8")))
    pages = res.body.scan(/<a href="#{page_regex}(\d+)/).flatten.uniq
    # in case we got something like 1, 2, 3,4,5,6,7,8,9,21
    pages.map!(&:to_i)
    if not pages.empty?
      if pages.length >= 2
        diff = pages[-2..-1].inject(:-).abs
        if diff > 1
          pages += 1.upto(diff).map{|d| d + pages[-2]}.to_a
          pages.sort!
          pages.slice!(limit..-1)
        end
      end
      pages.map{|p|
        # Using $active_trip_offers for the method, but specify the URL
        trip_offer_req = setup_http_request(obj_, @cookie, {:url => page_url, :url_arg => [p]})
        res = @http.request(trip_offer_req)
        trips = trips.merge(list_trip_offers(res.body))
      }
    end
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
    t[:trip] = res.scan(/<h2 class="u-left">\s(.*)\s*<\/h2>/).flatten.map{|c| c.strip!}.first.gsub("&rarr;", "->")
    t[:when] = parse_time(res.scan(/<p class="my-trip-elements size16 u-left no-clear my-trip-date">\s(.*)\s*<\/p>/).flatten.map{|c| c.strip!}.first)
    t[:seat_url] = res.scan(/<form action="(\/dashboard\/trip\/\d+\/_seatCount\?token=[^"]+)/).flatten.first
    t[:seats] = res.scan(/(?:<input type="text" name="count" class="nb-seats" data-booking-enabled="\d+" data-value-warning="\d+" data-number-min="\d+" data-number-max="\d+" value="(\d+)")/).flatten.first
    t[:who] = res.scan(/<a href="\/membre\/profil\/.*" class="blue">\s*(.*)\s*<\/a>/).flatten.map{|c| c.strip!}
    if t[:who].include?(nil)
      tmp = res.scan(/<ul class="u-reset size17 passenger-infos">\s*<li>\s*<span class="tip" title="([^"]*)" data-placement="top">/).flatten
      tmp_num = res.scan(/<p class="u-midGray size12">([^<]*)<\/p>/).flatten
      if t[:who].count(nil) > 1
      end
      tmp.each_with_index{|c,ind|
        t[:who].each_with_index{|w,i|
          if w == nil
            t[:who][i] = tmp[ind]
            break
          end
        }
      }
    end
    t[:note] = res.scan(/<span class="u-textBold u-darkGray">(.*)<\/span><span class="u-gray">/).flatten
    t[:phone] = res.scan(/<span class="mobile*">(.*)<\/span>/).flatten
    t[:seat_taken] = res.scan(/<li class="passenger-seat">(\d) place[s]?<\/li>/).flatten
    t[:status] = res.scan(/<div class="u-right (?:u-green|u-gray) size16 u-uppercase">\s*<b>([^<]+)<\/b>\s*<\/div>/).flatten
    t[:actual_trip] = res.scan(/<ul class="u-reset passenger-trip size17">\s*<li>\s([a-zA-Zé\ \-]*)\s*<\/li>/).flatten.map{|c| c.strip!;c.gsub!(" - ", " -> ")}

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
  def get_planned_passengers(trip_date = nil)
    dputs __method__.to_s
    _trips = get_active_trip_offers()
    if $VERBOSE
      m="Parsing (on #{_trips.length}): "
      print m
    end
    trips = {}
    _trips.each_with_index{|t,i|
      id = t.first
      t = t[1]
      if trip_date
        if parse_time(t[:date]) != parse_time(trip_date)
          next
        end
      end
      if $VERBOSE
        print i
      end
      trip_req = setup_http_request($trip, @cookie, {:url_arg => [id]})
      res = @http.request(trip_req)
      p = parse_trip(res.body)
      trips[id] = p
      trips[id][:stats] = t[:stats]
      if $VERBOSE
        print 0x08.chr * i.to_s.length
      end
    }
      if $VERBOSE
        print 0x08.chr * m.length
      end
    # Sort by date
    trips = Hash[trips.sort_by{|k, v| v[:when]}]
    trips
  end

  # Generic method to get public/private messages from link
  # @param url [String] URL to request
  # @param kind [String] What kind of messages: 'public' or 'private'
  # @param check [Boolean] Get our response too
  # @return [Array] Array of Hash. Hash containing those keys: :msgs_user, :url, :token, :trip_date, :trip, :msgs
  def get_conversations(url, kind='public', check=nil)
    dputs __method__.to_s
    messages_req = setup_http_request($messages, @cookie, {:url => url})
    res = @http.request(messages_req)
    body = CGI.unescapeHTML(res.body.force_encoding('utf-8').gsub("<br />", ""))
    if kind == 'public'
      lastindex = body.index('Questions sur les autres portions du trajet')
      if lastindex
        body = body[0..lastindex]
      end
      trip_date = body.scan(/<strong class="RideDetails-infoValue">\s*<i class="bbc-icon2-calendar" aria-hidden="true"><\/i>\s*<span>\s*(.*)\s*/).flatten.first
    else # 'private'
      trip = body.scan(/<a href="\/trajet-[^"]*" rel="nofollow">\s*(.*)\s*<\/a>/).flatten.first
      trip, trip_date = trip.split(",")
    end
    # looking for uniq value for each discussion (url to respond to)
    urls = body.scan(/<form id="qa"\s*class="[^"]*"\s*action="(\/messages\/send\/[^"]*)"\s*method="POST"/).flatten
    ret = Array.new
    # to be TESTED
    indexes = Array.new
    last = nil
    urls.map{|u| indexes << body.index(u)}
    indexes.each_slice(2).map{|id1,id2|
      if last
        body[last..id1]
      end
      if not id2
        body[id1..-1]
      else
        body[id1..id2]
        last = id2
      end
    }
    # end of the TESTED part
    u = 0
    urls.map{|t|
      ind = body.index(t)+2000
      body_ = body[u..ind]
      u = ind
      token = body_.scan(/message\[_token\]" value="([^"]*)" \/>/).flatten.first
      encrypted_id = body.scan(/name="message\[recipient_encrypted_id\]" value="([^"]*)"/).flatten
      users = body_.scan(/<a href="\/membre\/profil\/[^"]*"><img class="[^"]*" title="([^"]*)" alt="[^"]*"/).flatten
      msg_hours = body_.scan(/<time class="Speech-date" datetime="[^"]*">([^<]*)<\/time>/).flatten
      trip, trip_date = body_.scan(/<div class="header-thread">\s*<h3>\s*Covoiturage de ([^,]*), (.*)\s*<span/).flatten
      msgs = body_.scan(/<\/h4>\s*<p>"([^"]*)"<\/p>/).flatten
      msg_hours = body_.scan(/<p class="msg-date clearfix">\s*([^<]*)\s*</).flatten.map{|m| m.strip.chomp}
      tmp = {:msg_user => users.first, :url => t, :token => token, :encrypted_id => encrypted_id.first, :trip_date => trip_date, :trip => trip}
      tmp[:msgs] = []
      0.upto(msgs.length-1).map{|id|
        # When the current user has already responded
        if users[id].include?(@current_user)
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
  # @param (see #get_private_conversations)
  # @return (see #get_private_conversations)
  def get_public_conversations(url, check=nil)
    get_conversations(url, 'public', check)
  end

  # Reponse back to a question
  #
  # @param url [String] URL to response to
  # @param token [String] Uniq token to use in order to response to the question
  # @param resp [String] The response message
  # @return [Boolean] true if succeed, false if failed. Could raise on error if something wrong on the network
  def respond_to_question(url, token, encrypted_id, resp)
    dputs __method__.to_s
    messages_req = setup_http_request($respond_to_message, @cookie, {:url => url, :arg => [resp, encrypted_id, token]})
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
  def messages_parsing(body)
    term_re = "\\/messages\\/show\\/"
    body = CGI.unescapeHTML(body)
    urls = body.scan(/<a href="(#{term_re}[^"]*)"/).flatten
    return urls
  end

  # Get public/private message link
  #
  # @param all [Boolean] If true get our response too
  # @return [Hash] Hash of Array. Keys are :public. Each contains an array of Hash
  def get_messages_link_and_content()
    dputs __method__.to_s
    urls = {:public => []}
    # public messages
    message_req = setup_http_request($messages, @cookie)
    res = @http.request(message_req)
    urls[:public] = messages_parsing(res.body.force_encoding('utf-8'))
    msgs = {:public => []}
    until urls.empty?
      k, uu = urls.shift
      next if uu == nil
      uu.map{|u|
        get_conversations(u, k.to_s).map do |m|
          next if not m
          msgs[k] << m
        end
      }
    end
    # ex: {:public => [{:msg=>["[Aujourd'hui à 09h48] Miguel  L : \"BONJOUR  GREG  vous  arrive jusque  a la  gare pardieu\"", "..."], :url=>"/messages/respond/kAxP4rA...", :token => "XazeAFsdf..."}], :private => [{:msg => ...}]
    return msgs
  end

  # Get only new messages
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
    req = setup_http_request($rating_received, @cookie, {:url_arg => [page]})
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
    req = setup_http_request($search_req, @cookie, {:url_arg => [city_start, city_end, CGI.escape(date)]})
    res = @http.request(req)
    res=JSON.parse(res.body)['html']['results'].force_encoding('utf-8')
    results = []
    url = res.scan(/<meta itemprop="url" content="([^>]*)">/).flatten
    user = res.scan(/<div class="user-info">\s*<h2 class="username">(.*)<\/h2>\s*/)#(.*)<br \/>\s*<\/div>/)
    user = res.scan(/<strong class="MemberCard-name u-block">([^<]*)<\/strong>/).flatten
    user_bis = res.scan(/<h2 class="ProfileCard-info ProfileCard-info--name u-truncate">\s*(.*)\s*<\/h2>/).flatten
    users = user+user_bis
    #prefs = res.scan(/ <div class=\"preferences-container\">\s*((?:<span class="[^ ]* prefs tip" title=".*"><\/span>)*)\s*((?:<span class="[^ ]* prefs tip" title=".*"><\/span>)*)\s*((?:<span class="[^ ]* prefs tip" title=".*"><\/span>)*)\s*((?:<span class="[^ ]* prefs tip" title=".*"><\/span>)*)/)
    trip_time = res.scan(/<h3 class="time light-gray" itemprop="startDate" content="([^"]*)">\s*(.*)\s*<\/h3>/)
    trip = res.scan(/<span class="from trip-roads-stop">(.*)<\/span>\s*<span class="arrow-ie">.*<\/span>\s*<span class="trip-roads-stop">([^<]*)<\/span>/)
    start = res.scan(/<dd class="js-tip-custom" title="D.part">\s*(.*)\s*<\/dd>/).flatten
    stop = res.scan(/<dd class="js-tip-custom" title="Arriv.e">\s*(.*)\s*<\/dd>/).flatten
    #car = res.scan(/<dd class="js-tip-custom" title="Arriv.e">\s*.*\s*<\/dd>\s*<\/dl>\s*((?:<dl class="car-type" [^>]*>\s*<dt>V.hicule : <strong>.*<\/strong><\/dt>)){0,1}/)
    #car = res.scan(/Véhicule : <strong>(.*)<\/strong><\/dt>/)
    place = res.scan(/<div class="availability">\s*<strong>(.*)<\/strong>(?: <span>.*<\/span>){0,1}/).flatten
    price = res.scan(/<div class="price price-[^"]+" itemprop="location">\s*<strong>\s*<span class="" >\s*(\d+)*<span class="size20">(,[^<]*)<\/span>/)
    acceptation = res.scan(/title="Acceptation : ([^"]+)"/).flatten
    url.each_with_index{|u, ind|
      results[ind] = {
        :url => u[ind],
        :user => users[ind],
        #:preferences => prefs[ind].map{|p| p.scan(/<span class=".*" title="(.*)"><\/span>/)}.flatten,
        :time => trip_time[ind].join(" "),
        :trip => trip[ind].join(" -> "),
        :start => start[ind],
        :stop => stop[ind],
        #:car => car[ind].first ==nil ? "no info" : car[ind].first.scan(/hicule : <strong>(.*)<\/strong>/).flatten.first,
        :place => place[ind]=="Complet" ? "Complet" : "%s disponible(s)"%place[ind],
        :price => "%s" % price[ind].join(""),
        :acceptation => acceptation[ind]
      }
    }
    puts "[+] Got results"
    results
  end

  # Parse the dashboard web page
  #
  def parse_dashboard
    dputs __method__.to_s
    # Don't need to parse the all page to get message received...
    msg = @dashboard.scan(/"\/messages\/list">Messages\s*<span[^>]*>(\d+)<\/span>/).flatten.first
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

  # Parse the profile web page
  #
  def parse_profil
    dputs __method__.to_s
    req = setup_http_request($profil_request, @cookie, {})
    res = @http.request(req)
    @current_user = res.body.force_encoding('utf-8').scan(/data-toggle="dropdown">([^<]*)<span class="Header-navigationAvatar">/).flatten.first
  end

  # Get the notifications
  #
  # @param data [String] Net::HTTPResponse body
  # @return [Notification] Could be ValidationNotification, AvisNotification, AcceptationNotification or nil
  def parse_notifications(data)
    if data.first.match(/renseignez le(?:s)? code(?:s)?/)
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
    if data.first.include?("Avez vous voyag")
      return PassengerValidationNotification.new(@http, @cookie, data)
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
    trip_req = setup_http_request($trip, @cookie, {:url_arg => [t_id]})
    res = @http.request(trip_req)
    _p = parse_trip(res.body)
    req = setup_http_request($update_seat_req, @cookie, {:url => _p[:seat_url], :arg => [seat.to_i]})
    res = @http.request(req)
    # json return
    body = JSON.parse(res.body) #{"status":"OK","value":<seats_number>}
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
      $duplicate_inactive_trip_offers[:url] += "?page=#{indx}"
      trip_dupl_req = setup_http_request($duplicate_inactive_trip_offers, @cookie)
    end
    res = @http.request(trip_dupl_req)
    if res.code == "200"
      if res.body.include?('<div class="alert alert-error')
        raise DuplicateTripError, "Trip already available \n'%s'" % res.body.scan(/<div class="alert alert-error [^"]+">([^<]+)<a href/).flatten.first
      end
    end
    if res.code != "302" # Failed
      File.open("duplicate_error1.html","w") do |f| f.write(res.body); end
      raise DuplicateTripError, "HTTP code should be 302 after [step 1 requesting]"
    end
    to_req = res['location'] # should be /trip/<start>-<end>-<id>/compute
    req = setup_http_request($dashboard, @cookie, {:url => to_req}) # $dashboard for Get method
    res = @http.request(req)
    if res.code != "302"
      File.open("duplicate_error2.html","w") do |f| f.write(res.body); end
      raise DuplicateTripError, "HTTP code should be 302 after [step 2] computing"
    end
    to_req = res['location'] # should be /trip/publish
    req = setup_http_request($dashboard, @cookie, {:url => to_req}) # $dashboard for Get method
    res = @http.request(req)
    if res.code != "302"
      File.open("duplicate_error3.html","w") do |f| f.write(res.body); end
      raise DuplicateTripError, "HTTP code should be 302 after [step 3 publishing]"
    end
    to_req = res['location'] #should be /publication/processing
    req = setup_http_request($dashboard, @cookie, {:url => to_req}) # $dashboard for Get method
    res = @http.request(req)
    if res.code != "200"
      File.open("duplicate_error4.html","w") do |f| f.write(res.body); end
      raise DuplicateTripError, "HTTP code should be 302 after [step 4 processing]"
    end
    if res.body.include?("Votre annonce est en cours de traitement")
      return res.body.scan(/https:\/\/www.blablacar.fr\/publication\/(.*)\/processing/).first.first
    end
    return false
  end

  # Check if the previous duplicated trip is published
  # @todo maybe useless
  # @return [Boolean] true if succeed, false either
  def check_trip_published(arg)
    puts "[testing]sleeping 1 sec to avoid an error on blablacar server side"
    sleep(1)
    req = setup_http_request($publication_processed, @cookie, {:url_arg => [arg]})
    res = @http.request(req)
    if res.code != "200"
      if res.body.include?("maintenance")
        puts "[?] Blablacar est en maintenance"
      end
      File.open("Checkpublished_error1.html","w") do |f| f.write(res.body); end
      raise CheckPublishedTripError, "HTTP code should be 200 here [step 2 checking]"
    end
    if res.body.force_encoding('utf-8').include?("Voir votre annonce")
      puts "voir votre annonce"
      return true, 0
    elsif res.body.force_encoding('utf-8').include?("Votre annonce sera publiée dans quelques instants")
      puts "votre annonce sera publiée dans qq instants"
      return true, 1
    else
      puts "fail"
      return false
    end
  end

  # Get information about reservations
  # @return [Array]
  def get_info_about_reservation(url_res)
    req = setup_http_request($mybookings, @cookie, {:url => url_res})
    res = @http.request(req)
    if res.code != '200'
      puts "[?] Acces impossible a mes reservations"
    else
      body = CGI.unescapeHTML(res.body).gsub("&rdquo;","").gsub("&ldquo;","").force_encoding('utf-8')
      depart_arrivee = body.scan(/<i class="bbc-icon2-circle first size20 location-circle [green|red]+" aria-hidden="true"><\/i>\s*<strong>\s*(.*)\s*<\/strong>\s*<\/div>/).flatten
      _start = body.index('<p class="showmore"')
      if _start
        _start = _start + '<p class="showmore">'.length
        _end = body[_start..-1].index("</div>") + _start
        infos = body[_start.._end-5].split("<br />")[0..-1].join("").gsub("</p>","").gsub("\n", " ")
        infos.gsub!('<span class="showmore-ellipsis">...</span><span class="showmore-rest">', '')
        infos = infos.split("</span>").first
      else
        infos = "Pas d'informations"
      end
      code = body.scan(/<span class="text-code">([^<]*)<\/span>/).flatten.first
      return [code, depart_arrivee, infos]
    end
    return ""
  end

  # Get passengers for a trip
  # @return [Array]
  def list_passengers(url)
    req = setup_http_request($dashboard, @cookie, {:url => url})
    res = @http.request(req)
    if res.code != '200'
      puts "[?] Acces impossible a mes reservations"
      return ["erreur de la récupération des passagers"]
    else
      body = CGI.unescapeHTML(res.body).force_encoding('utf-8')
      return body.scan(/<li class="Booking-occupant">\s*<img class="PhotoWrapper-user PhotoWrapper-user--smaller tip u-block u-rounded" title="([^"]*)" alt="[^"]*"/).flatten
    end
  end

  # List my reservations
  # @return [Hash]
  def get_my_reservations
    req = setup_http_request($mybookings, @cookie, {})
    res = @http.request(req)
    if res.code != '200'
      puts "[?] Acces impossible a mes reservations"
    else
      results = []
      body    = CGI.unescapeHTML(res.body).gsub("&rarr;", "->").force_encoding('utf-8')
      ways    = body.scan(/<h2 class="span4">\s*(.*)\s*<\/h2>/).flatten
      status  = body.scan(/<div class="span8 status-trip (?:confirm-lib)?(?:wait-lib)?[^"]+">\s*(.*)\s*<\/div>/).flatten.map{|c| c.strip}
      reste   = body.scan(/<p class="u-overflowHidden">\s+(.*)\s+(.*)\s+<\/p>\s+<\/li>/)
      urls    = body.scan(/<a href="(\/dashboard\/manage-my-booking\/[^"]*)"/).flatten
      reste.each_slice(3).each_with_index{|c, ind|
        if status[ind] == "Acceptée"
          code, depart_arrivee, infos = get_info_about_reservation(urls[ind])
          passengers = list_passengers(body.scan(/<a href="(\/trajet-[^"]*)" class="look blue">\s*Voir l'annonce/).flatten[ind])
        elsif status[ind] == "En attente d'acceptation"
          # code should be nil
          code, depart_arrivee, infos = get_info_about_reservation(urls[ind])
          passengers = []
        elsif status[ind].downcase == "confirmée"
          code, depart_arrivee, infos = get_info_about_reservation(urls[ind])
          code = "FAIT"
          passengers = []
        else
          infos = ""
          depart_arrivee = "introuvable"
          code = "introuvable"
        end
        tel = c[2]
        if tel[1] and tel[1].length > 1
          tel = tel[1][2..-2].gsub(/\ +/, ' ')
        else
          tel = ""
        end
        results << {:way => ways[ind], :status => status[ind], :when => c[0].first, :price => c[1].join(" "), :who => "'%s' (%s)" % [c[2][0], tel], :lieux => depart_arrivee, :infos => infos, :code => code, :passengers => passengers}
      }
      results
    end
  end
end
