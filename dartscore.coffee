Rounds = new Meteor.Collection "rounds"

if Meteor.isServer
  Meteor.publish "rounds", (userId) ->
    Rounds.find {userId: userId}

if Meteor.isClient
  Meteor.autosubscribe ->
    Meteor.subscribe "rounds", Meteor.userId()

  Meteor.startup ->
    Backbone.history.start(pushState: true)

  getSections = ->
    obj = []
    obj.push(number: i, scores: []) for i in [20..15]
    obj.push(number: "B", scores: [])
    return obj

  Rounds.init = ->
    date: new Date
    sections: getSections()
    finished: null
    userId: Meteor.userId()

  Rounds.name = (round) ->
    new Date(round.date).toLocaleDateString()

  Rounds.currentId = (id) ->
    if id != undefined
      Session.set "round", id
      return id
    Session.get "round"

  Rounds.current = (id) ->
    if id = Rounds.currentId id
      Rounds.findOne id

  Rounds.selectedIds = ->
    Session.get("selectedRounds") or []

  Rounds.toggleSelected = (id) ->
    ids = Rounds.selectedIds()
    idx = ids.indexOf(id)
    if idx == -1
      ids.push id
    else
      ids.splice idx, 1
    Session.set "selectedRounds", ids

  Rounds.all = ->
    Rounds.find({}, {sort: {date: 1}})

  addScore = (score) ->
    round = Rounds.current()
    section = currentSection round
    section.scores.push score.valueOf()
    Rounds.update round._id, {$set: {sections: round.sections}}

  removeScore = ->
    round = Rounds.current()
    section = currentSection round
    section.scores.pop()
    Rounds.update round._id, {$set: {sections: round.sections}}

  currentSection = (round) ->
    unless round.finished?
      for s in round.sections
        return s if s.scores.length < 10
      Rounds.current null
      Rounds.update round._id, {$set: {finished: new Date()}}

  class Stats
    constructor: (round) ->
      sum = (numbers) ->
        total = 0
        total += i for i in numbers
        return total
      @hits = 0
      for s in round.sections
        s.hits = sum s.scores
        @hits += s.hits
        s.hpd = s.hits / 30
        s.dtc = 3 / s.hpd
        d = if s.number == "B" then 60 else 90
        s.pop = (s.hits / d) * 100
      @hpd = @hits / 210
      @dtc = 21 / @hpd
      @pop = (@hits / 600) * 100
    @generate: (round) ->
      if round? and round.finished? and !round.stats?
        stats = new @(round)
        Rounds.update round._id, {$set: {stats: stats, sections: round.sections}}
    @format: (number) ->
      Math.round(number * 100) / 100
    @localTime: (dateStr) ->
      d = new Date(dateStr)
      offset = d.getTimezoneOffset() * 60000
      Date.parse(d) - offset 

  class Charts
    @lineChartOfSections: (id) ->
      rounds = Rounds.find({}, {sort: {date: 1}}).fetch()
      series = ({name: s.number, data: []} for s in getSections())
      for r in rounds
        if r.finished?
          Stats.generate r
          for i, s of r.sections
            series[i].data.push [Stats.localTime(r.date), Stats.format(s.pop)]
      new Highcharts.Chart
        chart:
          renderTo: id
          type: "spline"
        title:
          text: ""
        xAxis:
          type: "datetime"
          title:
            text: "Time"
        yAxis:
          title:
            text: "POP"
        series: series
    @radialChartOfRound: (id, round) ->
      series = [{name: "POP", data: (Stats.format(s.pop) for s in round.sections)}]
      opts =
        chart:
          renderTo: id
          polar: true
        title:
          text: ""
        xAxis:
          categories: (s.number.toString() for s in round.sections)
        series: series
      new Highcharts.Chart opts

# main
  Template.main.round = ->
    if round = Rounds.current()
      Stats.generate round
      return round

  Template.main.editing = ->
    Session.get "editing"

  Template.main.editingActive = ->
    if Template.main.editing() then "active" else ""

  Template.main.user = Meteor.user

  Template.main.charts =
    line: 
      id: "lineChartOfSections"

  Template.main.events
    "click .create": ->
      round = Rounds.init()
      round._id = Rounds.insert round
      Router.setRound round._id
    "click .brand": ->
      Router.setRound null
    "click .edit": ->
      Router.setEditing true

# editRounds
  Template.editRounds.rounds = Rounds.all

  Template.editRounds.displayName = ->
    Rounds.name @

  Template.editRounds.selected = ->
    Rounds.selectedIds().indexOf(@_id) != -1

  Template.editRounds.events
    "click tr": ->
      Rounds.toggleSelected @_id
    "click .delete": ->
      Rounds.remove(_id: {$in: Rounds.selectedIds()})

  Template.editRounds.bool = (data) ->
    if data then "Yes" else "No"

  Template.editRounds.f = (data) ->
    if data == null
      return ""
    if typeof data == "number"
      return Stats.format data
    return data.toString()
      
# selectRound
  Template.selectRound.rounds = ->
    Rounds.find({}, {sort: {date: 1}})

  Template.selectRound.displayName = ->
    Rounds.name @

  Template.selectRound.roundActive = ->
    if Rounds.currentId() then "active" else ""

  Template.selectRound.events
    "click .round": ->
      Router.setRound @_id

# round
  Template.round.section = ->
    currentSection @

  Template.round.charts = ->
    radial:
      id: "radialChartOfRound"
      data: @

  Template.round.displayName = Template.selectRound.displayName

  Template.round.statsTable = ->
    out = "<table class='table table-bordered'><tr><th class='head'>&nbsp;</th>"
    out += "<th>" + s.number + "</th>" for s in @sections
    for i in [0..9]
      out += "<tr><td class='head'><i>" + (i + 1) + "</i></td>"
      out += "<td>" + s.scores[i] + "</td>" for s in @sections
      out += "</tr>"
    out += "<tr><td colspan='8' class='divider'></td></tr>"
    for stat in ["hits", "hpd", "dtc", "pop"]
      out += "<tr><td class='head stat'><b><i>" + stat + "</i></b></td>"
      out += "<td class='stat'><b>" + Stats.format(s[stat]) + "</b></td>" for s in @sections
      out += "</tr>"
    out + "</tr></table>"

  Template.round.format = Stats.format

  Template.round.events
    "click .back": ->
      Router.setRound null

# section
  Template.section.potentialScores = ->
    if @number == "B"
      (i for i in [0..6])
    else
      (i for i in [0..9])

  Template.section.scoreNumber = ->
    @scores.length + 1

  Template.section.events
    "click .score": ->
      addScore @
    "click .undo": ->
      removeScore()
    "click .back": ->
      Router.setRound null
      
  Template.chart.rendered = ->
    Charts[@data.id](@data.id, @data.data)


