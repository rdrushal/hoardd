Redis = require 'redis'
Fs    = require 'fs'
Path  = require 'path'
os    = require 'os'


# Metrics to get from the client_info object
metrics = ['uptime_in_seconds', 'uptime_in_days', 'connected_clients',
           'blocked_clients', 'used_memory', 'total_commands_processed',
           'keyspace_hits', 'keyspace_misses', 'evicted_keys', 'db0'
          ]

module.exports = (server) ->
  run = () ->
    server.cli.debug "Running the redis plugin"

    # This script needs configuration
    try
      confPath     = Path.join server.sPath, 'redis.json'
      configFile   = Fs.readFileSync confPath, 'utf-8'
      conf         = JSON.parse configFile

    catch e
      # The error object has some information on the type of error, stacktrace, etc
      console.log "ERROR:\nType: #{e.type}\nArgs: #{e.arguments}\nMessage: #{e.message}"
      console.log "\nSTACKTRACE:\n", e.stack


    keysRegex = ///keys="([0-9]{0,10})"///

    getRedisStats = (redisHost, redisPort, prettyHost, qName) ->
      server.cli.debug "hostname = #{redisHost}:#{redisPort}"
      metricPrefix = "#{prettyHost}.redis.#{redisPort}"
      server.cli.debug "REDISSTATS: #{metricPrefix}"


      conn = Redis.createClient(redisPort, redisHost)

      conn.on 'ready', ->
        #server.cli.debug conn.server_info
        for key, value of conn.server_info when key in metrics
          if key == 'db0'
            key = 'total_keys'
            value = value.split "="
            #server.cli.debug " = split #{value}"
            value = value[1].split ","
            #server.cli.debug "#{value}"
            value = value[0]
            #server.cli.debug "keys: #{value}"
            #db0:keys=72363,expires=0,avg_ttl=0
          server.push_metric("#{metricPrefix}.#{key}", value)

        key = qName
        conn.llen qName, (err, replies) ->
          # console.log qName
          # console.log "ERR: #{err}"
          # console.log replies
          value = "#{replies}"
          # console.log "llen value = #{value}"

          server.push_metric("#{metricPrefix}.#{key}", value)

        conn.quit()

      conn.on 'error', (error) ->
        server.cli.error "Error when connect to Redis: #{error}"
        conn.quit()

      conn.on 'end', ->
        #  console.log "END EVENT"
         conn.quit()

    try
      redisServers = for nodes in conf.servers
        prettyHost = nodes.host
        if nodes.host == "localhost"
          prettyHost = os.hostname()
          prettyHost = prettyHost.split('.')
          prettyHost = prettyHost[0]
          server.cli.debug "prettyHost:" + prettyHost

        getRedisStats(nodes.host, nodes.port, prettyHost, 'wbc_primary_q')

      time = new Date().getTime()
      server.cli.info "Ran Redis Monitor - #{time}"

    catch e
      # The error object has some information on the type of error, stacktrace, etc
      console.log "ERROR:\nType: #{e.type}\nArgs: #{e.arguments}\nMessage: #{e.message}"
      console.log "\nSTACKTRACE:\n", e.stack

    finally
