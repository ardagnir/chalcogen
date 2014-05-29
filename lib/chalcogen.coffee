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
VimStatusView = require('./vim-status-view.coffee')
Shadowvim = require('./shadowvim')

module.exports =
  activate: (state) ->
    atom.workspaceView.command "chalcogen:toggle", =>
      if @chalcogen
        @chalcogen.cleanup()
        @chalcogen = 0
      else
        @chalcogen = new Chalcogen

  deactivate: ->
    @chalcogen?.cleanup()

class Chalcogen
  constructor: ->
    @statusView = new VimStatusView
    @shadows = []
    atom.workspaceView.statusBar.prependLeft(@statusView)
    atom.workspaceView.eachEditorView @setupEditorView

  cleanup: ->
    for editorView in atom.workspaceView.getEditorViews()
      editorView.editor.shadowvim.exit()
      editorView.editor.buffer.off 'changed.shadowvim'
      editorView.off "keypress.shadowvim"
      editorView.off "keydown.shadowvim"
      editorView.off "cursor:moved.shadowvim"

  setupEditorView: (editorView) =>
    uid = Math.floor(Math.random()*0x100000000).toString(16)
    editor = editorView.getEditor()
    #TODO: Need to restore this
    editorView.showBufferConflictAlert = ->

    shadowvim = new Shadowvim 'chalcogen_'+uid, editor.getUri(), editor.getText(), editor.getSelectedBufferRange(),
      contentsChanged: (data) => @setContents(editor, data)
      metaChanged: (data) => @metaChanged(editor, data)
      messageReceived: (data) => @messageReceived(editor, data)
    editor.shadowvim = shadowvim
    @shadows.push(shadowvim)

    #If we die, our parent will lose a child. (There's probably a better way of doing this)
    reaper = new MutationObserver @cleanupShadows
    reaper.observe editorView.parent()[0],
      childList: true

    editor.buffer.on "changed.shadowvim", =>
      if @internalTextChange
        if @savedMeta
          @metaChanged(editor, @savedMeta)
      else
        shadowvim.changeContents(editor.getText(), editor.getCursorBufferPosition())

    editorView.on "keypress.shadowvim", (e) ->
      if editorView.hasClass('is-focused')
        shadowvim.send String.fromCharCode(e.which)
        false
      else
        true

    editorView.on "keydown.shadowvim", (e) =>
      if editorView.hasClass('is-focused')
        translation=@translateCode(e.which, e.shiftKey)
        if translation != ""
          shadowvim.send translation
          false
      else
        true

    editorView.on "cursor:moved.shadowvim", =>
      cursorPos = editor.getCursorBufferPosition()
      if @savedEndPosition
          if cursorPos["column"]!=@savedEndPosition[1] or cursorPos['row']!=@savedEndPosition[0]
            shadowvim.focusTextbox editor.getSelectedBufferRange()

  cleanupShadows: (mutations) =>
    unusedShadows = @shadows.slice()
    for currentEditor in atom.workspace.getEditors()
      index = unusedShadows.indexOf(currentEditor.shadowvim)
      if index != -1
        unusedShadows.splice(index, 1)

    for shadow in unusedShadows
      shadow.exit()
      index = @shadows.indexOf(shadow)
      if index != -1
        @shadows.splice(index, 1)

  setContents: (editor,data) =>
    if data
      @cleared=0
      @internalTextChange=1
      editor.buffer.setTextViaDiff(data)
      @internalTextChange=0
    else
      #The file is emptied before it is changed and we have to make sure it is actually empty.
      @cleared=1
      setTimeout( =>
        @internalTextChange=1
        #TODO: Race condition.
        if @cleared and @savedEndPosition[0]==0 and @savedEndPosition[1]==0
          editor.setText("")
        @internalTextChange=0
      ,100)

  messageReceived: (editor, data) =>
    @statusView.setText data
    @mode=''

  metaChanged: (editor, data) =>
    if data
      lines=data.split("\n")
      if lines.length>2
        if @mode!=lines[0] || @mode=='c'
          @mode=lines[0]
          @statusView.setStatus(@mode,lines[1])
        start=(parseInt(num) for num in lines[1].split(","))
        end=(parseInt(num) for num in lines[2].split(","))
        @savedEndPosition = [end[2],end[1]]
        if lines[1]==lines[2]
          editor.setCursorBufferPosition([start[2], start[1]])
          @savedMeta=data
        else if end.length>2
          editor.setSelectedBufferRange([[start[2], start[1]],
                                         [end[2], end[1]]])
          @savedMeta=data

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

