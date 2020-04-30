#!/usr/bin/ruby

require 'pp'
require 'net/ssh'
require 'thread'
require 'influxdb'
require 'date'
require 'ipaddress'
require 'open3'

load 'Pinger.rb'

MANDATORY_ARGS = ["--nodes"]  # the command to start this script MUST include these CLI arguments
SUPPORTED_ARGS = ["--jumphost", "--jumpuser"]   # TODO: make one for required too?


BEGIN {
  puts "pingnodes is starting...\n"
  if ARGV.length < 2
    puts "Usage: ./pingnodes.rb --nodes <nodeListFile>"
    puts "optional:"
    puts "\t--jumphost {<ip> | <host>}\tIP or hostname of jump server"
    puts "\t--jumpuser <user>\tuser to log in as in the jump server"
    exit
  end
}

END {
  puts "\npingnodes is ending..."
}


def checkCliArgs(args)
  # check whether all mandatory input arguments have been provided
  # TODO: check for any issues with optional arguments
  counter = 0
  for i in 0...args.size
    if MANDATORY_ARGS.find_index(args[i]) != nil
      counter += 1
    end
  end

  if counter != MANDATORY_ARGS.size
    puts "Not all mandatory arguments have been provided"
    return false
  end

  # if --jumphost was provided, we expect --jumpuser
  if args.find_index("--jumphost") != nil && args.find_index("--jumpuser") == nil
    puts "You need to provide --jumpuser when using --jumphost"
    return false
  end


  return true
end

def readNodeList(file)
  tmpList = Array.new
  IO.foreach(file) do |line|
    tmpList << line.chomp!
  end
  return tmpList
end



# start doing things here, read input arguments
validCliArgs = checkCliArgs(ARGV)
if validCliArgs == false
  exit
else
  puts "Input arguments are good, continuing ..."
end


# store input arguments in variables
if ARGV.index("--nodes"); nodeListFile = ARGV[ARGV.index("--nodes")+1]; else nodeListFile = "SampleNodeList.txt"; end
if ARGV.index("--jumphost"); jumpHost = ARGV[ARGV.index("--jumphost")+1]; else jumpHost = nil; end
if ARGV.index("--jumpuser"); jumpUser = ARGV[ARGV.index("--jumpuser")+1]; else jumpUser = nil; end

nodeList = readNodeList(nodeListFile) # read list of IPv6 nodes to ping
pp nodeList

testPinger = Pinger.new(nodeList[0], 0)



# prepare and start Pinger objects/threads
pingerThreads = Array.new
pingerObjs = Array.new
pingerThreads = (0...nodeList.size).map do |i|
  pingerObjs[i] = Pinger.new(nodeList[i], i, jumpHost, jumpUser)

  Thread.new(i) do |i|
    # Thread.current.report_on_exception = false
    pingerObjs[i].pingNode()
  end
end


# show up useful information on the terminal
Thread.start {
  loop do
    Gem.win_platform? ? (system "cls") : (system "clear")
    for i in 0...pingerObjs.size
      puts pingerObjs[i].getOutputString
    end
    sleep 1
  end
}

puts "Started #{nodeList.size} threads"
pingerThreads.each {|t| t.join}
