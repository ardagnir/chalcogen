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

module.exports =
class Shadowvim
  constructor: (@servername, path, startText, cursorSelection, @callbackFunctions) ->
    env = process.env
    env["TERM"] = "xterm"
    needToRead=false
    @svProcess = require("child_process").spawn("vim", [
      "--servername", @servername
      "+call Shadowvim_SetupShadowvim('#{path || ""}')"
    ], {
      env: env
    })

    #We know vim is loaded when we get stdout
    @svProcess.stdout.on 'data', (data) =>
      if needToRead
        @moveCursor(cursorSelection)
        needToRead = false

    @svProcess.stderr.on 'data', (data) =>
      console.log("stderr:"+data)

    execPerm = parseInt("700", 8)
    readWritePerm = parseInt("600", 8)
    allPerm = parseInt("777", 8)

    #These might already exist
    try
      fs.mkdirSync "/tmp/shadowvim", allPerm
    try
      fs.mkdirSync "/tmp/shadowvim/" + @servername, execPerm

    fs.open "/tmp/shadowvim/#{@servername}/contents.txt", "w", readWritePerm, (e, id) =>
      fs.writeSync id, startText, 0, startText.length, 0
      needToRead=true
      @contentsFile = id
      fs.watch "/tmp/shadowvim/#{@servername}/contents.txt", @contentsChanged
    fs.open "/tmp/shadowvim/#{@servername}/meta.txt", "w", readWritePerm, =>
      fs.watch "/tmp/shadowvim/#{@servername}/meta.txt", @metaChanged
    fs.open "/tmp/shadowvim/#{@servername}/messages.txt", "w", readWritePerm, =>
      fs.watch "/tmp/shadowvim/#{@servername}/messages.txt", @messageReceived

    return

  updateShadowvim: (textFunc, cursorFunc)=>
    @textSent = 0
    if @exprHot
      setTimeout(=>
        @updateIfCool(textFunc,cursorFunc)
      , 200)
      @exprHot=1
    else
      @exprHot=2

  updateIfCool: (textFunc, cursorFunc) =>
    if @exprHot<2
      @exprHot=0
      newText = textFunc()
      cursorSelection = cursorFunc()
      fs.writeSync @contentsFile, newText, 0, newText.length, 0
      require("child_process").spawn "vim", [
        "--servername", @servername
        "--remote-expr", "Shadowvim_UpdateText(#{cursorSelection.start.row+1},#{cursorSelection.start.column+1},#{cursorSelection.end.row+1},#{cursorSelection.end.column+1})"
      ]
    else
       @exprHot=1
       setTimeout(=>
         @updateIfCool(textFunc,cursorFunc)
       , 200)

  changeContents: (newText, cursorSelection) =>
    @textSent = 0
    console.log('newText:'+newText+cursorSelection)
    fs.writeSync @contentsFile, newText, 0, newText.length, 0
    require("child_process").spawn "vim", [
      "--servername", @servername
      "--remote-expr", "Shadowvim_UpdateText(#{cursorSelection.start.row+1},#{cursorSelection.start.column+1},#{cursorSelection.end.row+1},#{cursorSelection.end.column+1})"
    ]

  moveCursor: (selection) =>
    @textSent = 0
    require("child_process").spawn "vim", [
      "--servername", @servername
      "--remote-expr", "Shadowvim_UpdateText(#{selection.start.row+1},#{selection.start.column+1},#{selection.end.row+1},#{selection.end.column+1})"
    ]

  contentsChanged: =>
    try
      contents = fs.readFileSync "/tmp/shadowvim/#{@servername}/contents.txt"
    catch e
      #This function is triggered at file deletion
      if e.code != 'ENOENT'
        throw e
      return
    if @textSent
      @callbackFunctions.contentsChanged? contents.toString().slice(0,-1)


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
      @callbackFunctions.metaChanged? meta.toString()

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
      @callbackFunctions.messageReceived? messages.replace(/.*\n/, '')
      for message in messages.split("\n")
        if message
          console.log "message: " + message

  buffer: ""

  send: (message) =>
    @buffer+=message
    if @exprHot
      return
    @textSent = 1
    @svProcess.stdin.write @buffer
    @buffer = ""

  exit: =>
    #TODO: Empty the directory first or we can't delete it.
    fs.unlinkSync("/tmp/shadowvim/#{@servername}/contents.txt")
    fs.unlinkSync("/tmp/shadowvim/#{@servername}/meta.txt")
    fs.unlinkSync("/tmp/shadowvim/#{@servername}/messages.txt")
    fs.rmdirSync("/tmp/shadowvim/#{@servername}")
    @svProcess.kill('SIGKILL')
