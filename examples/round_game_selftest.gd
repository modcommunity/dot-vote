extends Node

## Proves [DotVoteRoundGame], the next-map vote every round-based game used to copy: the ballot opens once, in the last round only,
## applies at the round's end, waits out hibernation, and a game's names (channel, noun, kinds, commands) reach it.
##
## [codeblock]
## godot --headless --path . res://examples/round_game_selftest.tscn
## [/codeblock]

## A game's shim: names only.
class _Game extends DotVoteRoundGame:
	func _init() -> void:
		channel = "toy.vote"
		noun = "course"
		command_names = {"vote": "pick"}

	func _default_kinds() -> PackedStringArray:
		return PackedStringArray(["toy_map"])

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


func _rig(maps: Array, last_round := true) -> Array:
	var game := _Game.new()
	var applied: Array = []
	var voters: Array = [&"a", &"b", &"c"]
	game.maps_fn = func() -> Array: return maps
	game.apply_fn = func(id: StringName) -> DotResult:
		applied.append(id)
		return DotResult.success(id)
	game.voters_fn = func() -> Array: return voters
	game.due_fn = func() -> bool: return last_round
	game.content_index = DotContentIndex.new()
	add_child(game)
	var ready := game.setup()
	_check(ready.ok, "setup succeeds")
	game.note_map(&"m1")
	return [game, applied]


func _run() -> void:
	print("DotVoteRoundGame self-test")
	var maps := [["m1", "One"], ["m2", "Two"], ["m3", "Three"]]

	var rig := _rig(maps)
	var game: DotVoteRoundGame = rig[0]
	var applied: Array = rig[1]
	_check(game.feed.title == "Vote for the next course" and game.feed.command == "pick", "the game's noun and command name reach the feed")
	_check(game.source.entries.size() == 3, "the host's maps are the ballot's entries")
	_check(game.director.rules.trigger == DotVoteRules.Trigger.MANUAL and game.director.rules.apply == DotVoteRules.Apply.END_OF_ROUND, "defaults: opened by the game, applied at the round's end")

	game.advance(game.open_after_sec - 1.0)
	_check(not game.is_voting(), "no ballot before open_after_sec")
	game.advance(2.0)
	_check(game.is_voting(), "the ballot opens open_after_sec into the round")
	var _c1 := game.director.cast_one(&"a", &"m2")
	var _c2 := game.director.cast_one(&"b", &"m2")
	var _c3 := game.director.cast_one(&"c", &"m3")
	var closed := game.director.close_vote()
	_check(closed != null and closed.winner_id == &"m2", "plurality picks the winner")
	game.note_round_end()
	_check(applied == [&"m2"], "the winner is applied at the round's end, once: %s" % [applied])

	# Not the last round: due_fn holds the ballot back.
	rig = _rig(maps, false)
	game = rig[0]
	game.advance(game.open_after_sec + 5.0)
	_check(not game.is_voting(), "due_fn false: no ballot")

	# One map: nothing to choose.
	rig = _rig([["m1", "One"]])
	game = rig[0]
	game.advance(game.open_after_sec + 5.0)
	_check(not game.is_voting(), "one map and itself: no ballot")

	# A new round restarts the timer, and the ballot opens once per timer.
	rig = _rig(maps)
	game = rig[0]
	game.advance(game.open_after_sec - 1.0)
	game.note_round_start()
	game.advance(2.0)
	_check(not game.is_voting(), "a round start restarts the ballot timer")
	game.advance(game.open_after_sec)
	_check(game.is_voting(), "and it opens after a full timer")
	var _cancelled := game.director.cancel_vote()
	game.advance(game.open_after_sec)
	_check(not game.is_voting(), "a ballot opens once per map or round, not again")

	# Hibernation holds the timer.
	rig = _rig(maps)
	game = rig[0]
	game.director.hibernating = true
	game.advance(game.open_after_sec * 3.0)
	_check(not game.is_voting(), "a hibernating server counts no seconds")

	# The list grows on reload.
	rig = _rig([["m1", "One"]])
	game = rig[0]
	var more: Array = [["m1", "One"], ["m2", "Two"]]
	game.maps_fn = func() -> Array: return more
	game.refresh_maps()
	_check(game.source.entries.size() == 2, "refresh_maps reads the host's list again")

	var none := _Game.new()
	_check(not none.install_commands(self).ok, "no commands before setup")
	none.free()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
