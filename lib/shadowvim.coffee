# This is part of Chalcogen
#
# Copyright (C) 2014, James Kolb <jck1089@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

fs = require("fs")
childProcess = require("child_process")

module.exports =
class Shadowvim
  execPerm: parseInt("700", 8)
  readWritePerm: parseInt("600", 8)
  allPerm: parseInt("777", 8)

  maxBuffer:0

  constructor: (@servername, path, textFunc, cursorFunc, @callbackFunctions) ->
    env = process.env
    env["TERM"] = "xterm"
    @loaded=false
    @tabDataSet=false
    @svProcess = childProcess.spawn("vim", [
      "--servername", @servername
      "+call Shadowvim_SetupShadowvim('#{path || ""}','tabs')"
    ], {
      env: env
    })

    #We know vim is loaded when we get stdout
    @svProcess.stdout.on 'data', (data) =>
      if not @loaded
        @loaded=true
        @callbackFunctions.onLoad()

    @svProcess.stderr.on 'data', (data) =>
      console.log("stderr:"+data)

    #These might already exist
    try
      fs.mkdirSync "/tmp/shadowvim", @allPerm
    try
      fs.mkdirSync "/tmp/shadowvim/" + @servername, @execPerm

    #TODO: Grab all the filestrings from functions
    fs.writeFile "/tmp/shadowvim/#{@servername}/meta.txt", "", {mode: @readWritePerm}, =>
      fs.watch "/tmp/shadowvim/#{@servername}/meta.txt", @metaChanged
    fs.writeFile "/tmp/shadowvim/#{@servername}/messages.txt", "", {mode: @readWritePerm}, =>
      fs.watch "/tmp/shadowvim/#{@servername}/messages.txt", @messageReceived
    fs.writeFile "/tmp/shadowvim/#{@servername}/tabs.txt", "", {mode: @readWritePerm}, =>
      fs.watch "/tmp/shadowvim/#{@servername}/tabs.txt", @tabsChanged

    return

  tabsChanged: =>
    try
      tabs = fs.readFileSync("/tmp/shadowvim/#{@servername}/tabs.txt").toString().split("\n")
    catch e
      #This function is triggered at file deletion
      if e.code != 'ENOENT'
        throw e
      return

    if tabs.length
      currentInfo = tabs[0].split(" ")
      @currentBuffer = currentInfo[0]
      if @currentBuffer>@maxBuffer
        @maxBuffer = @currentBuffer
      currentTab = parseInt(currentInfo[1])
      
      fs.appendFile "/tmp/shadowvim/#{@servername}/contents-#{@currentBuffer}.txt", "", {mode: @readWritePerm}, =>
        if @oldCurrentBufferWatcher
          @oldCurrentBufferWatcher.close()
        @oldCurrentBufferWatcher=fs.watch "/tmp/shadowvim/#{@servername}/contents-#{@currentBuffer}.txt", @contentsChanged
      @callbackFunctions.tabsChanged? tabs, currentTab, @getContents

  contentsChanged: =>
    try
      contents = fs.readFileSync "/tmp/shadowvim/#{@servername}/contents-#{@currentBuffer}.txt"
    catch e
      #This function is triggered at file deletion
      if e.code != 'ENOENT'
        throw e
      return
    if @textSent and contents.toString()
      @callbackFunctions.contentsChanged? @currentBuffer, contents.toString()

  getContents:(buffer)=>
      try
        contents = fs.readFileSync "/tmp/shadowvim/#{@servername}/contents-#{buffer}.txt"
        return contents.toString()
      catch e
        if e.code != 'ENOENT'
          throw e
    null

  metaChanged: =>
    try
      meta = fs.readFileSync "/tmp/shadowvim/#{@servername}/meta.txt"
    catch e
      #This function is triggered at file deletion
      if e.code != 'ENOENT'
        throw e
      return
    #Ignore changes that are caused by us setting up vim
    if @textSent
      @callbackFunctions.metaChanged? @currentBuffer, meta.toString()

  messageReceived: =>
    try
      #TODO: Race condition
      messages = fs.readFileSync("/tmp/shadowvim/#{@servername}/messages.txt").toString()
    catch e
      #This function is triggered at file deletion
      if e.code != 'ENOENT'
        throw e
      return
    if messages
      fs.writeFileSync "/tmp/shadowvim/#{@servername}/messages.txt", ""
      @callbackFunctions.messageReceived? messages.replace(/(.*\n)*/, '')
      for message in messages.split("\n")
        if message
          console.log "message: " + message

  buffer: ""

  send: (message) =>
    @buffer+=message
    if @updateHot
      return
    @textSent = 1
    @svProcess.stdin.write @buffer
    @buffer = ""
    if not @pollHot
      @pollHot=1
      setTimeout(=>
        @pollHot=0
        @sendPoll()
      ,200)

  updateTabs: (activeTab,pathList,fileChanges)=>
    #   childProcess.spawn "vim", [
    #     "--servername", @servername
    #     "--remote-expr", "Shadowvim_UpdateTabs(#{activeTab+1}, [#{pathList.toString()}])"
    #   ]
    if fileChanges
      filesRemaining=fileChanges.length
      for contents,i in fileChanges
        writeTab= (cont, callback)=>
            fs.writeFile "/tmp/shadowvim/#{@servername}/tabin-#{i}.txt", cont, =>
              filesRemaining-=1
              if filesRemaining==0
                childProcess.spawn "vim", [
                  "--servername", @servername
                  "--remote-expr", "Shadowvim_UpdateTabs(#{activeTab+1}, [#{pathList.toString()}],1)"
                ]
                console.log "Shadowvim_UpdateTabs(#{activeTab+1}, [#{pathList.toString()}],1)"
        writeTab contents
    else
      childProcess.spawn "vim", [
        "--servername", @servername
        "--remote-expr", "Shadowvim_UpdateTabs(#{activeTab+1}, [#{pathList.toString()}],0)"
      ]

  updateShadowvim: (textFunc, cursorFunc, preserveMode, buffer)=>
    @textSent = 0
    if not @updateHot
      setTimeout(=>
        @updateIfCool(textFunc,cursorFunc, preserveMode, buffer)
      , 200)
      @updateHot=1
    else
      @updateHot=2

  updateIfCool: (textFunc, cursorFunc, preserveMode, buffer) =>
    if @updateHot<2
      @updateHot=0
      newText = textFunc()
      #If there's no selection, atom throws an exception
      try
        cursorSelection = cursorFunc()
      catch
        console.log("No selection!")
        return
      if buffer==@currentBuffer || buffer=="init"
        if buffer=="init"
          #TODO: This is a hack to force initial mouse pos to update correct. Find a cleaner way to do this.
          @textSent=1
        fs.writeFileSync "/tmp/shadowvim/#{@servername}/contents-#{@currentBuffer}.txt", newText
        childProcess.spawn "vim", [
          "--servername", @servername
          "--remote-expr", "Shadowvim_UpdateText(#{cursorSelection.start.row+1},#{cursorSelection.start.column+1},#{cursorSelection.end.row+1},#{cursorSelection.end.column+1},#{preserveMode})"
        ]
    else
       @updateHot=1
       setTimeout(=>
         @updateIfCool(textFunc, cursorFunc, preserveMode, buffer)
       , 200)

  sendPoll: =>
      childProcess.spawn "vim", [
        "--servername", @servername
        "--remote-expr", "Shadowvim_Poll()"
      ]

  exit: =>
    @svProcess.kill('SIGKILL')
    for i in [0..@maxBuffer]
      try
        fs.unlinkSync("/tmp/shadowvim/#{@servername}/contents-#{i}.txt")
    fs.unlinkSync("/tmp/shadowvim/#{@servername}/tabs.txt")
    fs.unlinkSync("/tmp/shadowvim/#{@servername}/meta.txt")
    fs.unlinkSync("/tmp/shadowvim/#{@servername}/messages.txt")
    fs.rmdirSync("/tmp/shadowvim/#{@servername}")
