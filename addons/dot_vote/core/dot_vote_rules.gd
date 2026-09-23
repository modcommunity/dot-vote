@tool
class_name DotVoteRules
extends DotConfig

## Every policy decision this addon makes, in one place, and nothing else.
##
## [b]The whole addon is here.[/b] [DotVoteBallot], [DotVoteClock] and
## [DotVoteNominations] hold state and arithmetic; what any of them should [i]do[/i]
## is one of these fields. That is not tidiness — it is the difference between a
## server operator changing a number and a server operator forking an addon, and
## every community that has ever run one of these has wanted a different number.
##
## A [DotConfig], so it layers exactly like everything else in the family:
##
## [codeblock]
## exported defaults  <  vote.json / vote.yml  <  DOT_VOTE_*  <  --vote-*
## [/codeblock]
##
## [b]Enum settings are written by name in a file[/b] — [code]method: instant_runoff[/code],
## not [code]method: 2[/code]. Godot exports them as integers and a config file full of
## integers is a config file nobody can read or diff; [method apply_dictionary] below
## translates the names on the way in. An operator should never have to count enum
## entries in somebody else's source.
##
## The defaults are the ones a public server can run untouched: a thirty-minute limit,
## rock the vote at 60% of at least two players, a six-option ballot with four places
## kept for nominations, plurality with the earliest-nominated winning a tie, and the
## winner applied at the end of the round.

## Not [code]CHANNEL[/code]: [DotConfig] already declares one, and a subclass that
## redeclares a parent's member does not parse.
const RULES_CHANNEL := "vote.rules"

