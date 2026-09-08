@tool
class_name DotVoteDirector
extends Node

## The node a game adds: the clock, the nominations, the ballot and the change, joined
## up and driven by one call per tick.
##
## [codeblock]
## var votes := DotVoteDirector.new()
## votes.rules = DotVoteRules.new()
## votes.source = my_source
## votes.player_count_fn = func() -> int: return players.size()
## add_child(votes)
## votes.begin(&"lobby")          # what is running now
##
## # once per tick
## votes.advance(delta)
## [/codeblock]
##
## [b]It does not decide what a game is.[/b] Every question that needs to know — how
## many players there are, whether one is an admin, whether one is a spectator, what
## their vote is worth — is a [Callable] the host sets. That is not indirection for its
## own sake: this addon has to serve a dedicated server with sessions, a client
## mirroring a server's ballot, and a headless test with no players at all, and the
## first two disagree about every one of those questions.
##
## [b]It does not have to change anything either.[/b] A source that cannot apply a
## result, or an [member auto_apply] of false, gives a director that runs the whole
## vote and emits [signal change_due] for the host to act on — which is what
## [DotMapSession] learned the hard way: what happens when a map ends is a game's
## decision, and a component that made it for them would be fought by every game that
## wanted anything else.

const CHANNEL := "vote"
const SERVICE := &"dot_vote_director"

## The ballot is open. [param options] is every votable id, in ballot order.
signal vote_opened(options: Array, seconds: float)

## Somebody voted. For a live tally.
signal vote_cast(voter: StringName, choices: Array)

## The live tally, every [member DotVoteRules.announce_interval_sec] seconds.
signal tally_updated(counts: Dictionary)

## The ballot closed. A [constant DotVoteResult.Outcome.RUNOFF] is followed by another
## [signal vote_opened]; everything else is final.
signal vote_closed(result: DotVoteResult)

## Something should be loaded now. [b]The signal a host acts on.[/b]
##
## Emitted whether or not this director is going to apply it itself, so a game that
## has to save a scoreboard or fade the screen out gets told either way.
signal change_due(id: StringName, choice: DotVoteChoice)

## The source finished applying a change, or failed to.
signal changed(id: StringName, result: DotResult)

## Passed through from the clock, so a host wires up one object rather than five.
signal warning(seconds_left: float)
signal rocked(voter: StringName, votes: int, needed: int)
signal extended(seconds: float, rounds: int)
signal nominated(voter: StringName, id: StringName)

enum State {
	## Something is running and no vote is in progress.
	RUNNING,
	## A ballot is open.
	VOTING,
	## A winner is decided and is waiting for its moment — the delay, the end of the
	## round, or the end of the clock.
	PENDING,
	## The source is being asked to change.
	APPLYING,
}

@export_group("Wiring")

## Whether to register in [DotRegistry] under [constant SERVICE].
##
## On, so a console command or a module can find it without being handed a reference.
## Off for a second director in one process — a client mirroring a server's vote — for
## the family's usual reason: the registry holds one.
@export var register_service: bool = true

## Whether this director asks the source to apply a result.
##
## Off makes it advisory: everything runs, [signal change_due] fires, and the host
## does the change. That is the correct setting on a client, which must never decide
## what it is playing.
@export var auto_apply: bool = true

## Whether a successful change makes this director call [method begin] itself.
##
## [b]Off when the host has its own "it changed" signal[/b] — dot-server's
## [code]game_loaded[/code], dot-map's [code]changed[/code]. Those fire for an
## operator typing [code]changelevel[/code] as well as for a vote, and a host that
## connects one and leaves this on gets [method begin] twice for every voted change:
## two entries in the history for one play, which quietly shortens every cooldown.
##
## On is right for a source with no such signal, which is most of them.
@export var begin_on_apply: bool = true

