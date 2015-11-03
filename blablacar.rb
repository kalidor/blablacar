#!/usr/bin/env ruby
# coding: utf-8
# Author: Gregory 'kalidor' Charbonneau
# Email: kalidor -AT- unixed -DOT- fr
# Published under the terms of the wtfPLv2

require 'optparse'
$LOAD_PATH.unshift(File.expand_path(File.dirname(__FILE__)))
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
  opts.on("-d", "--driver", "Driver name to evaluate and leave an opinion") do |v| options[:driver] = v; end
  opts.on("-l", "--list", "List planned trip with passengers") do |v| options[:list] = v; end
  opts.on("-n", "--note <NOTE>", "Send evaluation note to a user") do |v| options[:note] = v; end
  opts.on("-i", "--interactive <ON/OFF>", "Enable/disable interactive mode (default is ENABLED)") do |v| options[:interactive] = v; end
  opts.on("-N", "--notifications", "Check notifications") do |v| options[:notifications] = v; end
  opts.on("-m", "--message", "Get news messages. If new message, interactive mode allow you to respond") do |v| options[:message] = v; end
  opts.on("-M", "--money-available", "Get the available amount of money") do |v| options[:money] = v; end
  opts.on("-p", "--passenger", "Passenger name to evaluate and leave an opinion") do |v| options[:passenger] = v; end
  opts.on("-s", "--money-status", "Get the money transfer status") do |v| options[:money_status] = v; end
  opts.on("-t", "--transfert-request", "Make money transfert request") do |v| options[:transfer] = v; end
  opts.on("-u", "--user user", "Validate a trip with this guy") do |v| options[:user] = v; end
  #opts.on("-V", "--[no-]verbose", "Run verbosely") do |v| options[:verbose] = v; end
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
  opts.on_tail("#$0 --user 'Bob M' --code ABCXYZ")
end

parser.parse!
if options.length == 0
  puts parser
  exit 0
end

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
end

iputs "Starting: %s" % Time.now.to_s

blabla = Blablacar.new(options[:verbose], options[:debug])
blabla.run(options[:configuration])

#blabla.search_trip("Annecy", "Lyon", "30/09/2015")

if options[:avis_recu]
  if options[:avis_recu].empty?
    blabla.get_opinion()
  else
    blabla.get_opinion(options[:avis_recu])
  end
end

if options[:message]
  if blabla.messages?
    puts "#{blabla.messages} new message(s)"
    all_msgs = blabla.get_new_messages
    ind = 0
    all_msgs.map{|kind, msgs|
      puts "#{kind.to_s} messages: %s" % ((msgs.length == 0) ? "No messages" : "")
      msgs.each{|m|
        puts "Conversations n°#{ind})"
        puts "  #{m[:msg]}"
        puts "-"*10
        ind += 1
      }
    }
    if options[:interactive].to_boolean != true
      puts "Interactive mode disabled"
    else
      while true do
        print "('q' for quit, input question num to respond to) Respond to > "
        ind = STDIN.readline.chomp!
        if ind == "n" or ind == "next"
          break
        end
        if ind == "q" or ind == "quit"
          exit
        end
        ind = ind.to_i
        if msgs[ind] == nil
          puts "[!] Invalid index"
          next
        end
        print "Enter message (think to escape '!')> "
        response = STDIN.readline.chomp!
        if response.empty?
          puts "[!] Empty message"
          next
        end
        if blabla.respond_to_question(msgs[ind][:url], msgs[ind][:token], response)
          puts "Message sent"
          break
        end
      end
    end
  else
    puts "No new messages"
  end
end

if options[:notifications]
  if not blabla.notifications?
    puts "None notification"
  else
    puts "Notification:"
    blabla.notifications.map{|notif|
      puts notif.desc
    }
  end
end

if options[:avis]
  if not options[:user]
    STDERR.write("Need to pass username through --user option")
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
    STDERR.write("Who do you want to send a comment to")
    exit 0
  end
  i = blabla.notifications.map{|notif| notif.user}.index(options[:user])
  if not i
    STDERR.write("User not found in notification")
    exit 0
  end
  if blabla.notifications[i].instance_of?(AvisNotification)
    puts blabla.notifications[i].desc
    if blabla.notifications[i].send(s, options[:note], options[:avis])
      puts "Opinion sent"
    end
  end
end

if options[:code]
  if not options[:user]
    STDERR.write("Need to pass username through --user option")
    exit 0
  end
  i = blabla.notifications.map{|notif| notif.user}.index(options[:user])
  if not i
    STDERR.write("User not found in notification")
    exit 0
  end
  if blabla.notifications[i].instance_of?(ValidationNotification)
    puts blabla.notifications[i].desc
    if options[:user] == blabla.notifications[i].user
      if blabla.notifications[i].confirm(options[:code])
        puts "[+] Code ok for #{blabla.notifications[i].user}"
      else
        puts "[-] Code ko for #{blabla.notifications[i].user}"
      end
    end
  end
end

if options[:money]
  # Is money available for transfer ?
  puts "Total already requested: #{blabla.virement.total}"
  if blabla.virement.available?
    puts "Available money: #{blabla.virement.available?}"
  else
    puts "No money available"
  end
end

if options[:transfer]
  if blabla.virement.transfer()
    puts "Transfer successfully requested"
  else
    puts "Transfer request failed"
  end
end

if options[:money_status]
  # Show me if some transfer are pending or done
  # Search only on the last page...
  puts "Money status (lastpage):"
  blabla.virement.status?().map{|c|
    puts "  %s (%s) - %s [%s]" % c
  }
end

if options[:list]
  # See passengers for all future trips
  puts "Getting next planned trips:"
  trips = blabla.get_planned_passengers()
  if trips.length == 0
    puts "No future planned trip(s)"
  else
    puts "See planned_passengers:"
    trips.keys.map{|id|
      puts "%s (%s). Trip seen %s times" % [trips[id][:trip], trips[id][:when], trips[id][:stats]]
      if trips[id][:who].length == 0
        puts "\t-Empty"
        next
      end
      trips[id][:who].each_with_index{|v, i|
        puts "\t-%s [%s] (%s) :: %s - %s %s" % [trips[id][:who][i], trips[id][:note][i], trips[id][:phone][i], trips[id][:place][i], trips[id][:actual_trip][i], trips[id][:status][i] == "annulée" ? ">> ANNULÉE <<" : ""]
      }
    }
  end
end
