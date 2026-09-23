class_name DotVoteBallot
extends RefCounted

## The open ballot: what is on it, who voted for what, and who won.
##
## [b]One voter, one ballot, changeable until it closes[/b] — changeable because the
## alternative is a player who misclicked being stuck with it, and because being able
## to change your mind is what makes a live tally worth showing. Off, if a server
## wants it off: [member DotVoteRules.changeable_until_close].
##
## A ballot is an ordered list of ids, which is the one shape that serves every
## counting method this addon offers. Plurality reads the first entry, approval reads
## all of them, and an instant runoff reads them in order — so a client can always
## send the same thing and a server can change how it counts without changing the
## wire.
##
## [codeblock]
## ballot.begin(options, players.size())
## ballot.cast_vote(&"player_7", [&"arena"] as Array[StringName])
## var result := ballot.resolve()
## [/codeblock]
##
## Nothing here draws a menu, sends a chat message or counts down. A ballot is a tally
## and a rule; presenting it is the game's job, and [DotVoteDirector] is where the two
## are joined.

# No log channel: a tally and a rule. DotVoteDirector, which joins it to players and a
# clock, logs a vote opening and its result; a refused cast goes back to the voter.

## The pseudo-option for "keep this and add time to it".
const EXTEND := &"__extend__"

## The pseudo-option for "change nothing and add nothing".
const KEEP := &"__keep__"

signal opened(options: Array)
signal voted(voter: StringName, choices: Array)
signal closed(result: DotVoteResult)

## The choices on the ballot, in order. Nominations first.
var options: Array[DotVoteChoice] = []

## voter -> Array[StringName], in preference order.
var ballots: Dictionary = {}

## voter -> multiplier. Absent means 1.0.
var weights: Dictionary = {}

## How many people could vote when the ballot opened.
var eligible: int = 0

## Runoffs already held for this decision. Bounded by [member DotVoteRules.max_runoffs].
var runoffs_held: int = 0

var open: bool = false

var rules: DotVoteRules = null

## Consulted only by [constant DotVoteRules.TieBreak.LEAST_RECENTLY_PLAYED]. Optional.
var history: DotVoteHistory = null

## Consulted only by [constant DotVoteRules.TieBreak.NOMINATION_ORDER]. Optional.
var nominations: DotVoteNominations = null


static func of(p_rules: DotVoteRules) -> DotVoteBallot:
	var ballot := DotVoteBallot.new()
	ballot.rules = p_rules
	return ballot


# --- Opening ---------------------------------------------------------------

## Opens a ballot over [param p_options].
func begin(p_options: Array[DotVoteChoice], p_eligible: int) -> DotResult:
	if open:
		return DotResult.fail(DotError.CODE_STATE, "A ballot is already open.")

	if rules == null:
		return DotResult.fail(DotError.CODE_STATE, "A ballot needs rules.")

	if p_options.is_empty() and not rules.include_extend and not rules.include_keep:
		return DotResult.fail(
			DotError.CODE_STATE,
			"There is nothing to vote on.",
			"no options were offered and neither extend nor keep is on the ballot"
		)

	options = p_options.duplicate()
	ballots.clear()
	weights.clear()
	eligible = maxi(p_eligible, 0)
	runoffs_held = 0
	open = true

	opened.emit(option_ids())

	return DotResult.success(options)


## Re-opens over the tied or leading options, keeping the runoff count.
##
## [b]The ballots are cleared and that is the point.[/b] A runoff asks a different
## question — "of these two, which" — and carrying the first round's votes forward
## would answer the old one.
func begin_runoff(ids: Array[StringName]) -> DotResult:
	var kept: Array[DotVoteChoice] = []

	for choice in options:
		if ids.has(choice.id):
			kept.append(choice)

	var held := runoffs_held + 1
	var extend_in := ids.has(EXTEND)
	var keep_in := ids.has(KEEP)

	open = false

	var started := begin(kept, eligible)

	if not started.ok:
		return started

	runoffs_held = held

	# The pseudo-options survive a runoff only if they were in the tie. An extend that
	# came third does not get a second chance because two maps drew.
	_runoff_extend = extend_in
	_runoff_keep = keep_in

	return DotResult.success(kept)


