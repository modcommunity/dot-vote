@tool
extends "res://addons/dot_vote/runtime/dot_vote_director_state.gd"

## Questions, ballot filling and reporting of [DotVoteDirector], kept apart so each file stays readable.

## Tells the director what is running now, and starts its clock.
##
## Call it once at boot and after every change — including a change this director did
## not cause, because an operator typing `changelevel` by hand still resets the map's
## time limit and everybody's rock-the-vote.
func begin(id: StringName) -> void:
	_current_id = id
	# Before the clock starts, so a choice that arrived since the last ballot starts with
	# its own limit rather than the default one.
	_refresh_source()
	_reset_to_start()

	if id != &"":
		history.note_played(id)

	DotLog.info(CHANNEL, "now running", {
		"id": String(id),
		"limit": clock.formatted_remaining(),
		"rounds": clock.round_limit,
	})


## Starts what is running again from its configured start, without changing it.
##
## A fresh clock at the choice's own limit, no rock-the-vote, every extend, no ballot, no
## countdown and no decided change — everything [method begin] resets, without the second
## entry in the history that calling [method begin] again would write, which would shorten
## every cooldown by one play. What waking from hibernation does
## ([member DotVoteRules.wake_restart]); public for an admin's "restart the map clock".
func restart() -> void:
	_reset_to_start()
	_cooldown_remaining = 0.0

	DotLog.info(CHANNEL, "started again", {
		"id": String(_current_id), "limit": clock.formatted_remaining(),
	})


func _reset_to_start() -> void:
	_pending_id = &""
	_pending_delay = 0.0
	_vote_due_pending = false
	_vote_due_at_round_end = false
	_countdown_remaining = 0.0
	_runoff_ids.clear()
	_expired_reason = &""
	_since_expiry = 0.0
	_round_ended_since_expiry = false
	state = State.RUNNING

	ballot.reset()
	nominations.clear()

	clock.start(source.find(_current_id) if source != null else null)


func player_count() -> int:
	if player_count_fn.is_valid():
		return int(player_count_fn.call())

	if voters_fn.is_valid():
		return (voters_fn.call() as Array).size()

	return 0


func _is_admin(voter: StringName) -> bool:
	return is_admin_fn.is_valid() and bool(is_admin_fn.call(voter))


func _is_spectator(voter: StringName) -> bool:
	return is_spectator_fn.is_valid() and bool(is_spectator_fn.call(voter))


func _weight_for(voter: StringName) -> float:
	return float(weight_fn.call(voter)) if weight_fn.is_valid() else 1.0


## The name a line gives [param voter]: [member people_fn]'s, or the id when there is none.
func display_name(voter: StringName) -> String:
	if people_fn.is_valid():
		var person: Variant = people_fn.call(voter)

		if person is Dictionary:
			var shown: String = str((person as Dictionary).get("name", "")).strip_edges()

			if shown != "":
				return shown

	return String(voter)


func _say(line: String) -> void:
	if announce_fn.is_valid():
		announce_fn.call(line)


func _busy() -> bool:
	return busy_fn.is_valid() and bool(busy_fn.call())


## Emits [signal cue] for a configured cue. An empty id is silence, which is the default
## for every cue and must stay silent rather than emit an empty id a host then looks up.
func _cue(id: String) -> void:
	if id != "":
		cue.emit(StringName(id))


## Forgets everything one player did. Call when they disconnect.
##
## [b]Their rock-the-vote goes and their nominations stay[/b], which is not an
## oversight. A rock-the-vote is a fraction of the people who are here, so keeping a
## leaver's makes the map end on the votes of people who left; a nomination is a
## request of the server, and somebody who nominated a map and then crashed still
## wants it played.
##
## [member DotVoteRules.nominations_forget_leavers] reverses the second half, for a
## server that wants the long-standing map-choosers' behaviour.
func forget_voter(voter: StringName) -> void:
	clock.unrock(voter)

	if rules.nominations_forget_leavers:
		nominations.remove_voter(voter, DotVoteNominations.REASON_LEFT)

	if ballot.open and ballot.withdraw(voter):
		# Recomputed rather than decremented, so it stays right when several leave at
		# once — and so a vote cannot become unpassable by attrition.
		ballot.eligible = maxi(_eligible_count(), 1)


