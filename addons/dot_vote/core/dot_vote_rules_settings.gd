@tool
extends DotConfig

## The enums and exported settings of [DotVoteRules], kept apart so each file stays readable.

## Not [code]CHANNEL[/code]: [DotConfig] already declares one, and a subclass that
## redeclares a parent's member does not parse.
const RULES_CHANNEL := "vote.rules"

## The addon name [DotAddonConfig] turns into the folder `dot_vote`.
const CFG_ADDON := "dot-vote"

## When a vote happens at all.
enum Trigger {
	## The clock runs out (or [member vote_lead_sec] before it does).
	TIME_LIMIT,
	## At the end of a round: a limit reaching its lead mid-round waits for the host's next
	## [method DotVoteDirector.note_round_end], so no ballot opens over a fight.
	ROUND_END,
	## Only when enough players rock the vote. No clock.
	RTV_ONLY,
	## The scheduled ballot opens only when the host asks ([method DotVoteDirector.start_vote]).
	## A passed rock-the-vote still opens one, as under every trigger.
	MANUAL,
	## When the leading score reaches [member score_limit] (or [member vote_lead_score]
	## before it does). A frag limit, a team win limit, a points target — whatever the
	## host feeds [method DotVoteDirector.note_score].
	SCORE_LIMIT,
}

## How the ballot's non-nominated places are filled.
enum Fill {
	## Uniformly at random from what is eligible.
	RANDOM,
	## At random, in proportion to [member DotVoteChoice.weight].
	WEIGHTED,
	## Straight down the source's order, wrapping. Predictable, and what a small
	## server wants: everything gets its turn.
	SEQUENTIAL,
	## Whatever has gone longest without being played.
	LEAST_RECENTLY_PLAYED,
	## Whatever was nominated most, then the rest at random.
	MOST_NOMINATED,
}

## How the votes are counted.
enum Method {
	## Most votes wins. One choice per voter.
	PLURALITY,
	## One choice per voter, and the winner must clear [member majority_fraction] or
	## the top [member runoff_options] go to another ballot.
	MAJORITY_RUNOFF,
	## Ranked, counted in one pass: the last-placed choice is eliminated and its
	## ballots move to their next preference until something has a majority.
	INSTANT_RUNOFF,
	## Vote for as many as you like; most approvals wins.
	APPROVAL,
}

## How a tie is settled.
enum TieBreak {
	## Earlier on the ballot wins. Nominations are added first, so this is
	## nomination order for anything nominated.
	BALLOT_ORDER,
	## Whichever was nominated first, then ballot order.
	NOMINATION_ORDER,
	## Whichever has gone longest unplayed.
	LEAST_RECENTLY_PLAYED,
	## Seeded random. Reproducible from [member tie_break_seed], so a client can show
	## the same answer, but not predictable from the ballot.
	RANDOM,
	## Put the tied options to another vote.
	RUNOFF,
}

## What happens when too few people voted.
enum NoQuorum {
	## Take the winner anyway.
	WINNER_ANYWAY,
	## Stay where we are, and reset the clock.
	KEEP,
	## Ignore the vote and let the source's own order decide.
	ROTATION,
}

## When the winner actually takes effect.
enum Apply {
	## As soon as the ballot closes.
	IMMEDIATE,
	## At the end of the round in progress.
	END_OF_ROUND,
	## When the clock runs out, which may be long after the vote.
	END_OF_TIME,
}

## How long a played choice stays off the ballot.
enum Cooldown {
	## Measured in plays: the last N things played are excluded.
	PLAYS,
	## Measured in wall-clock minutes since it was last played.
	MINUTES,
}

## What passing a rock-the-vote does.
enum RtvOutcome {
	## Open a ballot. The usual, and what "rock the vote" has meant since 2005.
	OPEN_VOTE,
	## Change immediately to whatever the source offers next. No ballot.
	CHANGE_NOW,
	## End the clock and let [member apply] decide when. For a round-based game
	## where changing mid-round is the rude option.
	END_CURRENT,
}

## What happens when a ballot closes with nobody having voted for anything.
enum NoVotes {
	## Stay where we are. An empty server changing map for nobody is waste.
	KEEP,
	## Draw one of the ballot's real options, never extend or keep. The long-standing
	## community map-choosers' default: a server that nobody answered still moves on.
	RANDOM,
	## Ignore the ballot and let the source's own order decide.
	ROTATION,
}

