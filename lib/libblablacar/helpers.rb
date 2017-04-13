def vputs(str)
  puts "[+] #{str}" if $VERBOSE
end

def dputs(str)
  puts "[DEBUG] #{str}" if $DDEBUG
end

def eputs(str)
  puts "[-] #{str}"
end

def aputs(str)
  puts "[!] #{str}"
end
ALERT = Proc.new {|_call, ptr, msg|
  puts "[!] --- Stacktrace --- |!]"
  puts "Last call: #{ptr}"
  puts _call
  puts "[!] --- Error message --- |!]"
  puts "Last call: #{ptr}"
  puts msg
}