## Set while a runoff is running, to restrict the pseudo-options to those that tied.
var _runoff_extend: bool = true
var _runoff_keep: bool = true


func has_extend() -> bool:
	return rules != null and rules.include_extend and (runoffs_held == 0 or _runoff_extend)


func has_keep() -> bool:
	return rules != null and rules.include_keep and (runoffs_held == 0 or _runoff_keep)


## Every votable id, in ballot order: the options, then extend, then keep.
##
## The pseudo-options go last deliberately. [constant DotVoteRules.TieBreak.BALLOT_ORDER]
## resolves toward the front, and a tie-break that handed ties to "keep things as they
## are" would be a server that never changes.
func option_ids() -> Array[StringName]:
	var out: Array[StringName] = []

	for choice in options:
		out.append(choice.id)

	if has_extend():
		out.append(EXTEND)

	if has_keep():
		out.append(KEEP)

	return out


func find_option(id: StringName) -> DotVoteChoice:
	for choice in options:
		if choice.id == id:
			return choice

	return null


func has_option(id: StringName) -> bool:
	return option_ids().has(id)


# --- Voting ----------------------------------------------------------------

## Records a ballot. [param choices] is in preference order.
##
## [param weight] is what an operator's "an admin's vote counts double" turns into.
## 1.0 for everybody is the default and the sane configuration; the hook exists
## because premium servers in this genre have wanted it for twenty years and the
## alternative is a fork.
func cast_vote(
	voter: StringName,
	choices: Array[StringName],
	weight: float = 1.0
) -> DotResult:
	if not open:
		return DotResult.fail(DotError.CODE_STATE, "There is no vote running.")

	if choices.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "No choice was given.")

	if ballots.has(voter) and not rules.changeable_until_close:
		return DotResult.fail(
			DotError.CODE_STATE, "You have already voted."
		)

	var legal: Array[StringName] = []
	var known := option_ids()

	for id in choices:
		if not known.has(id):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"'%s' is not on the ballot." % id,
				"on it: %s" % ", ".join(_as_strings(known))
			)

		if legal.has(id):
			continue

		legal.append(id)

	match rules.method:
		DotVoteRules.Method.APPROVAL:
			if rules.approval_max_choices > 0:
				legal = legal.slice(0, rules.approval_max_choices)
		DotVoteRules.Method.INSTANT_RUNOFF:
			pass
		_:
			# A ranked ballot sent to a server counting first preferences is not an
			# error — it is a client that does not know how this server counts, and the
			# honest reading of it is its first preference. Refusing it would make a
			# generic client unusable against half the configurations here.
			legal = legal.slice(0, 1)

	ballots[voter] = legal
	weights[voter] = weight

	voted.emit(voter, legal)

	return DotResult.success(legal)


func withdraw(voter: StringName) -> bool:
	if not ballots.has(voter):
		return false

	ballots.erase(voter)
	weights.erase(voter)

	return true


func voter_count() -> int:
	return ballots.size()


func has_voted(voter: StringName) -> bool:
	return ballots.has(voter)


## Whether everybody who could vote has.
func everybody_voted() -> bool:
	return eligible > 0 and ballots.size() >= eligible


func _weight_of(voter: StringName) -> float:
	return float(weights.get(voter, 1.0))


static func _as_strings(ids: Array[StringName]) -> PackedStringArray:
	var out := PackedStringArray()

	for id in ids:
		out.append(String(id))

	return out


# --- Counting --------------------------------------------------------------

