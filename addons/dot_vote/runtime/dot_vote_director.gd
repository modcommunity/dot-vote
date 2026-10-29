@tool
class_name DotVoteDirector
extends "res://addons/dot_vote/runtime/dot_vote_director_ballot.gd"

## The node a game adds: the clock, the nominations, the ballot and the change, driven by one call per tick (see docs/design.md for setup).
## It does not decide what a game is: player count, admin, spectator and vote weight are [Callable]s the host sets, since a server, a mirroring client and a headless test disagree about each.
## It need not change anything either: with [member auto_apply] false it runs the vote and emits [signal change_due].


func _ready() -> void:
	if rules == null:
		rules = DotVoteRules.new()

	if history == null:
		history = DotVoteHistory.of(rules)

	if nominations == null:
		nominations = DotVoteNominations.of(rules)

	if ballot == null:
		ballot = DotVoteBallot.of(rules)

	if clock == null:
		clock = DotVoteClock.of(rules)

	history.rules = rules
	nominations.rules = rules
	ballot.rules = rules
	ballot.history = history
	ballot.nominations = nominations
	clock.rules = rules

	clock.vote_due.connect(_on_vote_due)
	clock.expired.connect(_on_expired)
	clock.warning.connect(func(left: float) -> void: warning.emit(left))
	clock.rocked.connect(
		func(voter: StringName, votes: int, needed: int) -> void:
			rocked.emit(voter, votes, needed)
	)
	clock.extended.connect(
		func(seconds: float, rounds: int) -> void: extended.emit(seconds, rounds)
	)
	clock.score_limit_changed.connect(
		func(limit: int) -> void: score_limit_changed.emit(limit)
	)
	nominations.removed.connect(
		func(voter: StringName, id: StringName, reason: StringName) -> void:
			nomination_removed.emit(voter, id, reason)
	)

	if register_service:
		DotRegistry.register(SERVICE, self)

	set_physics_process(self_advance)


func _exit_tree() -> void:
	if register_service:
		DotRegistry.unregister_instance(SERVICE, self)


func _physics_process(delta: float) -> void:
	advance(delta)


## Stops (true) or starts (false) everything this director counts, for a server that hibernates while empty.
## Nothing advances while hibernating, so the first player in does not get a map with a minute left; on waking, [member DotVoteRules.wake_restart] picks restart or resume.
func set_hibernating(on: bool) -> void:
	if on == hibernating:
		return

	hibernating = on

	if on:
		DotLog.info(CHANNEL, "hibernating; the clock waits", {
			"id": String(_current_id), "left": clock.formatted_remaining() if clock != null else "-",
		})
		return

	if rules != null and rules.wake_restart and clock != null:
		restart()
	else:
		DotLog.info(CHANNEL, "awake; the clock resumes", {"id": String(_current_id)})


## Follows a server's hibernation: [method set_hibernating] on its [code]hibernation_changed(bool)[/code] signal, from its current state.
## Duck-typed (no dot-server names); returns false if the object has no such signal. Safe to call twice.
func follow_hibernation(server: Object) -> bool:
	if server == null or not server.has_signal("hibernation_changed"):
		return false

	if not server.is_connected("hibernation_changed", set_hibernating):
		server.connect("hibernation_changed", set_hibernating)

	if server.has_method("is_hibernating"):
		set_hibernating(bool(server.call("is_hibernating")))

	return true


func current_id() -> StringName:
	return _current_id


## Advances every clock this addon owns by one tick of simulated time.
func advance(delta: float) -> void:
	if rules == null or not rules.enabled or hibernating:
		return

	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)

	if clock.is_expired():
		_since_expiry += delta

	match state:
		State.VOTING:
			_advance_vote(delta)
		State.COUNTDOWN:
			_advance_countdown(delta)
		State.PENDING:
			_pending_delay = maxf(_pending_delay - delta, 0.0)

			if _pending_delay <= 0.0 and _ready_to_apply():
				_do_change()
		State.RUNNING:
			if _vote_due_pending and _cooldown_remaining <= 0.0 and not _busy():
				var retried := start_vote(_vote_due_reason)

				if retried.ok:
					_vote_due_pending = false
		_:
			pass

	# The clock runs during a vote as well. A ballot that opened with two minutes left
	# and takes thirty seconds has to leave ninety, or a server with a long ballot and
	# a short lead never reaches its own expiry.
	clock.advance(delta)