## Whether an automatic ballot (any reason but manual) would have one voter to decide it.
## Nobody at all is not "one": [member DotVoteRules.min_players_to_vote] 0 asked for that.
func _lone_auto(reason: StringName) -> bool:
	return (
		reason != DotVoteClock.REASON_MANUAL and not rules.allow_single_voter_auto
		and player_count() > 0 and _eligible_count() < 2
	)


func _eligible_count() -> int:
	if voters_fn.is_valid():
		return (voters_fn.call() as Array).size()

	return player_count()


func pending_id() -> StringName:
	return _pending_id


## Asks the source to re-read a list it is fed rather than holds
## ([member DotVoteListSource.entries_fn]): when a choice begins and whenever a ballot is
## about to be filled. Duck-typed, so a source written before the hook existed, or one
## that is not a [DotVoteSource] at all, is left alone.
func _refresh_source() -> void:
	if source != null and source.has_method("before_ballot"):
		source.call("before_ballot")


## Re-reads the source, for a list an operator edited on disk.
func reload() -> DotResult:
	if source == null:
		return DotResult.fail(DotError.CODE_STATE, "No source.")

	var reloaded := source.reload()

	if reloaded.ok:
		DotLog.info(CHANNEL, "choices reloaded", {"count": source.choices().size()})

	return reloaded


## What the source would play next, ignoring the vote.
##
## Straight down the source's order from what is running, skipping anything on
## cooldown or unavailable. What [constant DotVoteRules.NoQuorum.ROTATION] uses, and
## what a `nextmap` command reports.
func _next_in_rotation() -> StringName:
	if source == null:
		return &""

	var all := source.choices()

	if all.is_empty():
		return &""

	var players := player_count()
	var start := 0

	for i in range(all.size()):
		if all[i].id == _current_id:
			start = i + 1
			break

	for step in range(all.size()):
		var choice := all[(start + step) % all.size()]

		if choice.id == _current_id:
			continue

		if not choice.available_for(players):
			continue

		if history.on_cooldown(choice.id, all.size(), -1.0, choice):
			continue

		return choice.id

	# Everything is on cooldown or unavailable. Playing something again is a much
	# better answer than stopping, which is dot-map's rotation's lesson.
	for step in range(all.size()):
		var choice := all[(start + step) % all.size()]

		if choice.id != _current_id and choice.available_for(players):
			return choice.id

	return &""


func next_in_rotation() -> StringName:
	return _next_in_rotation()


## The options a ballot opened right now would carry.
##
## Public because a HUD wants to show them before the vote and because it is the one
## piece of this addon worth testing on its own.
func build_options(players: int) -> Array[DotVoteChoice]:
	var out: Array[DotVoteChoice] = []
	var taken := {}

	if source == null:
		return out

	# An admin's forced additions first, and outside the places reserved for players.
	for id in nominations.forced_ids():
		if out.size() >= rules.max_options:
			break

		var forced := source.find(id)

		if forced != null and not taken.has(id):
			out.append(forced)
			taken[id] = true

	var nominated := nominations.ordered_ids()
	var slots := mini(rules.nomination_slots, rules.max_options)

	var players_placed := 0

	for id in nominated:
		if players_placed >= slots or out.size() >= rules.max_options:
			break

		var choice := source.find(id)

		if choice == null or taken.has(id):
			continue

		out.append(choice)
		taken[id] = true
		players_placed += 1

	var pool := _eligible_pool(players, taken)

	# Everything eligible is on cooldown. Offering nothing would leave the server where
	# it is for ever with no error anywhere, so the cooldown is dropped rather than the
	# ballot — the same choice dot-map's rotation makes, said out loud.
	if pool.is_empty():
		pool = _eligible_pool(players, taken, true)

		if not pool.is_empty():
			DotLog.warn(CHANNEL, "everything is on cooldown; ignoring it for this vote", {
				"pool": pool.size()
			})

	for choice in _order_pool(pool):
		if out.size() >= rules.max_options:
			break

		out.append(choice)
		taken[choice.id] = true

	return out


