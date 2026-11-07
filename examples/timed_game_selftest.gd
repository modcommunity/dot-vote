extends Node

## Proves [DotVoteTimedGame], the vote every game on a clock copied: the ballot opens by dot-vote's own clock, the winner reaches the host,
## the director's signals and the clock reach the host's relay, and a game's names, rules and hooks shape it.
##
## [codeblock]
## godot --headless --path . res://examples/timed_game_selftest.tscn
## [/codeblock]

## A game's shim: names and rules only.
class _Game extends DotVoteTimedGame:
	func _init() -> void:
		channel = "toy.vote"
		noun = "mountain"
		command_names = {"vote": "pick"}

	func _rules() -> DotVoteRules:
		var rules := DotVoteRules.new()
		rules.trigger = DotVoteRules.Trigger.TIME_LIMIT
		rules.duration_sec = 600.0
		rules.vote_lead_sec = 60.0
		rules.vote_duration_sec = 25.0
		rules.apply = DotVoteRules.Apply.IMMEDIATE
		rules.include_extend = false
		rules.include_current = true
		return rules

## A game that uses every hook.
class _Hooked extends _Game:
	var seen: Array = []

	func _init() -> void:
		super._init()
		bare_voter_ids = false
		drops_unfed = false
		register_service = false

	func _configure_director(d: DotVoteDirector) -> void:
		d.round_based = true

	func _voters() -> Array:
		return [&"x", &"y"]

	func _in_our_words(line: String) -> String:
		return line.replace("round", "haul")

	func _describe_extra() -> Dictionary:
		return {"minutes": 10}


var _passed := 0
var _failed := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s" % what)


func _rig(maps: Array) -> Array:
	var game := _Game.new()
	var applied: Array = []
	game.maps_fn = func() -> Array: return maps
	game.apply_fn = func(id: StringName) -> DotResult:
		applied.append(id)
		return DotResult.success(id)
	game.voters_fn = func() -> Array: return [&"a", &"b", &"c"]
	game.content_index = DotContentIndex.new()
	add_child(game)
	var ready := game.setup()
	_check(ready.ok, "setup succeeds")
	game.note_map(&"m1")
	return [game, applied]


func _run() -> void:
	print("DotVoteTimedGame self-test")
	var maps := [["m1", "One"], ["m2", "Two"], ["m3", "Three"]]

	var rig := _rig(maps)
	var game: DotVoteTimedGame = rig[0]
	var applied: Array = rig[1]
	var opened: Array = []
	var closed: Array = []
	var changes: Array = []
	var clocks: Array = []
	game.vote_opened.connect(func(options: Array, _seconds: float) -> void: opened.append(options))
	game.vote_closed.connect(func(result: DotVoteResult) -> void: closed.append(result))
	game.change_due.connect(func(id: StringName, _choice: DotVoteChoice) -> void: changes.append(id))
	game.clock_due.connect(func(state: Dictionary) -> void: clocks.append(state))
	_check(game.feed.title == "Vote for the next mountain" and game.feed.command == "pick", "the game's noun and command name reach the feed")
	_check(game.source is DotVoteListSource and (game.source as DotVoteListSource).label == "mountains", "the source is a list labelled with the noun, pluralised")
	_check((game.source as DotVoteListSource).entries.size() == 3 and (game.source as DotVoteListSource).current == &"m1", "the host's maps are the entries and the map in play is current")
	_check(game.director.rules.trigger == DotVoteRules.Trigger.TIME_LIMIT and not game.director.self_advance and not game.director.begin_on_apply, "the game's rules; the host drives the clock")
	_check(not game.director.register_service and game.director.auto_apply, "no service registration, the winner applied by the director")

	game.advance(1.0)
	_check(not clocks.is_empty(), "the first tick sends the clock a client counts from")
	var sent := clocks.size()
	game.advance(1.0)
	_check(clocks.size() == sent, "and not every second after")

	game.advance(600.0 - 60.0 - 4.0)
	_check(not game.is_voting(), "no ballot before the lead")
	game.advance(3.0)
	_check(game.is_voting() and opened.size() == 1, "the ballot opens vote_lead_sec before the limit, by dot-vote's clock")
	var _c1 := game.director.cast_one(&"a", &"m2")
	var _c2 := game.director.cast_one(&"b", &"m2")
	var _c3 := game.director.cast_one(&"c", &"m3")
	game.advance(30.0)
	_check(closed.size() == 1 and (closed[0] as DotVoteResult).winner_id == &"m2", "the ballot closes on its own and plurality picks the winner")
	game.advance(60.0)
	_check(applied == [&"m2"] and changes == [&"m2"], "the limit applies the winner once, and change_due relays it: %s %s" % [applied, changes])

	# Commands: the bare session id.
	var host := Node.new()
	add_child(host)
	var bound := game.install_commands(host)
	_check(bound != null and game.commands != null and game.commands.voter_fn.is_valid(), "install_commands binds, with the bare session id as voter")
	var voter: StringName = game.commands.voter_fn.call(self)
	_check(voter == &"console", "a context with no session is the console")

	# describe
	var info := game.describe()
	_check(info.get("mountains") == 3 and info.has("director"), "describe counts the list under the noun and holds the director")

	# Hooks.
	var hooked := _Hooked.new()
	hooked.maps_fn = func() -> Array: return maps
	hooked.content_index = DotContentIndex.new()
	var lines: Array = []
	hooked.announce_fn = func(line: String) -> void: lines.append(line)
	add_child(hooked)
	var _ready := hooked.setup()
	_check(hooked.director.round_based, "_configure_director reaches the director")
	_check(hooked._player_count() == 2 and hooked.director.voters_fn.call() == [&"x", &"y"], "_voters is the head count and the director's voters")
	hooked.announce_fn.call("a round")
	hooked.director.announce_fn.call("when this round ends")
	_check(lines.has("when this haul ends"), "_in_our_words rewrites what dot-vote announces")
	var _bound := hooked.install_commands(host)
	_check(not hooked.commands.voter_fn.is_valid(), "bare_voter_ids off leaves dot-vote's own spelling")
	_check(hooked.describe().get("minutes") == 10, "_describe_extra joins describe")

	# Unfed settings are taken out of an operator's file by default.
	var path := "user://timed_selftest_vote.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"trigger": "round_end"}')
	f.close()
	var fed := _Game.new()
	fed.config_path = path
	var rules := fed.configured_rules()
	_check(rules.trigger != DotVoteRules.Trigger.ROUND_END, "drops_unfed takes a round-end trigger out of an operator's file")
	var kept := _Hooked.new()
	kept.config_path = path
	_check(kept.configured_rules().trigger == DotVoteRules.Trigger.ROUND_END, "a game that reports rounds keeps it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	fed.free()
	kept.free()

	var none := _Game.new()
	_check(not none.install_commands(self).ok, "no commands before setup")
	none.free()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
