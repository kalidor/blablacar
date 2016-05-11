#!/usr/bin/env ruby
# coding: utf-8
# Author: Gregory 'kalidor' Charbonneau
# Email: kalidor -AT- unixed -DOT- fr
# Published under the terms of the wtfPLv2

require 'optparse'
$LOAD_PATH.unshift(File.join(File.expand_path(File.dirname(__FILE__)), "lib"))
require 'libblablacar'

options = {}
options[:interactive] = "true"
parser = OptionParser.new do |opts|
  opts.banner = "This is an example about what you can do with libblablacar.rb. Don't hesitate to improve it and let me know about it!"
  opts.banner = "Usage: #$0 <command>=<arg>"
  opts.on("-C", "--configuration <path_to_file>", "Configuration file to use. Read ~/.blablacar.rc by default") do |v| options[:configuration] = v; end
  opts.on("-a", "--avis <OPINION>", "Send an 'opinion' to a user") do |v| options[:avis] = v; end
  opts.on("-g", "--avis-recu [PAGE]", "Display user opinion") do |v| options[:avis_recu] = v || ''; end
  opts.on("-c", "--code <CODE>", "Code to validate a trip") do |v| options[:code] = v; end
  opts.on("-A", "--accept", "Accept passenger on a trip") do |v| options[:acceptation] = v; end
  opts.on("-d", "--driver", "Driver name to evaluate and leave an opinion") do |v| options[:driver] = v; end
  opts.on("-l", "--list", "List planned trip with passengers") do |v| options[:list] = v; end
  opts.on("-n", "--note <NOTE>", "Send evaluation note to a user") do |v| options[:note] = v; end
  opts.on("-i", "--interactive <ON/OFF>", "Enable/disable interactive mode (default is ENABLED)") do |v| options[:interactive] = v; end
  opts.on("-N", "--notifications", "Check notifications") do |v| options[:notifications] = v; end
  opts.on("-m", "--message", "Get news messages. If new message, interactive mode allow you to respond") do |v| options[:message] = v; end
  opts.on("-M", "--money-available", "Get the available amount of money") do |v| options[:money] = v; end
  opts.on("-p", "--passenger", "Passenger name to evaluate and leave an opinion") do |v| options[:passenger] = v; end
  opts.on("-s", "--money-status", "Get the money transfer status") do |v| options[:money_status] = v; end
  opts.on("-S", "--seats <SEATS>", "Number of available seats. If seat is already reserved, it doesn't count") do |v| options[:seats] = v; end
  opts.on("-t", "--transfert-request", "Make money transfert request") do |v| options[:transfer] = v; end
  opts.on("-T", "--tripdate <TRIPDATE>", "Trip date and hour") do |v| options[:trip] = v; end
  opts.on("-R", "--reason <REASON>", "Reason why you didn't accept this passenger on the trip. Use --reason=list to get available reasons") do |v| options[:reason] = v; end
  opts.on("-r", "--comment <comment>", "Comment on why you didn't accept this passenger on the trip") do |v| options[:comment] = v; end
  opts.on("-u", "--user user", "Validate a trip with this guy") do |v| options[:user] = v; end
  opts.on("-V", "--verbose", "Run verbosely") do |v| options[:verbose] = v; end
  opts.on("-x", "--duplicate <trip date and hour>", "Trip you want to duplicate ex: 2015/12/21 à 6h") do |v| options[:duplicate] = v; end
  opts.on("-D", "--debug", "For debug (run in proxy 127.0.0.1:8080)") do |v| options[:debug] = v; end
  opts.on_tail("-h", "--help", "Show this help message") do puts opts; exit 0; end
  opts.on_tail("Configuration sample (#{ENV['HOME']}/.blablacar.rc):")
  opts.on_tail("user: <email>")
  opts.on_tail('pass: "<password>"')
  opts.on_tail("cookie: /tmp/blablacar.cookie")
  opts.on_tail("The cookie will be saved after the first authentication.")
  opts.on_tail("")
  opts.on_tail("Example:")
  opts.on_tail("#$0 --avis 'Nice trip' --user 'Pierre P' --note 5 --passenger")
  opts.on_tail("#$0 --avis 'Nice trip' --user 'Bob M' --note 5 --driver 5")
  opts.on_tail("#$0 --user 'Bob M' --code ABCXYZ -p")
end

parser.parse!
if options.length == 0
  puts parser
  exit 0
end

# Add method to the original String class
class String
  def to_boolean
    case self
      when /^true$/i, /^on$/i, /^enable$/i
        true
      when /^false$/i, /^off$/i, /^disable$/i
        false
      else
        nil
    end
  end
  def strikethrough
    "\e[9m#{self}\e[0m"
  end
