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








  filterOne = (model, filter, callback) ->
    result = filterList(getStore(model), filter)
    return callback(new Error("No such id")) if result.length == 0
    callback(null, result[0])






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
    



    deleteFromRelations: (list, callback) ->
      list.forEach ({ model, relation, id }) ->
        getStore(model).forEach (x) ->
          x[relation] = x[relation].filter (s) -> s != id
      callback()

    setFieldsToNull: (list, callback) ->
      list.forEach ({ model, field, value }) ->
        result = filterList(getStore(model), _.object([[field, value]]))
        result.forEach (r) ->
          r[field] = null
      callback()

    atomicDelete: (model, obj, callback) ->
      index = getStore(model).indexOf(obj)
      throw new Error("Impossible") if index == -1
      getStore(model).splice(index, 1)
      callback()
  })
  getModel = absApi.getDbModel
  getMetaModel = absApi.getMetaModel
  api = _.omit(absApi, 'getDbModel', 'getMetaModel')