## Whether [method advance] is called automatically from [method _physics_process].
##
## Off by default, and deliberately: a dedicated server advances simulated time from
## its own tick, and a component that also ran itself off the frame clock would count
## a stalled server's stall against its map. Turn it on for a standalone client.
@export var self_advance: bool = false

var rules: DotVoteRules = null

var source: DotVoteSource = null

var history: DotVoteHistory = null

var nominations: DotVoteNominations = null

var ballot: DotVoteBallot = null

var clock: DotVoteClock = null

var state: State = State.RUNNING

# --- Host hooks ------------------------------------------------------------

## How many players there are. Required for anything with a threshold in it.
var player_count_fn: Callable = Callable()

## Who may vote, as ids. Optional; falls back to [member player_count_fn] for the
## count and to "anybody who casts one" for eligibility.
var voters_fn: Callable = Callable()

## Whether a voter is an admin. Optional; nobody is, by default.
var is_admin_fn: Callable = Callable()

## Whether a voter is a spectator. Optional; nobody is, by default.
var is_spectator_fn: Callable = Callable()

## What one voter's ballot is worth. Optional; everybody's is worth 1.
var weight_fn: Callable = Callable()

## Says something to the players. Optional; takes one [String].
##
## A [Callable] rather than a chat manager, because this addon must not name
## dot-server's classes — and because a client mirroring a vote wants the same lines on
## its HUD rather than in a chat log.
var announce_fn: Callable = Callable()

var _current_id: StringName = &""
var _vote_remaining: float = 0.0
var _announce_countdown: float = 0.0
var _pending_id: StringName = &""
var _pending_delay: float = 0.0
var _cooldown_remaining: float = 0.0
var _fill_cursor: int = 0

## A vote was due and could not be opened. Retried until it can be.
##
## [b]Without this the server stops changing, silently.[/b] The clock fires once and
## latches — it has to, or an expired limit opens a ballot on every tick — so a
## `vote_due` that arrives while the vote cooldown is still running, or while there
## are too few players, was the last one that would ever arrive. Rock the vote passing
## thirty seconds after a failed vote does it, which is the most ordinary sequence
## there is.
var _vote_due_pending: bool = false

## The reason the pending vote is due, kept so the retry says the same thing.
var _vote_due_reason: StringName = DotVoteClock.REASON_MANUAL


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

	if register_service:
		DotRegistry.register(SERVICE, self)

	set_physics_process(self_advance)


func _exit_tree() -> void:
	if register_service:
		DotRegistry.unregister_instance(SERVICE, self)


func _physics_process(delta: float) -> void:
	advance(delta)


# --- Lifecycle -------------------------------------------------------------

## Tells the director what is running now, and starts its clock.
##
## Call it once at boot and after every change — including a change this director did
## not cause, because an operator typing `changelevel` by hand still resets the map's
## time limit and everybody's rock-the-vote.
func begin(id: StringName) -> void:
	_current_id = id
	_pending_id = &""
	_pending_delay = 0.0
	_vote_due_pending = false
	state = State.RUNNING

	ballot.reset()
	nominations.clear()

	var choice := source.find(id) if source != null else null

	clock.start(choice)

	if id != &"":
		history.note_played(id)

	DotLog.info(CHANNEL, "now running", {
		"id": String(id),
		"limit": clock.formatted_remaining(),
		"rounds": clock.round_limit,
	})


func current_id() -> StringName:
	return _current_id


## Advances every clock this addon owns by one tick of simulated time.
func advance(delta: float) -> void:
	if rules == null or not rules.enabled:
		return

	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)

	match state:
		State.VOTING:
			_advance_vote(delta)
		State.PENDING:
			_pending_delay = maxf(_pending_delay - delta, 0.0)

			if _pending_delay <= 0.0 and _ready_to_apply():
				_do_change()
		State.RUNNING:
			if _vote_due_pending and _cooldown_remaining <= 0.0:
				var retried := open_vote(_vote_due_reason)

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
func note_round_end() -> bool:
	var over := clock.note_round_end()

	if state == State.PENDING and rules.apply == DotVoteRules.Apply.END_OF_ROUND:
		_pending_delay = 0.0
		_do_change()

	return over


