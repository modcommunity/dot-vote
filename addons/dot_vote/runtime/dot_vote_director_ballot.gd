@tool
extends "res://addons/dot_vote/runtime/dot_vote_director_nominate.gd"

## The ballot, countdown, casting and closing of [DotVoteDirector], kept apart so each file stays readable.

## Starts a vote the way the rules want it started: with the
## [member DotVoteRules.vote_warning_sec] countdown first, or at once when there is none.
##
## [b]What everything that is not a test should call.[/b] [method open_vote] opens a
## ballot this instant, which is right for a client mirroring a server's ballot and for
## a suite, and wrong for a server whose operator asked for fifteen seconds of warning.
##
## [param force] is an admin's "vote now": it replaces a change already decided rather
## than being refused by it.
func start_vote(
	reason: StringName = DotVoteClock.REASON_MANUAL,
	force: bool = false
) -> DotResult:
	var ready := _can_open()

	# Before has_alternatives: a server built with one map that has since been delivered a
	# second has something to vote for now.
	if ready.ok:
		_refresh_source()

	if not ready.ok:
		# [b]Another vote on screen is a wait, not a no.[/b] The refusal says "this one will
		# follow it", and until 2026-10-11 nothing made it true for a ballot a HOST asked for:
		# a MANUAL game opens its round's ballot once, so a refusal because the server's game
		# vote was up was that round's ballot gone. Owed through the same retry a due vote
		# takes, so it opens the tick the other one is down.
		if _refused_only_for_busy():
			_vote_due_pending = true
			_vote_due_reason = reason

		return ready

	if state == State.COUNTDOWN:
		return DotResult.fail(DotError.CODE_STATE, "A vote is about to start.")

	if state == State.PENDING:
		if not force:
			return DotResult.fail(
				DotError.CODE_STATE,
				"What plays next is already decided (%s)." % _name_of(_pending_id)
			)

		DotLog.info(CHANNEL, "a decided change was replaced by a new vote", {
			"was": String(_pending_id)
		})
		_pending_id = &""
		state = State.RUNNING

	# After the PENDING check, so an admin replacing a decided change with nothing to
	# replace it by is told so rather than having the decision thrown away.
	if not has_alternatives():
		if reason == DotVoteClock.REASON_MANUAL:
			return DotResult.fail(DotError.CODE_STATE, "There is nothing else to vote for.")

		# Success: the due vote is dealt with. A failure here would be retried every frame.
		_pass_over(reason)
		return DotResult.success(0.0)

	if _lone_auto(reason):
		DotLog.info(CHANNEL, "auto ballot skipped: one voter", {"reason": String(reason)})
		_pass_over(reason)
		return DotResult.success(0.0)

	if rules.vote_warning_sec > 0.0:
		_begin_countdown(rules.vote_warning_sec, false, reason)
		return DotResult.success(rules.vote_warning_sec)

	return open_vote(reason)


## Whether [method _can_open] refused only because another vote is on screen: everything
## else would let the ballot open, so it is owed rather than refused.
func _refused_only_for_busy() -> bool:
	return (
		rules.enabled and state == State.RUNNING and source != null
		and player_count() >= rules.min_players_to_vote
		and _cooldown_remaining <= 0.0 and _busy() and has_alternatives()
	)


## Why a ballot could not open right now, or success.
func _can_open() -> DotResult:
	if not rules.enabled:
		return DotResult.fail(DotError.CODE_UNSUPPORTED, "Voting is turned off.")

	if state == State.VOTING:
		return DotResult.fail(DotError.CODE_STATE, "A vote is already running.")

	if source == null:
		return DotResult.fail(DotError.CODE_STATE, "No source.")

	var players := player_count()

	if players < rules.min_players_to_vote:
		return DotResult.fail(
			DotError.CODE_STATE,
			"There are not enough players to hold a vote.",
			"%d here, %d needed" % [players, rules.min_players_to_vote]
		)

	if _cooldown_remaining > 0.0:
		return DotResult.fail(
			DotError.CODE_RATE_LIMITED,
			"Another vote can start in %ds." % int(ceil(_cooldown_remaining))
		)

	if _busy():
		return DotResult.fail(
			DotError.CODE_STATE, "Another vote is on screen; this one will follow it."
		)

	return DotResult.success(true)


