later = (f) ->
  if setImmediate?
    setImmediate(f)
  else
    setTimeout(f, 0)

exports.create = ->

  api = {}

  lateLoadModel = null
  dbObj = null
  dbModel = null

  api.connect = (connData, inputModels, callback) ->
    if !callback? && typeof inputModels == 'function'
      callback = inputModels
      inputModels = lateLoadModel

    if typeof connData != 'object'
      return callback(new Error("Invalid connection data. Please use an empty object."))

    dbObj = connData

    if inputModels
      api.load(inputModels, callback)
    else
      later(callback)


  api.close = (callback) ->
    later(callback)

  api.load = (models, callback) ->
    dbModel = models
    later(callback)

  api.connectionData = -> dbObj

  api.post = (model, indata, callback) ->
    later(callback)

  api.list = ->
  
  api.getOne = ->

  api.delOne = ->

  api.putOne = ->

  api.getMany = ->

  api.delMany = ->

  api.postMany = ->

  api
