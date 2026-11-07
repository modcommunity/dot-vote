class_name DotVoteTimedGame
extends Node

## The vote of a game that runs on a clock, not on rounds: [DotVoteDirector] over a source of the server's maps, with what every such game
## copied once here instead: the director and its callbacks, the ballot feed, rules layered under the server owner's files, `!vote`, the
## signals a host relays to clients, and the clock view that tells a client when its own count would be wrong. A game extends this, sets
## [member channel], [member metadata_key], [member command_names], [member noun] and [member config_path] in [code]_init[/code], and overrides:
## [method _rules] (its defaults, usually a TIME_LIMIT), [method _make_source] (when its choices are not a list), [method _configure_director]
## (anything else the director needs) and [method _voters].
##
## For a game with rounds, extend [DotVoteRoundGame] instead.

## The log channel, e.g. "delivery.vote".
var channel: String = "dot_vote.timed_game"

## The key in the running game's descriptor metadata an operator's overrides are read from
## ([code]metadata: mountain_vote:[/code] in a delivered game's [code]game.yml[/code]).
var metadata_key: String = "map_vote"

## What the vote command is called: `!vote 2` in chat, `vote 2` in a console.
var command_names: Dictionary = {"vote": "vote"}

## What a ballot is for, as the ballot's title, the source's label ("map" -> "maps") and the logs say it.
var noun: String = "map"

## The file a server owner configures the vote in, keyed as [DotVoteRules]:
## [code]_rules() < game.yml metadata < this file < DOT_VOTE_* < --vote-*[/code]. Empty skips the file; [code]{"enabled": false}[/code] turns the vote off.
@export var config_path: String = ""

## Whether the director applies a winner itself. A host that must change the map through its own path (to tell clients) turns it off and
## acts on [signal change_due].
var auto_apply: bool = true

## Whether the director registers as the `dot_vote_director` service. One ballot per screen is the host's to arrange, so off by default.
var register_service: bool = false

## Whether settings this game cannot drive (a round-end trigger, a score limit) are taken out of an operator's file: no round end and no score
## is reported, so they would wait for ever. A game that reports either turns this off.
var drops_unfed: bool = true

## Whether the default source follows the Workshop's index ([method _make_source]).
var follows_content: bool = true

## [code]func() -> Array[/code] of [code][id, name][/code] pairs: every map a ballot may offer. The host's, because which maps a server plays
## is the world's to say. Read before every ballot by the default source.
var maps_fn: Callable = Callable()

## The Workshop's index and the `map_kind`s taken from it. Null and empty are the shared index and [method _default_kinds]; a suite sets both.
var content_index: DotContentIndex = null
var accepted_kinds: PackedStringArray = PackedStringArray()

## [code]func(id: StringName) -> DotResult[/code]: play this map now.
var apply_fn: Callable = Callable()

## [code]func() -> Array[/code] of voter ids (StringName): the people who may vote. Stand-ins are not voters.
var voters_fn: Callable = Callable()

## [code]func() -> int[/code]: the head count, when it is not the number of [member voters_fn] (a host with no voter list).
var player_count_fn: Callable = Callable()

## Says a line to everybody.
var announce_fn: Callable = Callable()

## Whether a voter is an admin, for dot-vote's admin bypasses.
var is_admin_fn: Callable = Callable()

## [code]func(state: Dictionary)[/code]: the ballot as a client draws it, sent when it changes.
var ballot_fn: Callable = Callable()

## [code]func(voter: StringName) -> Dictionary[/code]: a voter's name and avatar, for the ballot.
var people_fn: Callable = Callable()

## `() -> Dictionary`: maps.yml's `commands:` block, so an operator renames the vote's commands without this game naming any.
var commands_spec_fn: Callable = Callable()

## `(id) -> bool` and `() -> Array`: maps.yml's active rotation, handed to the default source so the pack maps dot-vote merges are filtered and
## ordered like the game's own (dot-vote API level 12).
var in_rotation_fn: Callable = Callable()
var rotation_order_fn: Callable = Callable()

## Whether `!vote` voters are the bare session id (the spelling [member voters_fn] lists). dot-vote's own default is `u<userid>`; a game whose
## ids are that spelling turns this off.
var bare_voter_ids: bool = true

## The node name of the director.
var director_name: String = "VoteDirector"

var director: DotVoteDirector = null
var source: DotVoteSource = null
var commands: DotVoteCommands = null
var feed: DotVoteBallotFeed = null
var clock_view: DotVoteClockView = DotVoteClockView.new()

## The director's own signals, relayed so a host connects to this node and never to its director.
signal vote_opened(options: Array, seconds: float)
signal vote_closed(result: DotVoteResult)
signal rocked(voter: StringName, votes: int, needed: int)
signal change_due(id: StringName, choice: DotVoteChoice)