## What a time limit running out on an EMPTY server does, when nothing is paused for it.
enum EmptyChoice {
	## Draw the next one at random from what the ballot would have offered — never the one
	## running when there is anything else — and carry on. The user-facing default: an
	## always-on server keeps moving whether or not anybody is watching.
	RANDOM,
	## Take the next one in the source's own order, as [constant NoQuorum.ROTATION] does.
	ROTATION,
	## Change nothing until somebody arrives; the vote that was due opens for them. What
	## happened before this setting existed.
	WAIT,
}

## What a time or score limit running out does to the round in progress.
enum TimeUp {
	## The change happens the moment the limit is up, mid-round or not.
	CHANGE_NOW,
	## The round in progress is played out and the change happens when it ends. Only on a
	## host that reports rounds ([member DotVoteDirector.round_based]); everywhere else
	## there is no round to finish and this is [constant CHANGE_NOW].
	FINISH_ROUND,
}

## How a player chooses on a ballot drawn on their screen.
enum BallotInput {
	## The number keys choose, as a numbered menu has always worked. Nothing takes the
	## mouse.
	NUMBERS,
	## A key frees the mouse and the player clicks an option. The number keys are left to
	## the game.
	POINTER,
	## Both.
	BOTH,
}

## What rocking the vote does once the next choice has already been decided.
enum RtvAfterDecided {
	## A passed rock-the-vote changes to what was decided, now. The players have said
	## they are done with this one and the question of what is next is already answered.
	CHANGE_NOW,
	## Refused. What was decided happens when it was going to.
	DENY,
}

@export_group("Trigger")

## The master switch. Off means nothing here runs and nothing here complains.
@export var enabled: bool = true

@export var trigger: Trigger = Trigger.TIME_LIMIT

## Whether a limit running out — time, rounds or score — opens a ballot on its own.
@export var end_vote: bool = true

## Seconds before the clock expires that the ballot opens.
@export_range(0.0, 900.0, 5.0) var vote_lead_sec: float = 150.0

## The ballot opens when this fraction of the time limit is left. 0 uses
## [member vote_lead_sec] instead.
@export_range(0.0, 0.95, 0.05) var vote_lead_fraction: float = 0.0

## Rounds before the round limit that the ballot opens. The same idea, counted in
## rounds for a game whose rounds are the clock.
@export_range(0, 16, 1) var vote_lead_rounds: int = 1

## Seconds of warning before a ballot opens, counted down out loud. 0 opens it at once.
@export_range(0.0, 60.0, 1.0) var vote_warning_sec: float = 0.0

## Seconds of warning before a runoff ballot opens. 0 opens it at once.
@export_range(0.0, 30.0, 1.0) var runoff_warning_sec: float = 0.0

## Whether every second of a countdown is announced, or only its start.
@export var announce_countdown_every_sec: bool = false

## Fewest seconds between the end of one ballot and the start of the next.
@export_range(0.0, 3600.0, 5.0) var vote_cooldown_sec: float = 30.0

@export_group("Time limit")

## Seconds the current choice runs for — the MAP's clock, or the game's. 0 disables the
## clock entirely.
@export_range(0.0, 21600.0, 30.0) var duration_sec: float = 2700.0

## Rounds the current choice runs for. 0 disables the round limit.
##
## Both limits can be on at once and whichever arrives first ends it.
@export_range(0, 512, 1) var round_limit: int = 0

## The leading score that ends the current choice. 0 disables the score limit.
@export_range(0, 100000, 1) var score_limit: int = 0

## Points short of [member score_limit] at which the ballot opens.
@export_range(0, 1000, 1) var vote_lead_score: int = 5

## Seconds-remaining marks at which a warning is announced, e.g. "300,60,30".
@export var warn_at_sec: PackedStringArray = PackedStringArray(["300", "60", "30"])

## Seconds an extend adds.
@export_range(0.0, 3600.0, 30.0) var extend_seconds: float = 600.0

## Rounds an extend adds, when the limit is in rounds.
@export_range(0, 64, 1) var extend_rounds: int = 3

## Points an extend adds to [member score_limit], when there is one.
@export_range(0, 10000, 1) var extend_score: int = 10

