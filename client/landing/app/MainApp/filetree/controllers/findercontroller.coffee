class NFinderController extends KDViewController

  constructor:(options = {}, data)->

    {nickname}  = KD.whoami().profile

    options.view = new KDView cssClass : "nfinder file-container"
    treeOptions  = {}
    treeOptions.treeItemClass     = options.treeItemClass     or= NFinderItem
    treeOptions.nodeIdPath        = options.nodeIdPath        or= "path"
    treeOptions.nodeParentIdPath  = options.nodeParentIdPath  or= "parentPath"
    treeOptions.dragdrop          = options.dragdrop           ?= yes
    treeOptions.foldersOnly       = options.foldersOnly        ?= no
    treeOptions.hideDotFiles      = options.hideDotFiles       ?= no
    treeOptions.multipleSelection = options.multipleSelection  ?= yes
    treeOptions.addOrphansToRoot  = options.addOrphansToRoot   ?= no
    treeOptions.putDepthInfo      = options.putDepthInfo       ?= yes
    treeOptions.contextMenu       = options.contextMenu        ?= yes
    treeOptions.maxRecentFolders  = options.maxRecentFolders  or= 10
    treeOptions.useStorage        = options.useStorage         ?= no
    treeOptions.loadFilesOnInit   = options.loadFilesOnInit    ?= no
    treeOptions.delegate          = @

    super options, data

    TreeControllerClass = options.treeControllerClass or NFinderTreeController
    @treeController     = new TreeControllerClass treeOptions, []

    @appStorage = KD.getSingleton('appStorageController').storage 'Finder', '1.1'

    if options.useStorage
      @appStorage.ready =>
        @treeController.on "file.opened", @bound 'setRecentFile'
        @treeController.on "folder.expanded", (folder)=>
          @setRecentFolder folder.path
        @treeController.on "folder.collapsed", ({path})=>
          @unsetRecentFolder path
          @stopWatching path

    @noVMFoundWidget = new VMMountStateWidget
    @cleanup()

    KD.getSingleton("vmController").on "StateChanged", @bound "checkVMState"

    kc = KD.getSingleton("kiteController")
    kc.on "KiteConnected", (kitename) =>
      @mountFSKite kitename
      kc.once "KiteDisconnected", => @unmountFSKite kitename

  watchers: {}

  mountFSKite:(kitename)->
    log "FinderController: Mounting", kitename
    if kitename is "fs"

      vmName = "local-#{KD.nick()}"

      options =
        kiteName        : "fs"
        method          : "vm.info"
        correlationName : vmName

      kc = KD.getSingleton("kiteController")
      kc.run options, (err, info) =>
        if err then log err
        path = if info.homeDir then info.homeDir else "/Users/#{KD.nick()}"

        @vms.push FSHelper.createFile
          name   : "#{path}"
          path   : "[#{vmName}]#{path}"
          type   : "vm"
          vmName : vmName

        @treeController.addNode @vms.last

  unmountFSKite:(kitename)->
    log "FinderController: Unmounting", kitename
    if kitename is "fs"
      vmName = "local-#{KD.nick()}"
      vmItem = @getVmNode vmName

      FSHelper.unregisterVmFiles vmName
      @treeController.removeNodeView vmItem

  registerWatcher:(path, stopWatching)->
    @watchers[path] = stop: stopWatching

  stopAllWatchers:->
    (watcher.stop() for own path, watcher of @watchers)
    @watchers = {}

  stopWatching:(pathToStop)->
    for own path, watcher of @watchers  when (path.indexOf pathToStop) is 0
      watcher.stop()
      delete @watchers[path]

  loadView:(mainView)->
    mainView.addSubView @treeController.getView()
    mainView.addSubView @noVMFoundWidget
    @viewLoaded = yes

    @reset()  if @getOptions().loadFilesOnInit

    # temp hack, if page opens in develop section.
    @utils.wait 2500, =>
      KD.getSingleton("mainView").sidebar._windowDidResize()

  reset:->
    if @getOptions().useStorage
      @appStorage.ready => @loadVms()
    else
      @utils.defer => @loadVms()

  mountVms: (vms) ->
    return  unless Array.isArray vms
    @cleanup()
    @mountVm vm  for vm in vms

  loadVms:(vmNames, callback)->
    if vmNames then @mountVms vmNames
    else
      groupSlug  = KD.getSingleton("groupsController").getGroupSlug()
      groupSlug ?= KD.defaultSlug
      @appStorage.fetchValue "mountedVM", (vms)=>
        vms            or= {}
        vms[groupSlug] or= []
        if vms[groupSlug].length > 0
          @mountVms vms[groupSlug]
        else
          KD.remote.api.JVM.fetchVmsByContext {}, (err, vms)=>
            return callback? err  if err
            if not vms or vms.length is 0
              KD.getSingleton('vmController').fetchDefaultVmName (vm)=>
                if vm then @mountVms [vm]
                else @noVMFoundWidget.show()
            else
              @mountVms vms

  getVmNode:(vmName)->
    return null  unless vmName
    for own path, vmItem of @treeController.nodes  when vmItem.data?.type is 'vm'
      return vmItem  if vmItem.data.vmName is vmName

  updateMountState:(vmName, state)->
    return  if KD.isGuest()
    groupSlug  = KD.getSingleton("groupsController").getGroupSlug()
    groupSlug ?= KD.defaultSlug
    @appStorage.fetchValue "mountedVM", (vms)=>
      vms or= {}
      vms[groupSlug] or= []
      items = vms[groupSlug]
      if state and vmName not in items
        items.push vmName
      else if not state and vmName in items
        items.splice items.indexOf(vmName), 1
      @appStorage.setValue "mountedVM", vms

  checkVMState: (err, vm, info)->
    return warn err if err or not info
    switch info.state
      when "MAINTENANCE" then @unmountVm vm

  mountVm:(vm, fetchContent = yes)->
    return warn 'VM path required! e.g VMNAME[:PATH]'  unless vm

    [vmName, path] = vm.split ":"

    vmRoots = (@appStorage.getValue 'vmRoots') or {}
    pipedVm = @_pipedVmName vmName
    path or= vmRoots[pipedVm] or "/home/#{KD.nick()}"

    if vmItem = @getVmNode vmName
      return warn "VM #{vmName} is already mounted!"

    @_mountVMHelper vmName, path, fetchContent

  _mountVMHelper: (vmName, path, fetchContent)->
    @updateMountState vmName, yes

    @vms.push FSHelper.createFile
      name   : "#{path}"
      path   : "[#{vmName}]#{path}"
      type   : "vm"
      vmName : vmName

    @noVMFoundWidget.hide()
    @treeController.addNode @vms.last

    vmItem = @getVmNode vmName
    if fetchContent and vmItem
      # Without this, it fails to fetch Finder settings before creating
      # Fileitems o_0 FIXME ~ GG
      @utils.wait 1000, =>
        @treeController.expandFolder vmItem, (err)=>
          if err?.name is 'VMNotFoundError'
            return @unmountVm vmName
          @treeController.selectNode vmItem
          @utils.defer =>
            if @getOptions().useStorage then @reloadPreviousState vmName
        , yes


  unmountVm:(vmName)->
    vmItem = @getVmNode vmName
    return warn 'No such VM!'  unless vmItem

    @updateMountState vmName, no
    @stopWatching vmItem.data.path
    FSHelper.unregisterVmFiles vmName
    @treeController.removeNodeView vmItem
    @vms = @vms.filter (vmData)-> vmData isnt vmItem.data

    if @vms.length is 0
      @noVMFoundWidget.show()
      @emit 'EnvironmentsTabRequested'

  updateVMRoot:(vmName, path, callback)->
    return warn 'VM name and new path required!'  unless vmName or path

    @unmountVm vmName
    callback?()

    vmRoots = (@appStorage.getValue 'vmRoots') or {}
    pipedVm = @_pipedVmName vmName
    vmRoots[pipedVm] = path
    @appStorage.setValue 'vmRoots', vmRoots  if @getOptions().useStorage

    @mountVm "#{vmName}:#{path}"

  cleanup:->
    @treeController.removeAllNodes()
    FSHelper.resetRegistry()
    @stopAllWatchers()
    @vms = []

  setRecentFile:({path})->
    recentFiles = @appStorage.getValue('recentFiles')
    recentFiles = []  unless Array.isArray recentFiles

    unless path in recentFiles
      if recentFiles.length is @treeController.getOptions().maxRecentFiles
        recentFiles.pop()
      recentFiles.unshift path

    @appStorage.setValue 'recentFiles', recentFiles.slice(0,10), =>
      @emit 'recentfiles.updated', recentFiles

  hideDotFiles:(vmName)->
    return  unless vmName
    @setNodesHidden vmName, yes
    for own path, node of @treeController.nodes
      file = node.getData()
      if (file.vmName is vmName) and file.isHidden()
        @stopWatching file.path
        @treeController.removeNodeView node

  showDotFiles:(vmName)->
    return  unless vmName
    @setNodesHidden vmName, no
    for own path, node of @treeController.nodes when node.getData().type is 'vm'
      return if node.getData().vmName is vmName
        @treeController.collapseFolder node, =>
          @reloadPreviousState vmName
        , yes

  isNodesHiddenFor:(vmName)->
    pipedVm = @_pipedVmName vmName
    return (@appStorage.getValue('vmsDotFileChoices') or {})[pipedVm]

  setNodesHidden:(vmName, state)->
    pipedVm = @_pipedVmName vmName
    prefs   = @appStorage.getValue('vmsDotFileChoices') or {}
    prefs[pipedVm] = state
    @appStorage.setValue 'vmsDotFileChoices', prefs

  getRecentFolders:->
    recentFolders = @appStorage.getValue('recentFolders')
    recentFolders = []  unless Array.isArray recentFolders
    return recentFolders

  setRecentFolder:(folderPath, callback)->
    recentFolders = @getRecentFolders()
    unless folderPath in recentFolders
      recentFolders.push folderPath
    recentFolders.sort (path)-> if path is folderPath then -1 else 0
    @appStorage.setValue 'recentFolders', recentFolders, callback

  unsetRecentFolder:(folderPath, callback)->
    recentFolders = @getRecentFolders()
    recentFolders = recentFolders.filter (path)->
      path.indexOf(folderPath) isnt 0
    recentFolders.sort (path)->
      if path is folderPath then -1 else 0
    @appStorage.setValue 'recentFolders', recentFolders, callback

  expandFolder:(folderPath, callback=noop)->
    return  unless folderPath
    for own path, node of @treeController.nodes
      return @treeController.expandFolder node, callback  if path is folderPath
    callback {message:"Folder not exists: #{folderPath}"}

  expandFolders: do ->
    expandedFolderIndex = 0
    (paths, callback=noop)->
      @expandFolder paths[expandedFolderIndex], (err)=>
        if err
          callback? err
          @unsetRecentFolder paths[expandedFolderIndex]
        expandedFolderIndex++
        if expandedFolderIndex <= paths.length
          @expandFolders paths, callback, expandedFolderIndex

        if expandedFolderIndex is paths.length
          callback? null, @treeController.nodes[paths.last]
          expandedFolderIndex = 0

  reloadPreviousState:(vmName)->
    recentFolders = @getRecentFolders()
    if vmName
      recentFolders = recentFolders.filter (folder)->
        folder.indexOf "[#{vmName}]" is 0
      if recentFolders.length is 0
        recentFolders = ["[#{vmName}]/home/#{KD.nick()}"]
    @expandFolders recentFolders

  uploadTo: (path)->
    sidebarView = @getDelegate()
    sidebarView.dnduploader.setPath path
    sidebarView.dndUploadHolder.show()

  _pipedVmName:(vmName)-> vmName.replace /\./g, '|'

