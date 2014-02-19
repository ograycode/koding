# Kontrol is a class for communicating with the Kontrol Kite.
# In our application, there is only one instance of this and it can be
# reachable from KD.getSingleton("kontrol").
class Kontrol extends KDObject

  # TODO We need to send "watch" commands again on re-connection because old watchers will be removed on disconnect.
  # TODO Tokens need to be renewed before they expire.
  # TODO A token must be renewed when we get "authenticationError" from remote kite.

  constructor: (options={})->
    super options

    kite =
      name     : "kontrol"
      url      : "#{KD.config.newkontrol.url}"

    authentication =
      type     : "sessionID"
      key      : KD.remote.getSessionToken()

    @kite = new NewKite kite, authentication
    @kite.connect()
    @kite.on "ready", => @emit "ready"
  # getKites Calls the callback function with the list of NewKite instances.
  # The returned kites are not connected. You must connect with
  # NewKite.connect().
  #
  # Query parameters are below from general to specific:
  #
  #   username    string
  #   environment string
  #   name        string
  #   version     string
  #   region      string
  #   hostname    string
  #   id          string
  #
  getKites: (query={}, callback = noop)->
    @_sanitizeQuery query

    @kite.tell("getKites", [query]).then (kites) =>
      (@_createKite k for k in kites)

    .nodeify(callback)

  getKite: (query, callback) ->
    @getKites(query).then (kites) ->
      return kites[0] ? throw new Error "no kite found!"

  # watchKites watches for Kites that matches the query. The onEvent functions
  # is called for current kites and every new kite event.
  watchKites: (query={}, callback)->
    @_sanitizeQuery query

    changes = new KDEventEmitter

    onEvent = (options)=>
      err = options.withArgs[1]
      return callback err, null  if err

      e = options.withArgs[0]
      changes.emit kiteAction[e.action], kite: @_createKite e

    @kite.tell("getKites", [query, onEvent])
    .then ({ kites, watcherID }) =>

      # TODO Watcher ID is here but I don't know where to store it. (Cenk)
      # result.watcherID

      for kite in kites
        { action: kiteAction.register, kite: @_createKite kite, changes }

    .nodeify callback

  cancelWatcher: (id, callback)->
    @kite.tell "cancelWatcher", [id], (err, result)=>
      return callback err  # result will always be "null"

  # Returns a new NewKite instance from Kite data structure coming from
  # getKites() and watchKites() methods.
  _createKite: (k)->
    new NewKite k.kite, {type: "token", key: k.token}

  _sanitizeQuery: (query) ->
    query.username    = "#{KD.nick()}"              unless query.username
    query.environment = "#{KD.config.environment}"  unless query.environment

  kiteAction    =
    REGISTER    : "register"
    DEREGISTER  : "deregister"