## A cue to play, or a countdown second ([param cue] empty): dot-vote emits the two separately and merging them here would decide which is which.
signal cue_due(cue: StringName, seconds_left: int, runoff: bool)

## The clock as a client must count it, sent only when a client's own count would be wrong (an extend, a new map, a stopped clock).
signal clock_due(state: Dictionary)

var _clock_time: float = 0.0


## The Workshop `map_kind`s this game plays, when [member accepted_kinds] is empty.
func _default_kinds() -> PackedStringArray:
	return PackedStringArray()


## What a game with a clock wants from dot-vote by default. Every line is a default an operator overrides in [member config_path].
func _rules() -> DotVoteRules:
	var rules := DotVoteRules.new()
	rules.trigger = DotVoteRules.Trigger.TIME_LIMIT
	return rules


## The source of choices: a [DotVoteListSource] of [member maps_fn], plus the Workshop's maps when [member follows_content]. A game whose
## choices are something else (a map session) returns its own, or null when it has nothing to offer (setup then fails).
func _make_source() -> DotVoteSource:
	var list := DotVoteListSource.new()
	list.label = noun + "s"
	list.apply_fn = _apply
	list.entries_fn = func() -> Array:
		return maps_fn.call() if maps_fn.is_valid() else []
	source = list
	refresh_maps()
	# The Workshop's maps of the kinds this game plays, read from the index on every ballot. Solo they are listed; online the index has no
	# subscription entry, so none appear. The game's own ids are in the entries and win.
	if follows_content:
		list.follow_content(
			content_index if content_index != null else DotContentIndex.shared(),
			_default_kinds() if accepted_kinds.is_empty() else accepted_kinds)
	# By name, only where it exists: a delivered pack may run on an older shell dot-vote.
	if "in_rotation_fn" in list:
		list.set(&"in_rotation_fn", in_rotation_fn)
		list.set(&"rotation_order_fn", rotation_order_fn)
	return list


## Plays [param id]: [member apply_fn], or a plain success when none is set. A game overrides it to refuse an id it cannot play.
func _apply(id: StringName) -> DotResult:
	return apply_fn.call(id) if apply_fn.is_valid() else DotResult.success(id)


## Anything else the director needs, after the common fields and before it joins the tree: `round_based`, `busy_fn`, `is_spectator_fn`.
func _configure_director(_d: DotVoteDirector) -> void:
	pass


## The people who may vote. A game with its own list overrides it.
func _voters() -> Array:
	return voters_fn.call() if voters_fn.is_valid() else []


## The head count dot-vote's thresholds use.
func _player_count() -> int:
	return int(player_count_fn.call()) if player_count_fn.is_valid() else _voters().size()


## A line dot-vote announces, in the game's words. Overridden by a game that has no rounds to speak of.
func _in_our_words(line: String) -> String:
	return line


## What a game adds to [method describe].
func _describe_extra() -> Dictionary:
	return {}


## Builds the source and the director. Fails when the default rules do not validate, never because there are too few maps.
func setup() -> DotResult:
	var problem := _rules().validate()

	if not problem.ok:
		return problem.wrap("The vote rules are not usable")

	source = _make_source()

	if source == null:
		return DotResult.fail(DotError.CODE_STATE, "There is nothing to vote for.")

	_build_director()
	_build_feed()
	return DotResult.success(self)


func _build_director() -> void:
	director = DotVoteDirector.new()
	director.name = director_name
	director.rules = configured_rules()
	director.source = source
	director.auto_apply = auto_apply
	# The host calls begin() whenever the world is built on a map, which a vote is one cause of and an operator's command another; both firing
	# would write one play into the history twice. See DotVoteDirector.begin_on_apply.
	director.begin_on_apply = false
	# The server's tick drives it, not the frame clock: a server that stalls should not lose that time off its map, a test runs an hour of one
	# in a millisecond, and both would otherwise run every clock twice as fast as it says.
	director.self_advance = false
	director.register_service = register_service

	director.player_count_fn = _player_count
	director.voters_fn = _voters
	director.is_admin_fn = func(voter: StringName) -> bool:
		return is_admin_fn.is_valid() and bool(is_admin_fn.call(voter))
	director.announce_fn = func(line: String) -> void:
		if announce_fn.is_valid():
			announce_fn.call(_in_our_words(line))

	_configure_director(director)
	add_child(director)

	director.vote_opened.connect(func(options: Array, seconds: float) -> void: vote_opened.emit(options, seconds))
	director.vote_closed.connect(func(result: DotVoteResult) -> void:
		DotLog.info(channel, "the %s vote closed" % noun, {"winner": String(result.winner_id), "votes": result.votes_cast})
		vote_closed.emit(result)
	)
	director.rocked.connect(func(voter: StringName, votes: int, needed: int) -> void: rocked.emit(voter, votes, needed))
	director.change_due.connect(func(id: StringName, choice: DotVoteChoice) -> void: change_due.emit(id, choice))
	director.cue.connect(func(id: StringName) -> void: cue_due.emit(id, 0, false))
	director.countdown_tick.connect(func(seconds_left: int, runoff: bool) -> void: cue_due.emit(&"", seconds_left, runoff))