## When a vote happens at all.
enum Trigger {
	## The clock runs out (or [member vote_lead_sec] before it does).
	TIME_LIMIT,
	## At the end of a round. A round limit opens the ballot at the round end it is due
	## on, as under [constant TIME_LIMIT]; a time or score limit reaching its lead does
	## [i]not[/i] open it mid-round, but holds it until the host's next
	## [method DotVoteDirector.note_round_end]. For a round-based game, where a ballot over
	## a fight in progress is a ballot nobody reads.
	ROUND_END,
	## Only when enough players rock the vote. No clock.
	RTV_ONLY,
	## Only when the host asks. For a game that decides for itself.
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
##
## [b]Never a coin flip by default.[/b] A live tally that says 4–4 and a result that
## says one of them won reads, to the people who watched it, as the vote being rigged.
## Every option here except [constant TieBreak.RANDOM] is one a player watching can
## work out for themselves.
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
##
## [b]The switch a server owner is looking for when they ask for "an end-of-map
## vote".[/b] Off, the limits still end the map, and what plays next is whatever an
## admin set with [code]setnextmap[/code], a rock-the-vote decided, or the source's own
## rotation — the same fallback a server with no vote at all has. On is the default
## because a limit nobody is asked about is a server that changes map under people.
##
## Separate from [member trigger] rather than another entry in it, because it is
## orthogonal: a time limit, a round limit and a score limit each either ask the
## players or do not, and [constant Trigger.RTV_ONLY] is exactly "off" for all three.
@export var end_vote: bool = true

## Seconds before the clock expires that the ballot opens.
##
## [b]This is what a vote is for.[/b] A ballot that opens when the time is already up
## either changes the game late or gives players ten seconds to choose; opening it
## with a couple of minutes left means the vote finishes and the change happens
## exactly on time. 0 opens it at expiry.
@export_range(0.0, 900.0, 5.0) var vote_lead_sec: float = 120.0

## The ballot opens when this fraction of the time limit is left. 0 uses
## [member vote_lead_sec] instead.
##
## For a server whose maps run anywhere from ten minutes to an hour: a fixed two-minute
## lead is most of a short map's last act and nothing on a long one, and "when a third
## is left" scales with each. Measured against the limit [i]as extended[/i], so an
## extended map is asked again at the same point of its new length.
@export_range(0.0, 0.95, 0.05) var vote_lead_fraction: float = 0.0

## Rounds before the round limit that the ballot opens. The same idea, counted in
## rounds for a game whose rounds are the clock.
@export_range(0, 16, 1) var vote_lead_rounds: int = 1

## Seconds of warning before a ballot opens, counted down out loud. 0 opens it at once.
##
## [b]A ballot that appears in the middle of a fight is a ballot most people close
## without reading.[/b] A countdown gives them fifteen seconds to get somewhere they can
## look at it, and it is what [signal DotVoteDirector.countdown_tick] and the countdown
## cue exist for.
@export_range(0.0, 60.0, 1.0) var vote_warning_sec: float = 0.0

## Seconds of warning before a runoff ballot opens. 0 opens it at once.
##
## Shorter than [member vote_warning_sec] as a rule: everybody has just voted, they are
## already looking.
@export_range(0.0, 30.0, 1.0) var runoff_warning_sec: float = 0.0

## Whether every second of a countdown is announced, or only its start.
##
## Off, because [member DotVoteDirector.announce_fn] is usually chat, and fifteen chat
## lines in fifteen seconds bury everything else anybody said. A HUD that wants a live
## number connects [signal DotVoteDirector.countdown_tick], which fires every second
## either way.
@export var announce_countdown_every_sec: bool = false

## Fewest seconds between the end of one ballot and the start of the next.
##
## Bounds the failure mode where a vote ends with no quorum, the clock is still
## expired, and the next tick opens another one.
@export_range(0.0, 3600.0, 5.0) var vote_cooldown_sec: float = 30.0

@export_group("Time limit")

## Seconds the current choice runs for. 0 disables the clock entirely.
##
## Zero is a real configuration — a server that only ever changes by vote — and is
## deliberately not the same as a very long limit, which still fires eventually and
## surprises somebody at four in the morning.
@export_range(0.0, 21600.0, 30.0) var duration_sec: float = 1800.0

## Rounds the current choice runs for. 0 disables the round limit.
##
## Both limits can be on at once and whichever arrives first ends it.
@export_range(0, 512, 1) var round_limit: int = 0

## The leading score that ends the current choice. 0 disables the score limit.
##
## [b]Generic on purpose.[/b] What a score is — frags, team round wins, capture points
## — is the game's business; the host reports the leading one through
## [method DotVoteDirector.note_score] and this is the number it is compared with. All
## three limits can be on at once and whichever arrives first ends the choice.
@export_range(0, 100000, 1) var score_limit: int = 0

## Points short of [member score_limit] at which the ballot opens.
@export_range(0, 1000, 1) var vote_lead_score: int = 5

## Seconds-remaining marks at which a warning is announced, e.g. "300,60,30".
##
## [b]A list of strings rather than of floats[/b] because that is what survives the
## journey: an environment variable and a command-line argument are text, and
## [DotConfig] can read a comma-separated string into a [PackedStringArray] and not
## into a [PackedFloat32Array]. A setting that cannot be set from every layer is not
## configurable, whatever its type says.
@export var warn_at_sec: PackedStringArray = PackedStringArray(["300", "60", "30"])

## Seconds an extend adds.
@export_range(0.0, 3600.0, 30.0) var extend_seconds: float = 600.0

## Rounds an extend adds, when the limit is in rounds.
@export_range(0, 64, 1) var extend_rounds: int = 3

## Points an extend adds to [member score_limit], when there is one.
@export_range(0, 10000, 1) var extend_score: int = 10

## How many times one choice may be extended. 0 = unlimited.
##
## Bounded because extend wins by default: the people still here are the people who
## like it, so an unbounded extend runs one map until everybody else has left.
@export_range(0, 64, 1) var max_extends: int = 3

## Whether extending clears the rock-the-vote tally.
##
## On: the players who wanted out have just been outvoted, and keeping their votes
## means the map ends again the moment one more person joins and agrees.
@export var extend_resets_rtv: bool = true

@export_group("Rock the vote")

@export var rtv_enabled: bool = true

## Fraction of players who must rock the vote, 0..1.
##
## 0.6 rather than a bare majority: this is a request to abandon something early, and
## seven of twelve deciding for the five who chose it is not a mandate.
@export_range(0.0, 1.0, 0.05) var rtv_fraction: float = 0.6

## Fewest players before rocking the vote does anything.
##
## On a nearly-empty server one person is always a majority. 1 configures exactly
## that, and is the right answer for a private server.
@export_range(1, 64, 1) var rtv_min_players: int = 2

## Seconds at the start of a choice during which rocking the vote is refused.
##
## Otherwise the first thing that happens on every new map is somebody rocking it.
@export_range(0.0, 3600.0, 10.0) var rtv_delay_sec: float = 120.0

## Whether a player leaving withdraws their rock-the-vote.
##
## On, because otherwise a server whose players trickle away keeps their votes while
## the threshold falls with the player count — and the map ends on the votes of people
## who are not there.
@export var rtv_forgets_leavers: bool = true

## Whether one admin rocking the vote passes it on its own.
@export var rtv_admin_instant: bool = false

@export var rtv_outcome: RtvOutcome = RtvOutcome.OPEN_VOTE

## Seconds after a rock-the-vote ballot that changed nothing before another may pass.
##
## [b]Without it the vote that just failed is the vote that happens next.[/b] The same
## players who rocked it rock it again the moment the ballot closes, and a server whose
## majority wanted to stay is asked the same question every thirty seconds until the
## minority wins by attrition.
@export_range(0.0, 3600.0, 10.0) var rtv_interval_sec: float = 240.0

## When the winner of a ballot that rocking the vote opened takes effect.
##
## Separate from [member apply] because the two are different requests. The end-of-map
## ballot is "what next, when this ends"; a rock-the-vote is "we want to stop now", and
## honouring it at the end of the clock is a server that heard the question and did
## not answer it. [constant Apply.IMMEDIATE] is the long-standing default.
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
##
## Off by default: "play this again" is what extending is for, and having both on one
## ballot splits the vote of the people who want the same thing.
@export var nominate_current_allowed: bool = false

## Whether something still on cooldown may be nominated.
@export var nominate_on_cooldown_allowed: bool = false

## Ballot places reserved for nominations. The rest are filled by [member fill].
##
## Reserving some rather than all is what stops three organised players deciding every
## map on a twenty-player server.
@export_range(0, 32, 1) var nomination_slots: int = 4

## Whether an admin's nomination ignores the caps and the cooldown.
@export var admin_nominations_bypass: bool = true

## Whether a second player may nominate what somebody has already nominated.
##
## [b]On, and [constant Fill.MOST_NOMINATED] is why.[/b] SourceMod refuses a duplicate
## with "map already nominated", which is defensible and makes every nomination count
## exactly one — and a ballot filled by "most nominated" then has nothing to sort by,
## so the whole fill mode is decoration. Seconding turns a nomination into a signal of
## support as well as a request, which is what a popularity fill needs to exist at
## all. Off restores the SourceMod behaviour for a server that wants it.
##
## A player still cannot nominate the same thing twice: that is not support, it is a
## player pressing a key again because nothing visible happened.
@export var nomination_seconding: bool = true

## Whether a player leaving takes their nominations with them.
##
## Off, and [method DotVoteDirector.forget_voter] explains why: a nomination is a
## request of the server rather than of the person. The long-standing community
## map-choosers drop them on disconnect, and a server that wants that behaviour turns
## this on — the removal is reported through
## [signal DotVoteDirector.nomination_removed] either way.
@export var nominations_forget_leavers: bool = false

@export_group("Ballot")

## Most options on a ballot.
##
## Bounded because a ballot of thirty is one nobody reads: everybody picks from the
## first five they can see, which is a worse outcome than a shorter ballot chosen
## properly.
@export_range(2, 32, 1) var max_options: int = 6

@export var fill: Fill = Fill.RANDOM

## Seed for [constant Fill.RANDOM] and [constant Fill.WEIGHTED].
##
## Explicit and advanced deterministically on every fill, rather than reseeded from
## the clock, so a client filling the same ballot from the same history reaches the
## same options — the reason [code]DotMapRotation[/code] carries one too.
@export var fill_seed: int = 0

## Whether "extend this" is on the ballot.
@export var include_extend: bool = true

## Whether "none of these" is on the ballot.
##
## Distinct from extend: it means "do not change, and do not add time either", which
## on a round-based game is the difference between another round and another hour.
@export var include_keep: bool = false

## Whether what is currently running may be filled in as an ordinary option.
@export var include_current: bool = false

## Whether a ballot that rocking the vote opened offers "don't change" in place of
## "extend".
##
## [b]Extending a map the players just asked to leave is the wrong question.[/b] On an
## end-of-map ballot "extend" means "more of this"; on a rock-the-vote ballot the clock
## still has time on it, and what the people who did not rock it want is for nothing to
## happen — which is "don't change", and it leaves the clock where it was rather than
## adding to it.
@export var early_vote_keep: bool = true

## Whether a "no vote" option is on the ballot: recorded, and counted toward nothing.
##
## For the player who has been shown a ballot and has no opinion. Without it they either
## ignore it — and a ballot that closes when everybody has voted then waits out its
## whole clock for them — or they pick something at random, which is a vote for a map
## nobody wanted. An abstention closes their part of the ballot, counts toward the
## quorum (they were asked, and answered "you decide"), and is in no option's count and
## no majority's denominator.
@export var include_abstain: bool = false

## Whether "extend", "don't change" and "no vote" are listed before the choices.
##
## [b]Presentation only.[/b] A tie broken by [constant TieBreak.BALLOT_ORDER] is still
## broken as though the choices came first — see [method DotVoteBallot.option_ids] — or
## moving an option up a menu would quietly make every tie go to the status quo.
@export var pseudo_options_first: bool = false

## Whether the ballot is shuffled before it is shown.
##
## Nominations are placed first and everybody picks from the top of a list they only
## half read; shuffling removes the advantage of having been nominated early. Seeded
## from [member fill_seed], so a client that knows the seed shows the same order.
## [constant TieBreak.BALLOT_ORDER] follows the shuffled order, which is the point.
@export var shuffle_ballot: bool = false

## How an unofficial choice is marked on the ballot. Empty marks nothing.
##
## [code]%s[/code] is the choice's name — [code]"*%s"[/code], [code]"%s (custom)"[/code].
## A marker with no [code]%s[/code] is appended. Which choices are unofficial is the
## source's to say ([member DotVoteChoice.official]), from the thing's own metadata.
@export var unofficial_marker: String = "*%s"

## Seconds the ballot stays open.
@export_range(5.0, 600.0, 5.0) var vote_duration_sec: float = 30.0

## Close as soon as everyone eligible has voted rather than waiting out the clock.
@export var close_when_all_voted: bool = true

## Whether a player may change their vote before the ballot closes.
##
## On, because the alternative is a player who misclicked being stuck with it, and
## because being able to change your mind is what makes a live tally worth showing.
@export var changeable_until_close: bool = true

## Fewest players before a ballot may be opened at all.
##
## [b]0 is a real setting.[/b] It allows a vote on an empty server, which is what a
## private server run by two friends wants and what a headless test needs — there is
## nobody connected, and refusing to open a ballot is then indistinguishable from the
## vote system being broken.
@export_range(0, 64, 1) var min_players_to_vote: int = 1

## Whether players who are not in the game may vote.
##
## Off: a spectator on a timer server is often somebody waiting for a friend, and on
## any server it is the cheapest way to stuff a ballot.
@export var spectators_may_vote: bool = false

## Seconds between live-tally announcements while a ballot is open. 0 = never.
@export_range(0.0, 120.0, 1.0) var announce_interval_sec: float = 0.0

@export_group("Counting")

@export var method: Method = Method.PLURALITY

## Under [constant Method.APPROVAL], most options one voter may approve. 0 = all.
@export_range(0, 32, 1) var approval_max_choices: int = 0

## What share of the votes cast counts as a majority, 0..1.
##
## Used by [constant Method.MAJORITY_RUNOFF] and [constant Method.INSTANT_RUNOFF].
##
## [b]Below a half is allowed[/b], and is what "hold a runoff when the winner has less
## than 40%" means: the long-standing community map-choosers ask exactly that, and a
## six-way ballot where the leader has 38% is often a result people accept. Under an
## instant runoff a share below a half ends the elimination early, which is the same
## decision made the same way.
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
##
## Without one, a vote on a thirty-player server is decided 2–1 by the three people
## who noticed it.
@export_range(0.0, 1.0, 0.05) var quorum: float = 0.0

@export var on_no_quorum: NoQuorum = NoQuorum.WINNER_ANYWAY

## What a ballot nobody voted in decides.
##
## Distinct from [member on_no_quorum]: "too few voted" still has a leader to take, and
## "nobody voted" has none — so the answers are different, and [constant NoVotes.KEEP]
## is the default because the commonest cause is an empty server.
@export var on_no_votes: NoVotes = NoVotes.KEEP

## Whether extend must win outright rather than merely lead.
##
## On: a tie between "extend" and something new goes to the new thing, because the
## people who wanted a change are the ones who lose by staying, and a server that ties
## toward the status quo never moves.
@export var extend_needs_majority: bool = true

@export_group("History")

## How many recently played choices are excluded from a ballot.
@export_range(0, 64, 1) var cooldown: int = 5

@export var cooldown_mode: Cooldown = Cooldown.PLAYS

## Minutes a played choice is excluded for under [constant Cooldown.MINUTES].
@export_range(0.0, 1440.0, 5.0) var cooldown_minutes: float = 60.0

## Most of the pool a cooldown may exclude, 0..1.
##
## [b]The cooldown is clamped against the pool at choosing time, not here.[/b] A
## cooldown of eight on a server with six things in rotation excludes everything, and
## the honest behaviour is to shorten the memory rather than to offer nothing — which
## would leave the server where it is for ever with no error anywhere.
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
##
## Ids rather than files, and a signal rather than a player, because this addon must
## not depend on dot-audio — which is itself a catalogue of ids that ships no audio. A
## host connects the signal to its catalogue; a "sound set" is a different set of ids
## in this file.

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


func env_prefix() -> String:
	return "DOT_VOTE_"


func cli_prefix() -> String:
	return "--vote-"


## Enum settings, by property name, so a config file can name them in words.
##
## Kept as one table rather than as a method per enum because it is also what
## [method DotVoteRules.enum_names_for] reports to a settings UI and to
## [code]describe_lines[/code] — three readers of one list, which is one fewer place
## for a renamed enum entry to go stale.
const ENUMS := {
	"trigger": Trigger,
	"fill": Fill,
	"method": Method,
	"tie_break": TieBreak,
	"on_no_quorum": NoQuorum,
	"apply": Apply,
	"cooldown_mode": Cooldown,
	"rtv_outcome": RtvOutcome,
	"rtv_apply": Apply,
	"rtv_after_decided": RtvAfterDecided,
	"on_no_votes": NoVotes,
}


## Applies a layer, translating enum names to their values first.
##
## [code]method: instant_runoff[/code], [code]METHOD=INSTANT_RUNOFF[/code] and
## [code]method: 2[/code] all set the same thing. The last one still works because a
## config written by a program should not have to know the names.
func apply_dictionary(
	d: Dictionary,
	layer_name: String = "dict",
	allow_sensitive: bool = true
) -> PackedStringArray:
	return super.apply_dictionary(
		_translate_enums(d), layer_name, allow_sensitive
	)


func _translate_enums(d: Dictionary) -> Dictionary:
	var out := {}