## Current counts by id, including zero-vote options so a tally renders in full.
##
## Approval counts every entry on a ballot; every other method counts the first.
func tally() -> Dictionary:
	var counts := {}

	for id in option_ids():
		counts[id] = 0.0

	var approval := rules != null and rules.method == DotVoteRules.Method.APPROVAL

	for voter: Variant in ballots:
		var choices: Array = ballots[voter]
		var weight := _weight_of(voter)

		if choices.is_empty():
			continue

		if approval:
			for id: Variant in choices:
				counts[id] = float(counts.get(id, 0.0)) + weight
		else:
			counts[choices[0]] = float(counts.get(choices[0], 0.0)) + weight

	return counts


## Closes the ballot and decides it.
func resolve() -> DotVoteResult:
	var result := DotVoteResult.new()

	if not open:
		result.summary = "There was no vote running."
		closed.emit(result)
		return result

	open = false

	result.eligible = eligible
	result.votes_cast = ballots.size()

	var ids := option_ids()

	if ids.is_empty():
		result.summary = "Nothing was on the ballot."
		closed.emit(result)
		return result

	var counts := tally()
	result.counts = counts

	if ballots.is_empty():
		# Distinguished from "too few voted": nobody at all voting is usually an empty
		# server or a vote nobody was shown, and a quorum message about it is confusing.
		result.outcome = DotVoteResult.Outcome.EMPTY
		result.summary = "Nobody voted."
		closed.emit(result)
		return result

	if rules.quorum > 0.0 and eligible > 0:
		var turnout := float(ballots.size()) / float(eligible)

		if turnout < rules.quorum:
			# The leader is worked out BEFORE the outcome is stamped. _leader can ask
			# for a runoff, and a runoff nobody voted enough in is not the answer to
			# "too few people voted".
			var leader := _leader(counts, result)
			result.outcome = DotVoteResult.Outcome.NO_QUORUM
			result.winner_id = leader
			result.winner = find_option(leader)
			result.summary = "Not enough people voted (%d of %d, %d%% needed)." % [
				ballots.size(), eligible, int(rules.quorum * 100.0)
			]
			closed.emit(result)
			return result

	match rules.method:
		DotVoteRules.Method.INSTANT_RUNOFF:
			_resolve_instant_runoff(result)
		DotVoteRules.Method.MAJORITY_RUNOFF:
			_resolve_majority(result, counts)
		_:
			_settle(result, _leader(counts, result), counts)

	closed.emit(result)

	return result


func _total(counts: Dictionary) -> float:
	var sum := 0.0

	for id: Variant in counts:
		sum += float(counts[id])

	return sum


func _resolve_majority(result: DotVoteResult, counts: Dictionary) -> void:
	var leader := _leader(counts, result)

	if result.outcome == DotVoteResult.Outcome.RUNOFF:
		_settle(result, leader, counts)
		return

	var total := _total(counts)
	var share := float(counts.get(leader, 0.0)) / maxf(total, 1.0)

	if share >= rules.majority_fraction:
		_settle(result, leader, counts)
		return

	if runoffs_held >= rules.max_runoffs:
		# Out of runoffs. Taking the leader is the only answer that terminates, and a
		# server that kept holding runoffs would never change anything.
		_settle(result, leader, counts)
		result.summary += " (no majority, and the runoffs are used up)"
		return

	var ordered := _ordered_ids_by_count(counts)

	result.outcome = DotVoteResult.Outcome.RUNOFF
	result.runoff_ids = ordered.slice(0, mini(rules.runoff_options, ordered.size()))
	result.summary = "No majority — a runoff between %s." % ", ".join(
		_as_strings(result.runoff_ids)
	)