func _eligible_pool(
	players: int,
	taken: Dictionary,
	ignore_cooldown: bool = false
) -> Array[DotVoteChoice]:
	var out: Array[DotVoteChoice] = []
	var all := source.choices()
	var current_name := _shown_name(source.find(_current_id))

	for choice in all:
		if taken.has(choice.id):
			continue

		if not choice.available_for(players):
			continue

		# [b]By the name on the ballot as well as by id.[/b] A player tells options apart
		# only by what is printed, so a second install of the running game under another id
		# — a built-in copy beside a published one — is offered as "the same thing again",
		# and a one-game server held a ballot of that game against Extend.
		if not rules.include_current and (
			choice.id == _current_id
			or (current_name != "" and _shown_name(choice) == current_name)
		):
			continue

		if not ignore_cooldown and history.on_cooldown(choice.id, all.size(), -1.0, choice):
			continue

		out.append(choice)

	return out


## What a choice is called on a ballot, folded for comparison, or "" for none.
func _shown_name(choice: DotVoteChoice) -> String:
	return choice.name_or_id().strip_edges().to_lower() if choice != null else ""


## Whether a ballot opened now would offer anything that changes what is running.
##
## [b]Not [method build_options], which would answer it[/b]: filling advances the
## SEQUENTIAL cursor, so asking would skip a page of the rotation. Cooldowns are ignored
## here because [method build_options] drops them rather than the ballot when they are all
## that is left.
func has_alternatives(players: int = -1) -> bool:
	if source == null:
		return false

	if not nominations.forced_ids().is_empty():
		return true

	var count := players if players >= 0 else player_count()

	return not _eligible_pool(count, {}, true).is_empty()


func _order_pool(pool: Array[DotVoteChoice]) -> Array[DotVoteChoice]:
	var out := pool.duplicate()

	match rules.fill:
		DotVoteRules.Fill.SEQUENTIAL:
			if out.is_empty():
				return out

			var start := _fill_cursor % out.size()
			var rotated: Array[DotVoteChoice] = []

			for i in range(out.size()):
				rotated.append(out[(start + i) % out.size()])

			_fill_cursor += mini(rules.max_options, out.size())

			return rotated

		DotVoteRules.Fill.LEAST_RECENTLY_PLAYED:
			out.sort_custom(func(a: DotVoteChoice, b: DotVoteChoice) -> bool:
				var sa := history.plays_since(a.id)
				var sb := history.plays_since(b.id)

				# -1 is "never played", which must sort first rather than last.
				if sa < 0 or sb < 0:
					return sa < 0 and sb >= 0

				return sa > sb
			)

			return out

		DotVoteRules.Fill.MOST_NOMINATED:
			var counts := nominations.counts()

			out.sort_custom(func(a: DotVoteChoice, b: DotVoteChoice) -> bool:
				return int(counts.get(a.id, 0)) > int(counts.get(b.id, 0))
			)

			return out

		DotVoteRules.Fill.WEIGHTED:
			return _weighted_shuffle(out)

		_:
			return _shuffle(out)


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = rules.fill_seed

	# Advanced deterministically rather than reseeded from the clock, so a client
	# filling the same ballot from the same history reaches the same options.
	rules.fill_seed = int(rules.fill_seed * 1103515245 + 12345) & 0x7FFFFFFF

	return rng


func _shuffle(pool: Array[DotVoteChoice]) -> Array[DotVoteChoice]:
	var rng := _rng()
	var out := pool.duplicate()

	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: DotVoteChoice = out[i]
		out[i] = out[j]
		out[j] = swap

	return out


## Draws without replacement, in proportion to weight.
func _weighted_shuffle(pool: Array[DotVoteChoice]) -> Array[DotVoteChoice]:
	var rng := _rng()
	var left := pool.duplicate()
	var out: Array[DotVoteChoice] = []

	while not left.is_empty():
		var total := 0.0

		for choice in left:
			total += maxf(choice.weight, 0.0)

		if total <= 0.0:
			# Every remaining weight is zero. They are excluded rather than appended:
			# a weight of 0 means "never offer this", and appending them here would
			# make it mean "offer this last", which is a different setting.
			break

		var roll := rng.randf() * total
		var picked := 0

		for i in range(left.size()):
			roll -= maxf(left[i].weight, 0.0)

			if roll <= 0.0:
				picked = i
				break

		out.append(left[picked])
		left.remove_at(picked)

	return out


