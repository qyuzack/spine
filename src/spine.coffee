$ = @jQuery or Zepto or -> arguments[0]

Events = 
  bind: (ev, callback) ->
    evs   = ev.split(" ")
    calls = @hasOwnProperty("_callbacks") and @_callbacks or= {}
  
    for name in evs
      calls[name] or= []
      calls[name].push(callback)
    @

  trigger: (args...) ->
    ev = args.shift()
      
    list = @hasOwnProperty("_callbacks") and @_callbacks?[ev]
    return false unless list
  
    for callback in list
      if callback.apply(this, args) is false
        break      
    true

  unbind: (ev, callback) ->
    unless ev
      @_callbacks = {}
      return @
  
    list = @_callbacks?[ev]
    return @ unless list
  
    unless callback
      delete @_callbacks[ev]
      return @

    for cb, i in list when cb is callback
      list = list.slice()
      list.splice(i, 1)
      @_callbacks[ev] = list
      break
    @

Log =
  trace: true

  logPrefix: "(App)"

  log: (args...) ->
    return unless @trace
    return if typeof console is "undefined"
    if @logPrefix then args.unshift(@logPrefix)
    console.log.apply(console, args)
    @

moduleKeywords = ["included", "extended"]

class Module
  @include: (obj) ->
    for key, value of obj when key not in moduleKeywords
      @::[key] = value

    included = obj.included
    included.apply(this) if included
    @

  @extend: (obj) ->
    for key, value of obj when key not in moduleKeywords
      @[key] = value
    
    extended = obj.extended
    extended.apply(this) if extended
    @
    
  @proxy: (func) ->
    => func.apply(@, arguments)

  proxy: (func) ->
    => func.apply(@, arguments)

class Model extends Module
  @records: {}
  @attributes: []
  
  @setup: (name, attributes...) ->
    @className  = name
    @records    = {}
    @attributes = attributes if attributes.length
    @attributes and= makeArray(@attributes)
    @attributes or=  []
    @unbind()
    @
    
  @toString: -> "#{@className}(#{@attributes.join(", ")})"

  @find: (id) ->
    record = @records[id]
    throw("Unknown record") unless record
    record.clone()

  @exists: (id) ->
    try
      return @find(id)
    catch e
      return false

  @refresh: (values, options = {}) ->
    @records = {} if options.clear

    for record in @fromJSON(values) 
      record.newRecord    = false
      @records[record.id] = record

    @trigger("refresh")
    @

  @select: (callback) ->
    result = (record for id, record of @records when callback(record))
    @cloneArray(result)

  @findByAttribute: (name, value) ->
    for id, record of @records
      if record[name] == value
        return record.clone()
    null

  @findAllByAttribute: (name, value) ->
    @select (item) ->
      item[name] is value

  @each: (callback) ->
    for key, value of @records
      callback(value)

  @all: ->
    @cloneArray(@recordsValues())

  @first: ->
    record = @recordsValues()[0]
    record?.clone()

  @last: ->
    values = @recordsValues()
    record = values[values.length - 1]
    record?.clone()

  @count: ->
    @recordsValues().length

  @deleteAll: ->
    for key, value of @records
      delete @records[key]

  @destroyAll: ->
    for key, value of @records
      @records[key].destroy()

  @update: (id, atts) ->
    @find(id).updateAttributes(atts)

  @create: (atts) ->
    record = new @(atts)
    record.save()

  @destroy: (id) ->
    @find(id).destroy()

  @change: (callbackOrParams) ->
    if typeof callbackOrParams is "function"
      @bind("change", callbackOrParams)
    else
      @trigger("change", callbackOrParams)

  @fetch: (callbackOrParams) ->
    if typeof callbackOrParams is "function"
      @bind("fetch", callbackOrParams)
    else
      @trigger("fetch", callbackOrParams)

  @toJSON: ->
    @recordsValues()
  
  @fromJSON: (objects) ->
    return unless objects
    if typeof objects is "string"
      objects = JSON.parse(objects)
    if isArray(objects)
      (new @(value) for value in objects)
    else
      new @(objects)

  # Private

  @recordsValues: ->
    result = []
    for key, value of @records
      result.push(value)
    result

  @cloneArray: (array) ->
    (value.clone() for value in array)

  # Instance
 
  model: true
  newRecord: true

  constructor: (atts) ->
    super
    @load atts if atts

  isNew: () ->
    @newRecord
  
  isValid: () ->
    not @validate()

  validate: ->

  load: (atts) ->
    for key, value of atts
      @[key] = value

  attributes: ->
    result = {}
    result[key] = @[key] for key in @constructor.attributes
    result.id   = @id
    result

  eql: (rec) ->
    rec and rec.id is @id and rec.constructor is @constructor

  save: ->
    error = @validate()
    if error
      @trigger("error", @, error)
      return false
    
    @trigger("beforeSave", @)
    if @newRecord then @create() else @update()
    @trigger("save", @)
    return @

  updateAttribute: (name, value) ->
    @[name] = value
    @save()

  updateAttributes: (atts) ->
    @load(atts)
    @save()
  
  destroy: ->
    @trigger("beforeDestroy", @)
    delete @constructor.records[@id]
    @destroyed = true
    @trigger("destroy", @)
    @trigger("change", @, "destroy")

  dup: (newRecord) ->
    result = new @constructor(@attributes())
    if newRecord is false
      result.newRecord = @newRecord
    else
      delete result.id
    result
  
  clone: ->
    Object.create(@)

  reload: ->
    return @ if @newRecord
    original = @constructor.find(@id)
    @load(original.attributes())
    return original

  toJSON: ->
    @attributes()
    
  toString: ->
    "<#{@constructor.className} (#{JSON.stringify(@)})>"
  
  exists: ->
    @id && @id of @constructor.records

  # Private

  update: ->
    @trigger("beforeUpdate", @)
    records = @constructor.records
    records[@id].load @attributes()
    clone = records[@id].clone()
    @trigger("update", clone)
    @trigger("change", clone, "update")

  create: ->
    @trigger("beforeCreate", @)
    @id          = guid() unless @id
    @newRecord   = false    
    records      = @constructor.records
    records[@id] = @dup(false)
    clone        = records[@id].clone()
    @trigger("create", clone)
    @trigger("change", clone, "create")
  
  bind: (events, callback) ->
    @constructor.bind events, (record) =>
      if record && @eql(record)
        callback.apply(@, arguments)
  
  trigger: ->
    @constructor.trigger.apply(@constructor, arguments)