func _advance_vote(delta: float) -> void:
	_vote_remaining = maxf(_vote_remaining - delta, 0.0)

	if rules.announce_interval_sec > 0.0:
		_announce_countdown -= delta

		if _announce_countdown <= 0.0:
			_announce_countdown = rules.announce_interval_sec
			tally_updated.emit(ballot.tally())

	if rules.close_when_all_voted and ballot.everybody_voted():
		close_vote()
		return

	if _vote_remaining <= 0.0:
		close_vote()


## Records the end of a round. Returns whether that ended the current choice.
## Under [constant DotVoteRules.Trigger.ROUND_END] a ballot held back by a limit opens here.
func note_round_end() -> bool:
	# Before the clock hears it: a round ending AFTER the limit ran out is the end of the
	# round a FINISH_ROUND was holding the change for. The round that ran the limit out —
	# a round limit, reached here — is not a round in progress and holds nothing.
	if clock.is_expired():
		_round_ended_since_expiry = true

	var over := clock.note_round_end()

	if state == State.PENDING and _pending_moment == DotVoteRules.Apply.END_OF_ROUND:
		_pending_delay = 0.0
		_do_change()

	# After the clock, which may itself have made a round-limit ballot due on this very
	# round end and opened it — in which case the held one is the same ballot and the
	# flag is cleared by open_vote below rather than opening a second.
	if _vote_due_at_round_end:
		_vote_due_at_round_end = false

		if state == State.RUNNING:
			var opened := start_vote(_vote_due_reason)

			if not opened.ok:
				# The ordinary retry from here: the round has ended, and a ballot refused
				# for a cooldown or a head count is owed, not cancelled.
				_vote_due_pending = true

				DotLog.warn(CHANNEL, "the round ended and the vote could not open yet; will retry", {
					"reason": String(_vote_due_reason), "why": opened.error.message
				})

	return over


## Whether a ballot is due and waiting for the round in progress to end.
func is_waiting_for_round_end() -> bool:
	return _vote_due_at_round_end


## Records the leading score, for [member DotVoteRules.score_limit]. Returns whether that ended the current choice.
## What a score is, is the game's; this only compares it with a number.
func note_score(score: int) -> bool:
	return clock.note_score(score)


func _on_vote_due(reason: StringName) -> void:
	if not rules.enabled or state != State.RUNNING:
		return

	if reason == DotVoteClock.REASON_RTV:
		match rules.rtv_outcome:
			DotVoteRules.RtvOutcome.CHANGE_NOW:
				_vote_reason = reason
				_schedule_change(_next_in_rotation(), DotVoteRules.Apply.IMMEDIATE)
				return
			DotVoteRules.RtvOutcome.END_CURRENT:
				return
			_:
				pass

	# MANUAL hands the host WHEN the scheduled ballot opens, so a limit reaching its lead does
	# nothing here. A rock-the-vote is the players asking now and opens as under any trigger;
	# vote_due fires before expired, so a host's own open from clock.expired is refused, not doubled.
	if (
		rules.trigger == DotVoteRules.Trigger.MANUAL
		and reason != DotVoteClock.REASON_RTV
		and not _forcing
	):
		return

	# A limit running out asks the players only when the end-of-map vote is on. With it
	# off the limit still ends the map, and _on_expired hands it to the rotation.
	if reason != DotVoteClock.REASON_RTV and not end_vote_enabled():
		return

	# Under round_end a time or score limit waits for the round to end. A round limit
	# does not wait — it is only ever due from inside note_round_end, which IS the end of
	# a round — and neither does a rock-the-vote, which is the players asking now.
	if (
		rules.trigger == DotVoteRules.Trigger.ROUND_END
		and reason != DotVoteClock.REASON_RTV
		and reason != DotVoteClock.REASON_ROUNDS
		and not _forcing
	):
		_vote_due_at_round_end = true
		_vote_due_reason = reason

		DotLog.info(CHANNEL, "a vote is due and waits for the round to end", {
			"reason": String(reason)
		})
		return

	var opened := start_vote(reason)

	if not opened.ok:
		# Remembered rather than logged and dropped. See _vote_due_pending.
		_vote_due_pending = true
		_vote_due_reason = reason

		DotLog.warn(CHANNEL, "could not open the vote yet; will retry", {
			"reason": String(reason), "why": opened.error.message
		})


