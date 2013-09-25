async = require 'async'
_ = require 'underscore'
tools = require 'manikin-tools'
xdate = require 'xdate'

if typeof setImmediate == 'undefined'
  setImmediate = (f) -> setTimeout(f, 0)

later = (f, args...) -> setImmediate(f.bind(null, args...))

toDateTimeFormat = (x) -> new xdate(x, true).toString('yyyy-MM-dd HH:mm:ss.fffzz').replace(' ', 'T')

delayCallback = (f) -> (args...) -> setImmediate => f(args...)

defaultValidator = (api, value, callback) -> callback(true)

propagate = (onErr, onSucc) -> (err, rest...) -> if err? then onErr(err) else onSucc(rest...)

formatField = (info, data) ->
  if info.type == 'date'
    toDateTimeFormat(data)
  else
    data

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




exports.create = (abstracts) ->

  {
    listWithIdLimit
    addManyToMany
    getModelDataById
    deleteManyRelation
    filterOne
    deleteObj
    listSorted
    createId
    apiConnect
    apiClose
    initDb
    ensureHasOnesExist
    appendToCollection
    getApi
  } = abstracts

  connectionDataObj = null
  dbModel123 = null
  dbMetaModel = null

  getModel = -> dbModel123
  getMetaModel = -> dbMetaModel

  setOwnerData = (model, indata, callback) ->
    input = {}
    async.forEach _.pairs(getModel()[model].owners), ([singular, plural], callback) ->
      getModelDataById plural, indata[singular], propagate callback, (match) ->
        input[singular] = indata[singular]
        Object.keys(getModel()[model].indirectOwners).forEach (key) ->
          input[key] = match[key]
        callback()
    , propagate callback, ->
      callback(null, input)

  # detta är helt fel. det är inte alls säkert att manyToMany är lagrad som en array för den abstraka manikin-implementationen!
  ensureManyToManyIsArrays = (model, input) ->
    getMetaModel()[model].manyToMany.map ({name}) ->
      if !Array.isArray(input[name])
        input[name] = []

  mustHaveModel = (f) ->
    (model, args..., callback) ->
      throw new Error("No model defined") if !getModel()?
      return later(callback, new Error("No model named #{model}")) if !getModel()[model]
      f.apply(this, arguments)

  getManyToManyMeta = (model, relation, callback) ->
    metadata = getMetaModel()[model].manyToMany.filter((x) -> x.name == relation)[0]
    if !metadata?
      callback(new Error('Invalid many-to-many property'))
    else
      callback(null, metadata)

  preprocessInput = (model, data, includeDefaults, callback) ->
    preprocessInputCore(model, data, includeDefaults, ensureHasOnesExist, getApi(), callback)

  preprocessInputCore = (model, data, includeDefaults, ensureHasOnesExist, api, callback) ->
    dbModel = getModel()
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




  api =
    connect: delayCallback (connData, rest..., callback) ->
      [inputModels] = rest
      apiConnect connData, propagate callback, ->
        connectionDataObj = connData

        if inputModels
          api.load(inputModels, callback)
        else
          if dbModel123?
            initDb(callback)
          else
            callback()

    close: delayCallback apiClose

    load: delayCallback (models, callback) ->
      dbModel123 = tools.desugar(models)
      dbMetaModel = tools.getMeta(dbModel123)

      if connectionDataObj?
        initDb(callback)
      else
        callback()

    connectionData: -> connectionDataObj
    getDbModel: -> dbModel123
    getMetaModel: -> dbMetaModel

    post: mustHaveModel delayCallback (model, indata, callback) ->
      preprocessInput model, indata, true, propagate callback, (processedInput) ->
        setOwnerData model, indata, propagate callback, (ownerData) ->
          input = _.extend({}, processedInput, ownerData, { id: createId() })
          ensureManyToManyIsArrays(model, input)
          appendToCollection(model, input, callback)


    list: mustHaveModel delayCallback listSorted

    # Inneffektiv implementation. Borde inte hämta ALLA objekt; bättre att ha en atomär operation till i så fall.
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
        deleteObj model, result, propagate callback, ->
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