## How many times one choice may be extended. 0 = unlimited.
@export_range(0, 64, 1) var max_extends: int = 3

## Whether extending clears the rock-the-vote tally.
@export var extend_resets_rtv: bool = true

@export_group("Time up")

## What a time or score limit running out does to a round in progress. See [enum TimeUp].
@export var time_up: TimeUp = TimeUp.CHANGE_NOW

## Longest a [constant TimeUp.FINISH_ROUND] waits for the round to end, in seconds. 0 waits
## however long the round takes.
@export_range(0.0, 3600.0, 10.0) var finish_round_max_sec: float = 300.0

@export_group("Rock the vote")

@export var rtv_enabled: bool = true

## Fraction of players who must rock the vote, 0..1.
@export_range(0.0, 1.0, 0.05) var rtv_fraction: float = 0.6

## Fewest players before rocking the vote does anything.
@export_range(1, 64, 1) var rtv_min_players: int = 1

## Seconds at the start of a choice during which rocking the vote is refused.
##
## Otherwise the first thing that happens on every new map is somebody rocking it.
@export_range(0.0, 3600.0, 10.0) var rtv_delay_sec: float = 120.0

## Whether a player leaving withdraws their rock-the-vote.
@export var rtv_forgets_leavers: bool = true

## Whether one admin rocking the vote passes it on its own.
@export var rtv_admin_instant: bool = false

@export var rtv_outcome: RtvOutcome = RtvOutcome.OPEN_VOTE

## Seconds after a rock-the-vote ballot that changed nothing before another may pass.
@export_range(0.0, 3600.0, 10.0) var rtv_interval_sec: float = 240.0

## When the winner of a ballot that rocking the vote opened takes effect.
@export var rtv_apply: Apply = Apply.IMMEDIATE

## What a passed rock-the-vote does once the next choice is already decided.
@export var rtv_after_decided: RtvAfterDecided = RtvAfterDecided.CHANGE_NOW

@export_group("Nominations")

@export var nominations_enabled: bool = true

## How many things one player may have nominated at once.
@export_range(1, 16, 1) var nominations_per_player: int = 1

## Most nominations held in total. 0 = unlimited.
@export_range(0, 64, 1) var nominations_max: int = 16

## Whether the thing currently running may be nominated.
@export var nominate_current_allowed: bool = false

## Whether something still on cooldown may be nominated.
@export var nominate_on_cooldown_allowed: bool = false

## Ballot places reserved for nominations. The rest are filled by [member fill].
@export_range(0, 32, 1) var nomination_slots: int = 4

## Whether an admin's nomination ignores the caps and the cooldown.
@export var admin_nominations_bypass: bool = true

## Whether a second player may nominate what somebody has already nominated.
@export var nomination_seconding: bool = true

## Whether a player leaving takes their nominations with them.
@export var nominations_forget_leavers: bool = false

@export_group("Ballot")

## Most options on a ballot.
@export_range(2, 32, 1) var max_options: int = 6

@export var fill: Fill = Fill.RANDOM

## Seed for [constant Fill.RANDOM] and [constant Fill.WEIGHTED].
@export var fill_seed: int = 0

## Whether "extend this" is on the ballot.
@export var include_extend: bool = true

## Whether "none of these" is on the ballot.
@export var include_keep: bool = false

## Whether what is currently running may be filled in as an ordinary option.
@export var include_current: bool = false

## Whether a ballot that rocking the vote opened offers "don't change" in place of
## "extend".
@export var early_vote_keep: bool = true

## Whether a "no vote" option is on the ballot: recorded, and counted toward nothing.
@export var include_abstain: bool = false

## Whether "extend", "don't change" and "no vote" are listed before the choices.
@export var pseudo_options_first: bool = false

## Whether the ballot is shuffled before it is shown.
@export var shuffle_ballot: bool = false

## How an unofficial choice is marked on the ballot. Empty marks nothing.
@export var unofficial_marker: String = "*%s"

## Seconds the ballot stays open.
@export_range(5.0, 600.0, 5.0) var vote_duration_sec: float = 30.0

## How a player chooses on a ballot drawn on their screen. See [enum BallotInput].
@export var ballot_input: BallotInput = BallotInput.BOTH