func _on_expired(reason: StringName) -> void:
	_expired_reason = reason
	_since_expiry = 0.0
	_round_ended_since_expiry = false

	if is_finishing_round():
		DotLog.info(CHANNEL, "the limit is up; the round in progress is played out first", {
			"reason": String(reason), "at_most_sec": rules.finish_round_max_sec,
		})
		_say("Time is up. The change happens when this round ends.")

	if state == State.PENDING:
		# A vote already decided this and is waiting for the clock; this IS that moment.
		# Or the players rocked the vote after it was decided, and asked for it now.
		if _pending_moment == DotVoteRules.Apply.END_OF_TIME or (
			reason == DotVoteClock.REASON_RTV
			and rules.rtv_after_decided == DotVoteRules.RtvAfterDecided.CHANGE_NOW
		):
			_pending_delay = 0.0

			# Under FINISH_ROUND the round in progress is played out first, and the
			# PENDING branch of advance applies it the tick _ready_to_apply agrees.
			if not is_finishing_round():
				_do_change()
		return

	if state != State.RUNNING:
		return

	# Nobody here to ask. Only a limit — never a rock-the-vote or an admin, both of which
	# are somebody. A hibernating server never gets here: its clock stops with the room.
	if (
		reason != DotVoteClock.REASON_RTV
		and reason != DotVoteClock.REASON_MANUAL
		and player_count() <= 0
		and rules.empty_choice != DotVoteRules.EmptyChoice.WAIT
	):
		_resolve_empty(reason)
		return

	# Nothing was voted on (RTV_ONLY, end-of-map vote off, or rtv_outcome END_CURRENT), so the
	# rotation decides, or an expired limit would do nothing. MANUAL is left to its host.
	var unasked := (
		reason != DotVoteClock.REASON_RTV
		and not end_vote_enabled()
		and rules.trigger != DotVoteRules.Trigger.MANUAL
	)

	if unasked or (
		rules.rtv_outcome == DotVoteRules.RtvOutcome.END_CURRENT
		and reason == DotVoteClock.REASON_RTV
	):
		_vote_reason = reason
		_schedule_change(_next_in_rotation(), rules.apply)


## A limit ran out on a server with nobody on it. See [enum DotVoteRules.EmptyChoice].
func _resolve_empty(reason: StringName) -> void:
	# The vote that fell due at the lead and could not open for want of a voter is settled
	# here, or it would open over the next map the moment somebody arrives.
	_vote_due_pending = false
	_vote_due_at_round_end = false
	_vote_reason = reason

	var picked: StringName = &""
	var how := ""

	match rules.empty_choice:
		DotVoteRules.EmptyChoice.RANDOM:
			picked = empty_draw()
			how = "drawn at random"
		DotVoteRules.EmptyChoice.ROTATION:
			picked = _next_in_rotation()
			how = "next in rotation"

	if picked == &"":
		# A one-map server. Carry on with a fresh clock, as a ballot that chose Extend
		# would, rather than sitting expired until somebody arrives.
		DotLog.info(CHANNEL, "the limit is up on an empty server and there is nothing else; carrying on", {
			"current": String(_current_id),
		})
		_carry_on()
		return

	DotLog.info(CHANNEL, "the limit is up and nobody is here to vote; changing", {
		"from": String(_current_id), "to": String(picked), "how": how,
	})

	# Nobody is playing a round worth finishing, so FINISH_ROUND has nothing to wait for; and
	# nobody is reading a result, so apply_delay_sec — the pause that lets them — is 0.
	_round_ended_since_expiry = true
	_schedule_change(picked, DotVoteRules.Apply.IMMEDIATE, 0.0)
