Rounds = new Meteor.Collection "rounds"

if Meteor.isServer
  Meteor.publish "rounds", (userId) ->
    Rounds.find {userId: userId}

  # Meteor.startup ->



if Meteor.isClient
  Meteor.autosubscribe ->
    Meteor.subscribe "rounds", Meteor.userId()

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

  Rounds.current = (id) ->
    Session.set "round", id if id != undefined
    round = Rounds.findOne id || Session.get("round")
    Stats.generate round
    return round

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
    @generate: (round) ->
      if round? and round.finished? and !round.stats?
        stats = new @(round)
        Rounds.update round._id, {$set: {stats: stats, sections: round.sections}}
    @format: (number) ->
      Math.round(number * 100) / 100
    @chartData: (rounds) ->
      localTime = (dateStr) ->
        d = new Date(dateStr)
        offset = d.getTimezoneOffset() * 60000
        Date.parse(d) - offset

      series = ({name: s.number, data: []} for s in getSections())
      for r in rounds
        if r.finished?
          Stats.generate r
          for i, s of r.sections
            series[i].data.push [localTime(r.date), Stats.format(s.pop)]
      return series
    @pieChartData: (round) ->
      [{name: "Hits", data: ([s.number.toString(), s.hits] for s in round.sections)}]
    @polarChartData: (round) ->
      [{name: "POP", data: (Stats.format(s.pop) for s in round.sections)}]


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
    
      
# main
  Template.main.round = ->
    Rounds.current()

  Template.main.user = ->
    Meteor.user()

  Template.main.rendered = ->
    new Highcharts.Chart
      chart:
        renderTo: "chart"
        type: "line"
      title:
        text: ""
      xAxis:
        type: "datetime"
        title:
          text: "Time"
      yAxis:
        title:
          text: "POP"
      series: Stats.chartData Rounds.find({}, {sort: {date: 1}}).fetch()

  Template.main.events
    "click .create": ->
      round = Rounds.init()
      round._id = Rounds.insert round
      Rounds.current round._id
      
# selectRound
  Template.selectRound.rounds = ->
    Rounds.find({}, {sort: {date: 1}})

  Template.selectRound.displayName = ->
    Rounds.name @

  Template.selectRound.events
    "click .btn": ->
      Rounds.current @_id

# round
  Template.round.section = ->
    currentSection @

  Template.round.statsTable = ->
    out = "<table class='table table-bordered'><tr><th>&nbsp;</th>"
    out += "<th>" + s.number + "</th>" for s in @sections
    for i in [0..9]
      out += "<tr><td>" + (i + 1) + "</td>"
      out += "<td>" + s.scores[i] + "</td>" for s in @sections
      out += "</tr>"
    for stat in ["hits", "hpd", "dtc", "pop"]
      out += "<tr><td><b>" + stat + "</b></td>"
      out += "<td><b>" + Stats.format(s[stat]) + "</b></td>" for s in @sections
      out += "</tr>"
    out + "</tr></table>"

  Template.round.format = Stats.format

  Template.round.rendered = ->
    if round = @data
      opts =
        chart:
          renderTo: "roundChart"
          polar: true
        title:
          text: ""
        xAxis:
          categories: (s.number.toString() for s in round.sections)
        series: Stats.polarChartData round
      new Highcharts.Chart opts

  Template.round.events
    "click .back": ->
      Rounds.current null

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
      Rounds.current null
      



