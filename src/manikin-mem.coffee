async = require 'async'
_ = require 'underscore'
tools = require 'manikin-tools'
xdate = require 'xdate'
absManikin = require './abstract-manikin'
{owns, modelToHasOnes, expectedHasOnes} = require './util'

if typeof setImmediate == 'undefined'
  setImmediate = (f) -> setTimeout(f, 0)

filterList = (data, filter = {}) ->
  keys = Object.keys(filter)
  data.filter (x) ->
    keys.every (k) -> x[k] == filter[k]

propagate = (onErr, onSucc) -> (err, rest...) -> if err? then onErr(err) else onSucc(rest...)


exports.create = ->

  api = {}
  dbObj = null

  getStore = (name) ->
    if name
      dbObj.collections[name]
    else
      dbObj.collections

  ensureHasOnesExist = (model, data, callback) ->
    expected = expectedHasOnes(getModel(), model, data)
    async.forEach expected, ({model,id,key}, callback) ->
      filterOne model, { id }, (err) ->
        return callback(new Error("Invalid hasOne-key for '#{key}'")) if err?
        callback()
    , callback

  deleteObjFromManyToManyRelations = (model, obj) ->
    getMetaModel()[model].manyToMany.forEach ({ ref, inverseName }) ->
      getStore(ref).forEach (x) ->
        x[inverseName] = x[inverseName].filter (s) -> s != obj.id

  deleteObjFromOneToManyRelations = (model, obj) ->
    whatToDelete = modelToHasOnes(getModel())[model] || []
    whatToDelete.forEach ({ inModel, fieldName }) ->
      filt = _.object([[fieldName, obj.id]])
      result = filterList(getStore(inModel), filt)
      result.forEach (r) ->
        r[fieldName] = null

  # Det som denna gör borde kunna abstraheras mer. Den borde bestå av ett par stycken primitiver.
  deleteObj = (model, obj) ->
    index = getStore(model).indexOf(obj)
    throw new Error("Impossible") if index == -1
    deleteObjFromManyToManyRelations(model, obj)
    deleteObjFromOneToManyRelations(model, obj)
    getStore(model).splice(index, 1)
    owns(getModel(), model).forEach ({ model, field }) ->
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
    _.pairs(getModel()[model].owners).forEach ([singular, plural]) ->
      matches = filterList(getStore(plural), { id: indata[singular] })
      match = matches[0]
      if matches.length == 1
        input[singular] = indata[singular]
        Object.keys(getModel()[model].indirectOwners).forEach (key) ->
          input[key] = match[key]
    input





  absApi = absManikin.create({

    apiClose: (callback) ->
      callback()

    apiConnect: (connData, callback) ->
      return callback(new Error("Invalid connection data. Please use an empty object.")) if typeof connData != 'object'
      dbObj = connData
      dbObj.collections ?= {}
      callback()

    createId: do ->
      counter = 0
      -> "uid#{++counter}"

    getApi: -> api

    addManyToMany: (entry, property, value, callback) ->
      entry[property].push(value)
      callback()

    listWithIdLimit: (model, filter, ids, callback) ->
      res1 = getStore(model)
      res2 = res1.filter (x) -> x.id in ids
      res3 = filterList(res2, filter)
      callback(null, res3)

    # Error message could be kept out of this. No need to impement the same text over and over.
    getModelDataById: (model, id, callback) ->
      modelData = filterList(getStore(model), { id })[0]
      if !modelData?
        callback(new Error("Could not find an instance of '#{model}' with id '#{id}'"))
      else
        callback(null, modelData)

    deleteManyRelation: (element, relation, id, callback) ->
      element[relation] = element[relation].filter (x) -> x != id
      setImmediate(callback)

    appendToCollection: (collection, entry, callback) ->
      getStore(collection).push(entry)
      callback(null, entry)

    listSorted: (model, filter, callback) ->
      result = filterList(getStore(model), filter)
      defaultSort = getModel()[model].defaultSort
      result = _(result).sortBy(defaultSort) if defaultSort
      callback(null, result)

    initDb: (callback) ->
      Object.keys(getModel()).forEach (key) ->
        getStore()[key] = []
      callback()

    ensureHasOnesExist # lite weird namn, men den behöver vara här. dependar på en av de andra funktionerna också.. mindre nice..
    filterOne # denna är det som dependas på. kan det lösas?
    

    setOwnerData # den ska fixas till!
    deleteObj # improve in terms of atomicity
  })
  getModel = absApi.getDbModel
  getMetaModel = absApi.getMetaModel
  api = _.omit(absApi, 'getDbModel', 'getMetaModel')