# --- Players ---------------------------------------------------------------

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


func _say(line: String) -> void:
	if announce_fn.is_valid():
		announce_fn.call(line)


## Forgets everything one player did. Call when they disconnect.
##
## [b]Their rock-the-vote goes and their nominations stay[/b], which is not an
## oversight. A rock-the-vote is a fraction of the people who are here, so keeping a
## leaver's makes the map end on the votes of people who left; a nomination is a
## request of the server, and somebody who nominated a map and then crashed still
## wants it played.
func forget_voter(voter: StringName) -> void:
	clock.unrock(voter)

	if ballot.open and ballot.withdraw(voter):
		# Recomputed rather than decremented, so it stays right when several leave at
		# once — and so a vote cannot become unpassable by attrition.
		ballot.eligible = maxi(_eligible_count(), 1)


func _eligible_count() -> int:
	if voters_fn.is_valid():
		return (voters_fn.call() as Array).size()

	return player_count()


# --- Nominating ------------------------------------------------------------

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
			DotError.CODE_FORBIDDEN, "%s is not available." % choice.name_or_id()
		)

	var admin := _is_admin(voter)
	var bypass := admin and rules.admin_nominations_bypass

	if not choice.available_for(player_count(), true) and not bypass:
		return DotResult.fail(
			DotError.CODE_STATE,
			"%s is not available with %d players here."
				% [choice.name_or_id(), player_count()]
		)

	if id == _current_id and not rules.nominate_current_allowed and not bypass:
		return DotResult.fail(
			DotError.CODE_STATE,
			"%s is already running." % choice.name_or_id(),
			"vote to extend instead"
		)

	if not rules.nominate_on_cooldown_allowed and not bypass:
		if history.on_cooldown(id, 0, -1.0, choice):
			return DotResult.fail(
				DotError.CODE_RATE_LIMITED,
				"%s was played too recently." % choice.name_or_id()
			)

	var added := nominations.add(voter, id, admin)

	if not added.ok:
		return added

	nominated.emit(voter, id)
	_say("%s nominated %s." % [voter, choice.name_or_id()])

	return DotResult.success(choice)


func withdraw_nomination(voter: StringName, id: StringName) -> bool:
	return nominations.remove(voter, id)


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


# --- Rocking the vote ------------------------------------------------------

func rock_the_vote(voter: StringName) -> DotResult:
	if not rules.enabled:
		return DotResult.fail(DotError.CODE_UNSUPPORTED, "Voting is turned off.")

	if state != State.RUNNING:
		return DotResult.fail(
			DotError.CODE_STATE, "A vote is already on the way."
		)

	var result := clock.rock_the_vote(voter, player_count(), _is_admin(voter))

	if result.ok and not clock.is_expired():
		_say("%s wants a vote (%d of %d)." % [
			voter, clock.rtv_votes(), clock.rtv_needed(player_count())
		])

	return result


# --- Voting ----------------------------------------------------------------