Model.extend(Events)

class Controller extends Module
  eventSplitter: /^(\w+)\s*(.*)$/
  tag: "div"
  
  constructor: (options) ->
    @options = options

    for key, value of @options
      @[key] = value

    @el = document.createElement(@tag) unless @el
    @el = $(@el)

    @events = @constructor.events unless @events
    @elements = @constructor.elements unless @elements

    @delegateEvents() if @events
    @refreshElements() if @elements
      
  $: (selector) -> $(selector, @el)
      
  delegateEvents: ->
    for key of @events
      methodName = @events[key]
      method     = @proxy(@[methodName])
      
      match      = key.match(@eventSplitter)
      eventName  = match[1]
      selector   = match[2]

      if selector is ''
        @el.bind(eventName, method)
      else
        @el.delegate(selector, eventName, method)
  
  refreshElements: ->
    for key, value of @elements
      @[value] = @$(key)
  
  delay: (func, timeout) ->
    setTimeout(@proxy(func), timeout || 0)
    
  html: (element) -> @el.html(element.el or element)

  append: (elements...) -> 
    elements = (e.el or e for e in elements)
    @el.append.apply(@el, elements)
    
  appendTo: (element) -> 
    @el.appendTo(element.el or element)

Controller.include(Events)
Controller.include(Log)

# Utilities & Shims

unless typeof Object.create is "function"
  Object.create = (o) ->
    F = ->
    F.prototype = o
    new F()

isArray = (value) ->
  Object::toString.call(value) is "[object Array]"
  
makeArray = (args) ->
  Array.prototype.slice.call(args, 0)
  
guid = ->
  'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace /[xy]/g, (c) ->
    r = Math.random() * 16 | 0
    v = if c is 'x' then r else r & 3 | 8
    v.toString 16
  .toUpperCase()

# Globals

if typeof exports is not "undefined"
  Spine = exports
else
  Spine = @Spine = {}
  
Spine.version = "2.0.0"
Spine.isArray = isArray
Spine.$       = $
Spine.Events  = Events
Spine.Log     = Log
Spine.Module  = Module
Spine.Controller = Controller
Spine.Model   = ->
  existingModel = Model
  class Model extends existingModel
  Model.setup.apply(Model, arguments)
  
# Backwards compatability

Module.create = Module.sub =
Controller.create = Controller.sub =
Model.sub = (instance, static) ->
  class result extends this
  result.include(instance) if instance
  result.extend(static) if static
  result.unbind?()
  result

Module.init = Controller.init = Model.init = (a1, a2, a3, a4, a5) ->
  new this(a1, a2, a3, a4, a5)

Spine.Class = Module