	for raw_key: Variant in d:
		var value: Variant = d[raw_key]
		var key := _match_key(str(raw_key), config_keys())

		if key != "" and ENUMS.has(key) and (
			typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME
		):
			var text := str(value).strip_edges()

			# A numeric string is left alone for _coerce to read as the integer it is.
			if not text.is_valid_int():
				var table: Dictionary = ENUMS[key]
				var wanted := text.to_upper().replace("-", "_").replace(" ", "_")

				if table.has(wanted):
					out[raw_key] = int(table[wanted])
					continue

				DotLog.warn(RULES_CHANNEL, "unknown value for an enum setting", {
					"key": key,
					"value": text,
					"known": ", ".join(enum_names_for(key)),
				})

		out[raw_key] = value

	return out


## The legal names for an enum setting, lower case. Empty for anything else.
static func enum_names_for(key: String) -> PackedStringArray:
	var out := PackedStringArray()

	if not ENUMS.has(key):
		return out

	var table: Dictionary = ENUMS[key]

	for name: Variant in table:
		out.append(str(name).to_lower())

	return out


## The name of an enum setting's current value, for a log line or a console reply.
func enum_name(key: String) -> String:
	if not ENUMS.has(key):
		return ""

	var table: Dictionary = ENUMS[key]
	var current := int(get(key))

