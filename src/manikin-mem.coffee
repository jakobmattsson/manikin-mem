async = require 'async'
_ = require 'underscore'
tools = require 'manikin-tools'

later = (f, args...) ->
  if setImmediate?
    setImmediate(f.bind(null, args...))
  else
    setTimeout(f.bind(null, args...), 0)

toDateTimeFormat = (x) ->
  "2012-10-15T00:00:00.000Z"   ## denna måste beräknas på riktigt

filterList = (data, filter) ->
  keys = Object.keys(filter)
  data.filter (x) ->
    keys.every (k) -> x[k] == filter[k]


exports.create = ->

  api = {}

  lateLoadModel = null
  dbObj = null
  dbModel = null

  createId = do ->
    counter = 0
    -> "uid#{++counter}"

  initDb = ->
    if dbModel? && dbObj?
      Object.keys(dbModel).forEach (key) ->
        dbObj[key] = []

  mustHaveModel = (f) ->
    ->
      throw new Error("No model defined") if !dbModel?
      f.apply(this, arguments)

  preprocessInput = (model, data) ->
    fields = dbModel[model].fields

    out = {}

    _.pairs(fields).forEach ([name, info]) ->
      if info.type == 'date'
        out[name] = toDateTimeFormat(data[name])
      else
        out[name] = data[name]

    out



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
      initDb()
      later(callback)

  api.close = (callback) ->
    later(callback)

  api.load = (models, callback) ->
    dbModel = tools.desugar(models)
    initDb()
    later(callback)

  api.connectionData = -> dbObj

  api.post = mustHaveModel (model, indata, callback) ->
    input = _.extend({}, preprocessInput(model, indata), { id: createId() })
    dbObj[model].push(input)
    later(callback, null, input)

  api.list = mustHaveModel (model, filter, callback) ->
    result = filterList(dbObj[model], filter)
    later(callback, null, result)

  api.getOne = mustHaveModel (model, config, callback) ->
    filter = config.filter ? {}
    api.list model, filter, (err, data) ->
      return callback(err) if err?
      return callback(new Error("Could not find anything")) if data.length == 0
      callback(null, data[0])

  api.delOne = mustHaveModel ->

  api.putOne = mustHaveModel ->

  api.getMany = mustHaveModel ->

  api.delMany = mustHaveModel ->

  api.postMany = mustHaveModel ->

  api