## One choice, drawn at random from what a ballot opened now would offer, or
## [code]&""[/code] when there is nothing but what is running.
##
## The ballot's own pool ([method _eligible_pool]): enabled, not on cooldown (dropped when
## everything is, as a ballot drops it), and never what is running when there is anything
## else — even under [member DotVoteRules.include_current], because a draw that lands on the
## current map is a server that did not change. Availability is judged for one player, the
## next to arrive: a choice that needs eight is the wrong thing to hand them.
func empty_draw() -> StringName:
	if source == null:
		return &""

	var players := maxi(player_count(), 1)
	var pool := _eligible_pool(players, {})

	if pool.is_empty():
		pool = _eligible_pool(players, {}, true)

	var others: Array[DotVoteChoice] = []

	for choice in pool:
		if choice.id != _current_id:
			others.append(choice)

	if others.is_empty():
		return &""

	if empty_rng == null:
		empty_rng = RandomNumberGenerator.new()
		empty_rng.randomize()

	return others[empty_rng.randi_range(0, others.size() - 1)].id


#
# The questions the long-standing community map-choosers answer for other plugins, so a
# HUD, a menu or another addon can ask rather than duplicate the state.


## Whether the clock has run out and the change is waiting for the round in progress to
## end, under [constant DotVoteRules.TimeUp.FINISH_ROUND].
##
## False the moment a round ends, once [member DotVoteRules.finish_round_max_sec] has
## passed, on a host that is not [member round_based], while [member round_in_progress_fn]
## answers false, and for any limit but time or score.
func is_finishing_round() -> bool:
	if rules == null or rules.time_up != DotVoteRules.TimeUp.FINISH_ROUND:
		return false

	if not round_based or not clock.is_expired() or _round_ended_since_expiry:
		return false

	if round_in_progress_fn.is_valid() and not bool(round_in_progress_fn.call()):
		return false

	if _expired_reason != DotVoteClock.REASON_TIME and _expired_reason != DotVoteClock.REASON_SCORE:
		return false

	return rules.finish_round_max_sec <= 0.0 or _since_expiry < rules.finish_round_max_sec


## Whether a limit running out opens a ballot on this server.
func end_vote_enabled() -> bool:
	return (
		rules != null
		and rules.enabled
		and rules.end_vote
		and rules.trigger != DotVoteRules.Trigger.RTV_ONLY
		and rules.trigger != DotVoteRules.Trigger.MANUAL
	)


## Whether what plays next is already decided — by a ballot or by an admin — and is
## waiting for its moment.
func has_end_vote_finished() -> bool:
	return state == State.PENDING and _pending_id != &""


## Whether a ballot could be started right now.
func can_start_vote() -> bool:
	if rules == null or not rules.enabled or source == null:
		return false

	if state != State.RUNNING and state != State.PENDING:
		return false

	return not _busy() and not _vote_due_pending


## Whether a player may nominate right now, and if not, why.
func nomination_state() -> NominationState:
	if rules == null or not rules.enabled or not rules.nominations_enabled:
		return NominationState.DISABLED

	if state == State.VOTING or state == State.COUNTDOWN:
		return NominationState.VOTE_IN_PROGRESS

	if state == State.PENDING or state == State.APPLYING:
		return NominationState.VOTE_COMPLETE

	if rules.nominations_max > 0 and nominations.size() >= rules.nominations_max:
		return NominationState.FULL

	return NominationState.YES


func can_nominate() -> bool:
	return nomination_state() == NominationState.YES


## Everything a player could nominate right now, in the source's order.
##
## [b]The list a nomination menu draws[/b] — so it leaves out exactly what
## [method nominate] would refuse: the disabled, the wrong player count, what is
## running, and what is on cooldown, each unless the rules allow it.
func nominatable_ids() -> Array[StringName]:
	var out: Array[StringName] = []

	if source == null:
		return out

	var players := player_count()

	for choice in source.choices():
		if not choice.enabled or not choice.available_for(players, true):
			continue

		if choice.id == _current_id and not rules.nominate_current_allowed:
			continue

		if not rules.nominate_on_cooldown_allowed and history.on_cooldown(
			choice.id, 0, -1.0, choice
		):
			continue

		out.append(choice.id)

	return out


