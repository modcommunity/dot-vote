extends Node

## The suite's harness: counters, [method _check], [method _section]; the test layers extend it.

const DATA := "user://dot_vote_selftest"

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


func _ban_rig(count: int) -> Array:
	var bans := DotVoteBans.new()
	var banned: Array = []
	var told: Array = []
	var ids: Array = []
	for i in range(count):
		ids.append(StringName("p%d" % i))
	bans.voters_fn = func() -> Array: return ids
	bans.role_fn = func(id: StringName) -> String: return "admin" if id == &"p0" else "player"
	bans.ban_fn = func(target: StringName, minutes: float, reason: String) -> void: banned.append([target, minutes, reason])
	bans.announce_fn = func(line: String) -> void: told.append(line)
	return [bans, banned, told]


## A console whose command line says `+sv_map_menu_flag anyone`.
class _ArgvConsole extends RefCounted:
	func command_line_statements() -> PackedStringArray:
		return PackedStringArray(["sv_tickrate 128", "sv_map_menu_flag \"anyone\""])


## A source with a reason for what it does not offer, as a game's would be.
class _ReasonSource extends DotVoteListSource:
	func unavailable_reason(id: StringName) -> String:
		return "%s cannot run here." % id


func _section(title: String) -> void:
	_entered += 1
	print("")
	print(title)


func _done() -> void:
	_completed += 1


func _check(condition: bool, what: String, detail: String = "") -> bool:
	if condition:
		_passed += 1
		print("  ok    %s" % what)
		return true

	_failed += 1
	_failures.append("%s%s" % [what, "  —  %s" % detail if detail != "" else ""])
	print("  FAIL  %s%s" % [what, "  —  %s" % detail if detail != "" else ""])
	return false


func _rules() -> DotVoteRules:
	var rules := DotVoteRules.new()
	# The suite drives every clock by hand, so nothing here should also be waiting on
	# a real one. Everything else stays at its shipped default deliberately: a suite
	# that configures its way around the defaults is a suite that never tests them.
	rules.apply_delay_sec = 0.0
	return rules


func _choices(ids: Array) -> Array[DotVoteChoice]:
	var out: Array[DotVoteChoice] = []

	for id: Variant in ids:
		out.append(DotVoteChoice.of(StringName(str(id)), str(id).capitalize()))

	return out


func _one(id: StringName) -> Array[StringName]:
	return [id] as Array[StringName]


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _make_director(rules: DotVoteRules, source: DotVoteSource) -> DotVoteDirector:
	var director := DotVoteDirector.new()
	director.rules = rules
	director.source = source
	# Off, because several directors exist at once in this suite and the registry
	# holds one — which is the reason the setting is there.
	director.register_service = false
	director.player_count_fn = func() -> int: return 4
	add_child(director)
	return director


func _rtv_director(rules: DotVoteRules, applied: Array) -> DotVoteDirector:
	var source := DotVoteListSource.of(_choices(["a", "b", "c"]))
	source.apply_fn = func(id: StringName) -> DotResult:
		applied.append(id)
		return DotResult.success(id)

	rules.duration_sec = 100.0
	rules.vote_lead_sec = 10.0
	rules.rtv_delay_sec = 0.0
	rules.rtv_fraction = 0.5
	rules.rtv_min_players = 2
	rules.vote_cooldown_sec = 0.0
	rules.close_when_all_voted = false
	rules.vote_duration_sec = 5.0
	rules.cooldown = 0

	var director := _make_director(rules, source)
	director.begin(&"a")
	source.current = &"a"
	return director


## What every MANUAL game did by hand until dot-vote opened a rocked ballot itself:
func _game_rtv_workaround(director: DotVoteDirector, attempts: Array) -> void:
	director.clock.expired.connect(func(reason: StringName) -> void:
		if reason != DotVoteClock.REASON_RTV or director.is_voting():
			return

		attempts.append(director.start_vote(DotVoteClock.REASON_RTV))
	)


