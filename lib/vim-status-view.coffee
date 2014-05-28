{View} = require 'atom'

module.exports =
class VimStatusView extends View
  @content: ->
    @span ""
        
  setStatus: (status, arg) ->
    @html @getStatusHtml(status,arg)+" "
    @find('.commandText').text arg

  setText: (text) ->
    @html "<span class='commandText' /><br/>"
    @find('.commandText').text text

  getStatusHtml: (status)->
    switch status
      when "n"
          ""
      when "v"
          "<b>-- VISUAL --</b>"
      when "V"
          "<b>-- VISUAL LINE --</b>"
      when "s"
          "<b>-- SELECT --</b>"
      when "S"
          "<b>-- SELECT LINE --</b>"
      when "i"
          "<b>-- INSERT --</b>"
      when "R"
          "<b>-- REPLACE --</b>"
      when "R"
          "<b>-- REPLACE --</b>"
      when "Rv"
          "<b>-- VREPLACE --</b>"
      when "Rv"
          "<b>-- VREPLACE --</b>"
      when "c"
          "<span class='commandText' /><br/>"
