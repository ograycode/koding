class StartTabOldAppThumbView extends KDView

  constructor:(options, data)->
    newClass = if data.disabled? then 'start-tab-item disabled' else if data.catalog? then 'start-tab-item appcatalog' else 'start-tab-item'
    options = $.extend
      tagName     : 'figure'
      cssClass    : newClass
    , options
    super options, data

  viewAppended:->
    @setTemplate @pistachio()
    @template.update()

  pistachio:->
    {image} = @getData()
    """
      <img src="#{image}" />
      <cite>{{ #(name)}}</cite>
      <span>{{ #(type)}}</span>
    """

  click:(event)->
    {appToOpen, disabled} = @getData()
    {tab}                 = @getOptions()
    KD.getSingleton("appManager").openApplication appToOpen
