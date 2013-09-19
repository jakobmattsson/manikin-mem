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
  dbMetaModel = null

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

  deleteObjFromManyToManyRelations = (model, obj) ->
    dbMetaModel[model].manyToMany.forEach ({ ref, inverseName }) ->
      getStore(ref).forEach (x) ->
        x[inverseName] = x[inverseName].filter (s) -> s != obj.id

  deleteObj = (model, obj) ->
    index = getStore(model).indexOf(obj)
    throw new Error("Impossible") if index == -1
    deleteObjFromManyToManyRelations(model, obj)
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


  ensureManyToManyIsArrays = (model, input) ->
    dbMetaModel[model].manyToMany.map ({name}) ->
      if !Array.isArray(input[name])
        input[name] = []


  insertOps = []




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
        setImmediate(callback)

    close: (callback) ->
      setImmediate(callback)

    load: (models, callback) ->
      dbModel = tools.desugar(models)
      dbMetaModel = tools.getMeta(dbModel)
      initDb()
      setImmediate(callback)

    connectionData: ->
      dbObj

    post: mustHaveModel (model, indata, callback) ->
      preprocessInput model, indata, true, propagate callback, (processedInput) ->
        input = _.extend({}, processedInput, setOwnerData(model, indata), { id: createId() })
        return callback(new Error("Must give owner k thx plz ._0")) if Object.keys(dbModel[model].owners).some((x) -> !input[x]?)
        ensureManyToManyIsArrays(model, input)
        setImmediate ->
          getStore(model).push(input)
          callback(null, input)

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
          setImmediate ->
            _.extend(result, d2)
            ensureManyToManyIsArrays(model, result)
            callback(null, result)

    delOne: mustHaveModel (model, filter, callback) ->
      self = @
      filterOne model, filter, propagate callback, (result) ->
        setImmediate ->
          deleteObj(model, result)
          callback(null, result)



    getMany: mustHaveModel (model, id, relation, filterData, callback) ->
      if !callback
        callback = filterData
        filterData = {}

      metadata = dbMetaModel[model].manyToMany.filter((x) -> x.name == relation)[0] # om noll matches?
      modelData = filterList(getStore(model), { id })[0] # vad händer om denna har en längd på noll?

      setImmediate ->
        result = getStore(metadata.ref)
        res = result.filter (x) -> x.id in (modelData[relation] || [])
        res = filterList(res, filterData)
        callback(null, res)



    delMany: mustHaveModel (model, id1, relation, id2, callback) ->
      metadata = dbMetaModel[model].manyToMany.filter((x) -> x.name == relation)[0]

      if !metadata?
        later(callback, new Error('Invalid many-to-many property'))
        return

      modelData = filterList(getStore(model), { id: id1 })[0] # vad händer om denna har en längd på noll?
      modelData2 = filterList(getStore(metadata.ref), { id: id2 })[0] # vad händer om denna har en längd på noll?

      setImmediate ->
        modelData[relation] = modelData[relation].filter (x) -> x != id2
        modelData2[metadata.inverseName] = modelData2[metadata.inverseName].filter (x) -> x != id1
        callback(null, modelData[relation]) # varför returnera något här? testa vad som ska komma tillbaka



    postMany: mustHaveModel (model, id1, relation, id2, callback) ->
      relationInfo = dbMetaModel[model].manyToMany.filter((x) -> x.name == relation)[0]

      if !relationInfo?
        later(callback, new Error('Invalid many-to-many property'))
        return

      inverseModel = relationInfo.ref
      inverseField = relationInfo.inverseName

      insertOpNow = [
        { primaryModel: model, primaryId: id1, propertyName: relation, secondaryId: id2 }
        { primaryModel: inverseModel, primaryId: id2, propertyName: inverseField, secondaryId: id1 }
      ]

      insertOpMatch = (x1, x2) ->
        x1.primaryModel == x2.primaryModel &&
        x1.primaryId    == x2.primaryId    &&
        x1.propertyName == x2.propertyName &&
        x1.secondaryId  == x2.secondaryId

      hasAlready = insertOps.some((x) -> insertOpNow.some((y) -> insertOpMatch(x, y)))

      if hasAlready
        setImmediate ->
          callback(null, { status: 'insert already in progress' })
        return

      insertOpNow.forEach (op) ->
        insertOps.push(op)


      # måste ju testa att denna releasas också.. utan detta så blir det lite tokigt..
      # Testa genom att ta bort en manyToMany som lagts till. Efter det måste det gå att lägga in den på nytt.
      # insertOps = insertOps.filter (x) -> !_(insertOpNow).contains(x)


      model1 = filterList(getStore(model), { id: id1 })[0] # vad händer om denna har en längd på noll?
      model2 = filterList(getStore(inverseModel), { id: id2 })[0] # vad händer om denna har en längd på noll?

      setImmediate ->
        model1[relation].push(id2) # vad händer om denna redan finns i data settet?
        model2[inverseField].push(id1) # vad händer om denna redan finns i data settet?
        callback(null, { status: 'inserted' })
