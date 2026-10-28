@tool
extends "res://addons/dot_vote/runtime/dot_vote_director_query.gd"

## Nominations, rock-the-vote and the pending change of [DotVoteDirector], kept apart so each file stays readable.

## Nominates something for the next ballot.
func nominate(voter: StringName, id: StringName) -> DotResult:
	if not rules.enabled:
		return DotResult.fail(DotError.CODE_UNSUPPORTED, "Voting is turned off.")

	if source == null:
		return DotResult.fail(DotError.CODE_STATE, "No source.")

	var choice := source.find(id)

	if choice == null:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"There is nothing called '%s'." % id,
			_nearest(id)
		)

	if not choice.enabled:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "%s is not available." % choice.label()
		)

	var admin := _is_admin(voter)
	var bypass := admin and rules.admin_nominations_bypass

	# Refused while a ballot is open or coming, and once the next is decided. A
	# nomination then is one that cannot reach any ballot — it would be consumed by
	# nothing, or cleared by the change — and accepting it is telling a player something
	# happened when nothing will.
	match nomination_state():
		NominationState.VOTE_IN_PROGRESS:
			return DotResult.fail(
				DotError.CODE_STATE, "A vote is already running; vote in that instead."
			)
		NominationState.VOTE_COMPLETE:
			return DotResult.fail(
				DotError.CODE_STATE,
				"What plays next is already decided (%s)." % _name_of(_pending_id)
			)

	if not choice.available_for(player_count(), true) and not bypass:
		return DotResult.fail(
			DotError.CODE_STATE,
			"%s is not available with %d players here."
				% [choice.label(), player_count()]
		)

	if id == _current_id and not rules.nominate_current_allowed and not bypass:
		return DotResult.fail(
			DotError.CODE_STATE,
			"%s is already running." % choice.label(),
			"vote to extend instead"
		)

	if not rules.nominate_on_cooldown_allowed and not bypass:
		if history.on_cooldown(id, 0, -1.0, choice):
			return DotResult.fail(
				DotError.CODE_RATE_LIMITED,
				"%s was played too recently." % choice.label()
			)

	var added := nominations.add(voter, id, admin)

	if not added.ok:
		return added

	nominated.emit(voter, id)
	_say("%s nominated %s." % [display_name(voter), choice.label()])

	return DotResult.success(choice)


func withdraw_nomination(voter: StringName, id: StringName) -> bool:
	return nominations.remove(voter, id, DotVoteNominations.REASON_WITHDRAWN)


## Puts [param id] on the next ballot whatever the caps, the cooldown or the switches
## say. An admin's command; the caller checks who is asking.
##
## It takes none of the places reserved for players' nominations — see
## [method DotVoteNominations.forced_ids] — so an admin adding a map does not quietly
## cost the players one of theirs.
func force_nominate(id: StringName, by: StringName = &"admin") -> DotResult:
	if source == null:
		return DotResult.fail(DotError.CODE_STATE, "No source.")

	var choice := source.find(id)

	if choice == null:
		return DotResult.fail(
			DotError.CODE_INVALID, "There is nothing called '%s'." % id, _nearest(id)
		)

	var added := nominations.add(by, id, true, true)

	if added.ok:
		nominated.emit(by, id)
		_say("%s will be on the next vote." % ballot_name(choice))
		DotLog.info(CHANNEL, "forced onto the next ballot", {
			"id": String(id), "by": String(by)
		})

	return added


## Removes every nomination of [param id]. Returns how many there were.
func remove_nomination(id: StringName) -> int:
	return nominations.remove_id(id, DotVoteNominations.REASON_ADMIN)


## Removes everything [param voter] nominated. Returns how many there were.
func remove_nominations_by(voter: StringName) -> int:
	return nominations.remove_voter(voter, DotVoteNominations.REASON_ADMIN)


func _nearest(id: StringName) -> String:
	if source == null:
		return ""

	var text := String(id).to_lower()
	var near := PackedStringArray()

	for candidate in source.ids():
		if String(candidate).to_lower().contains(text):
			near.append(String(candidate))

		if near.size() >= 5:
			break

	return "did you mean: %s" % ", ".join(near) if not near.is_empty() else ""


func rock_the_vote(voter: StringName) -> DotResult:
	if not rules.enabled:
		return DotResult.fail(DotError.CODE_UNSUPPORTED, "Voting is turned off.")

	if state == State.PENDING:
		# The next choice is decided and waiting for its moment. Rocking the vote now is
		# "we are done with this one", and the answer to "what next" already exists —
		# so it either brings that forward or is refused, and never opens another ballot.
		if rules.rtv_after_decided == DotVoteRules.RtvAfterDecided.DENY:
			return DotResult.fail(
				DotError.CODE_STATE,
				"What plays next is already decided (%s)." % _name_of(_pending_id)
			)
	elif state != State.RUNNING:
		return DotResult.fail(
			DotError.CODE_STATE, "A vote is already on the way."
		)

	var result := clock.rock_the_vote(voter, player_count(), _is_admin(voter))

	if result.ok and not clock.is_expired():
		_say("%s wants a vote (%d of %d)." % [
			display_name(voter), clock.rtv_votes(), clock.rtv_needed(player_count())
		])

	return result


