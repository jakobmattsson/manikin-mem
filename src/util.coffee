_ = require 'underscore'

exports.owns = (dbModel, ownerModel) ->
  _.flatten _.pairs(dbModel).map ([model, {owners, indirectOwners}]) ->
    _.pairs(owners).filter(([singular, plural]) -> plural == ownerModel).map ([singular, plural]) ->
      { model: model, field: singular }

exports.modelToHasOnes = (dbModel) ->
  apa = _.flatten _.pairs(dbModel).map ([modelName, modelData]) ->
    fields = _.pairs(modelData.fields).filter(([fieldName, fieldData]) -> fieldData.type == 'hasOne')
    .map ([fieldName, fieldData]) -> { targetModel: fieldData.model, inModel: modelName, fieldName }
  _.groupBy(apa, 'targetModel')

exports.expectedHasOnes = (dbModel, model, data) ->
  hasOnes = _.pairs(dbModel[model].fields).filter(([key, {type}]) -> type == 'hasOne').map ([key]) -> key
  keys = _.object _.pairs(_.pick(data, hasOnes)).filter(([key, value]) -> value?)
  _.pairs(keys).map ([key, value]) ->
    model = dbModel[model].fields[key].model
    { model, key, id: value }