class VMMountStateWidget extends JView

  constructor:->
    super cssClass : 'no-vm-found-widget'

    @loader = new KDLoaderView
      size          : width : 20
      loaderOptions :
        speed       : 0.7
        FPS         : 24

    @warning = new KDCustomHTMLView
      partial : "There is no attached VM"

  pistachio:->
    """
    {{> @loader}}
    {{> @warning}}
    """

  showMessage:(message)->
    message or= """There is no VM attached to filetree, you can
                   attach or create one from environment menu below."""

    @warning.updatePartial message
    @warning.show()

    @loader.hide()

  show:->
    @setClass 'visible'
    @warning.hide()
    @loader.show()

    if KD.getSingleton("groupsController").getGroupSlug() is KD.defaultSlug
      @showMessage()

    # Not sure about it I guess only owners can create GroupVM?
    else if ("admin" in KD.config.roles) or ("owner" in KD.config.roles)
      group = KD.getSingleton("groupsController").getCurrentGroup()
      group.checkPayment (err, payments)=>
        warn err  if err
        if payments.length is 0
          @showMessage """There is no VM attached for this group, you can
                          attach one or you can <b>pay</b> and create
                          a new one from environment menu below."""
        else
          @showMessage """There is no VM attached for this group, you can
                          attach one or you can create a new one from
                          environment menu below."""

    else
      @showMessage """There is no VM for this group or not attached to
                      filetree yet, you can attach one from environment
                      menu below."""

  hide:->
    @unsetClass 'visible'
    @loader.hide()