	for name: Variant in table:
		if int(table[name]) == current:
			return str(name).to_lower()

	return str(current)


## The warning marks, as seconds, largest first.
##
## Parsed rather than stored because [member warn_at_sec] is text — see the note on
## that field. Anything unreadable is dropped with a warning rather than taking the
## whole configuration down: one bad entry in a list of three should cost one warning.
func warn_marks() -> PackedFloat32Array:
	var out := PackedFloat32Array()

	for entry in warn_at_sec:
		var text := entry.strip_edges()

		if text == "":
			continue

		if not text.is_valid_float():
			DotLog.warn(RULES_CHANNEL, "ignoring an unreadable warning mark", {
				"value": text
			})
			continue

		var seconds := text.to_float()

		if seconds > 0.0:
			out.append(seconds)

	var sorted := Array(out)
	sorted.sort()
	sorted.reverse()

	return PackedFloat32Array(sorted)


## Whether a countdown second has a cue, per [member cue_countdown_at].
##
## Parsed on every ask rather than cached, for the same reason [method warn_marks] is:
## the field is text and may be changed by a console command at any moment.
func has_countdown_cue(seconds_left: int) -> bool:
	if cue_countdown == "":
		return false

	for entry in cue_countdown_at:
		var text := entry.strip_edges()

