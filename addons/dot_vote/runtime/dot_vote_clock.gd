class_name DotVoteClock
extends RefCounted

## How long the current choice has left, in seconds and in rounds, and the two ways
## the players can end it early.
##
## [b]A server that never changes is not a server.[/b] Somebody joins, plays the thing
## they arrived on, and leaves — the catalogue, the rotation and the ballot all exist
## and nothing ever reaches them. Every long-lived server in this genre grows the same
## three mechanisms, and they are three because each covers a case the others do not:
##
## - a [b]limit[/b], so something ends even when nobody asks;
## - [b]rock the vote[/b], so something everybody hates ends early;
## - [b]extending[/b], so something everybody is enjoying does not end on a timer.
##
## [b]Counted in simulated seconds, advanced by the host.[/b] Not a wall clock: a
## server that stalls for ten seconds should not lose ten seconds of its map, and a
## test must be able to run an hour of it in a millisecond.
##
## [codeblock]
## clock.start(choice)                    # a new game or map has begun
## clock.advance(delta)                   # once per tick
## clock.rock_the_vote(&"player_3", 12)   # somebody typed !rtv
## [/codeblock]

const CHANNEL := "vote.clock"

## The limit is up, or the players ended it.
##
## [param reason] is one of the [code]REASON_*[/code] constants. Emitted once per
## choice; the host decides what happens — which is deliberately not this class's
## business, because "the map is over" means something different in a round-based
## game, a timer server and a replay being scrubbed.
signal expired(reason: StringName)

## Time to open the ballot: [member DotVoteRules.vote_lead_sec] before the end, or
## [member DotVoteRules.vote_lead_rounds] rounds before it.
##
## [b]Separate from [signal expired] and that is the entire point of a lead.[/b] A
## ballot that opens when the time is already up either runs late or gives players ten
## seconds to read it.
signal vote_due(reason: StringName)

## Emitted once per mark in [member DotVoteRules.warn_at_sec].
signal warning(seconds_left: float)

## Somebody rocked the vote. [param needed] is how many more are wanted.
signal rocked(voter: StringName, votes: int, needed: int)

signal extended(seconds: float, rounds: int)

## A round ended. [param played] counts from 1.
signal round_ended(played: int, limit: int)

const REASON_TIME := &"time"
const REASON_ROUNDS := &"rounds"
const REASON_RTV := &"rtv"
const REASON_MANUAL := &"manual"

var rules: DotVoteRules = null

## Seconds left. Counted down by [method advance].
var remaining: float = 0.0

## Seconds this choice was given, after any per-choice override.
var duration: float = 0.0

## Seconds since [method start]. What [member DotVoteRules.rtv_delay_sec] is measured
## against.
var elapsed: float = 0.0

## Rounds finished on this choice.
var rounds_played: int = 0

## Rounds this choice was given. 0 = no round limit.
var round_limit: int = 0

var extends_used: int = 0

var running: bool = false

## Voter ids who have rocked the vote.
var _rocked: Dictionary = {}

var _warned: Dictionary = {}
var _expired: bool = false
var _vote_due: bool = false


static func of(p_rules: DotVoteRules) -> DotVoteClock:
	var clock := DotVoteClock.new()
	clock.rules = p_rules
	return clock


## Starts the clock for a new choice. Call on every change.
##
## [param choice] may be null, in which case the rules' own limits are used. Its
## per-choice overrides are what makes "each game has its own time limit" a property
## of the game rather than a setting an operator has to remember to change with it.
func start(choice: DotVoteChoice = null) -> void:
	duration = (
		choice.duration_for(rules.duration_sec) if choice != null else rules.duration_sec
	)
	round_limit = (
		choice.rounds_for(rules.round_limit) if choice != null else rules.round_limit
	)

	remaining = duration
	elapsed = 0.0
	rounds_played = 0
	extends_used = 0

	# [b]Running means started, NOT "has a limit".[/b] It used to mean the latter, and
	# a choice with no time limit and no round limit — a legitimate configuration, and
	# the one a vote-only server runs — then returned from `advance` before its elapsed
	# time was counted. Nothing else uses `elapsed`, so nothing broke except the one
	# thing that does: `rtv_delay_sec` is measured against it, so rocking the vote was
	# refused for ever, on exactly the server whose only way to change anything is a
	# vote. Found by asserting on `elapsed` rather than on the symptom.
	running = true

	_rocked.clear()
	_warned.clear()
	_expired = false
	_vote_due = false


