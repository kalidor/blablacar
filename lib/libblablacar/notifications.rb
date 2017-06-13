# Author: Gregory 'kalidor' Charbonneau
# Email: kalidor -AT- unixed -DOT- fr
# Published under the terms of the wtfPLv2

# Notifications files

# Generic Notification class
# All notification will heritated from it
class Notification
  attr_reader :desc, :trip_date
  def initialize(http, cookie, data)
    @http = http
    @cookie = cookie
    @desc = data.first
    @url = data.last
    prepare(data)
  end

  # Get the date of the trip about this notification
  #
  # @param url [String] URL to parse
  def get_date(url)
    req = setup_http_request($dashboard, @cookie,{:url=>url})
    res = @http.request(req)
    if not res.code.to_i == 302
      aputs "#{File.basename(__FILE__)}: line:#{__LINE__} Pas de redirection. Error somewhere"
      return nil
    end
    req = setup_http_request($dashboard, @cookie,{:url=>res['location']})
    res = @http.request(req)
    body = res.body.force_encoding('utf-8')
    body.scan(/<p class="my-trip-elements size16 push-left no-clear my-trip-date">\s*(.*)\s*<\/p>/).flatten.first
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
    @user = data.first.force_encoding('utf-8').scan(/(.*) veut réserver sur votre/).flatten.first
    if not @user
      raise AcceptationError, "User unknown", caller
    end
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
    @trip = body.scan(/<h2 class="u-left">\s(.*)\s*<\/h2>/).flatten.first.strip.gsub("&rarr;", "->")
    @trip_date = body.scan(/<p class="my-trip-elements size16 u-left no-clear my-trip-date">\s*(.*)\s*<\/p>/).flatten.first
    if not @trip_date
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
    if not data.first.match(/renseignez les codes de r.servation/)
      return
    end
    get_confirm_req = setup_http_request($dashboard, @cookie, {:url=>@url})
    res = @http.request(get_confirm_req)
    loc = res['location']
    if res.code.to_i != 302 and not loc.start_with?("/dashboard/trip-offer/")
      eputs "Can't valid the trip.. Error somewhere."
      return nil
    end
    @ret_address = res['location']
    get_form_confirm_req = setup_http_request($dashboard, @cookie,{:url=>@ret_address})
    res = @http.request(get_form_confirm_req)
    @data = find_user_need_confirm(res.body.force_encoding('utf-8'))
    @user = @data.keys()
    @trip_date = get_date(data.last)
  end

  # Get the list of all user we drove with
  #
  # @param data [String] HTTP response body
  # @return [String] Stripped HTTP response body
  def find_user_need_confirm(data)
    res = {}
    us = data.scan(/<b>acceptée<\/b>\s*<\/div>\s*<span class="passenger-fullname">([^<]*)<\/span>/).flatten
    ur = data.scan(/<form method="post" action="(\/seat-driver-confirm\/[^"]*)">/).flatten
    to = data.scan(/name="confirm_booking\[_token\]" value="([^"]*)" \/>/).flatten
    us.each_with_index{|u, id|
      res[u] = {}
      res[u][:url] = ur[id]
      res[u][:token] = to[id]
    }
    res
  end

  # Confirm the validation
  #
  # @param loc [String] URL
  # @return [Boolean] Return true if the confirmation includes the username
  def get_validation_confirmation(loc)
    get_form_confirm_req = setup_http_request($dashboard, @cookie,{:url=>loc})
    res = @http.request(get_form_confirm_req)
    body = res.body.force_encoding('utf-8')
    confirmed = body.scan(/<div class="u-right u-green size16 uppercase">\s*<b>Confirm.e<\/b>\s*<\/div>\s*<span class="passenger-fullname">([^<]*)<\/span>/).flatten
    return confirmed.include?(@user)
  end

  # Validate the trip
  #
  # @param code [String] Validation code given by the passenger after the trip
  # @return [Boolean] true if succeed, false if validation code if bad, nil if the request failed
  def confirm(user,code)
    dputs __method__.to_s
    confirm_req = setup_http_request($trip_confirmation, @cookie, {:url => @data[user][:url], :arg => [code, @data[user][:token]]})
    res = @http.request(confirm_req)
    # We get 302 code, and we have to request the first page in order to check if
    # the validation is "Confirmée"
    if res.code.to_i == 302
      return get_validation_confirmation(@ret_address)
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

  def available
    @current.empty? ? 0 : @current
  end

  def available?
    @current.empty? ? false : true
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
    m[:status] = body.scan(/<td class="u-alignMiddle u-alignCenter .*span3">\s*(.*)\s*/).flatten.map{|c| c.gsub('<br/>','')}
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
    @total = body.scan(/Total [^<]+<span class="money-highlight size24 bold">(.*)<\/span>/).flatten.first
    if not body.include?("Pas d'argent en attente")
      @current = body.scan(/<p class="RequestMoney-available[^"]*">\s*<strong>(\d*,\d*)[^<]*<\/strong>/).flatten.first
    else
      @current = ""
    end
    if not @total or not @current
      raise VirementError, "Failed to parse total/available money"
    end
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
    @user = data.first.scan(/laissez un avis . votre (?:passager)?(?:conducteur)? (.*)/).flatten.first
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
      puts "#{__LINE__} Uh I'm not being redirected?... What a failure!"
      return nil
    end
    url = res['location']
    # on est redirigé
    loc = res['location']
    req = setup_http_request($avis_req_get, @cookie, {:url => loc})
    res = @http.request(req)
    token = res.body.scan(/<input type="hidden" id="rating__token" name="rating\[_token\]" value="([^"]*)" \/>/).flatten.first
    # post for previsualisation
    if driver
      req = setup_http_request($avis_driver_req_post, @cookie, {:url => url, :arg => [note, CGI.escape(comment), driver, token]})
    else
      req = setup_http_request($avis_req_post, @cookie, {:url => url, :arg => [note, CGI.escape(comment), token]})
    end
    res = @http.request(req)
    if not res['location']
      puts "#{__LINE__} Uh I'm not being redirected?... What a failure!"
      return nil
    end
    url = res['location']
    req = setup_http_request($avis_req_get, @cookie, {:url => url})
    res = @http.request(req)
    token = res.body.scan(/name="rating_preview\[_token\]" value="([^"]*)" \/>/).flatten.first
    if driver
      req = setup_http_request($avis_driver_req_post_confirm, @cookie, {:url => url, :arg => [status, note, CGI.escape(comment), driver, token]})
    else
      req = setup_http_request($avis_req_post_confirm, @cookie, {:url => url, :arg => [status, note, CGI.escape(comment), token]})
    end
    res = @http.request(req)
    if res['location'].match(/\/dashboard\/ratings\/saved\/([^\/]+)/) or
      res['location'] == "/dashboard/ratings/hints"
      return true
    else
      eputs res['location']
      return false
    end

    #req = setup_http_request($avis_req_get, @cookie, {:url => res['location']})
    #res = @http.request(req)
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