## Whether a drawn ballot shows who voted for what: every voter's avatar sits beside the
## option they chose, and moves when they change their mind.
@export var ballot_show_voters: bool = true

## Close as soon as everyone eligible has voted rather than waiting out the clock.
@export var close_when_all_voted: bool = true

## Whether a player may change their vote before the ballot closes.
@export var changeable_until_close: bool = true

## Fewest players before a ballot may be opened at all.
@export_range(0, 64, 1) var min_players_to_vote: int = 1

## Whether an automatic ballot (time, rounds, score, rock-the-vote) may open with one voter.
@export var allow_single_voter_auto: bool = false

## Whether players who are not in the game may vote.
@export var spectators_may_vote: bool = false

## Seconds between live-tally announcements while a ballot is open. 0 = never.
@export_range(0.0, 120.0, 1.0) var announce_interval_sec: float = 0.0

@export_group("Counting")

@export var method: Method = Method.PLURALITY

## Under [constant Method.APPROVAL], most options one voter may approve. 0 = all.
@export_range(0, 32, 1) var approval_max_choices: int = 0

## What share of the votes cast counts as a majority, 0..1.
@export_range(0.05, 1.0, 0.01) var majority_fraction: float = 0.5

## How many go through to a runoff.
@export_range(2, 8, 1) var runoff_options: int = 2

## Most runoffs before the leader is simply taken. 0 refuses to run one at all.
@export_range(0, 8, 1) var max_runoffs: int = 1

@export var tie_break: TieBreak = TieBreak.BALLOT_ORDER

## Seed for [constant TieBreak.RANDOM]. Advanced on every use, deterministically, so
## a client following along reaches the same answer.
@export var tie_break_seed: int = 0

## Fraction of eligible players who must vote for the result to stand, 0..1.
@export_range(0.0, 1.0, 0.05) var quorum: float = 0.0

@export var on_no_quorum: NoQuorum = NoQuorum.WINNER_ANYWAY

## What a ballot nobody voted in decides.
@export var on_no_votes: NoVotes = NoVotes.KEEP

## What a time limit running out on a server with nobody on it does. See [enum EmptyChoice].
@export var empty_choice: EmptyChoice = EmptyChoice.RANDOM

## Whether waking from hibernation starts what is running again from its configured start.
@export var wake_restart: bool = true

## Whether extend must win outright rather than merely lead.
@export var extend_needs_majority: bool = true

@export_group("History")

## How many recently played choices are excluded from a ballot.
@export_range(0, 64, 1) var cooldown: int = 5

@export var cooldown_mode: Cooldown = Cooldown.PLAYS

## Minutes a played choice is excluded for under [constant Cooldown.MINUTES].
@export_range(0.0, 1440.0, 5.0) var cooldown_minutes: float = 60.0

## Most of the pool a cooldown may exclude, 0..1.
@export_range(0.0, 1.0, 0.05) var cooldown_max_fraction: float = 0.5

## Longest play history kept. Bounds the memory on a server up for months.
@export_range(8, 1024, 8) var history_limit: int = 64

@export_group("Applying")

@export var apply: Apply = Apply.END_OF_ROUND

## Seconds between the result being announced and the change happening.
##
## Not decoration: it is the gap in which players read what won.
@export_range(0.0, 60.0, 1.0) var apply_delay_sec: float = 5.0

@export_group("Cues")

## Sound cue ids, emitted through [signal DotVoteDirector.cue] for the host to play.
## [b]Empty is silent[/b], and every one ships empty.

## A ballot opened.
@export var cue_vote_start: String = ""

## A ballot closed, whatever it decided.
@export var cue_vote_end: String = ""

## The countdown before a ballot started.
@export var cue_warning: String = ""

## The countdown before a runoff started.
@export var cue_runoff_warning: String = ""

## One second of a countdown, as a template: [code]%d[/code] is the seconds left, so
## [code]"vote.count.%d"[/code] asks for [code]vote.count.3[/code]. Without a
## [code]%d[/code] the same cue plays every time.
@export var cue_countdown: String = ""

## Which seconds of a countdown have a cue. Text, for the reason
## [member warn_at_sec] is text.
@export var cue_countdown_at: PackedStringArray = PackedStringArray(
	["10", "5", "4", "3", "2", "1"]
)