end

vputs "Starting: %s" % Time.now.to_s

blabla = Blablacar.new(options[:verbose], options[:debug])
blabla.run(options[:configuration])
if not blabla.authenticated?
  puts "[!] Echec de l'authentication"
  exit 0
end
puts "[+] Authentifié"
blabla.parse_dashboard()
blabla.parse_profil()

#blabla.search_trip("Annecy", "Lyon", "30/09/2015")

if options[:avis_recu]
  blabla.get_opinion(options[:avis_recu]).map{|a|
    puts "[%s] par %s: %s (%s)" % a
  }
end

if options[:message]
  if blabla.messages? > 0
    puts "#{blabla.messages} new message(s)"
    all_msgs = blabla.get_new_messages
    cpt = 0
    all_msgs.map{|kind, msgs|
      puts "#{kind.to_s} messages: %s" % ((msgs.length == 0) ? "No messages" : "")
      msgs.each{|m|
        puts "#{cpt}) #{m[:trip]} (#{m[:trip_date]})"
        puts "  User: #{m[:msg_user]}:"
        m[:msgs].map{|mm|
          puts "  · #{mm[:msg_date].capitalize}: #{mm[:msg]}"
        }
        puts "-"*10
        cpt += 1
      }
    }
    if options[:interactive].to_boolean != true
      puts "Mode interactif desactivé"
    else
      while true do
        print "('q' pour quitter, entrer le numéro de la question pour y répondre >"
        ind = STDIN.readline.chomp!
        if ind == "n" or ind == "next"
          break
        end
        if ind == "q" or ind == "quit"
          exit
        end
        ind = ind.to_i
        found = false
        all_msgs.map{|k,v|
          if v[ind] != nil
            found = v[ind]
            break
          end
        }
        if not found
          puts "[!] Index invalide"
          next
        end
        print "Entrer le message (penser à échapper '!')> "
        response = STDIN.readline.chomp!
        if response.empty?
          puts "[!] Message vide"
          next
        end
        if blabla.respond_to_question(found[:url], found[:token], response)
          puts "Message envoyé"
          break
        end
      end
    end
  else
    puts "0 nouveaux messages"
  end
end

if options[:reason]
  case options[:reason]
    when "l", "L", "list", "List", "LIST"
      puts "Raisons:"
      l = REASON_REFUSE.keys().map{|r| r.length}.max + 5
      REASON_REFUSE.map{|k, v|
        puts "  #{k} %s  #{v}" % (" " * (l - k.length))
      }
  end
end

if options[:refuse]
  if not options[:user]
    STDERR.write("Argument nécessaire -u <username>")
  end
  if not options[:trip]
    STDERR.write("Argument nécessaire -T <tripdate>")
  end
  if not options[:reason]
    STDERR.write("Argument nécessaire -R <reason> (-R pour lister toutes les raisons)")
  end
  if not options[:comment]
    STDERR.write("Argument nécessaire -r <comment>")
  end
  if not blabla.notifications?
    puts "Aucune notification"
    return
  end
  blabla.notifications.map{|notif|
    next if not notif.class == AcceptationNotification
    if notif.refuse(options[:user], options[:trip], options[:reason], options[:comment])
      puts "[+] Refusé"
    else
      puts "[-] Echec"
    end
  }
end

if options[:acceptation]
  if not options[:user]
    STDERR.write("Argument nécessaire -u <username>")
  end
  if not options[:trip]
    STDERR.write("Argument nécessaire -T <tripdate>")
  end
  if not blabla.notifications?
    puts "None notification"
    return
  end
  blabla.notifications.map{|notif|
    next if not notif.class == AcceptationNotification
    if options[:user] == notif.user
      if notif.accept()
        puts "[+] Accepté"
      else
        puts "[-] Echec"
      end
    end
  }
end

if options[:notifications]
  if not blabla.notifications?
    puts "Aucune notification"
  else
    puts "Notification:"
    blabla.notifications.map{|notif|
      if notif.class == AcceptationNotification
        puts "#{notif.desc} : #{notif.trip} (#{notif.trip_date})"
      else
        puts notif.desc
      end
    }
  end
end

if options[:code]
  if not options[:user]
    STDERR.write("Argument nécessaire --user <utilisateur>")
    exit 0
  end
  i = blabla.notifications.map{|notif| notif.user}.index(options[:user])
  if not i
    STDERR.write("Utilisateur introuvable dans les notifications")
    exit 0
  end
  if blabla.notifications[i].instance_of?(ValidationNotification)
    puts blabla.notifications[i].desc
    if options[:user] == blabla.notifications[i].user
      if blabla.notifications[i].confirm(options[:code])
        puts "[+] Code ok pour #{blabla.notifications[i].user}"
      else
        puts "[-] Code ko pour #{blabla.notifications[i].user}"
      end
    end
  end
