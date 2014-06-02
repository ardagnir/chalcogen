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
{Range} = require('atom')

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
    atom.workspaceView.statusBar.prependLeft(@statusView)
    shadowvim = @setupShadowvim()
    atom.workspaceView.eachEditorView (editorView)=>
      #TODO: Need to restore this
      editorView.showBufferConflictAlert = ->
      editor = editorView.editor
      editor.buffer.on "changed.shadowvim", =>
        if @internalTextChange
          if editor.savedMeta
            @metaChanged(editor.vimBuffer, editor.savedMeta)
        else
          cursorRange = editor.getSelectedBufferRange()
          #shadowvim.changeContents(editor.getText(), cursorRange)
          shadowvim.updateShadowvim( ->
            editor.getText()
          , ->
            editor.getSelectedBufferRange()
          )

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
        cursorRange = editor.getSelectedBufferRange()
        if @savedRange
            if not @waitingForContents and not cursorRange.isEqual(@savedRange)
              shadowvim.updateShadowvim( ->
                editor.getText()
              , ->
                editor.getSelectedBufferRange()
              )

  cleanup: ->
    for editorView in atom.workspaceView.getEditorViews()
      editorView.editor.shadowvim.exit()
      editorView.editor.buffer.off 'changed.shadowvim'
      editorView.off "keypress.shadowvim"
      editorView.off "keydown.shadowvim"
      editorView.off "cursor:moved.shadowvim"

  setupShadowvim: (editorView) =>
    uid = Math.floor(Math.random()*0x100000000).toString(16)
    editor = atom.workspace.getActiveEditor()

    #TODO: don't prepick editor
    shadowvim = new Shadowvim 'chalcogen_'+uid, editor?.getUri(),(=> editor?.getText()), (=> editor?.getSelectedBufferRange()),
      contentsChanged: (vimBuffer, data) => @setContents(vimBuffer, data)
      metaChanged: (vimBuffer, data) => @metaChanged(vimBuffer, data)
      messageReceived: (data) => @messageReceived(data)
      tabsChanged: (tabList, currentTab) => @tabsChangedInVim(tabList, currentTab)

    #If we die, our parent will lose a child. (There's probably a better way of doing this)
   # reaper = new MutationObserver @cleanupShadows
   # reaper.observe editorView.parent()[0],
   #   childList: true


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

  setContents: (vimBuffer, data) =>
    @waitingForContents=0
    @internalTextChange=1
    editor = @getEditorForVimBuffer(vimBuffer)
    editor.buffer.setTextViaDiff(data)
    @internalTextChange=0

  messageReceived: (data) =>
    @statusView.setText data
    @mode=''

  tabsChangedInVim: (tabList, currentTab) =>
    lastPane=null
    needToDestroy=[]
    unusedEditors=[]
    #TODO: add support for multiple panes
    pane = atom.workspace.getPanes()[0]
    for editor in pane.getItems()
       if editor?.buffer
          unusedEditors.push editor

    for vimTab,i in tabList.slice(1)
       bufferNum = vimTab.replace(/:.*/, "")
       tabpath = vimTab.replace(/[^:]*:/, "")
       editor = pane.itemForUri(tabpath || undefined)
       if editor
         editor.vimBuffer = bufferNum
         pane.moveItem(editor, i)
         unusedEditors.splice(unusedEditors.indexOf(editor), 1)
         if i+1 == currentTab
           pane.activateItemForUri(tabpath || undefined)
       else
         #TODO: This could mess up ordering if it takes too long
         atom.workspace.open(tabpath).then (editor) =>
           editor.vimBuffer = bufferNum
           pane.addItem(editor)
           pane.moveItem(editor, i)
           if i+1 == currentTab
             pane.activateItemForUri(tabpath)

     for editor in unusedEditors
        pane.destroyItem(editor)

  metaChanged: (vimBuffer, data) =>
    editor = @getEditorForVimBuffer(vimBuffer)
    if data and editor
      lines=data.split("\n")
      if lines.length>2
        if @mode!=lines[0] || @mode=='c'
          @mode=lines[0]
          @statusView.setStatus(@mode,lines[1])
        start=(parseInt(num) for num in lines[1].split(","))
        end=(parseInt(num) for num in lines[2].split(","))
        @savedRange = new Range([start[2], start[1]],[end[2],end[1]])
        if lines[1]==lines[2]
          editor.setCursorBufferPosition([start[2], start[1]])
        else if end.length>2
          editor.setSelectedBufferRange([[start[2], start[1]],
                                         [end[2], end[1]]])
        if not @savedRange.isEqual(editor.getSelectedBufferRange())
          #We haven't got the text we want to put this cursor on yet
          @waitingForContents=1
        editor.savedMeta=data

  getEditorForVimBuffer: (vimBuffer) ->
    for editor in atom.workspace.getEditors()
      if editor.vimBuffer == vimBuffer
        return editor

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

