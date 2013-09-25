async = require 'async'
_ = require 'underscore'
tools = require 'manikin-tools'
xdate = require 'xdate'
absManikin = require './abstract-manikin'

if typeof setImmediate == 'undefined'
  setImmediate = (f) -> setTimeout(f, 0)

later = (f, args...) -> setImmediate(f.bind(null, args...))

toDateTimeFormat = (x) -> new xdate(x, true).toString('yyyy-MM-dd HH:mm:ss.fffzz').replace(' ', 'T')

filterList = (data, filter = {}) ->
  keys = Object.keys(filter)
  data.filter (x) ->
    keys.every (k) -> x[k] == filter[k]

delayCallback = (f) -> (args...) -> setImmediate => f(args...)

deepCopy = (x) -> JSON.parse(JSON.stringify(x))

defaultValidator = (api, value, callback) -> callback(true)

propagate = (onErr, onSucc) -> (err, rest...) -> if err? then onErr(err) else onSucc(rest...)

owns = (dbModel, ownerModel) ->
  _.flatten _.pairs(dbModel).map ([model, {owners, indirectOwners}]) ->
    _.pairs(owners).filter(([singular, plural]) -> plural == ownerModel).map ([singular, plural]) ->
      { model: model, field: singular }

modelToHasOnes = (dbModel) ->
  apa = _.flatten _.pairs(dbModel).map ([modelName, modelData]) ->
    fields = _.pairs(modelData.fields).filter(([fieldName, fieldData]) -> fieldData.type == 'hasOne')
    .map ([fieldName, fieldData]) -> { targetModel: fieldData.model, inModel: modelName, fieldName }
  _.groupBy(apa, 'targetModel')


formatField = (info, data) ->
  if info.type == 'date'
    toDateTimeFormat(data)
  else
    data

createId = do ->
  counter = 0
  -> "uid#{++counter}"


expectedHasOnes = (dbModel, model, data) ->
  hasOnes = _.pairs(dbModel[model].fields).filter(([key, {type}]) -> type == 'hasOne').map ([key]) -> key
  keys = _.object _.pairs(_.pick(data, hasOnes)).filter(([key, value]) -> value?)
  _.pairs(keys).map ([key, value]) ->
    model = dbModel[model].fields[key].model
    { model, key, id: value }


preprocessInputCore = (dbModel, model, data, includeDefaults, ensureHasOnesExist, api, callback) ->
  inputKeys = Object.keys(data) # Detta hanterar inte nestade properties
  validKeys = Object.keys(dbModel[model].fields).concat(Object.keys(dbModel[model].owners))
  invalidKeys = _.difference(inputKeys, validKeys)
  return callback(new Error("Invalid fields: #{invalidKeys.join(', ')}")) if invalidKeys.length > 0
  ensureHasOnesExist model, data, propagate callback, ->
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