		if text.is_valid_int() and text.to_int() == seconds_left:
			return true

	return false


## The cue id for one second of a countdown, or empty.
func countdown_cue_id(seconds_left: int) -> String:
	if not has_countdown_cue(seconds_left):
		return ""

	return cue_countdown % seconds_left if cue_countdown.contains("%d") else cue_countdown


## A choice's name as a ballot shows it, marked when it is unofficial.
##
## [b]Formatted with [code]replace[/code] rather than [code]%[/code][/b]: a marker an
## operator typed with a stray [code]%[/code] in it would otherwise fail to format, and
## GDScript hands back the unformatted string rather than raising — so the ballot would
## show "*%s" for every custom map with nothing in the log.
func marked_name(display: String, official: bool) -> String:
	if official or unofficial_marker == "":
		return display

	if unofficial_marker.contains("%s"):
		return unofficial_marker.replace("%s", display)

	return display + unofficial_marker


## Layers a game's own vote configuration onto these rules, which hold its defaults.
##
## [codeblock]
## code defaults  <  overlay (the running game's metadata)  <  file  <  DOT_VOTE_*  <  --vote-*
## [/codeblock]
##
## [b]This is [method DotConfig.load_layered] with one layer in front of it, not a new
## loader.[/b] The overlay is what an operator writes beside the game — a delivered
## game's [code]game.yml[/code] — and the file is what an operator writes beside the
## server. Both are optional.
##
## [b]A result that does not validate is refused as a whole[/b], and the rules are put
## back to the defaults they held: a vote whose rules contradict each other is a vote
## that never opens, and a server that keeps its own tested defaults and logs why is
## better than one that half-applies a broken file.
func layer_over_defaults(file_path: String, overlay: Dictionary = {}) -> DotResult:
	var defaults := to_dictionary()

