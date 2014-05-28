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
  constructor: (@servername, startText, cursorPos, @callbackFunctions) ->
    #TODO: Something's off by one. This is a hack
    cursorPos["column"] = cursorPos["column"]-1
    env = process.env
    env["TERM"] = "xterm"
    needToRead=false
    @svProcess = require("child_process").spawn("vim", [
      "--servername", @servername
      "+call Shadowvim_SetupShadowvim()"
    ], {
      env: env
    })

    #We know vim is loaded when we get stdout
    @svProcess.stdout.on 'data', (data) =>
      if needToRead
        @focusTextbox(cursorPos)
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

  changeContents: (newText, cursorPos) =>
    fs.writeSync @contentsFile, newText, 0, newText.length, 0
    require("child_process").spawn "vim", [
      "--servername", @servername
      "--remote-expr", "Shadowvim_UpdateTextbox(#{cursorPos["row"]+1},#{cursorPos["column"]+1},#{cursorPos["row"]+1},#{cursorPos["column"]+1})"
    ]

  focusTextbox: (cursorPos) =>
    require("child_process").spawn "vim", [
      "--servername", @servername
      "--remote-expr", "Shadowvim_FocusTextbox(#{cursorPos["row"]+1},#{cursorPos["column"]+1},#{cursorPos["row"]+1},#{cursorPos["column"]+1})"
    ]

  contentsChanged: =>
    try
      contents = fs.readFileSync "/tmp/shadowvim/#{@servername}/contents.txt"
    catch e
      #This function is triggered at file deletion
      if e.code != 'ENOENT'
        throw e
      return
    @callbackFunctions.contentsChanged? contents.toString().slice(0,-1)


  metaChanged: =>
    try
      meta = fs.readFileSync "/tmp/shadowvim/#{@servername}/meta.txt"
    catch e
      #This function is triggered at file deletion
      if e.code != 'ENOENT'
        throw e
      return
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
      @callbackFunctions.messageReceived? messages
      for message in messages.split("\n")
        if message
          console.log "message: " + message

  send: (message) =>
    @svProcess.stdin.write message

  exit: =>
    #TODO: Empty the directory first or we can't delete it.
    fs.unlinkSync("/tmp/shadowvim/#{@servername}/contents.txt")
    fs.unlinkSync("/tmp/shadowvim/#{@servername}/meta.txt")
    fs.unlinkSync("/tmp/shadowvim/#{@servername}/messages.txt")
    fs.rmdirSync("/tmp/shadowvim/#{@servername}")
    @svProcess.kill('SIGKILL')
