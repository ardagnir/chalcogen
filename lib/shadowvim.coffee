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

  constructor: (@servername, path, textFunc, cursorFunc, @callbackFunctions) ->
    env = process.env
    env["TERM"] = "xterm"
    loaded=false
    @svProcess = childProcess.spawn("vim", [
      "--servername", @servername
      "+call Shadowvim_SetupShadowvim('#{path || ""}','tabs')"
    ], {
      env: env
    })

    #We know vim is loaded when we get stdout
    @svProcess.stdout.on 'data', (data) =>
      if not loaded
        loaded=true
        @callbackFunctions.onLoad()

    @svProcess.stderr.on 'data', (data) =>
      console.log("stderr:"+data)


    #These might already exist
    try
      fs.mkdirSync "/tmp/shadowvim", @allPerm
    try
      fs.mkdirSync "/tmp/shadowvim/" + @servername, @execPerm

    fs.open "/tmp/shadowvim/#{@servername}/meta.txt", "w", @readWritePerm, =>
      fs.watch "/tmp/shadowvim/#{@servername}/meta.txt", @metaChanged
    fs.open "/tmp/shadowvim/#{@servername}/messages.txt", "w", @readWritePerm, =>
      fs.watch "/tmp/shadowvim/#{@servername}/messages.txt", @messageReceived
    fs.open "/tmp/shadowvim/#{@servername}/tabs.txt", "w", @readWritePerm, (e, id) =>
      @tabFile = id
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
    console.log(tabs)

    if tabs.length
      if @contentsFile
        fs.close @contentsFile
        @contentsFile = null
        #fs.unlink("/tmp/shadowvim/#{@servername}/contents-#{@currentBuffer}.txt")

      currentInfo = tabs[0].split(" ")
      @currentBuffer = currentInfo[0]
      currentTab = parseInt(currentInfo[1])
      
      fs.open "/tmp/shadowvim/#{@servername}/contents-#{@currentBuffer}.txt", "w", @readWritePerm, (e, id) =>
        @contentsFile = id
        #needToRead=true
        fs.watch "/tmp/shadowvim/#{@servername}/contents-#{@currentBuffer}.txt", @contentsChanged
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
      contents.toString()
    catch e
      if e.code != 'ENOENT'
        throw e
      ""

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

  updateTabs: (activeTab,pathList)=>
      childProcess.spawn "vim", [
        "--servername", @servername
        "--remote-expr", "Shadowvim_UpdateTabs(#{activeTab+1}, [#{pathList.toString()}])"
      ]

  updateShadowvim: (textFunc, cursorFunc)=>
    @textSent = 0
    if not @updateHot
      setTimeout(=>
        @updateIfCool(textFunc,cursorFunc)
      , 200)
      @updateHot=1
    else
      @updateHot=2

  updateIfCool: (textFunc, cursorFunc) =>
    if @updateHot<2
      @updateHot=0
      newText = textFunc()
      #If there's no selection, atom throws an exception
      try
        cursorSelection = cursorFunc()
      catch
        console.log("No selection!")
        return
      fs.writeSync @contentsFile, newText, 0, newText.length, 0
      childProcess.spawn "vim", [
        "--servername", @servername
        "--remote-expr", "Shadowvim_UpdateText(#{cursorSelection.start.row+1},#{cursorSelection.start.column+1},#{cursorSelection.end.row+1},#{cursorSelection.end.column+1},0)"
      ]
    else
       @updateHot=1
       setTimeout(=>
         @updateIfCool(textFunc,cursorFunc)
       , 200)

  sendPoll: =>
      childProcess.spawn "vim", [
        "--servername", @servername
        "--remote-expr", "Shadowvim_Poll()"
      ]

  exit: =>
    #TODO: Empty the directory first or we can't delete it.
    fs.unlinkSync("/tmp/shadowvim/#{@servername}/contents-#{@currentBuffer}.txt")
    fs.unlinkSync("/tmp/shadowvim/#{@servername}/meta.txt")
    fs.unlinkSync("/tmp/shadowvim/#{@servername}/messages.txt")
    fs.rmdirSync("/tmp/shadowvim/#{@servername}")
    @svProcess.kill('SIGKILL')