## Opens a ballot now, with no countdown.
##
## [param only] puts exactly those ids on the ballot instead of filling it — an admin's
## hand-picked shortlist. Ids the source does not know are dropped with a warning
## rather than refusing the whole ballot.
func open_vote(
	reason: StringName = DotVoteClock.REASON_MANUAL,
	only: Array[StringName] = []
) -> DotResult:
	var ready := _can_open()

	if not ready.ok:
		return ready

	# Again here as well as in start_vote: a countdown can run for a minute, and the list
	# can grow during it.
	_refresh_source()

	var players := player_count()
	var options: Array[DotVoteChoice] = (
		build_options(players) if only.is_empty() else _choices_for(only)
	)

	if rules.shuffle_ballot:
		options = _shuffle(options)

	ballot.extend_available = clock.can_extend()
	ballot.early = reason == DotVoteClock.REASON_RTV

	var started := ballot.begin(options, maxi(_eligible_count(), 1))

	if not started.ok:
		return started

	nominations.clear(DotVoteNominations.REASON_BALLOT)

	state = State.VOTING
	_vote_reason = reason
	_vote_due_pending = false
	_vote_due_at_round_end = false
	_vote_remaining = rules.vote_duration_sec
	_announce_countdown = rules.announce_interval_sec

	var names := PackedStringArray()

	for choice in options:
		names.append(ballot_name(choice))

	DotLog.info(CHANNEL, "vote opened", {
		"reason": String(reason), "options": names.size(), "eligible": ballot.eligible
	})

	_say("Vote: %s (%ds)" % [", ".join(names), int(rules.vote_duration_sec)])
	_cue(rules.cue_vote_start)

	vote_opened.emit(ballot.option_ids(), _vote_remaining)

	return DotResult.success(options)


func _choices_for(ids: Array[StringName]) -> Array[DotVoteChoice]:
	var out: Array[DotVoteChoice] = []

	for id in ids:
		var choice := source.find(id) if source != null else null

		if choice == null:
			DotLog.warn(CHANNEL, "a hand-picked option is not in the source", {
				"id": String(id)
			})
			continue

		out.append(choice)

	return out


func _begin_countdown(seconds: float, runoff: bool, reason: StringName) -> void:
	state = State.COUNTDOWN
	_countdown_remaining = seconds
	_countdown_runoff = runoff
	_countdown_reason = reason
	_countdown_last = int(ceil(seconds))

	DotLog.info(CHANNEL, "counting down to a ballot", {
		"seconds": seconds, "runoff": runoff, "reason": String(reason)
	})

	countdown_started.emit(seconds, runoff)
	_cue(rules.cue_runoff_warning if runoff else rules.cue_warning)
	_say(
		"A runoff vote starts in %ds." % _countdown_last if runoff
		else "A vote for what plays next starts in %ds." % _countdown_last
	)
	_tick(_countdown_last, false)


func _advance_countdown(delta: float) -> void:
	_countdown_remaining -= delta

	var now := maxi(int(ceil(_countdown_remaining)), 0)

	# Every whole second crossed gets its tick, even when one advance crosses several —
	# a server that stalled for two seconds still says "3" before "1", and a sound layer
	# playing a countdown does not skip a number.
	while _countdown_last > now:
		_countdown_last -= 1

		if _countdown_last >= 1:
			_tick(_countdown_last, rules.announce_countdown_every_sec)

	if _countdown_remaining > 0.0:
		return

	state = State.RUNNING

	if _countdown_runoff:
		_open_runoff()
		return

	# The last alternative can go during the countdown: a player leaves and the only other
	# game needs more of them.
	if not has_alternatives():
		_pass_over(_countdown_reason)
		return

	if _lone_auto(_countdown_reason):
		DotLog.info(CHANNEL, "auto ballot skipped: one voter", {"reason": String(_countdown_reason)})
		_pass_over(_countdown_reason)
		return

	var opened := open_vote(_countdown_reason)

	if not opened.ok:
		# The same retry a vote refused by the cooldown takes. See _vote_due_pending.
		_vote_due_pending = true
		_vote_due_reason = _countdown_reason

		DotLog.warn(CHANNEL, "the counted-down vote could not open; will retry", {
			"why": opened.error.message
		})


func _tick(seconds_left: int, say: bool) -> void:
	countdown_tick.emit(seconds_left, _countdown_runoff)
	_cue(rules.countdown_cue_id(seconds_left))

	if say:
		_say("%d…" % seconds_left)


func is_counting_down() -> bool:
	return state == State.COUNTDOWN


func countdown_remaining() -> float:
	return maxf(_countdown_remaining, 0.0) if state == State.COUNTDOWN else 0.0


