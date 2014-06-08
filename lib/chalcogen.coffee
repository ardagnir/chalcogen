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
        @chalcogen = null
      else
        @chalcogen = new Chalcogen

  deactivate: ->
    @chalcogen?.cleanup()

class Chalcogen
  updatingTabsFromVim: 0
  constructor: ->
    @statusView = new VimStatusView
    atom.workspaceView.statusBar.prependLeft(@statusView)
    pane = atom.workspace.getPanes()[0]
    @shadowvim = @setupShadowvim(pane)
    pane.on "item-removed.chalcogen", => @changeTabs(pane)
    pane.on "item-moved.chalcogen", => @changeTabs(pane)
    pane.on "item-added.chalcogen", => @changeTabs(pane)
    paneView=atom.workspaceView.getPaneViews()[0]
    paneView.on "pane:active-item-changed.chalcogen", => @changeTabs(pane)

    atom.workspaceView.eachEditorView (editorView)=>
      editor = editorView.editor
      #TODO: Need to restore this
      editorView.showBufferConflictAlert_chalc_backup = editorView.showBufferConflictAlert
      editorView.showBufferConflictAlert = ->
      editor.buffer.on "changed.chalcogen", =>
        if @internalTextChange
          if editor.savedMeta
            @metaChanged(editor.vimBuffer, editor.savedMeta)
        else
          cursorRange = editor.getSelectedBufferRange()
          #shadowvim.changeContents(editor.getText(), cursorRange)
          @shadowvim.updateShadowvim( ->
            editor.getText()
          , ->
            editor.getSelectedBufferRange()
          )

      editorView.on "keypress.chalcogen", (e) =>
        if editorView.hasClass('is-focused')
          @shadowvim.send String.fromCharCode(e.which)
          false
        else
          true

      editorView.on "keydown.chalcogen", (e) =>
        if editorView.hasClass('is-focused')
          translation=@translateCode(e.which, e.shiftKey)
          if translation != ""
            @shadowvim.send translation
            false
        else
          true

      editorView.on "cursor:moved.chalcogen", =>
        cursorRange = editor.getSelectedBufferRange()
        if @savedRange
            if not @waitingForContents and not cursorRange.isEqual(@savedRange)
              @shadowvim.updateShadowvim( ->
                editor.getText()
              , ->
                editor.getSelectedBufferRange()
              )

  cleanup: ->
    for editorView in atom.workspaceView.getEditorViews()
      editorView.editor.shadowvim.exit()
      editorView.editor.buffer.off 'changed.chalcogen'
      editorView.off "keypress.chalcogen"
      editorView.off "keydown.chalcogen"
      editorView.off "cursor:moved.chalcogen"
    for pane in atom.workspace.getPanes()
      pane.off "item-removed.chalcogen"
      pane.off "item-moved.chalcogen"
      pane.off "item-added.chalcogen"

  changeTabs: (pane)=>
    if @updatingTabsFromVim==0
      @shadowvim.updateTabs(
        pane.getItems().indexOf(pane.getActiveItem()),
        for editor in pane.getItems()
          if uri = editor.getUri()
            "'"+uri+"'"
          else
            editor.vimBuffer || 0
      )

  setupShadowvim: (pane) =>
    uid = Math.floor(Math.random()*0x100000000).toString(16)
    editor = atom.workspace.getActiveEditor()

    #TODO: don't prepick editor
    shadowvim = new Shadowvim 'chalcogen_'+uid, editor?.getUri(),(=> editor?.getText()), (=> editor?.getSelectedBufferRange()),
      contentsChanged: (vimBuffer, data) => @setContents(vimBuffer, data)
      metaChanged: (vimBuffer, data) => @metaChanged(vimBuffer, data)
      messageReceived: (data) => @messageReceived(data)
      tabsChanged: (tabList, currentTab) => @tabsChangedInVim(tabList, currentTab)
      onLoad: => @changeTabs(pane)

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

  lastTabChange:0

  tabsChangedInVim: (tabList, currentTab, getContents) =>


    #We only care about carying out the last tabchange. If we do multiple at the same time we break stuff.
    @lastTabChange+=1
    thisTabChange=@lastTabChange

    if @updatingTabsFromVim
      setTimeout(=>
        if thisTabChange==@lastTabChange
          @tabsChangedInVim(tabList,currentTab,getContents)
      ,100)
      return

    @updatingTabsFromVim=1
    lastPane=null
    needToDestroy=[]
    unusedEditors=[]
    #TODO: add support for multiple panes
    pane = atom.workspace.getPanes()[0]
    for editor in pane.getItems()
       if editor?.buffer
          unusedEditors.push editor

    #Postpones finishing the loop until each step is completed so that all tabs are added in order.
    tabRecurs = (start, length)=>
      i = start
      for vimTab in tabList.slice(start+1)
        bufferNum = vimTab.replace(/:.*/, "")
        tabpath = vimTab.replace(/[^:]*:/, "")
        editor = @getEditorForVimBuffer(bufferNum, unusedEditors)
        if editor
          pane.moveItem(editor, i)
          unusedEditors.splice(unusedEditors.indexOf(editor), 1)
          if i+1 == currentTab
            pane.activateItem(editor)
        else
          closure = (buf, tab)=>
            atom.workspace.open(tab).then (newEditor) =>
              newEditor.vimBuffer = buf
              pane.addItem(newEditor)
              if thisTabChange == @lastTabChange
                newEditor.setText @shadowvim.getContents(buf)
                if i+1 == currentTab
                  pane.activateItem(newEditor)
                tabRecurs(i+1, length)
              else
                @updatingTabsFromVim=0
          closure(bufferNum, tabpath)
          return
        i+=1
      for editor in unusedEditors
        @destroyNoWarning(pane,editor)
      @updatingTabsFromVim=0

    tabRecurs 0,tabList.length

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

  getEditorForVimBuffer: (vimBuffer, editors) ->
    editors ?= atom.workspace.getEditors()
    for editor in editors
      if editor.vimBuffer == vimBuffer
        return editor

  destroyNoWarning: (pane, editor) ->
        storePromptFunc=pane.promptToSaveItem
        pane.promptToSaveItem= ->
          true
        pane.destroyItem(editor)
        pane.promptToSaveItem=storePromptFunc

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

