do ->
  rtr = Backbone.Router.extend
    routes:
      "": "home"
      "manage": "manage"
      "round/:id": "round"
    home: ->
      Rounds.current null
    round: (id) ->
      Rounds.current id
    manage: ->
      Session.set "editing", true
    setRound: (id) ->
      @setEditing false
      Rounds.current id
      if id == null
        @navigate ""
      else
        @navigate "round/" + id
      return false
    setEditing: (to) ->
      Rounds.current null
      Session.set "editing", to
      @navigate "manage" if to

  window.Router = new rtr()