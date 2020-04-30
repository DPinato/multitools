
class Pinger

  def initialize(node, id, jumpHost=nil, jumpUser=nil)
    # by default, run pings from the local machine
    @node = node
    @jobId = id   # helps distinguish threads
    @jumpHost = jumpHost
    @jumpUser = jumpUser

    # basic check of input parameters
    if !IPAddress.valid?(@node)
      puts "Bad input values to Pinger object #{@jobId}"
      puts "node: #{@node}"
      exit
    end

    if @jumpHost != nil || @jumpUser != nil
      if !IPAddress.valid?(@jumpHost) || @jumpUser == nil
        puts "Bad input values to Pinger object #{@jobId}"
        puts "jumpHost: #{@jumpHost}"
        puts "jumpUser: #{@jumpUser}"
      end
    end

    # counters and variables related to
    @countSuccess = 0             # number of successful pings, i.e. answer was received before timeout
    @countFailure = 0             # number of failed pings, i.e. answer not received before timeout
    @totalCount = 0               # total number of ping commands executed
    @successString = ""           # this is used to store ! and .
    @maxSuccessStringLength = 60  # maximum length of successString that will be displayed

    # build base ping command to run
    # TODO: different OS will interpret the timeout value differently, i.e. seconds vs milliseconds
    @basePingCmd = "ping"
    if IPAddress.valid_ipv6?(@node)
      @basePingCmd += "6"
    end
    @basePingCmd += " #{@node} -c 1 -W 1000"   # MAC OS uses -W value in milliseconds


    @latencyHistory = Array.new
    @lastPing = 0.0               # latency of the latest ping
    @minPing = 10000.0            # minimum latency measured
    @maxPing = 0.0                # maximum latency measured
    @avgPing = 0.0                # average latency measured
    @rollingTotalLatency = 0.0    # sum of ping latencies, used to calculate avgPing
  end

  def pingNode()
    # start pings to node either from local machine or from jump server
    if @jumpHost != nil
      pingNodeFromJumpServer()
    else
      pingNodeFromLocal()
    end
  end

  def pingNodeFromLocal()
    # run ping command from the local machine
    # uses Open3 to get stdout and the exit status code
    # any exit status code apart from 0 indicate that the ping was not successful
    lastFailed = true
    time = Time.new
    outFile = File.open(time.strftime("%Y-%m-%d_%H-%M-%S_")+@jobId.to_s+".log", "w")

    loop do
      cmdOutput = ""
      stdout, stderr, status = Open3.capture3(@basePingCmd) # this should do just fine
      @totalCount += 1
      cmdOutput = stdout
      tmpTimestamp = DateTime.now.strftime('%Q').to_i

      pingResult = cmdOutput.split("\n")[1] # get result from ping, it will be the second line of STDOUT
      # pp pingResult

      timeNow = Time.now.strftime("%Y-%m-%d_%H-%M-%S")
      @lastPing = -1.0  # this will be overwritten if the ping succeeded


      if status.exitstatus > 0
        # ping failed
        lastFailed = true
        @countFailure += 1
        @successString << "."
        outFile.write("#{timeNow} -----" + "\n")
      else
        # ping succeeded
        lastFailed = false
        @countSuccess += 1
        @successString << "!"
        outFile.write(timeNow+" "+pingResult + "\n")

        # calculate stats
        @lastPing = getLatency(pingResult)
        @rollingTotalLatency += @lastPing
        @avgPing = @rollingTotalLatency / @countSuccess
        if @lastPing < @minPing; @minPing = @lastPing; end
        if @lastPing > @maxPing; @maxPing = @lastPing; end
      end

      @latencyHistory << @lastPing

      sleep 1
    end

    outFile.close
  end

  def pingNodeFromJumpServer()
    # TODO: This should probably be re-written to use the exit code of the remote ping command
    lastFailed = true
    time = Time.new
    outFile = File.open(time.strftime("%Y-%m-%d_%H-%M-%S_")+@jobId.to_s+".log", "w")

    Net::SSH.start(@jumpHost, @jumpUser, :forward_agent => true) do |ssh|
      loop do
        cmdOutput = ssh.exec!(@basePingCmd)
        @totalCount += 1

        pingResult = cmdOutput.split("\n")[1] # get result from ping, it will be the second line of STDOUT

        timeNow = Time.now.strftime("%Y-%m-%d_%H-%M-%S")
        @lastPing = -1.0  # this will be overwritten if the ping succeeded

        if pingResult == nil || pingResult == "" || pingResult =~ /unreachable/i
          # ping failed
          lastFailed = true
          @countFailure += 1
          @successString << "."
          outFile.write("#{timeNow} -----" + "\n")

        else
          # ping succeeded
          lastFailed = false
          @countSuccess += 1
          @successString << "!"
          outFile.write(timeNow+" "+pingResult + "\n")

          # calculate stats
          @lastPing = getLatency(pingResult)
          @rollingTotalLatency += @lastPing
          @avgPing = @rollingTotalLatency / @countSuccess
          if @lastPing < @minPing; @minPing = @lastPing; end
          if @lastPing > @maxPing; @maxPing = @lastPing; end
        end

        @latencyHistory << @lastPing

        sleep 1
        # ssh.loop
      end

    end

    outFile.close
  end
  def getLatency(str)
    # TODO: I would like for this to return a double, but it is not a big problem
    # returns a float comtaining the latency for the ping, in ms
    # if any of these index return nil, this method should not have been run
    pos1 = str.index("time=") + "time=".length
    pos2 = str.index("ms", pos1) - 1
    # puts str[pos1, pos2-pos1] + " #{str[pos1, pos2-pos1].length}"
    return str[pos1, pos2-pos1].to_f
  end



  def getOutputString
    # format data collected so far in a way that can be shown in a single line
    # a nice format would be
    # <IPv6> <countSuccess / countFailure / total> <! and ., up to maxSuccessStringLength characters
    outString = "#{@node}\t"
    outString << "#{@countSuccess.to_s}/#{@countFailure.to_s}/#{(@totalCount).to_s}\t"

    # show success rate
    successRate = 1.0
    if @totalCount != 0
      successRate = @countSuccess.to_f / @totalCount.to_f
      # puts successRate
    end
    outString << "(#{"%.2f" % (successRate*100).to_s}%)\t"

    # show historical success/fail string
    startIndex = @totalCount - @maxSuccessStringLength
    if startIndex >= 0
      outString << @successString[startIndex, @maxSuccessStringLength]
    else
      outString << @successString
    end
    outString << "\t"

    # show latency stats
    # TODO: this does not work very well with low latency, i.e. sub 10 ms
    outString << "#{"%.1f" % @lastPing} / "
    outString << "#{"%.1f" % @minPing} / "
    outString << "#{"%.1f" % @avgPing} / "
    outString << "#{"%.1f" % @maxPing}"

    return outString
  end


  attr_accessor :jumpHost, :jumpUser, :node, :jobId
  attr_accessor :basePingCmd
  attr_accessor :successString, :maxSuccessStringLength
  attr_accessor :countSuccess, :countFailure, :totalCount
  attr_accessor :latencyHistory, :lastPing, :maxPing, :minPing, :avgPing, :rollingTotalLatency

end