func stop() -> void:
	running = false


## Advances by one tick of simulated time.
func advance(delta: float) -> void:
	if not running or _expired:
		return

	elapsed += delta

	if duration <= 0.0:
		# A round-limited choice with no clock still needs its elapsed time advanced —
		# it is what the rock-the-vote delay is measured against — and must not then be
		# expired by a countdown it does not have.
		return

	remaining = maxf(remaining - delta, 0.0)

	for mark in rules.warn_marks():
		if remaining <= mark and not _warned.has(mark):
			_warned[mark] = true
			warning.emit(remaining)

	if not _vote_due and remaining <= rules.vote_lead_sec:
		_fire_vote_due(REASON_TIME)

	if remaining <= 0.0:
		_fire(REASON_TIME)


## Records the end of a round. Returns whether that ended the choice.
func note_round_end() -> bool:
	if _expired:
		return false

	rounds_played += 1
	round_ended.emit(rounds_played, round_limit)

	if round_limit <= 0:
		return false

	if not _vote_due and rounds_played >= round_limit - rules.vote_lead_rounds:
		_fire_vote_due(REASON_ROUNDS)

	if rounds_played >= round_limit:
		_fire(REASON_ROUNDS)
		return true

	return false


func _fire_vote_due(reason: StringName) -> void:
	if _vote_due:
		return

	_vote_due = true

	DotLog.info(CHANNEL, "a vote is due", {"reason": String(reason)})

	vote_due.emit(reason)


func _fire(reason: StringName) -> void:
	# Latched, because the host's response is to run a vote and change the game, and
	# both take time. Without the latch a limit that reached zero fires again on every
	# tick until the change actually happens — a ballot opened a hundred times a second.
	if _expired:
		return

	_expired = true
	running = false

	# A limit reached without a ballot still has to open one. Otherwise a server
	# configured with no lead time — vote_lead_sec of 0, which is a legitimate and
	# common setting — expires with nothing ever having asked the players.
	_fire_vote_due(reason)

	DotLog.info(CHANNEL, "the limit is up", {"reason": String(reason)})

	expired.emit(reason)


## Ends it now, as if the limit had been reached. For a console command.
func expire_now(reason: StringName = REASON_MANUAL) -> void:
	_fire(reason)


func is_expired() -> bool:
	return _expired


func is_vote_due() -> bool:
	return _vote_due


# --- Extending -------------------------------------------------------------

func can_extend() -> bool:
	return rules.max_extends <= 0 or extends_used < rules.max_extends


func extends_left() -> int:
	if rules.max_extends <= 0:
		return 0x7FFFFFFF

	return maxi(rules.max_extends - extends_used, 0)


## Extends the current choice. False when it has been extended as often as it may be.
func extend(seconds: float = -1.0, rounds: int = -1) -> bool:
	if not can_extend():
		return false

	var by_time := seconds if seconds >= 0.0 else rules.extend_seconds
	var by_rounds := rounds if rounds >= 0 else rules.extend_rounds

	extends_used += 1

	if duration > 0.0:
		remaining += by_time
		duration += by_time

	if round_limit > 0:
		round_limit += by_rounds

	running = true

	# The warnings and both latches reset: an extended choice has a fresh ending, and a
	# player who saw "two minutes left" ten minutes ago should see it again.
	_warned.clear()
	_expired = false
	_vote_due = false

	if rules.extend_resets_rtv:
		# The players who wanted it to end have just been outvoted. Carrying their votes
		# into the extension means it ends again the moment one more person agrees.
		_rocked.clear()

	DotLog.info(CHANNEL, "extended", {
		"seconds": by_time, "rounds": by_rounds, "used": extends_used
	})

	extended.emit(by_time, by_rounds)

	return true