	if not overlay.is_empty():
		apply_dictionary(overlay, "game metadata")

	var overlay_unknown := unknown_keys.duplicate()
	var loaded := load_layered(file_path)

	# load_layered starts its own list of unknown keys; the overlay's are kept in front
	# of them, so a typo in game.yml is reported exactly like a typo in the file.
	overlay_unknown.append_array(unknown_keys)
	unknown_keys = overlay_unknown

	if loaded.ok:
		return loaded

	apply_dictionary(defaults, "defaults")

	return loaded


func validate() -> DotResult:
	if max_options < 2:
		return DotResult.fail(
			DotError.CODE_INVALID, "A ballot needs at least two options."
		)

	if nomination_slots > max_options:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"nomination_slots (%d) exceeds max_options (%d)."
				% [nomination_slots, max_options],
			"every place on the ballot would be reserved and nothing would be filled in"
		)

	if runoff_options > max_options:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"runoff_options (%d) exceeds max_options (%d)."
				% [runoff_options, max_options]
		)

	if trigger == Trigger.TIME_LIMIT and duration_sec <= 0.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"trigger is time_limit but duration_sec is 0.",
			"nothing would ever start a vote; use trigger: rtv_only or manual"
		)

	# Any limit will do: under round_end a time or a score limit is held for the round's
	# end rather than ignored. What cannot work is no limit at all.
	if (
		trigger == Trigger.ROUND_END
		and round_limit <= 0 and duration_sec <= 0.0 and score_limit <= 0
	):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"trigger is round_end but there is no round, time or score limit.",
			"nothing would ever start a vote"
		)

	if vote_lead_sec > 0.0 and duration_sec > 0.0 and vote_lead_sec >= duration_sec:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"vote_lead_sec (%.0f) is not less than duration_sec (%.0f)."
				% [vote_lead_sec, duration_sec],
			"the ballot would open the instant the choice started"
		)

	if rtv_delay_sec > 0.0 and duration_sec > 0.0 and rtv_delay_sec >= duration_sec:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"rtv_delay_sec (%.0f) is not less than duration_sec (%.0f)."
				% [rtv_delay_sec, duration_sec],
			"rocking the vote would be refused for the whole of every map"
		)

	if not rtv_enabled and trigger == Trigger.RTV_ONLY:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"trigger is rtv_only but rtv_enabled is off.",
			"nothing could ever start a vote"
		)

	if max_runoffs > 0 and tie_break == TieBreak.RUNOFF and runoff_options < 2:
		return DotResult.fail(
			DotError.CODE_INVALID, "A runoff needs at least two options."
		)

	if trigger == Trigger.SCORE_LIMIT and score_limit <= 0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"trigger is score_limit but score_limit is 0.",
			"nothing would ever start a vote"
		)

	if score_limit > 0 and vote_lead_score >= score_limit:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"vote_lead_score (%d) is not less than score_limit (%d)."
				% [vote_lead_score, score_limit],
			"the ballot would open at the first point scored"
		)

	if vote_lead_fraction >= 1.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"vote_lead_fraction must be less than 1.",
			"the ballot would open the instant the choice started"
		)

	return DotResult.success(true)


