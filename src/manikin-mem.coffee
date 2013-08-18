async = require 'async'
_ = require 'underscore'
tools = require 'manikin-tools'

later = (f, args...) ->
  if setImmediate?
    setImmediate(f.bind(null, args...))
  else
    setTimeout(f.bind(null, args...), 0)

## denna måste beräknas på riktigt. utan timeCounter
toDateTimeFormat = do ->
  timeCounter = 0
  (x) ->
    ++timeCounter
    if timeCounter < 3
      "2012-10-15T00:00:00.000Z"
    else
      "2012-10-15T13:37:00.000Z"

filterList = (data, filter = {}) ->
  keys = Object.keys(filter)
  data.filter (x) ->
    keys.every (k) -> x[k] == filter[k]

deepCopy = (x) -> JSON.parse(JSON.stringify(x))

propagate = (onErr, onSucc) -> (err, rest...) -> if err? then onErr(err) else onSucc(rest...)


owns = (dbModel, ownerModel, includeIndirect) -> #includeIndirect är inte implementerad. men behövs den?
  _.flatten _.pairs(dbModel).map ([model, {owners, indirectOwners}]) ->
    _.pairs(owners).filter(([singular, plural]) -> plural == ownerModel).map ([singular, plural]) ->
      { model: model, field: singular }


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
    (model, args..., callback) ->
      throw new Error("No model defined") if !dbModel?
      return later(callback, new Error("No model named #{model}")) if !dbModel[model]
      f.apply(this, arguments)

  preprocessInput = (model, data, includeDefaults, callback) ->
    fields = dbModel[model].fields

    out = {}

    async.forEach _.pairs(fields), ([name, info], callback) ->
      return callback() if !includeDefaults && name not of data

      if info.type == 'date'
        out[name] = toDateTimeFormat(data[name])
      else
        out[name] = data[name]

      if info.validate
        info.validate api, out[name], (isOk) ->
          if !isOk
            er = new Error("Validation failed")
            er.errors = { name: path: name }
            callback(er)
          else
            callback()
      else
        callback()
    , (err) ->
      callback(err, out)

  deleteObj = (model, obj) ->
    index = dbObj[model].indexOf(obj)
    throw new Error("Impossible") if index == -1
    dbObj[model].splice(index, 1)
    owns(dbModel, model).forEach ({ model, field }) ->
      delAll(model, _.object([[field, obj.id]]))

  delAll = (model, filter) ->
    result = filterList(dbObj[model], filter)
    result.forEach (r) ->
      deleteObj(model, r)

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
    preprocessInput model, indata, true, propagate callback, (dd) ->
      input = _.extend({}, dd, { id: createId() })

      _.pairs(dbModel[model].owners).forEach ([singular, plural]) ->
        matches = filterList(dbObj[plural], { id: indata[singular] })
        match = matches[0]
        if matches.length == 1
          input[singular] = indata[singular]
          Object.keys(dbModel[model].indirectOwners).forEach (key) ->
            input[key] = match[key]

      if Object.keys(dbModel[model].owners).some((x) -> !input[x]?)
        return callback(new Error("Must give owner k thx plz ._0"))

      dbObj[model].push(input)
      later(callback, null, input)

  api.list = mustHaveModel (model, filter, callback) ->
    result = filterList(dbObj[model], filter)
    defaultSort = dbModel[model].defaultSort
    result = _(result).sortBy(defaultSort) if defaultSort
    later(callback, null, result)

  api.getOne = mustHaveModel (model, config, callback) ->
    filter = config.filter ? {}
    api.list model, filter, (err, data) ->
      return callback(err) if err?
      return callback(new Error("No such id")) if data.length == 0 && Object.keys(filter).length == 1 && "id" of filter
      return callback(new Error("No match")) if data.length == 0
      callback(null, data[0])

  api.putOne = mustHaveModel (model, data, filter, callback) ->
    result = filterList(dbObj[model], filter)
    return callback(new Error("No such id")) if result.length == 0
    preprocessInput model, data, false, propagate callback, (d2) ->
      _.extend(result[0], d2) # här måste man se till att inga ogiltiga objekt stoppas in
      later(callback, null, result[0])

  api.delOne = mustHaveModel (model, filter, callback) ->
    result = filterList(dbObj[model], filter)
    return callback(new Error("No such id")) if result.length == 0
    deleteObj(model, result[0])
    later(callback, null, result[0])





  api.getMany = mustHaveModel ->

  api.delMany = mustHaveModel ->

  api.postMany = mustHaveModel ->

  api
