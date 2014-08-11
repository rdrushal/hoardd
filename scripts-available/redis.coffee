Redis = require 'redis'
Fs    = require 'fs'
Path  = require 'path'
os    = require 'os'


# Metrics to get from the client_info object
metrics = ['uptime_in_seconds', 'uptime_in_days', 'connected_clients',
           'blocked_clients', 'used_memory', 'total_commands_processed',
           'keyspace_hits', 'keyspace_misses', 'evicted_keys', 'db0'
          ]

# db0 is used report the total number of keys in the redis instance.

module.exports = (server) ->
  run = () ->
    server.cli.debug "Running the redis plugin"

    # This script needs configuration. It uses a file redis.json that
    # contains the list of the servers this script will query.
    try
      confPath     = Path.join server.sPath, 'redis.json'
      configFile   = Fs.readFileSync confPath, 'utf-8'
      conf         = JSON.parse configFile

    catch e
      # The error object has some information on the type of error, stacktrace, etc
      console.log "ERROR:\nType: #{e.type}\nArgs: #{e.arguments}\nMessage: #{e.message}"
      console.log "\nSTACKTRACE:\n", e.stack

    # This regex is used to extract the total number of keys in redis.
    keysRegex = ///keys="([0-9]{0,10})"///

    getRedisStats = (redisHost, redisPort, prettyHost, qName) ->
      server.cli.debug "hostname = #{redisHost}:#{redisPort}"
      metricPrefix = "#{prettyHost}.redis.#{redisPort}"

      conn = Redis.createClient(redisPort, redisHost)

      conn.on 'ready', ->
        # Check if any keys match the 'db0' value. This is used to extract
        # the total number of keys in the redis instance. Else, push metric
        # and value.
        for key, value of conn.server_info when key in metrics
          if key == 'db0'
            key = 'total_keys'
            value = value.split "="
            value = value[1].split ","
            value = value[0]
          server.push_metric("#{metricPrefix}.#{key}", value)
        conn.quit()

      conn.on 'error', (error) ->
        server.cli.error "Error when connect to Redis: #{error}"
        conn.quit()

      conn.on 'end', ->
        conn.quit()

    try
      redisServers = for nodes in conf.servers
        # Use the computer name for redis instances residing on localhost when
        # pushing metrics.
        prettyHost = nodes.host
        if nodes.host == "localhost"
          prettyHost = os.hostname()
          prettyHost = prettyHost.split('.')
          prettyHost = prettyHost[0]
          server.cli.debug "prettyHost:" + prettyHost

        getRedisStats(nodes.host, nodes.port, prettyHost)

      time = new Date().getTime()
      server.cli.info "Ran Redis Monitor - #{time}"

    catch e
      # The error object has some information on the type of error, stacktrace, etc
      console.log "ERROR:\nType: #{e.type}\nArgs: #{e.arguments}\nMessage: #{e.message}"
      console.log "\nSTACKTRACE:\n", e.stack

    finally
