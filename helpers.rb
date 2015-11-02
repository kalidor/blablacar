def vputs(str)
  puts "[V] #{str}()" if $VERBOSE
end

def dputs(str)
  puts "[DEBUG] #{str}()" if $DDEBUG
end

def iputs(str)
  puts "[+] #{str}"
end

def eputs(str)
  puts "[-] #{str}"
end

def aputs(str)
  puts "[!] #{str}"
end
