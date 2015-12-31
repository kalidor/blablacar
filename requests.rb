# Author: Gregory 'kalidor' Charbonneau
# Email: kalidor -AT- unixed -DOT- fr
# Published under the terms of the wtfPLv2

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

$active_trip_offers = {
  :method => Net::HTTP::Get,
  :url => "/dashboard/trip-offers/active?page=%s",
}

$inactive_trip_offers = {
  :method => Net::HTTP::Get,
  :url => "/dashboard/trip-offers/inactive?page=%s",
}

$duplicate_active_trip_offers = {
  :method => Net::HTTP::Post,
  :url => "/dashboard/trip-offers/active",
  :header => ["Content-Type", "application/x-www-form-urlencoded"],
  :referer => "https://www.blablacar.fr/dashboard/trip-offers/active"
}

$duplicate_inactive_trip_offers = {
  :method => Net::HTTP::Post,
  :url => "/dashboard/trip-offers/inactive",
  :header => ["Content-Type", "application/x-www-form-urlencoded", "Pragma", "no-cache", "upgrade-insecure-requests", "1"],
  :referer => "https://www.blablacar.fr/dashboard/trip-offers/inactive"
}

$check_publication = {
  :method => Net::HTTP::Get,
  :url => "/publication/_check",
}

$publication_processed = {
  :method => Net::HTTP::Get,
  :url => "/publication/processed/%s"
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
$update_seat_req = {
  :method => Net::HTTP::Post,
  :url => "",
  :data => "count=%d",
  :header => ["Content-Type", "application/x-www-form-urlencoded; charset=UTF-8"]
}