## Extends without a vote. For an admin command.
func extend(seconds: float = -1.0, rounds: int = -1, score: int = -1) -> DotResult:
	if not clock.can_extend():
		return DotResult.fail(
			DotError.CODE_STATE,
			"This has already been extended %d times." % clock.extends_used
		)

	clock.extend(seconds, rounds, score)
	_say("Extended. %s." % clock.timeleft_line())

	return DotResult.success(clock.timeleft_line())


## [param delay] replaces [member DotVoteRules.apply_delay_sec] when it is not negative.
func _schedule_change(id: StringName, moment: int, delay: float = -1.0) -> void:
	if id == &"" or id == DotVoteBallot.EXTEND or id == DotVoteBallot.KEEP:
		state = State.RUNNING
		return

	_pending_id = id
	_pending_moment = moment
	_pending_delay = delay if delay >= 0.0 else rules.apply_delay_sec
	state = State.PENDING

	# A rock-the-vote stopped the clock. A winner that waits for the end of the round or
	# of the clock needs that clock running again, or the moment it waits for never
	# comes and the map it replaced plays for ever.
	if (
		_vote_reason == DotVoteClock.REASON_RTV
		and moment != DotVoteRules.Apply.IMMEDIATE
		and clock.is_expired()
	):
		clock.resume()

	if _ready_to_apply() and _pending_delay <= 0.0:
		_do_change()


## Whether the moment the pending change waits for has arrived.
func _ready_to_apply() -> bool:
	if is_finishing_round():
		return false

	match _pending_moment:
		DotVoteRules.Apply.END_OF_ROUND:
			# Driven by note_round_end rather than polled. A round-based game whose
			# round never ends keeps its winner pending, which is right: the change was
			# meant to happen between rounds.
			return clock.round_limit <= 0 and clock.is_expired()
		DotVoteRules.Apply.END_OF_TIME:
			return clock.is_expired()
		_:
			return true


## Applies the pending change now, whatever the rules said about timing.
func apply_pending() -> DotResult:
	if _pending_id == &"":
		return DotResult.fail(DotError.CODE_STATE, "Nothing is pending.")

	return await _do_change()


## Sets what plays next by hand, as though a vote had chosen it. An admin's command.
##
## It takes effect when the clock runs out — the end of the map, not now: an admin who
## wants now has [code]changelevel[/code] — and it counts as the end-of-map vote having
## finished, so no ballot opens in the meantime. Rocking the vote after it follows
## [member DotVoteRules.rtv_after_decided], exactly as it would after a vote.
func set_next(id: StringName) -> DotResult:
	if source == null:
		return DotResult.fail(DotError.CODE_STATE, "No source.")

	var choice := source.find(id)

	if choice == null:
		return DotResult.fail(
			DotError.CODE_INVALID, "There is nothing called '%s'." % id, _nearest(id)
		)

	if state == State.VOTING:
		return DotResult.fail(
			DotError.CODE_STATE,
			"A vote is running.",
			"close it first, or let it finish"
		)

	if state == State.APPLYING:
		return DotResult.fail(DotError.CODE_STATE, "A change is already under way.")

	if state == State.COUNTDOWN:
		state = State.RUNNING
		_countdown_remaining = 0.0
		_runoff_ids.clear()

	_vote_due_pending = false
	_vote_reason = DotVoteClock.REASON_MANUAL
	_schedule_change(id, DotVoteRules.Apply.END_OF_TIME)

	DotLog.info(CHANNEL, "next set by hand", {"id": String(id)})
	_say("%s is next." % ballot_name(choice))

	return DotResult.success(choice)


func _do_change() -> DotResult:
	var id := _pending_id

	if id == &"":
		return DotResult.fail(DotError.CODE_STATE, "Nothing is pending.")

	var choice := source.find(id) if source != null else null

	state = State.APPLYING
	_pending_id = &""

	change_due.emit(id, choice)

	if not auto_apply or source == null or not source.supports_apply():
		# Advisory. The host was told and the director stops here rather than pretending
		# to have done something — and it does NOT call begin(), because what is running
		# has not changed yet and the host will say when it has.
		state = State.RUNNING
		return DotResult.success(id)

	var applied: DotResult = await source.apply(id)

	changed.emit(id, applied)

	if not applied.ok:
		DotLog.error(CHANNEL, "the change failed", {
			"id": String(id), "why": applied.error.message
		})
		_say("Could not change to %s." % (
			choice.label() if choice != null else String(id)
		))

		# Left running on the thing that still works, with a fresh clock, so the server
		# tries again at the next expiry rather than sitting in APPLYING for ever.
		state = State.RUNNING
		clock.start(source.find(_current_id) if source != null else null)

		return applied

	if begin_on_apply:
		begin(id)
	else:
		# The host will call begin() when its own signal says the change landed. Left
		# in RUNNING rather than APPLYING so nothing is stuck if that signal never
		# comes — a wrong clock is recoverable, a director frozen in APPLYING is not.
		state = State.RUNNING

	return applied
