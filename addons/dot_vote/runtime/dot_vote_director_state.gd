@tool
extends Node

## The signals, enums, settings and state of [DotVoteDirector], kept apart so each file stays readable.

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
@export var register_service: bool = true

## Whether this director asks the source to apply a result.
@export var auto_apply: bool = true

## Whether a successful change makes this director call [method begin] itself.
@export var begin_on_apply: bool = true

## Whether [method advance] is called automatically from [method _physics_process].
@export var self_advance: bool = false

var rules: DotVoteRules = null

var source: DotVoteSource = null

var history: DotVoteHistory = null

var nominations: DotVoteNominations = null

var ballot: DotVoteBallot = null

var clock: DotVoteClock = null

var state: State = State.RUNNING


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

## Who a voter is: [code]voter -> {"name": String, "avatar": String}[/code], the same
## shape [method DotVoteBallotView.state_of] takes. Optional; without it, or when it has
## no name for somebody, a line names the voter by id.
var people_fn: Callable = Callable()

## Says something to the players. Optional; takes one [String].
var announce_fn: Callable = Callable()

## Whether some other vote is on the players' screens right now. Optional.
var busy_fn: Callable = Callable()

## Whether the host reports the end of every round through [method note_round_end].
var round_based: bool = false

## Whether a round is being played right now, asked by [method is_finishing_round]. Optional.
var round_in_progress_fn: Callable = Callable()

## Whether the server this director serves is hibernating, and so whether anything here
## counts. See [method set_hibernating].
var hibernating: bool = false

## What [constant DotVoteRules.EmptyChoice.RANDOM] draws with. Null makes one, seeded from
## the system's entropy, the first time it is needed.
var empty_rng: RandomNumberGenerator = null

var _current_id: StringName = &""
var _vote_remaining: float = 0.0
var _announce_countdown: float = 0.0
var _pending_id: StringName = &""
var _pending_delay: float = 0.0
var _cooldown_remaining: float = 0.0
var _fill_cursor: int = 0

## A vote was due and could not be opened. Retried until it can be.
var _vote_due_pending: bool = false

## The reason the pending vote is due, kept so the retry says the same thing.
var _vote_due_reason: StringName = DotVoteClock.REASON_MANUAL

## Why the ballot now open (or last closed) was opened. Decides whether it was an early
## vote, and which of [member DotVoteRules.apply] and [member DotVoteRules.rtv_apply]
## its winner waits for.
var _vote_reason: StringName = DotVoteClock.REASON_MANUAL

## The moment the pending change waits for, as a [enum DotVoteRules.Apply].
var _pending_moment: int = DotVoteRules.Apply.END_OF_ROUND

var _countdown_remaining: float = 0.0
var _countdown_last: int = 0
var _countdown_runoff: bool = false
var _countdown_reason: StringName = DotVoteClock.REASON_MANUAL
var _runoff_ids: Array[StringName] = []

## Set while [method force_rtv] expires the clock: an admin's "vote now" is never held for
## a round end or handed back to a MANUAL host. A player's rock-the-vote is not either
## (see [method _on_vote_due]); this is the admin's half of the same rule.
var _forcing: bool = false

## A ballot is due and is waiting for the round in progress to end, under
## [constant DotVoteRules.Trigger.ROUND_END]. [member _vote_due_reason] says why it is due.
var _vote_due_at_round_end: bool = false

## Why the clock last ran out, as a [code]DotVoteClock.REASON_*[/code]. Empty while it has
## not. Decides whether [method is_finishing_round] applies at all: only a time or score
## limit waits for the round, never a rock-the-vote or an admin.
var _expired_reason: StringName = &""

## Seconds since the clock ran out, for [member DotVoteRules.finish_round_max_sec].
var _since_expiry: float = 0.0

## Whether a round has ended since the clock ran out, which is the moment
## [constant DotVoteRules.TimeUp.FINISH_ROUND] was waiting for.
var _round_ended_since_expiry: bool = false
