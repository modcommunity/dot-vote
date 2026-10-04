class_name DotVoteBallotView
extends RefCounted

## A ballot as a player's screen draws it: the options, the counts, who voted for what, and
## how to choose.
##
## [b]The other half of [DotVoteClockView][/b], and built the same way: a dictionary a
## server makes from the director it runs and a client draws from, with no wire format of
## its own. Whatever carries it — a game's netcode bridge, dot-server's notice — is the
## host's, for the reason this addon has no wire format at all.
##
## [b]A ballot used to reach a player as chat[/b], a numbered list in a scrollback they
## answered by typing. That still works and nothing here replaces it: this is what a client
## needs to draw the same ballot as a menu that takes a number key or a click, and to show
## each voter's avatar on the option they chose.
##
## The dictionary, every field optional to a reader:
##
## [codeblock]
## {
##   "open": true,                 # false: the ballot closed; "winner" says what won
##   "runoff": false,
##   "seconds": 27.0,              # left, from the moment it arrives; the client counts
##   "input": "both",              # numbers | pointer | both — DotVoteRules.ballot_input
##   "multi": false,               # true: ranked or approval, a click adds rather than replaces
##   "options": [{"id": "dm_hall", "label": "Hall", "votes": 2.0}, ...],
##   "voters": {"u7": 0, "u12": 1},  # voter -> index into options; absent when secret
##   "people": {"u7": {"name": "ana", "avatar": "https://..."}},
##   "winner": "Hall",             # only when closed
##   "title": "Vote for the next map",   # the host's
##   "command": "votefor",               # the host's: what a choice is typed as, with its number
## }
## [/codeblock]
##
## [b]Options are in [method DotVoteBallot.option_ids] order[/b] — the order a typed number
## indexes, so option [code]i[/code] is [code]!<command> i+1[/code] on every screen and in
## every console. Never [method DotVoteBallot.countable_ids], which is the tie-break order.
##
## A pure function of the director. It logs nothing.

## Most options sent. [member DotVoteRules.max_options] is at most 32 already; this is what a
## reader can rely on without trusting the writer.
const MAX_OPTIONS := 32

## Most voters named. Past this the counts are still right and the rest are not drawn: a
## ballot with a hundred faces on it is not readable anyway, and the dictionary has to fit
## comfortably in one message.
const MAX_VOTERS := 64

## Longest label sent.
const MAX_LABEL := 48


## The ballot [param director] has open, or a closed one when it has none.
##
## [param people_fn] answers [code]voter -> {"name": String, "avatar": String}[/code] for
## the voters shown — the host's, because who a voter id is belongs to the server, not this
## addon. Optional; without it voters are drawn by id.
static func state_of(director: DotVoteDirector, people_fn: Callable = Callable()) -> Dictionary:
	if director == null or director.ballot == null or not director.ballot.open:
		return {"open": false}

	var rules := director.rules
	var ballot := director.ballot
	var ids := ballot.option_ids()
	var counts := ballot.tally()

	var options := []
	var index := {}

	for id in ids:
		if options.size() >= MAX_OPTIONS:
			break

		index[id] = options.size()
		options.append({
			"id": String(id),
			"label": director.option_label(id).left(MAX_LABEL),
			"votes": float(counts.get(id, 0.0)),
		})

	var out := {
		"open": true,
		"runoff": ballot.runoffs_held > 0,
		"seconds": snappedf(director.vote_seconds_remaining(), 0.1),
		"input": input_name(rules.ballot_input),
		"multi": rules.method == DotVoteRules.Method.APPROVAL
			or rules.method == DotVoteRules.Method.INSTANT_RUNOFF,
		"options": options,
	}

	if not rules.ballot_show_voters:
		return out

	var voters := {}
	var people := {}

	for voter: Variant in ballot.ballots:
		if voters.size() >= MAX_VOTERS:
			break

		var chosen: Array = ballot.ballots[voter]

		# An abstention is an empty ballot: answered, and nowhere on the board.
		if chosen.is_empty() or not index.has(chosen[0]):
			continue

		var key := String(voter)
		voters[key] = int(index[chosen[0]])

		if people_fn.is_valid():
			var who: Variant = people_fn.call(StringName(key))

			if who is Dictionary:
				people[key] = {
					"name": str((who as Dictionary).get("name", key)).left(MAX_LABEL),
					"avatar": str((who as Dictionary).get("avatar", "")).left(512),
				}

	out["voters"] = voters

	if not people.is_empty():
		out["people"] = people

	return out


## The closed state for [param result]: what won, for a client to show briefly before the
## ballot goes away.
static func closed_state(director: DotVoteDirector, result: DotVoteResult) -> Dictionary:
	var out := {"open": false}

	if result == null:
		return out

	if result.winner_id != &"":
		out["winner"] = (
			director.option_label(result.winner_id) if director != null
			else String(result.winner_id)
		).left(MAX_LABEL)

	if result.outcome == DotVoteResult.Outcome.RUNOFF:
		out["runoff_next"] = true

	return out


## The lower-case name of a [enum DotVoteRules.BallotInput], as the dictionary carries it.
static func input_name(value: int) -> String:
	match value:
		DotVoteRules.BallotInput.NUMBERS:
			return "numbers"
		DotVoteRules.BallotInput.POINTER:
			return "pointer"
		_:
			return "both"


## Whether two states would draw the same ballot, ignoring the time left — which a client
## counts for itself and which differs on every tick, so comparing it would resend the
## whole ballot sixty times a second.
static func same_ballot(a: Dictionary, b: Dictionary) -> bool:
	var x := a.duplicate()
	var y := b.duplicate()
	x.erase("seconds")
	y.erase("seconds")
	return x.hash() == y.hash()