## What is kept off a ballot for having been played recently, most recent first.
func excluded_ids() -> Array[StringName]:
	var out: Array[StringName] = []

	if source == null:
		return out

	var pool := source.choices().size()

	for id in history.played:
		if out.has(id):
			continue

		if history.on_cooldown(id, pool, -1.0, source.find(id)):
			out.append(id)

	return out


## Nominated ids, in order, forced ones first.
func nominated_ids() -> Array[StringName]:
	var out := nominations.forced_ids()

	for id in nominations.ordered_ids():
		if not out.has(id):
			out.append(id)

	return out


## Every nomination with who made it, as [code]{id, voter, admin, forced}[/code].
func nominated_list() -> Array[Dictionary]:
	return nominations.list()


## Whether [param id] is one of the server's own rather than a custom choice.
## Unknown ids are not official.
func is_official(id: StringName) -> bool:
	var choice := source.find(id) if source != null else null
	return choice != null and choice.official


## A choice's name as a ballot shows it, marked when it is unofficial.
func ballot_name(choice: DotVoteChoice) -> String:
	if choice == null:
		return "-"

	return rules.marked_name(choice.label(), choice.official)


## The name a player sees for an id, pseudo-options included.
func option_label(id: StringName) -> String:
	match id:
		DotVoteBallot.EXTEND:
			return "Extend"
		DotVoteBallot.KEEP:
			return "Don't change"
		DotVoteBallot.ABSTAIN:
			return "No vote"

	var choice := ballot.find_option(id)

	if choice == null and source != null:
		choice = source.find(id)

	return ballot_name(choice) if choice != null else String(id)


func _name_of(id: StringName) -> String:
	var choice := source.find(id) if source != null else null
	return choice.label() if choice != null else String(id)


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	out.append("state      %s%s" % [State.keys()[state], " (hibernating)" if hibernating else ""])
	out.append("running    %s" % (String(_current_id) if _current_id != &"" else "-"))
	out.append("clock      %s" % clock.timeleft_line())
	out.append("rtv        %d of %d" % [
		clock.rtv_votes(), clock.rtv_needed(player_count())
	])
	out.append("nominated  %d" % nominations.size())

	if state == State.COUNTDOWN:
		out.append("countdown  %ds to a %s" % [
			int(ceil(_countdown_remaining)), "runoff" if _countdown_runoff else "vote"
		])

	if state == State.VOTING:
		out.append("vote       %ds left, %d of %d voted" % [
			int(_vote_remaining), ballot.voter_count(), ballot.eligible
		])

		for entry: Array in _tally_lines():
			out.append("  %-20s %s" % [entry[0], entry[1]])

	if _pending_id != &"":
		out.append("pending    %s, at %s" % [
			String(_pending_id),
			str(DotVoteRules.Apply.keys()[_pending_moment]).to_lower(),
		])

	out.append("end vote   %s" % ("on" if end_vote_enabled() else "off"))

	if _vote_due_pending:
		out.append("due        a vote is owed and could not be opened yet")

	if _vote_due_at_round_end:
		out.append("due        a vote opens when this round ends (%s)" % String(_vote_due_reason))

	if is_finishing_round():
		out.append("time up    finishing the round in progress, %ds so far" % int(_since_expiry))

	out.append("next       %s" % String(_next_in_rotation()))

	return out


func _tally_lines() -> Array:
	var counts := ballot.tally()
	var out := []

	for id: Variant in counts:
		out.append([String(id), DotVoteBallot._format_votes(float(counts[id]))])

	return out


func describe() -> Dictionary:
	return {
		"state": State.keys()[state],
		"current": String(_current_id),
		"clock": clock.describe(),
		"ballot": ballot.describe(),
		"nominations": nominations.size(),
		"end_vote": end_vote_enabled(),
		"waiting_for_round_end": _vote_due_at_round_end,
		"finishing_round": is_finishing_round(),
		"round_based": round_based,
		"hibernating": hibernating,
		"pending": String(_pending_id) if _pending_id != &"" else "-",
		"history": history.describe(),
		"source": source.describe() if source != null else {},
	}
