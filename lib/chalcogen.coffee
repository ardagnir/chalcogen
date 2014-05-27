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

{Task} = require 'atom'
fs = require("fs")


currentShadows =[]
cleared = 0
savedMeta =""
savedEndPosition= []

#Atom moves the cursor to the end of the text diff. This is a hack to stop that from breaking things.
atomCursorHack = 0

#TODO: These should not all be exports. This code needs to be cleaned up.
module.exports =

  activate: (state) ->
    #TODO: add a way to disable fullvim
    atom.workspaceView.command "chalcogen:toggle", => @fullvim()

  setContents: (editor,data) =>
    if data
      cleared=0
      atomCursorHack=1
      #TODO: use a better custom diff function
      editor.buffer.setTextViaDiff(data)
    else
      cleared=1

  messageReceived: (editor, data) =>
    if cleared
      editor.setText("")

  metaChanged: (editor, data) ->
    if data
      lines=data.split("\n")
      if lines.length>2
        start=(parseInt(num) for num in lines[1].split(","))
        end=(parseInt(num) for num in lines[2].split(","))
        savedEndPosition = [end[2],end[1]]
        if lines[1]==lines[2]
          editor.setCursorBufferPosition([start[2], start[1]])
          savedMeta=data
        else if end.length>2
          editor.setSelectedBufferRange([[start[2], start[1]],
                                         [end[2], end[1]]])
          savedMeta=data



  fullvim: ->
    atom.workspaceView.eachEditorView (editorView) =>
      uid = Math.floor(Math.random()*0x100000000).toString(16)
      editor = editorView.getEditor()
      shadowvim = new Task(require.resolve('./shadowvim'))
      shadowvim.start('chalcogen_'+uid, editor.getText(), editor.getCursorBufferPosition())
      shadowvim.on 'shadowvim:contentsChanged', (data) => @setContents(editor, data)
      shadowvim.on 'shadowvim:metaChanged', (data) => @metaChanged(editor, data)
      shadowvim.on 'shadowvim:messagesReceived', (data) => @messageReceived(editor, data)
      shadowvim.on 'shadowvim:exited', =>
        shadowvim.terminate()
      editor.shadowvim = shadowvim
      currentShadows.push(shadowvim)

      reaper = new MutationObserver (mutations) =>
        unusedShadows = currentShadows.slice()
        for currentEditor in atom.workspace.getEditors()
          index = unusedShadows.indexOf(currentEditor.shadowvim)
          if index != -1
            unusedShadows.splice(index, 1)

        for shadow in unusedShadows
          shadow.send
              exit: true
          index = currentShadows.indexOf(shadow)
          if index != -1
            currentShadows.splice(index, 1)

      #If we die, our parent will lose a child. (There's probably a better way of doing this)
      reaper.observe editorView.parent()[0],
        childList: true

      editor.buffer.on 'changed', =>
        if savedMeta
          @metaChanged(editor, savedMeta)
      editorView.keypress (e) =>
        shadowvim.send
            send: String.fromCharCode(e.which)
        false
      editorView.keydown (e) =>
        translation=@translateCode(e.which, e.shiftKey)
        if translation != ""
          shadowvim.send
            send: translation
          false

      editorView.on 'cursor:moved', =>
        cursorPos = editor.getCursorBufferPosition()
        if savedEndPosition
            if cursorPos["column"]!=savedEndPosition[1] or cursorPos['row']!=savedEndPosition[0]
                if not atomCursorHack
                    shadowvim.send
                        focus: editor.getCursorBufferPosition()
            else
                atomCursorHack=0

  translateCode: (code, shift) ->
    if code>=8 && code<=10 || code==13 || code==27
      String.fromCharCode(code)
    else if code==37
      String.fromCharCode(27)+'[D'
    else if code==38
      String.fromCharCode(27)+'[A'
    else if code==39
      String.fromCharCode(27)+'[C'
    else if code==40
      String.fromCharCode(27)+'[B'
    else
      ""


  deactivate: ->
    for editor in atom.workspace.getEditors()
      editor.shadowvim.send
        exit: true
      #TODO: We can't call terminate here, but we still need to terminate
      #editor.shadowvim.terminate()