## Opens a ballot now.
func open_vote(reason: StringName = DotVoteClock.REASON_MANUAL) -> DotResult:
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

	var options := build_options(players)
	var started := ballot.begin(options, maxi(_eligible_count(), 1))

	if not started.ok:
		return started

	nominations.clear()

	state = State.VOTING
	_vote_due_pending = false
	_vote_remaining = rules.vote_duration_sec
	_announce_countdown = rules.announce_interval_sec

	var names := PackedStringArray()

	for choice in options:
		names.append(choice.name_or_id())

	DotLog.info(CHANNEL, "vote opened", {
		"reason": String(reason), "options": names.size(), "eligible": ballot.eligible
	})

	_say("Vote: %s (%ds)" % [", ".join(names), int(rules.vote_duration_sec)])

	vote_opened.emit(ballot.option_ids(), _vote_remaining)

	return DotResult.success(options)


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

	_cooldown_remaining = rules.vote_cooldown_sec

	DotLog.info(CHANNEL, "vote closed", result.describe())
	_say(result.summary)

	vote_closed.emit(result)

	match result.outcome:
		DotVoteResult.Outcome.RUNOFF:
			var again := ballot.begin_runoff(result.runoff_ids)

			if again.ok:
				_vote_remaining = rules.vote_duration_sec
				_announce_countdown = rules.announce_interval_sec
				vote_opened.emit(ballot.option_ids(), _vote_remaining)
				return result

			# A runoff that cannot start is not a reason to leave the server in VOTING
			# for ever. Falling back to the leader is the only answer that terminates.
			state = State.RUNNING
			return result

		DotVoteResult.Outcome.EXTEND:
			state = State.RUNNING
			_extend_now()
			return result

		DotVoteResult.Outcome.KEEP:
			state = State.RUNNING
			# The clock is restarted rather than left expired, or the next tick would
			# expire again and open another ballot immediately.
			clock.start(source.find(_current_id) if source != null else null)
			return result

		DotVoteResult.Outcome.NO_QUORUM:
			_after_no_quorum(result)
			return result

		DotVoteResult.Outcome.EMPTY:
			state = State.RUNNING
			clock.start(source.find(_current_id) if source != null else null)
			return result

		_:
			_schedule_change(result.winner_id)
			return result


func _after_no_quorum(result: DotVoteResult) -> void:
	match rules.on_no_quorum:
		DotVoteRules.NoQuorum.KEEP:
			state = State.RUNNING
			clock.start(source.find(_current_id) if source != null else null)

		DotVoteRules.NoQuorum.ROTATION:
			# The source's own order decides. Not the ballot's leader: the point of this
			# setting is that a ballot too few people voted in should not choose.
			var next := _next_in_rotation()

			if next == &"":
				state = State.RUNNING
				clock.start(source.find(_current_id) if source != null else null)
				return

			_schedule_change(next)

		_:
			if result.winner_id == &"" or result.winner_id == DotVoteBallot.EXTEND:
				state = State.RUNNING
				clock.start(source.find(_current_id) if source != null else null)
				return

			_schedule_change(result.winner_id)


func _extend_now() -> void:
	if clock.extend():
		_say("Extended. %s." % clock.timeleft_line())
		return

	# Out of extends and the players voted for one anyway. Left running rather than
	# silently changing: the clock is already expired, the next expiry has nothing to
	# fire, and the honest thing is to say so and let the next vote decide.
	_say("This cannot be extended again.")
	clock.start(source.find(_current_id) if source != null else null)


func is_voting() -> bool:
	return state == State.VOTING


func vote_seconds_remaining() -> float:
	return _vote_remaining if state == State.VOTING else 0.0


# --- Extending -------------------------------------------------------------

## Extends without a vote. For an admin command.
func extend(seconds: float = -1.0, rounds: int = -1) -> DotResult:
	if not clock.can_extend():
		return DotResult.fail(
			DotError.CODE_STATE,
			"This has already been extended %d times." % clock.extends_used
		)

	clock.extend(seconds, rounds)
	_say("Extended. %s." % clock.timeleft_line())

	return DotResult.success(clock.timeleft_line())


# --- Changing --------------------------------------------------------------

func _schedule_change(id: StringName) -> void:
	if id == &"" or id == DotVoteBallot.EXTEND or id == DotVoteBallot.KEEP:
		state = State.RUNNING
		return

	_pending_id = id
	_pending_delay = rules.apply_delay_sec
	state = State.PENDING

	if _ready_to_apply() and _pending_delay <= 0.0:
		_do_change()