## Cancels a countdown, leaving the server running. An admin's "not now".
func cancel_countdown() -> bool:
	if state != State.COUNTDOWN:
		return false

	state = State.RUNNING
	_countdown_remaining = 0.0
	_runoff_ids.clear()

	_say("The vote was called off.")

	return true


## Calls off an open ballot without acting on it, so a map can be changed outright.
func cancel_vote() -> bool:
	if state != State.VOTING:
		return false

	var result := DotVoteResult.empty("The vote was called off.")
	DotLog.info(CHANNEL, "vote called off", {"reason": String(_vote_reason)})
	_say(result.summary)
	vote_closed.emit(result)
	_carry_on()
	return true


## Records a vote. [param choices] is in preference order; one entry is the usual case.
func cast_vote(voter: StringName, choices: Array[StringName]) -> DotResult:
	if state != State.VOTING:
		return DotResult.fail(DotError.CODE_STATE, "There is no vote running.")

	if not rules.spectators_may_vote and _is_spectator(voter):
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "You must be in the game to vote."
		)

	var result := ballot.cast_vote(voter, choices, _weight_for(voter))

	if result.ok:
		vote_cast.emit(voter, choices)

	return result


## Convenience for the overwhelmingly common case of one choice.
func cast_one(voter: StringName, choice: StringName) -> DotResult:
	return cast_vote(voter, [choice] as Array[StringName])


## Closes the ballot and acts on it.
func close_vote() -> DotVoteResult:
	if state != State.VOTING:
		return DotVoteResult.empty("There is no vote running.")

	var result := ballot.resolve()

	_decide_no_votes(result)

	_cooldown_remaining = rules.vote_cooldown_sec

	DotLog.info(CHANNEL, "vote closed", result.describe())
	_say(result.summary)
	_cue(rules.cue_vote_end)

	vote_closed.emit(result)

	var moment := _moment_for(_vote_reason)

	match result.outcome:
		DotVoteResult.Outcome.RUNOFF:
			if rules.runoff_warning_sec > 0.0:
				_runoff_ids = result.runoff_ids.duplicate()
				_begin_countdown(rules.runoff_warning_sec, true, _vote_reason)
				return result

			_runoff_ids = result.runoff_ids.duplicate()
			_open_runoff()
			return result

		DotVoteResult.Outcome.EXTEND:
			state = State.RUNNING
			_extend_now()
			return result

		DotVoteResult.Outcome.KEEP:
			_carry_on()
			return result

		DotVoteResult.Outcome.NO_QUORUM:
			_after_no_quorum(result, moment)
			return result

		DotVoteResult.Outcome.EMPTY:
			_carry_on()
			return result

		_:
			_schedule_change(result.winner_id, moment)
			return result


func _open_runoff() -> void:
	var again := ballot.begin_runoff(_runoff_ids)
	_runoff_ids.clear()

	if again.ok:
		state = State.VOTING
		_vote_remaining = rules.vote_duration_sec
		_announce_countdown = rules.announce_interval_sec
		_cue(rules.cue_vote_start)
		vote_opened.emit(ballot.option_ids(), _vote_remaining)
		return

	# A runoff that cannot start is not a reason to leave the server in VOTING for ever.
	state = State.RUNNING


## The moment a winner of a ballot opened for [param reason] waits for.
func _moment_for(reason: StringName) -> int:
	if reason == DotVoteClock.REASON_RTV:
		return rules.rtv_apply

	return rules.apply


## Nothing changes: carry on with what is running.
##
## [b]Two different "carry on"s, and using the wrong one is a real bug.[/b] After an
## end-of-map ballot the clock is expired or nearly so, and it restarts — or the next
## tick expires it again and opens another ballot at once. After a rock-the-vote ballot
## the clock still had time on it; restarting it would hand an unpopular map a fresh
## limit for having been voted on, so it resumes where it stopped, and rocking the vote
## waits out [member DotVoteRules.rtv_interval_sec] before it can pass again.
func _carry_on() -> void:
	state = State.RUNNING

	if _vote_reason == DotVoteClock.REASON_RTV:
		clock.resume()
		clock.block_rtv_for(rules.rtv_interval_sec)
		return

	clock.start(source.find(_current_id) if source != null else null)