## Eliminates the last-placed choice until something has a majority.
##
## [b]Ties for last are broken toward elimination in reverse ballot order.[/b] Some
## rule is needed and every rule is arbitrary; this one is at least the mirror of the
## tie-break that decides the winner, so the two never disagree about which of two
## equal options this server considers "first".
func _resolve_instant_runoff(result: DotVoteResult) -> void:
	var remaining := option_ids()
	var counts := {}

	while true:
		counts = _count_among(remaining)
		result.rounds.append(counts.duplicate())

		var total := _total(counts)
		var leader := _leader(counts, result)

		if total <= 0.0:
			_settle(result, leader, counts)
			return

		if float(counts.get(leader, 0.0)) / total >= rules.majority_fraction:
			result.counts = counts
			_settle(result, leader, counts)
			return

		if remaining.size() <= 2:
			result.counts = counts
			_settle(result, leader, counts)
			return

		var loser := _last_placed(counts, remaining)
		remaining.erase(loser)

	# Unreachable; GDScript wants no return here because the loop never exits.


func _count_among(remaining: Array[StringName]) -> Dictionary:
	var counts := {}

	for id in remaining:
		counts[id] = 0.0

	for voter: Variant in ballots:
		var choices: Array = ballots[voter]
		var weight := _weight_of(voter)

		for id: Variant in choices:
			if remaining.has(id):
				counts[id] = float(counts[id]) + weight
				break

	return counts


func _last_placed(counts: Dictionary, remaining: Array[StringName]) -> StringName:
	var worst := INF
	var loser: StringName = remaining[0]

	for id in remaining:
		var votes := float(counts.get(id, 0.0))

		# `<=` rather than `<`: later on the ballot loses a tie for last, which is the
		# mirror of BALLOT_ORDER resolving a tie for first toward the front.
		if votes <= worst:
			worst = votes
			loser = id

	return loser


# --- Deciding --------------------------------------------------------------

## Turns a winning id into an outcome, applying the extend and keep rules.
func _settle(result: DotVoteResult, winner_id: StringName, counts: Dictionary) -> void:
	result.counts = result.counts if not result.counts.is_empty() else counts

	# A tie-break of RUNOFF has already decided the outcome, and settling on top of it
	# would announce a winner the server is about to hold another vote about. The id it
	# returned is only the placeholder leader; the runoff is the answer.
	if result.outcome == DotVoteResult.Outcome.RUNOFF:
		result.summary = "A tie — a runoff between %s." % ", ".join(
			_as_strings(result.runoff_ids)
		)
		return

	if winner_id == EXTEND:
		result.outcome = DotVoteResult.Outcome.EXTEND
		result.winner_id = EXTEND
		result.summary = "The players voted to extend."
		return

	if winner_id == KEEP:
		result.outcome = DotVoteResult.Outcome.KEEP
		result.winner_id = KEEP
		result.summary = "The players voted to stay."
		return

	if winner_id == &"":
		result.outcome = DotVoteResult.Outcome.EMPTY
		result.summary = "The vote decided nothing."
		return

	result.outcome = DotVoteResult.Outcome.WINNER
	result.winner_id = winner_id
	result.winner = find_option(winner_id)

	var name := result.winner.name_or_id() if result.winner != null else String(winner_id)
	var votes := float(counts.get(winner_id, 0.0))

	result.summary = "%s wins with %s." % [name, _format_votes(votes)]

	if result.tie_break != "":
		result.summary += " (tie, %s)" % result.tie_break


static func _format_votes(votes: float) -> String:
	if is_equal_approx(votes, roundf(votes)):
		var whole := int(roundf(votes))
		return "%d vote%s" % [whole, "" if whole == 1 else "s"]

	return "%.1f votes" % votes