exports.create = ->

  api = {}
  dbObj = null
  dbModel123 = null
  dbMetaModel = null

  getStore = (name) ->
    if name
      dbObj.collections[name]
    else
      dbObj.collections

  getModel = -> dbModel123

  initDb = ->
    if getModel()? && dbObj?
      Object.keys(getModel()).forEach (key) ->
        getStore()[key] = []

  mustHaveModel = (f) ->
    (model, args..., callback) ->
      throw new Error("No model defined") if !getModel()?
      return later(callback, new Error("No model named #{model}")) if !getModel()[model]
      f.apply(this, arguments)

  ensureHasOnesExist = (model, data, callback) ->
    expected = expectedHasOnes(getModel(), model, data)
    async.forEach expected, ({model,id,key}, callback) ->
      filterOne model, { id }, (err) ->
        return callback(new Error("Invalid hasOne-key for '#{key}'")) if err?
        callback()
    , callback

  preprocessInput = (model, data, includeDefaults, callback) ->
    preprocessInputCore(getModel(), model, data, includeDefaults, ensureHasOnesExist, api, callback)

  deleteObjFromManyToManyRelations = (model, obj) ->
    dbMetaModel[model].manyToMany.forEach ({ ref, inverseName }) ->
      getStore(ref).forEach (x) ->
        x[inverseName] = x[inverseName].filter (s) -> s != obj.id

  deleteObjFromOneToManyRelations = (model, obj) ->
    whatToDelete = modelToHasOnes(getModel())[model] || []
    whatToDelete.forEach ({ inModel, fieldName }) ->
      filt = _.object([[fieldName, obj.id]])
      result = filterList(getStore(inModel), filt)
      result.forEach (r) ->
        r[fieldName] = null

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

  ensureManyToManyIsArrays = (model, input) ->
    dbMetaModel[model].manyToMany.map ({name}) ->
      if !Array.isArray(input[name])
        input[name] = []

  getManyToManyMeta = (model, relation, callback) ->
    metadata = dbMetaModel[model].manyToMany.filter((x) -> x.name == relation)[0]
    if !metadata?
      callback(new Error('Invalid many-to-many property'))
    else
      callback(null, metadata)

  getModelDataById = (model, id, callback) ->
    modelData = filterList(getStore(model), { id })[0]
    if !modelData?
      callback(new Error("Could not find an instance of '#{model}' with id '#{id}'"))
    else
      callback(null, modelData)

  appendToCollection = (collection, entry, callback) ->
    getStore(collection).push(entry)
    callback(null, entry)

  deleteManyRelation = (element, relation, id, callback) ->
    element[relation] = element[relation].filter (x) -> x != id
    setImmediate(callback)

  listSorted = (model, filter, callback) ->
    result = filterList(getStore(model), filter)
    defaultSort = getModel()[model].defaultSort
    result = _(result).sortBy(defaultSort) if defaultSort
    callback(null, result)

  listWithIdLimit = (model, filter, ids, callback) ->
    res1 = getStore(model)
    res2 = res1.filter (x) -> x.id in ids
    res3 = filterList(res2, filter)
    callback(null, res3)

  addManyToMany = (entry, property, value, callback) ->
    entry[property].push(value)
    callback()


  lockInsertion = do ->
    insertOps = []

    (model, id1, relation, id2, inverseModel, inverseField, callback, next) ->

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
        # ännu bättre vore kanske att vänta på processen som håller på att stoppa in den och sedan returnera samtidigt?
        # mycket mer användbart!
        callback(null, { status: 'insert already in progress' })
        return

      insertOpNow.forEach (op) ->
        insertOps.push(op)

      setImmediate ->
        next (args...) ->
          args = [null, { status: 'inserted' }] if args.length == 0
          insertOps = insertOps.filter (x) -> !_(insertOpNow).contains(x)
          callback(args...)

  api =
    connect: delayCallback (connData, rest..., callback) ->
      [inputModels] = rest
      return callback(new Error("Invalid connection data. Please use an empty object.")) if typeof connData != 'object'
      dbObj = connData
      dbObj.collections ?= {}
      if inputModels
        api.load(inputModels, callback)
      else
        initDb()
        callback()

    close: delayCallback (callback) ->
      callback()

    load: delayCallback (models, callback) ->
      dbModel123 = tools.desugar(models)
      dbMetaModel = tools.getMeta(dbModel123)
      initDb()
      callback()

    connectionData: ->
      dbObj

    post: mustHaveModel delayCallback (model, indata, callback) ->
      preprocessInput model, indata, true, propagate callback, (processedInput) ->
        input = _.extend({}, processedInput, setOwnerData(model, indata), { id: createId() })
        return callback(new Error("Must give owner k thx plz ._0")) if Object.keys(getModel()[model].owners).some((x) -> !input[x]?)
        ensureManyToManyIsArrays(model, input)
        appendToCollection(model, input, callback)

    list: mustHaveModel delayCallback listSorted

    getOne: mustHaveModel delayCallback (model, config, callback) ->
      filter = config.filter ? {}
      api.list model, filter, propagate callback, (data) ->
        return callback(new Error('No such id')) if data.length == 0 && Object.keys(filter).length == 1 && 'id' of filter
        return callback(new Error('No match')) if data.length == 0
        callback(null, data[0])

    putOne: mustHaveModel delayCallback (model, data, filter, callback) ->
      preprocessInput model, data, false, propagate callback, (d2) ->
        filterOne model, filter, propagate callback, (result) ->
          _.extend(result, d2)
          ensureManyToManyIsArrays(model, result)
          callback(null, result)

    delOne: mustHaveModel delayCallback (model, filter, callback) ->
      filterOne model, filter, propagate callback, (result) ->
        deleteObj(model, result)
        callback(null, result)

    getMany: mustHaveModel delayCallback (model, id, relation, filterData, callback) ->
      if !callback
        callback = filterData
        filterData = {}

      getManyToManyMeta model, relation, propagate callback, (metadata) ->
        getModelDataById model, id, propagate callback, (modelData) ->
          listWithIdLimit(metadata.ref, filterData, modelData[relation] || [], callback)

    delMany: mustHaveModel delayCallback (model, id1, relation, id2, callback) ->
      getManyToManyMeta model, relation, propagate callback, (metadata) ->
        getModelDataById model, id1, propagate callback, (modelData) ->
          getModelDataById metadata.ref, id2, propagate callback, (modelData2) ->
            deleteManyRelation modelData, relation, id2, propagate callback, ->
              deleteManyRelation modelData2, metadata.inverseName, id1, propagate callback, ->
                callback()

    postMany: mustHaveModel (model, id1, relation, id2, callback) ->
      getManyToManyMeta model, relation, propagate callback, (relationInfo) ->
        getModelDataById model, id1, propagate callback, (model1) ->
          getModelDataById relationInfo.ref, id2, propagate callback, (model2) ->
            lockInsertion model, id1, relation, id2, relationInfo.ref, relationInfo.inverseName, callback, (done) ->

              has1 = id2 in model1[relation]
              has2 = id1 in model2[relationInfo.inverseName]

              if has1 && has2
                done(null, { status: 'already inserted' })
              else if !has1 && !has2
                addManyToMany model1, relation, id2, propagate done, ->
                  addManyToMany model2, relationInfo.inverseName, id1, propagate done, ->
                    done()
              else
                done(new Error("How the fuck did this happen? Totally invalid state!"))