end

if options[:avis]
  if not options[:user]
    STDERR.write("Argument nécessaire --user <utilisateur>")
    exit 0
  end
  if not options[:note]
    STDERR.write("Argument nécessaire --note <note>")
    exit 0
  end
  s = nil
  if options[:driver]
    s = "D"
  end
  if options[:passenger]
    s = "P"
  end
  if not s
    STDERR.write("A qui voulez-vous envoyé un avis")
    exit 0
  end
  i = blabla.notifications.map{|notif| notif.user}.index(options[:user])
  if not i
    STDERR.write("Utilisateur introuvable dans les notifications")
    exit 0
  end
  notif = blabla.notifications.map{|notif|
    if notif.desc.include?("avis") and notif.user.include?(options[:user])
      notif
    end
  }
  notif = notif.delete_if{|c| c == nil}.first
  if notif.instance_of?(AvisNotification)
    puts notif.desc
    if notif.send(s, options[:note], options[:avis])
      puts "Opinion envoyée"
    end
  end
end


if options[:money]
  # Is money available for transfer ?
  puts "Total déjà transféré: #{blabla.virement.total}"
  if blabla.virement.available?
    puts "Argent disponible: #{blabla.virement.available}"
  else
    puts "Pas d'argent disponible"
  end
end

if options[:transfer]
  if blabla.virement.transfer()
    puts "Requête du transfert de l'argent effectuée"
  else
    puts "Echec de la requête du transfert"
  end
end

if options[:money_status]
  # Show me if some transfer are pending or done
  # Search only on the last page...
  puts "Status de l'argent (dernière page):"
  blabla.virement.status?().map{|c|
    puts "  %s (%s) - %s [%s]" % c
  }
end

if options[:list]
  # See passengers for all future trips
  puts "Récupération des prochains trajets:"
  if options[:trip]
    trips = blabla.get_planned_passengers(options[:trip])
  else
    trips = blabla.get_planned_passengers()
  end
  if trips.length == 0
    puts "Aucun trajet de prévu"
  else
    puts "Trajets avec passager(s) associé(s):"
    trips.keys.map{|id|
      t = trips[id][:when].strftime("%A %d %b à %R")
      d = t.gsub(t.split(" ").first, DAYS[t.split(" ").first])
      puts
      puts "%s (%s). Trajet vu %s fois" % [trips[id][:trip], d, trips[id][:stats]]
      if trips[id][:seats]
        puts "  |  %s" % [trips[id][:seats]=="0" ? "[COMPLET]" : "#{trips[id][:seats]} sièges disponibles"]
      else
        puts "  |  [Trajet fait]"
      end
      if trips[id][:who].length > 0
        trips[id][:who].each_with_index{|v, i|
          if trips[id][:status][i] == "annulée"
            s = "%s %s\xe2\x98\x85 (%s) :: [%s seat(s)] - %s" % [trips[id][:who][i], trips[id][:note][i], trips[id][:phone][i], trips[id][:seat_taken][i], trips[id][:actual_trip][i]]
            puts "  |  #{s.strikethrough}"
          else
            puts "  |  %s %s\xe2\x98\x85 (%s) :: [%s seat(s)] - %s" % [trips[id][:who][i], trips[id][:note][i], trips[id][:phone][i], trips[id][:seat_taken][i], trips[id][:actual_trip][i]]
          end
        }
      end
    }
  end
end
if options[:duplicate]
  if not options[:trip]
    STDERR.write("Argument nécessaire --trip <date et heure du trajet> qui doit être créer")
    exit 0
  end
  r = blabla.duplicate(options[:duplicate], options[:trip])
  if r
    puts "[+] Trajet en cours de création"
    ret = blabla.check_trip_published(r)
    if ret == [true, 0]
      puts "[+] Trajet dupliqué"
    elsif ret == [true, 1]
      puts "[+] Trajet sera bientôt dupliqué"
    else
      puts "[!] Trajet ne peut pas être dupliqué"
    end
  else
    puts "[!] Erreur dans la création du trajet"
  end
end
if options[:seats]
  if not options[:trip]
    STDERR.write("Argument nécessaire --trip <date et heure du trajet> ")
    exit 0
  end
  if blabla.update_seat(options[:trip], options[:seats])
    puts "OK"
  else
    puts "Erreur dans la modification du nombre de place pour ce trajet"
  end
end