# PassengerValidationNotification
# When you have to confirm the trip with this person
class PassengerValidationNotification < Notification
  attr_reader :user

  # Save the user who made the trip with us
  #
  # @param data [String] HTTP response body
  def prepare(data)
    @user = data.first.scan(/Avez vous voyag. avec (.*) sur le trajet (.*) ?/).flatten.first
    @trip_date = get_date(data.last)
  end

  # Get the link to validate the trip (passenger mode)
  #
  # @return [Boolean] if succeed: true, else: false
  def get_link_to_confirm
    dputs __method__.to_s
    get_confirm_req = setup_http_request($dashboard, @cookie, {:url=>@url})
    res = @http.request(get_confirm_req)
    loc = res['location']
    get_confirm_req = setup_http_request($dashboard, @cookie, {:url=>loc})
    res = @http.request(get_confirm_req)
    return res.body.scan(/<a href="(\/seat-passenger-confirm\/[^"]*)" class="btn-acceptation">\s*Oui\s*<\/a>/).flatten.first
  end

  # Validate the trip
  #
  # @return [Boolean] if succeed: true, else: false
  def confirm
    url = get_link_to_confirm()
    get_confirm_req = setup_http_request($dashboard, @cookie, {:url=>url})
    res = @http.request(get_confirm_req)
    if res.code == '302'
      get_confirm_req = setup_http_request($dashboard, @cookie, {:url=>url})
      res = @http.request(get_confirm_req)
      if res.include?("Voyage fait")
        return true
      end
    end
    return false
  end
end
