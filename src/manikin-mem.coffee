exports.create = ->

  api = {}

  lateLoadModel = null

  api.connect = (databaseUrl, inputModels, callback) ->
    if !callback? && typeof inputModels == 'function'
      callback = inputModels
      inputModels = lateLoadModel

    if inputModels
      api.load(inputModels, callback)
    else
      callback()


  api.close = (callback) ->
    callback()

  api.load = (models, callback) ->
    callback()

  api.connectionData = ->

  api.post = ->

  api.list = ->
  
  api.getOne = ->

  api.delOne = ->

  api.putOne = ->

  api.getMany = ->

  api.delMany = ->

  api.postMany = ->

  api