func _manual_rules() -> DotVoteRules:
	var rules := _rules()
	rules.trigger = DotVoteRules.Trigger.MANUAL
	return rules


## Stands in for a dot-server [code]DotServer[/code]: the one signal and the one question
## [method DotVoteDirector.follow_hibernation] duck-types. The real one is followed in the
## real game manager's section.
class FakeHibernatingServer extends Node:
	signal hibernation_changed(hibernating: bool)

	var asleep := false

	func is_hibernating() -> bool:
		return asleep

	func sleep(on: bool) -> void:
		asleep = on
		hibernation_changed.emit(on)


func _history_after_one_play(rules: DotVoteRules, id: StringName) -> Dictionary:
	var history := DotVoteHistory.of(rules)
	history.note_played(id)
	return history.describe()


## A director on a server nobody is on, whose clock runs out. [param seed_value] seeds its
## draw; returns what it changed to.
func _empty_run(
	choice: DotVoteRules.EmptyChoice, ids: Array, seed_value: int, include_current: bool = false
) -> Array:
	var applied := []
	var source := DotVoteListSource.of(_choices(ids))
	source.apply_fn = func(id: StringName) -> DotResult:
		applied.append(id)
		return DotResult.success(id)

	var rules := _rules()
	rules.duration_sec = 100.0
	rules.vote_lead_sec = 20.0
	rules.empty_choice = choice
	rules.include_current = include_current

	# And no cooldown, which would otherwise keep what just played off the pool by itself.
	if include_current:
		rules.cooldown = 0

	var director := _make_director(rules, source)
	director.player_count_fn = func() -> int: return 0
	director.empty_rng = RandomNumberGenerator.new()
	director.empty_rng.seed = seed_value
	director.begin(&"a")
	source.current = &"a"

	for i in range(101):
		director.advance(1.0)

	director.queue_free()
	return applied


## A director whose clock runs out with a winner already decided, for the time_up checks.
func _time_up_director(
	time_up: DotVoteRules.TimeUp, round_based: bool, applied: Array, max_wait: float = 0.0
) -> DotVoteDirector:
	var source := DotVoteListSource.of(_choices(["a", "b"]))
	source.apply_fn = func(id: StringName) -> DotResult:
		applied.append(id)
		return DotResult.success(id)

	var rules := _rules()
	rules.duration_sec = 100.0
	rules.vote_lead_sec = 40.0
	rules.vote_duration_sec = 5.0
	rules.include_extend = false
	rules.apply = DotVoteRules.Apply.END_OF_TIME
	rules.cooldown = 0
	rules.time_up = time_up
	rules.finish_round_max_sec = max_wait

	var director := _make_director(rules, source)
	director.round_based = round_based
	director.begin(&"a")
	source.current = &"a"

	for i in range(61):
		director.advance(1.0)

	director.cast_one(&"p1", &"b")

	for i in range(6):
		director.advance(1.0)

	return director


func _read_scripts(directory: String, into: Dictionary) -> void:
	var dir := DirAccess.open(directory)

	if dir == null:
		return

	for name in dir.get_files():
		if name.ends_with(".gd"):
			var path := directory.path_join(name)
			into[path] = FileAccess.get_file_as_string(path)

	for name in dir.get_directories():
		_read_scripts(directory.path_join(name), into)


## Whether anything actually consults [param key].
func _reads_setting(key: String, sources: Dictionary, declarations: String) -> bool:
	var qualified := RegEx.new()
	qualified.compile("rules\\.%s\\b" % key)

	for path: Variant in sources:
		if qualified.search(str(sources[path])) != null:
			return true

	var bare := RegEx.new()
	bare.compile("\\b%s\\b" % key)

	for line in declarations.split("\n"):
		var text := line.strip_edges()

		if text.begins_with("@export") or text.begins_with("##"):
			continue

		if text.begins_with("\"%s\"" % key):
			# The ENUMS table, which names a key without reading it.
			continue

		if bare.search(text) != null:
			return true

	return false