## A short human summary. [b]Not [code]describe_lines[/code][/b], which [DotConfig]
## already defines as the full dump of every key — both are worth having, and a
## console command that showed only one of them would show the wrong one.
func summary_lines() -> PackedStringArray:
	var out := PackedStringArray()

	out.append("enabled    %s" % ("yes" if enabled else "no"))
	out.append("trigger    %s, end vote %s" % [
		enum_name("trigger"), "on" if end_vote else "off"
	])
	out.append("limit      %s%s%s" % [
		"none" if duration_sec <= 0.0 else "%ds" % int(duration_sec),
		"" if round_limit <= 0 else ", %d rounds" % round_limit,
		"" if score_limit <= 0 else ", score %d" % score_limit,
	])
	out.append("extend     %s, +%ds, %s" % [
		"offered" if include_extend else "not offered",
		int(extend_seconds),
		"unlimited" if max_extends <= 0 else "at most %d" % max_extends,
	])
	out.append("ballot     %d options, %d reserved, filled %s" % [
		max_options, nomination_slots, enum_name("fill")
	])
	out.append("counting   %s, ties by %s" % [
		enum_name("method"), enum_name("tie_break")
	])
	out.append("rtv        %s at %d%% of %d+" % [
		"on" if rtv_enabled else "off",
		int(rtv_fraction * 100.0),
		rtv_min_players,
	])
	out.append("cooldown   %s" % (
		"%d plays" % cooldown if cooldown_mode == Cooldown.PLAYS
		else "%.0f minutes" % cooldown_minutes
	))
	out.append("applies    %s after %.0fs" % [enum_name("apply"), apply_delay_sec])

	return out