# --- Rock the vote ---------------------------------------------------------

## How many players must rock the vote right now. 0 when it cannot pass at all.
func rtv_needed(player_count: int) -> int:
	if not rules.rtv_enabled or player_count < rules.rtv_min_players:
		return 0

	return maxi(int(ceil(float(player_count) * rules.rtv_fraction)), 1)


## Whether rocking the vote is allowed yet.
func rtv_ready() -> bool:
	return elapsed >= rules.rtv_delay_sec


func rtv_wait_remaining() -> float:
	return maxf(rules.rtv_delay_sec - elapsed, 0.0)


## Registers a rock-the-vote. Succeeds whether or not it passed; check
## [method rtv_passed] or watch [signal expired].
##
## [b]Idempotent per voter.[/b] Typing it twice is what a player does when nothing
## visible happened, and counting it twice would let two people end a map on a
## six-player server.
func rock_the_vote(
	voter: StringName,
	player_count: int,
	is_admin: bool = false
) -> DotResult:
	if not rules.rtv_enabled:
		return DotResult.fail(
			DotError.CODE_UNSUPPORTED, "Rocking the vote is turned off on this server."
		)

	if _expired:
		return DotResult.fail(
			DotError.CODE_STATE, "A vote is already on the way."
		)

	if not rtv_ready():
		return DotResult.fail(
			DotError.CODE_RATE_LIMITED,
			"You can rock the vote in %d seconds." % int(ceil(rtv_wait_remaining()))
		)

	if player_count < rules.rtv_min_players:
		return DotResult.fail(
			DotError.CODE_STATE,
			"There are not enough players to rock the vote.",
			"%d here, %d needed" % [player_count, rules.rtv_min_players]
		)

	if _rocked.has(voter):
		return DotResult.fail(
			DotError.CODE_STATE,
			"You have already rocked the vote.",
			"%d of %d" % [_rocked.size(), rtv_needed(player_count)]
		)

	_rocked[voter] = true

	var needed := rtv_needed(player_count)
	var votes := _rocked.size()

	rocked.emit(voter, votes, maxi(needed - votes, 0))

	if (is_admin and rules.rtv_admin_instant) or votes >= needed:
		_fire(REASON_RTV)

	return DotResult.success(votes)


## Withdraws a rock-the-vote. For a player who leaves, or changes their mind.
##
## [b]Called when somebody disconnects, and that matters.[/b] Without it a server
## whose players trickle away keeps their votes while the threshold falls with the
## player count — so the map ends on the votes of people who are not there.
func unrock(voter: StringName) -> bool:
	if not rules.rtv_forgets_leavers:
		return false

	return _rocked.erase(voter)


func rtv_votes() -> int:
	return _rocked.size()


func has_rocked(voter: StringName) -> bool:
	return _rocked.has(voter)


# --- Reporting -------------------------------------------------------------

## Time remaining as [code]m:ss[/code], or a word when there is no clock.
func formatted_remaining() -> String:
	if duration <= 0.0:
		return "no limit"

	var total := maxf(remaining, 0.0)

	return "%d:%02d" % [int(total / 60.0), int(fmod(total, 60.0))]


## The one line a `timeleft` command replies with.
func timeleft_line() -> String:
	var parts := PackedStringArray()

	if duration > 0.0:
		parts.append("%s left" % formatted_remaining())

	if round_limit > 0:
		parts.append("round %d of %d" % [rounds_played + 1, round_limit])

	if parts.is_empty():
		parts.append("no time limit")

	return ", ".join(parts)


func describe() -> Dictionary:
	return {
		"running": running,
		"remaining": formatted_remaining(),
		"rounds": "%d of %s" % [
			rounds_played, "-" if round_limit <= 0 else str(round_limit)
		],
		"extends": "%d of %s" % [
			extends_used, "unlimited" if rules.max_extends <= 0 else str(rules.max_extends)
		],
		"rtv": _rocked.size(),
		"vote_due": _vote_due,
		"expired": _expired,
	}


func _to_string() -> String:
	return "DotVoteClock(%s)" % timeleft_line()
