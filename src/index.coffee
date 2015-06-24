path = require("path")
es = require("event-stream")
util = require("gulp-util")
http = require("http")
https = require("https")
fs = require("fs")
connect = require("connect")
liveReload = require("connect-livereload")
tiny_lr = require("tiny-lr")
opt = {}
server = undefined
lr = undefined

class ConnectApp
  constructor: (options) ->
    opt = options
    opt.port = opt.port || "8080"
    opt.root = opt.root || path.dirname(module.parent.id)
    opt.host = opt.host || "localhost"
    opt.debug = opt.debug || false
    @oldMethod("open") if opt.open
    @server()

  server: ->
    app = connect()
    @middleware().forEach (middleware) ->
      app.use middleware
    if opt.https?
      server = https.createServer
        key: opt.https.key || fs.readFileSync __dirname + '/certs/server.key'
        cert: opt.https.cert || fs.readFileSync __dirname + '/certs/server.crt'
        ca: opt.https.ca || fs.readFileSync __dirname + '/certs/ca.crt'
        passphrase: opt.https.passphrase || 'gulp'
        app
    else
      server = http.createServer app
    app.use connect.directory(if typeof opt.root == "object" then opt.root[0] else opt.root)
    server.listen opt.port, (err) =>
      if err
        @log "Error on starting server: #{err}"
      else
        @log "Server started http://#{opt.host}:#{opt.port}"
        
        stoped = false;
        sockets = [];
        
        server.on 'close', =>
          if (!stoped)
            stoped = true
            @log "Server stopped"

        # Log connections and request in debug
        server.on "connection", (socket) =>
          sockets.push socket
          socket.on "close", =>
            sockets.splice sockets.indexOf(socket), 1

        server.on "request", (request, response) =>
          @logDebug "Received request #{request.method} #{request.url}"
        
        stopServer = =>
          if (!stoped)
            sockets.forEach (socket) =>
              socket.destroy()

            server.close()
            process.nextTick( ->
              process.exit(0);
            )
            
        process.on("SIGINT", stopServer);
        process.on("exit", stopServer);
        
        if opt.livereload
          tiny_lr.Server::error = ->
          if opt.https?
            lr = tiny_lr
              key: opt.https.key || fs.readFileSync __dirname + '/certs/server.key'
              cert: opt.https.cert || fs.readFileSync __dirname + '/certs/server.crt'
          else
            lr = tiny_lr()
          lr.listen opt.livereload.port, ->
            if isNaN(opt.livereload.port)
              if fs.existsSync(opt.livereload.port)
                fs.chmodSync opt.livereload.port, '0777'
              else
                return _this.log('LiveReload could not start')
            return
          @log "LiveReload started on port #{opt.livereload.port}"

  middleware: ->
    middleware = if opt.middleware then opt.middleware.call(this, connect, opt) else []
    if opt.livereload
      opt.livereload = {}  if typeof opt.livereload is "boolean"
      opt.livereload.proxyport = opt.livereload.port or 35729 unless opt.livereload.proxyport
      
      middleware.push liveReload(port: opt.livereload.proxyport)
    if typeof opt.root == "object"
      opt.root.forEach (path) ->
        middleware.push connect.static(path)
    else
      middleware.push connect.static(opt.root)
    if opt.fallback
      middleware.push (req, res) ->
        require('fs').createReadStream(opt.fallback).pipe(res);

    return middleware

  log: (@text) ->
    if !opt.silent
      util.log util.colors.green(@text)

  logWarning: (@text) ->
    if !opt.silent
      util.log util.colors.yellow(@text)

  logDebug: (@text) ->
    if opt.debug
      util.log util.colors.blue(@text)

  oldMethod: (type) ->
    text = 'does not work in gulp-connect v 2.*. Please read "readme" https://github.com/AveVlad/gulp-connect'
    switch type
      when "open" then @logWarning("Option open #{text}")

module.exports =
  server: (options = {}) -> new ConnectApp(options)
  reload: ->
    es.map (file, callback) ->
      if opt.livereload and typeof lr == "object"
        lr.changed body:
          files: file.path
      callback null, file
  serverClose: -> do server.close
