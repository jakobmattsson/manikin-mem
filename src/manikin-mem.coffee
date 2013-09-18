async = require 'async'
_ = require 'underscore'
tools = require 'manikin-tools'

if typeof setImmediate == 'undefined'
  setImmediate = (f) -> setTimeout(f, 0)

later = (f, args...) -> setImmediate(f.bind(null, args...))

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

defaultValidator = (api, value, callback) -> callback(true)

propagate = (onErr, onSucc) -> (err, rest...) -> if err? then onErr(err) else onSucc(rest...)

owns = (dbModel, ownerModel) ->
  _.flatten _.pairs(dbModel).map ([model, {owners, indirectOwners}]) ->
    _.pairs(owners).filter(([singular, plural]) -> plural == ownerModel).map ([singular, plural]) ->
      { model: model, field: singular }

formatField = (info, data) ->
  if info.type == 'date'
    toDateTimeFormat(data)
  else
    data

createId = do ->
  counter = 0
  -> "uid#{++counter}"



exports.create = ->

  api = {}
  dbObj = null
  dbModel = null

  getStore = (name) ->
    if name
      dbObj.collections[name]
    else
      dbObj.collections

  initDb = ->
    if dbModel? && dbObj?
      Object.keys(dbModel).forEach (key) ->
        getStore()[key] = []

  mustHaveModel = (f) ->
    (model, args..., callback) ->
      throw new Error("No model defined") if !dbModel?
      return later(callback, new Error("No model named #{model}")) if !dbModel[model]
      f.apply(this, arguments)

  preprocessInput = (model, data, includeDefaults, callback) ->
    inputKeys = Object.keys(data) # Detta hanterar inte nestade properties
    validKeys = Object.keys(dbModel[model].fields).concat(Object.keys(dbModel[model].owners))
    invalidKeys = _.difference(inputKeys, validKeys)
    return callback(new Error("Invalid fields: #{invalidKeys.join(', ')}")) if invalidKeys.length > 0

    out = {}
    async.forEach _.pairs(dbModel[model].fields), ([name, info], callback) ->
      return callback() if !includeDefaults && name not of data
      out[name] = formatField(info, data[name])
      validation = info.validate || defaultValidator
      validation api, out[name], (isOk) ->
        return callback() if isOk 
        er = new Error("Validation failed")
        er.errors = { name: path: name }
        callback(er)
    , (err) ->
      callback(err, out)

  deleteObj = (model, obj) ->
    index = getStore(model).indexOf(obj)
    throw new Error("Impossible") if index == -1
    getStore(model).splice(index, 1)
    owns(dbModel, model).forEach ({ model, field }) ->
      delAll(model, _.object([[field, obj.id]]))

  delAll = (model, filter) ->
    result = filterList(getStore(model), filter)
    result.forEach (r) ->
      deleteObj(model, r)

  filterOne = (model, filter, callback) ->
    result = filterList(getStore(model), filter)
    return callback(new Error("No such id")) if result.length == 0
    callback(null, result[0])

  setOwnerData = (model, indata) ->
    input = {}
    _.pairs(dbModel[model].owners).forEach ([singular, plural]) ->
      matches = filterList(getStore(plural), { id: indata[singular] })
      match = matches[0]
      if matches.length == 1
        input[singular] = indata[singular]
        Object.keys(dbModel[model].indirectOwners).forEach (key) ->
          input[key] = match[key]
    input



  api =
    connect: (connData, rest..., callback) ->
      [inputModels] = rest
      return callback(new Error("Invalid connection data. Please use an empty object.")) if typeof connData != 'object'
      dbObj = connData
      dbObj.collections ?= {}
      if inputModels
        api.load(inputModels, callback)
      else
        initDb()
        later(callback)

    close: (callback) ->
      later(callback)

    load: (models, callback) ->
      dbModel = tools.desugar(models)
      initDb()
      later(callback)

    connectionData: ->
      dbObj

    post: mustHaveModel (model, indata, callback) ->
      preprocessInput model, indata, true, propagate callback, (processedInput) ->
        input = _.extend({}, processedInput, setOwnerData(model, indata), { id: createId() })
        return callback(new Error("Must give owner k thx plz ._0")) if Object.keys(dbModel[model].owners).some((x) -> !input[x]?)
        getStore(model).push(input)
        later(callback, null, input)

    list: mustHaveModel (model, filter, callback) ->
      result = filterList(getStore(model), filter)
      defaultSort = dbModel[model].defaultSort
      result = _(result).sortBy(defaultSort) if defaultSort
      later(callback, null, result)

    getOne: mustHaveModel (model, config, callback) ->
      filter = config.filter ? {}
      api.list model, filter, propagate callback, (data) ->
        return callback(new Error('No such id')) if data.length == 0 && Object.keys(filter).length == 1 && 'id' of filter
        return callback(new Error('No match')) if data.length == 0
        callback(null, data[0])

    putOne: mustHaveModel (model, data, filter, callback) ->
      filterOne model, filter, propagate callback, (result) ->
        preprocessInput model, data, false, propagate callback, (d2) ->
          _.extend(result, d2)
          later(callback, null, result)

    delOne: mustHaveModel (model, filter, callback) ->
      filterOne model, filter, propagate callback, (result) ->
        deleteObj(model, result)
        later(callback, null, result)

    getMany: mustHaveModel (model, id, relation, callback) ->
      modelData = filterList(getStore(model), { id })[0] # vad händer om denna har en längd på noll?
      later ->
        callback(null, modelData[relation])

    delMany: mustHaveModel ->

    postMany: mustHaveModel (model, id1, relation, id2, callback) ->
      modelData = filterList(getStore(model), { id: id1 })[0] # vad händer om denna har en längd på noll?
      modelData[relation] = modelData[relation] || []
      modelData[relation].push(id2) # vad händer om denna redan finns i data settet?
      later(callback)



# Testa att alla operationerna anropar sin callback EFTER att de returnerat