## Decides a ballot nobody voted in, per [member DotVoteRules.on_no_votes].
##
## Done to the result BEFORE it is announced, so [signal vote_closed] carries what
## actually happens rather than "nobody voted" followed by a change nobody was told
## about.
func _decide_no_votes(result: DotVoteResult) -> void:
	if result.outcome != DotVoteResult.Outcome.EMPTY or ballot.options.is_empty():
		return

	if ballot.real_voter_count() > 0:
		return

	var picked: StringName = &""
	var how := ""

	match rules.on_no_votes:
		DotVoteRules.NoVotes.RANDOM:
			# Only the ballot's real options: never "extend", which the long-standing
			# map-choosers also refuse to draw — a server nobody answered does not get
			# more time for it.
			var rng := _rng()
			picked = ballot.options[rng.randi_range(0, ballot.options.size() - 1)].id
			how = "drawn, because nobody voted"
		DotVoteRules.NoVotes.ROTATION:
			picked = _next_in_rotation()
			how = "next in rotation, because nobody voted"
		_:
			return

	if picked == &"":
		return

	result.outcome = DotVoteResult.Outcome.WINNER
	result.winner_id = picked
	result.winner = source.find(picked) if source != null else null
	result.tie_break = how
	result.summary = "Nobody voted; %s is next (%s)." % [_name_of(picked), how]


func _after_no_quorum(result: DotVoteResult, moment: int) -> void:
	match rules.on_no_quorum:
		DotVoteRules.NoQuorum.KEEP:
			_carry_on()

		DotVoteRules.NoQuorum.ROTATION:
			# The source's own order decides. Not the ballot's leader: the point of this
			# setting is that a ballot too few people voted in should not choose.
			var next := _next_in_rotation()

			if next == &"":
				_carry_on()
				return

			_schedule_change(next, moment)

		_:
			if (
				result.winner_id == &""
				or result.winner_id == DotVoteBallot.EXTEND
				or result.winner_id == DotVoteBallot.KEEP
			):
				_carry_on()
				return

			_schedule_change(result.winner_id, moment)


func _extend_now() -> void:
	if clock.extend():
		_say("Extended. %s." % clock.timeleft_line())
		return

	# Out of extends and the players voted for one anyway. A ballot no longer offers
	# "extend" once it cannot happen (DotVoteBallot.extend_available), so this is reached
	# only by a host casting EXTEND by hand. Left running rather than silently changing:
	# the clock is already expired, and the honest thing is to say so and let the next
	# vote decide.
	_say("This cannot be extended again.")
	clock.start(source.find(_current_id) if source != null else null)


func is_voting() -> bool:
	return state == State.VOTING


func vote_seconds_remaining() -> float:
	return _vote_remaining if state == State.VOTING else 0.0


## Rocks the vote on everybody's behalf. An admin's command.
##
## With the next choice already decided it brings that forward — now, after the apply
## delay — whatever [member DotVoteRules.rtv_after_decided] says, because an admin is not
## a player being refused a second say. Otherwise it is exactly a rock-the-vote passing.
func force_rtv() -> DotResult:
	if not rules.enabled:
		return DotResult.fail(DotError.CODE_UNSUPPORTED, "Voting is turned off.")

	if state == State.PENDING:
		_pending_moment = DotVoteRules.Apply.IMMEDIATE
		_pending_delay = rules.apply_delay_sec
		_say("Changing to %s." % _name_of(_pending_id))
		return DotResult.success(_pending_id)

	if state != State.RUNNING:
		return DotResult.fail(DotError.CODE_STATE, "A vote is already on the way.")

	if clock.is_expired():
		# Nothing left to expire — a vote-only server, or a limit that ran out with no
		# ballot. Open one as a rock-the-vote directly.
		return start_vote(DotVoteClock.REASON_RTV, true)

	_forcing = true
	clock.expire_now(DotVoteClock.REASON_RTV)
	_forcing = false

	return DotResult.success(true)


## A vote fell due with nothing to choose between, so none is held and play carries on.
##
## [b]Rather than a ballot of Extend alone[/b], which is all a server whose content offers
## one thing — or one thing these players can play — could ever put up: a full-screen
## question with one answer, on a clock, every time the limit ran out. A refusal instead
## would be worse: the due vote is retried until it opens, so the clock would sit expired
## for ever. The clock is restarted exactly as a ballot that chose Extend would leave it,
## minus the extend it would have used.
func _pass_over(reason: StringName) -> void:
	DotLog.info(CHANNEL, "a vote was due and there is nothing else to vote for; carrying on", {
		"reason": String(reason), "current": String(_current_id),
	})

	if reason == DotVoteClock.REASON_RTV:
		_say("There is nothing else to vote for.")

	_vote_reason = reason
	_vote_due_pending = false
	_carry_on()