## The leading id, with ties broken by the configured rule.
##
## Records the tie-break on [param result] when one was used, so the announcement can
## say why — see [DotVoteResult].
func _leader(counts: Dictionary, result: DotVoteResult) -> StringName:
	var best := -INF
	var tied: Array[StringName] = []

	for id in option_ids():
		if not counts.has(id):
			continue

		var votes := float(counts[id])

		if votes > best + 0.0001:
			best = votes
			tied = [id] as Array[StringName]
		elif absf(votes - best) <= 0.0001:
			tied.append(id)

	if tied.is_empty():
		return &""

	# [b]The two halves of extend_needs_majority, and both of them are here.[/b] With
	# it on, extend leading on equal votes is not extend winning: the people who wanted
	# something new are the ones who lose by staying, and a server that ties toward the
	# status quo never changes anything. With it off, the incumbent keeps a tie — at
	# least as many people want to stay as want to go.
	#
	# The `off` half is not decoration and was missing. Leaving the tie to the ordinary
	# tie-break looks like the other policy and is not one: every pseudo-option sorts
	# last in ballot order, so BALLOT_ORDER handed the tie to the map as well and the
	# setting decided nothing in either position.
	if tied.size() > 1 and tied.has(EXTEND):
		if rules.extend_needs_majority:
			tied.erase(EXTEND)
		else:
			result.tie_break = "extend keeps a tie"
			result.tied_ids = tied.duplicate()
			return EXTEND

	if tied.size() == 1:
		return tied[0]

	result.tied_ids = tied.duplicate()

	return _break_tie(tied, result)


func _break_tie(tied: Array[StringName], result: DotVoteResult) -> StringName:
	match rules.tie_break:
		DotVoteRules.TieBreak.NOMINATION_ORDER:
			if nominations != null:
				result.tie_break = "nominated first"
				return _min_by(tied, func(id: StringName) -> int:
					return nominations.first_index(id)
				)

			result.tie_break = "first on the ballot"
			return tied[0]

		DotVoteRules.TieBreak.LEAST_RECENTLY_PLAYED:
			if history != null:
				result.tie_break = "longest unplayed"
				# plays_since is -1 for "never played", which must sort best rather than
				# worst — so it is mapped to the largest possible distance.
				return _min_by(tied, func(id: StringName) -> int:
					var since := history.plays_since(id)
					return -0x7FFFFFFF if since < 0 else -since
				)

			result.tie_break = "first on the ballot"
			return tied[0]

		DotVoteRules.TieBreak.RANDOM:
			result.tie_break = "drawn"
			var rng := RandomNumberGenerator.new()
			rng.seed = rules.tie_break_seed
			var picked := tied[rng.randi_range(0, tied.size() - 1)]
			# Advanced deterministically rather than reseeded from the clock, so a
			# client following the same ballots reaches the same answer — the reason
			# DotMapRotation advances its seed the same way.
			rules.tie_break_seed = int(
				hash(String(picked)) ^ (rules.tie_break_seed * 1103515245 + 12345)
			) & 0x7FFFFFFF
			return picked

		DotVoteRules.TieBreak.RUNOFF:
			if runoffs_held < rules.max_runoffs:
				result.outcome = DotVoteResult.Outcome.RUNOFF
				result.runoff_ids = tied.duplicate()
				result.tie_break = "runoff"
				return tied[0]

			result.tie_break = "first on the ballot (out of runoffs)"
			return tied[0]

		_:
			result.tie_break = "first on the ballot"
			return tied[0]


func _min_by(ids: Array[StringName], key: Callable) -> StringName:
	var best: StringName = ids[0]
	var best_key: int = key.call(best)

	for id in ids:
		var k: int = key.call(id)

		if k < best_key:
			best_key = k
			best = id

	return best


## Ids ordered by count, most first, ties in ballot order.
func _ordered_ids_by_count(counts: Dictionary) -> Array[StringName]:
	var order := option_ids()
	var out := order.duplicate()

	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ca := float(counts.get(a, 0.0))
		var cb := float(counts.get(b, 0.0))

		if not is_equal_approx(ca, cb):
			return ca > cb

		return order.find(a) < order.find(b)
	)

	return out


func reset() -> void:
	open = false
	options.clear()
	ballots.clear()
	weights.clear()
	runoffs_held = 0
	_runoff_extend = true
	_runoff_keep = true


func describe() -> Dictionary:
	return {
		"open": open,
		"options": option_ids().size(),
		"votes": ballots.size(),
		"eligible": eligible,
		"runoffs": runoffs_held,
		"tally": tally(),
	}
