# Author: Gregory 'kalidor' Charbonneau
# Email: kalidor -AT- unixed -DOT- fr
# Published under the terms of the wtfPLv2

# Notifications files

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
    if not body.include?("Vous n'avez pas d'argent disponible")
      @current = body.scan(/<p class="RequestMoney-available[^"]+">[^<]+<strong>(.*)<\/strong>.+ disponible.<\/p>/).flatten.first
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
