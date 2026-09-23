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
signal score_limit_changed(limit: int)
signal nominated(voter: StringName, id: StringName)

## A nomination came off the list — withdrawn, replaced, taken onto a ballot, cleared
## by a new map, removed by an admin, or its owner left. [param reason] is one of
## [DotVoteNominations]'s [code]REASON_*[/code].
signal nomination_removed(voter: StringName, id: StringName, reason: StringName)

## A countdown to a ballot started: [member DotVoteRules.vote_warning_sec], or
## [member DotVoteRules.runoff_warning_sec] when [param runoff].
signal countdown_started(seconds: float, runoff: bool)

## One second of that countdown. Fires for every whole second from the first down to
## 1; the ballot opening is the zero. [b]The signal a HUD counts down from[/b], and
## what a sound layer plays "three, two, one" on.
signal countdown_tick(seconds_left: int, runoff: bool)

## A sound cue is due. [param id] is one of the [code]cue_*[/code] settings — a
## dot-audio id, typically — and is never empty.
##
## A signal, not a player: this addon names no audio class and plays nothing, for the
## same reason [member announce_fn] is a [Callable] rather than a chat manager.
signal cue(id: StringName)

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
	## Counting down to a ballot (or a runoff) that has not opened yet.
	COUNTDOWN,
}

## Whether a player may nominate right now, and if not, why. What
## [method nomination_state] returns — the question a menu asks before it draws.
enum NominationState {
	YES,
	## Nominations are off, or voting is.
	DISABLED,
	## The list is at [member DotVoteRules.nominations_max].
	FULL,
	## A ballot is open or about to be; a nomination now would miss it.
	VOTE_IN_PROGRESS,
	## What plays next is already decided.
	VOTE_COMPLETE,
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

## Whether some other vote is on the players' screens right now. Optional.
##
## A ballot opened on top of a votekick is two menus fighting for the same number keys,
## and whichever loses was voted in by accident. While this answers true a vote that is
## due waits — through the same retry a vote refused by the cooldown takes — rather than
## being dropped. dot-server's [code]DotVoteManager[/code] is the obvious answer to it.
var busy_fn: Callable = Callable()

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

## Why the ballot now open (or last closed) was opened. Decides whether it was an early
## vote, and which of [member DotVoteRules.apply] and [member DotVoteRules.rtv_apply]
## its winner waits for.
var _vote_reason: StringName = DotVoteClock.REASON_MANUAL

## The moment the pending change waits for, as a [enum DotVoteRules.Apply].
##
## Held per change rather than read from the rules at apply time, because two things
## now schedule changes with different moments — an end-of-map ballot and a
## rock-the-vote one, and an admin's [method set_next] — and a change that re-read the
## rules when it came due would wait for the wrong one.
var _pending_moment: int = DotVoteRules.Apply.END_OF_ROUND

var _countdown_remaining: float = 0.0
var _countdown_last: int = 0
var _countdown_runoff: bool = false
var _countdown_reason: StringName = DotVoteClock.REASON_MANUAL
var _runoff_ids: Array[StringName] = []

## Set while [method force_rtv] expires the clock, so a MANUAL trigger — which ignores a
## player's rock-the-vote — does not also ignore an admin's.
var _forcing: bool = false

## A ballot is due and is waiting for the round in progress to end, under
## [constant DotVoteRules.Trigger.ROUND_END]. [member _vote_due_reason] says why it is due.
##
## [b]This is the whole of what makes `round_end` a different trigger from
## `time_limit`.[/b] Until it existed the two behaved identically and differed only in
## what [method DotVoteRules.validate] demanded — a setting that read differently and
## decided nothing. Under `round_end` a time or score limit reaching its lead does not put
## a ballot over a fight in progress: it is held here and opened by [method
## note_round_end], which is the moment a round-based game has always voted at.
var _vote_due_at_round_end: bool = false


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
	_vote_due_at_round_end = false
	_countdown_remaining = 0.0
	_runoff_ids.clear()
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
##
## Under [constant DotVoteRules.Trigger.ROUND_END] this is also where a ballot held back
## by a time or score limit opens — see [member _vote_due_at_round_end].
func note_round_end() -> bool:
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


## Records the leading score, for [member DotVoteRules.score_limit]. Returns whether
## that ended the current choice.
##
## Call it whenever the leader's score changes — the top player's frags, the leading
## team's wins. What a score is, is the game's; this only compares it with a number.
func note_score(score: int) -> bool:
	return clock.note_score(score)


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


# --- Rocking the vote ------------------------------------------------------

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
			voter, clock.rtv_votes(), clock.rtv_needed(player_count())
		])

	return result


# --- Voting ----------------------------------------------------------------

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

	if not ready.ok:
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

	if rules.vote_warning_sec > 0.0:
		_begin_countdown(rules.vote_warning_sec, false, reason)
		return DotResult.success(rules.vote_warning_sec)

	return open_vote(reason)


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


# --- The countdown ---------------------------------------------------------

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


# --- Casting and closing ---------------------------------------------------

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


# --- Extending -------------------------------------------------------------

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


# --- Changing --------------------------------------------------------------

func _schedule_change(id: StringName, moment: int) -> void:
	if id == &"" or id == DotVoteBallot.EXTEND or id == DotVoteBallot.KEEP:
		state = State.RUNNING
		return

	_pending_id = id
	_pending_moment = moment
	_pending_delay = rules.apply_delay_sec
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


func pending_id() -> StringName:
	return _pending_id


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


## Re-reads the source, for a list an operator edited on disk.
func reload() -> DotResult:
	if source == null:
		return DotResult.fail(DotError.CODE_STATE, "No source.")

	var reloaded := source.reload()

	if reloaded.ok:
		DotLog.info(CHANNEL, "choices reloaded", {"count": source.choices().size()})

	return reloaded


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
				_vote_reason = reason
				_schedule_change(_next_in_rotation(), DotVoteRules.Apply.IMMEDIATE)
				return
			DotVoteRules.RtvOutcome.END_CURRENT:
				return
			_:
				pass

	if rules.trigger == DotVoteRules.Trigger.MANUAL and not _forcing:
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
	if state == State.PENDING:
		# A vote already decided this and is waiting for the clock; this IS that moment.
		# Or the players rocked the vote after it was decided, and asked for it now.
		if _pending_moment == DotVoteRules.Apply.END_OF_TIME or (
			reason == DotVoteClock.REASON_RTV
			and rules.rtv_after_decided == DotVoteRules.RtvAfterDecided.CHANGE_NOW
		):
			_pending_delay = 0.0
			_do_change()
		return

	if state != State.RUNNING:
		return

	# Nothing was voted on — RTV_ONLY, the end-of-map vote turned off, or rtv_outcome
	# END_CURRENT — so the rotation decides. A server whose limit expired and did nothing
	# at all is the failure this addon exists to prevent. MANUAL is the one trigger left
	# alone: its host decides for itself.
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


# --- Asking ----------------------------------------------------------------
#
# The questions the long-standing community map-choosers answer for other plugins, so a
# HUD, a menu or another addon can ask rather than duplicate the state.

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

	return rules.marked_name(choice.name_or_id(), choice.official)


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
	return choice.name_or_id() if choice != null else String(id)


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
		"pending": String(_pending_id) if _pending_id != &"" else "-",
		"history": history.describe(),
		"source": source.describe() if source != null else {},
	}
