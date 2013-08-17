jscov = require 'jscov'
manikinSpec = require 'manikin'
_ = require 'underscore'
async = require 'async'

manikin = require jscov.cover('..', 'lib', 'manikin-mem')

dropDatabase = (connData, done) ->
  Object.keys(connData).forEach (key) ->
    delete connData[key]
  done()

connData = {}

manikinSpec.runTests(manikin, dropDatabase, connData)