func _build_feed() -> void:
	feed = DotVoteBallotFeed.of(director, func(state: Dictionary) -> void:
		if ballot_fn.is_valid():
			ballot_fn.call(state)
	)
	feed.title = "Vote for the next %s" % noun
	feed.command = command_names["vote"]
	feed.people_fn = func(voter: StringName) -> Dictionary:
		return people_fn.call(voter) if people_fn.is_valid() else {}


## [method _rules] under the server owner's layers. A layer that does not validate is refused whole, with the reason logged, and the defaults
## stand: loud and not fatal, because a server that refused to start over its vote file is one nobody can fix from a chat window.
func configured_rules() -> DotVoteRules:
	var rules := _rules()
	var loaded := rules.layer_over_defaults(
		config_path, DotVoteGameSource.running_game_metadata(metadata_key)
	)
	DotLog.result(channel, "the %s vote's rules" % noun, loaded)

	if drops_unfed:
		# No rounds and no score are fed, so an operator's `trigger: round_end` or a score limit would validate and then wait for ever.
		var dropped := rules.drop_unfed(false, false)

		if not dropped.is_empty():
			DotLog.error(channel, "settings this game cannot drive were taken out", {"dropped": ", ".join(dropped)})

	return rules


## Reads the map list again: on boot and whenever a map is built, because the maps a server holds (delivered packs, an operator's list)
## decide what it can offer. Only a list source has one.
func refresh_maps() -> void:
	if not (source is DotVoteListSource):
		return

	var list := source as DotVoteListSource
	list.entries.clear()

	if not maps_fn.is_valid():
		return

	for pair: Variant in maps_fn.call():
		var row: Array = pair
		var _added := list.add(DotVoteChoice.of(StringName(str(row[0])), str(row[1])))


## The world is on [param id] now (a vote, an operator, or the boot): the clock starts over and the history gains an entry.
func note_map(id: StringName) -> void:
	if director == null:
		return

	refresh_maps()

	if source is DotVoteListSource:
		(source as DotVoteListSource).current = id

	director.begin(id)


## One tick.
func advance(delta: float) -> void:
	if director == null:
		return

	director.advance(delta)

	if feed != null:
		feed.poll()

	_clock_time += delta

	# Sent when a client's own count would be wrong, not every second. Both ends count with [DotVoteClockView], so the server knows exactly
	# what every client is showing and only an extend, a new map or a stopped clock is worth a message.
	if clock_view.is_stale(director, _clock_time):
		clock_view.adopt(clock_state(), _clock_time)
		clock_due.emit(clock_view.to_state())


func clock_state() -> Dictionary:
	return DotVoteClockView.state_of(director)


func forget_voter(voter: StringName) -> void:
	if director != null:
		director.forget_voter(voter)


func is_voting() -> bool:
	return director != null and director.is_voting()


## dot-vote's commands on [param host]: `vote`, `rtv`, `nominate` and the operator's. Voters are the bare session id when
## [member bare_voter_ids], the same spelling [member voters_fn] lists; dot-vote's default is `u<userid>`, and two spellings of one voter is
## a player who rocks the vote twice.
func install_commands(host: Object) -> DotResult:
	if director == null:
		return DotResult.fail(DotError.CODE_STATE, "There is no vote to command.")

	commands = DotVoteCommands.new()
	commands.director = director
	commands.names = command_names.duplicate()
	commands.spec_fn = commands_spec_fn

	if bare_voter_ids:
		commands.voter_fn = func(ctx: Object) -> StringName:
			var session: Variant = ctx.get("session")

			if session is Object and (session as Object).get("userid") != null:
				return StringName(str((session as Object).get("userid")))

			return &"console"

	var bound := commands.bind(host)

	if feed != null:
		feed.command = commands.command_name("vote")

	return bound


func describe() -> Dictionary:
	var out := {}

	if source is DotVoteListSource:
		out[noun + "s"] = (source as DotVoteListSource).entries.size()

	out.merge(_describe_extra())
	out["director"] = director.describe() if director != null else {}
	return out


func describe_lines() -> PackedStringArray:
	return director.describe_lines() if director != null else PackedStringArray()
