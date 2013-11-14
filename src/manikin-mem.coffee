_ = require 'underscore'
absManikin = require './abstract-manikin'

filterList = (data, filter = {}) ->
  keys = Object.keys(filter)
  data.filter (x) ->
    keys.every (k) ->
      if Array.isArray(filter[k])
        if Array.isArray(x[k])
          x[k].some (v) -> filter[k].indexOf(v) != -1
        else
          filter[k].indexOf(x[k]) != -1
      else
        x[k] == filter[k]

exports.create = ->

  dbObj = null

  getStore = (name) ->
    if name
      dbObj.collections[name]
    else
      dbObj.collections

  absInstance = absManikin.create({

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

    addManyToMany: (entry, property, value, callback) ->
      entry[property].push(value)
      callback()

    listWithIdLimit: (model, filter, ids, callback) ->
      res1 = getStore(model)
      res2 = res1.filter (x) -> x.id in ids
      res3 = filterList(res2, filter)
      callback(null, res3)

    getModelDataById: (model, id, callback) ->
      modelData = filterList(getStore(model), { id })[0]
      if !modelData?
        callback(new Error("Could not find an instance of '#{model}' with id '#{id}'"))
      else
        callback(null, modelData)

    deleteManyRelation: (element, relation, id, callback) ->
      element[relation] = element[relation].filter (x) -> x != id
      callback()

    appendToCollection: (collection, entry, callback) ->
      getStore(collection).push(entry)
      callback(null, entry)

    listSorted: (model, filter, callback) ->
      result = filterList(getStore(model), filter)
      defaultSort = absInstance.getDbModel()[model].defaultSort
      result = _(result).sortBy(defaultSort) if defaultSort
      callback(null, result)

    initDb: (callback) ->
      Object.keys(absInstance.getDbModel()).forEach (key) ->
        getStore()[key] = []
      callback()

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

    filterOne: (model, filter, callback) ->
      result = filterList(getStore(model), filter)
      return callback(new Error("No such id")) if result.length == 0
      callback(null, result[0])
  })

  absInstance.api