## Whether the moment the rules asked for has arrived.
func _ready_to_apply() -> bool:
	match rules.apply:
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


func pending_id() -> StringName:
	return _pending_id


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
			choice.name_or_id() if choice != null else String(id)
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


# --- Filling the ballot ----------------------------------------------------

## The options a ballot opened right now would carry.
##
## Public because a HUD wants to show them before the vote and because it is the one
## piece of this addon worth testing on its own.
func build_options(players: int) -> Array[DotVoteChoice]:
	var out: Array[DotVoteChoice] = []
	var taken := {}

	if source == null:
		return out

	var nominated := nominations.ordered_ids()
	var slots := mini(rules.nomination_slots, rules.max_options)

	for id in nominated:
		if out.size() >= slots:
			break

		var choice := source.find(id)

		if choice == null or taken.has(id):
			continue

		out.append(choice)
		taken[id] = true

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

	for choice in all:
		if taken.has(choice.id):
			continue

		if not choice.available_for(players):
			continue

		if choice.id == _current_id and not rules.include_current:
			continue

		if not ignore_cooldown and history.on_cooldown(choice.id, all.size(), -1.0, choice):
			continue

		out.append(choice)

	return out


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


# --- Clock reactions -------------------------------------------------------

func _on_vote_due(reason: StringName) -> void:
	if not rules.enabled or state != State.RUNNING:
		return

	if reason == DotVoteClock.REASON_RTV:
		match rules.rtv_outcome:
			DotVoteRules.RtvOutcome.CHANGE_NOW:
				_schedule_change(_next_in_rotation())
				return
			DotVoteRules.RtvOutcome.END_CURRENT:
				return
			_:
				pass

	if rules.trigger == DotVoteRules.Trigger.MANUAL:
		return

	var opened := open_vote(reason)

	if not opened.ok:
		# Remembered rather than logged and dropped. See _vote_due_pending.
		_vote_due_pending = true
		_vote_due_reason = reason

		DotLog.warn(CHANNEL, "could not open the vote yet; will retry", {
			"reason": String(reason), "why": opened.error.message
		})


func _on_expired(reason: StringName) -> void:
	# A vote already decided this and is waiting for the clock; this IS that moment.
	if state == State.PENDING and rules.apply == DotVoteRules.Apply.END_OF_TIME:
		_pending_delay = 0.0
		_do_change()
		return

	if state != State.RUNNING:
		return

	# Nothing was voted on — RTV_ONLY with rtv_outcome END_CURRENT, or a trigger of
	# MANUAL — so the rotation decides. A server whose limit expired and did nothing at
	# all is the failure this addon exists to prevent.
	if rules.trigger == DotVoteRules.Trigger.RTV_ONLY or (
		rules.rtv_outcome == DotVoteRules.RtvOutcome.END_CURRENT
		and reason == DotVoteClock.REASON_RTV
	):
		_schedule_change(_next_in_rotation())


# --- Reporting -------------------------------------------------------------

func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	out.append("state      %s" % State.keys()[state])
	out.append("running    %s" % (String(_current_id) if _current_id != &"" else "-"))
	out.append("clock      %s" % clock.timeleft_line())
	out.append("rtv        %d of %d" % [
		clock.rtv_votes(), clock.rtv_needed(player_count())
	])
	out.append("nominated  %d" % nominations.size())

	if state == State.VOTING:
		out.append("vote       %ds left, %d of %d voted" % [
			int(_vote_remaining), ballot.voter_count(), ballot.eligible
		])

		for entry: Array in _tally_lines():
			out.append("  %-20s %s" % [entry[0], entry[1]])

	if _pending_id != &"":
		out.append("pending    %s in %ds" % [String(_pending_id), int(_pending_delay)])

	if _vote_due_pending:
		out.append("due        a vote is owed and could not be opened yet")

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
		"history": history.describe(),
		"source": source.describe() if source != null else {},
	}
