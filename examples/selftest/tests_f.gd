extends "res://examples/selftest/tests_e.gd"

## Selftest sections, part f.

var _v_director_end_to_end_applied: Array
var _v_director_end_to_end_rules: DotVoteRules
var _v_director_end_to_end_director: DotVoteDirector
var _v_director_end_to_end_opened: Array
var _v_director_end_to_end_changed: Array
var _v_fill_modes_source: DotVoteListSource
var _v_fill_modes_director: DotVoteDirector
var _v_apply_moments_director: DotVoteDirector
var _v_apply_moments_delayed: DotVoteRules
var _v_chooser_settings_game: DotVoteRules
var _v_chooser_settings_layered: DotResult
var _v_countdown_rules: DotVoteRules
var _v_countdown_director: DotVoteDirector
var _v_countdown_ticks: Array
var _v_countdown_cues: Array
var _v_countdown_said: Array
var _v_countdown_stalled: DotVoteDirector
var _v_countdown_stalled_ticks: Array


func _test_director_end_to_end() -> void:
	_section("A whole vote: nominate, rock it, count it, and change what is running")

	_v_director_end_to_end_applied = []
	var source := DotVoteListSource.of(_choices(["alpha", "bravo", "charlie", "delta"]))
	source.apply_fn = func(id: StringName) -> DotResult:
		_v_director_end_to_end_applied.append(id)
		return DotResult.success(id)

	_v_director_end_to_end_rules = _rules()
	_v_director_end_to_end_rules.duration_sec = 100.0
	_v_director_end_to_end_rules.vote_lead_sec = 20.0
	_v_director_end_to_end_rules.vote_duration_sec = 10.0
	_v_director_end_to_end_rules.include_extend = false
	_v_director_end_to_end_rules.close_when_all_voted = false
	_v_director_end_to_end_rules.rtv_delay_sec = 0.0
	_v_director_end_to_end_rules.apply = DotVoteRules.Apply.IMMEDIATE

	_v_director_end_to_end_director = _make_director(_v_director_end_to_end_rules, source)

	_v_director_end_to_end_opened = []
	_v_director_end_to_end_changed = []
	_v_director_end_to_end_director.vote_opened.connect(func(options: Array, _s: float) -> void:
		_v_director_end_to_end_opened.append(options)
	)
	_v_director_end_to_end_director.change_due.connect(func(id: StringName, _c: DotVoteChoice) -> void:
		_v_director_end_to_end_changed.append(id)
	)

	_v_director_end_to_end_director.begin(&"alpha")
	source.current = &"alpha"

	_check(_v_director_end_to_end_director.current_id() == &"alpha", "the director knows what is running")
	_check(
		_v_director_end_to_end_director.history.plays_since(&"alpha") == 0,
		"and records it as played, so it goes on cooldown"
	)

	_test_director_end_to_end_2()


func _test_director_end_to_end_2() -> void:
	var nominated := _v_director_end_to_end_director.nominate(&"p1", &"delta")
	_check(nominated.ok, "a player nominates something", str(nominated.error))
	_check(
		not _v_director_end_to_end_director.nominate(&"p2", &"alpha").ok,
		"and cannot nominate what is already running",
		"'play this again' is what extending is for"
	)
	_check(
		not _v_director_end_to_end_director.nominate(&"p2", &"nonsense").ok,
		"nor something that does not exist"
	)

	for i in range(81):
		_v_director_end_to_end_director.advance(1.0)

	_check(_v_director_end_to_end_director.is_voting(), "the ballot opens 20 seconds before the end")
	_check(_v_director_end_to_end_opened.size() == 1, "and says so once")

	var options := _v_director_end_to_end_director.ballot.option_ids()
	_check(options.has(&"delta"), "the nomination is on it")
	_check(
		not options.has(&"alpha"),
		"and what is currently running is not",
		"having both it and 'extend' on a ballot splits the vote of the people "
		+ "who want the same thing"
	)
	_check(
		_v_director_end_to_end_director.nominations.size() == 0,
		"the nominations are consumed by the ballot rather than carried into the next"
	)

	_v_director_end_to_end_director.cast_one(&"p1", &"delta")
	_v_director_end_to_end_director.cast_one(&"p2", &"delta")
	_v_director_end_to_end_director.cast_one(&"p3", &"bravo")

	_check(_v_director_end_to_end_director.ballot.voter_count() == 3, "three of four vote")

	for i in range(11):
		_v_director_end_to_end_director.advance(1.0)

	_check(not _v_director_end_to_end_director.is_voting(), "the ballot closes on its own clock")
	_check(_v_director_end_to_end_changed.size() == 1 and _v_director_end_to_end_changed[0] == &"delta", "delta wins")
	_check(
		_v_director_end_to_end_applied.size() == 1 and _v_director_end_to_end_applied[0] == &"delta",
		"and the source is actually asked to play it",
		"a vote that elects a winner and cannot make the server play it is the "
		+ "family's own 'the two ends never met'"
	)
	_check(
		_v_director_end_to_end_director.current_id() == &"delta",
		"the director follows the change and restarts the clock"
	)
	_check(
		_v_director_end_to_end_director.clock.remaining > 95.0,
		"with a fresh clock (%.0f of 100)" % _v_director_end_to_end_director.clock.remaining
	)

	_test_director_end_to_end_3()


func _test_director_end_to_end_3() -> void:
	# Rocking the vote opens a ballot rather than changing blind.
	_v_director_end_to_end_director.rules.rtv_min_players = 2
	_v_director_end_to_end_director.rules.rtv_fraction = 0.5

	_v_director_end_to_end_director.rock_the_vote(&"p1")
	_check(not _v_director_end_to_end_director.is_voting(), "one of four is not enough to rock the vote")
	_v_director_end_to_end_director.rock_the_vote(&"p2")

	_check(
		not _v_director_end_to_end_director.is_voting(),
		"two of four passes it, but the last vote's cooldown is still running"
	)

	for i in range(int(_v_director_end_to_end_rules.vote_cooldown_sec) + 1):
		_v_director_end_to_end_director.advance(1.0)

	_check(
		_v_director_end_to_end_director.is_voting(),
		"and the ballot opens as soon as the cooldown is up",
		"the clock fires ONCE and latches, so a vote_due refused by the cooldown "
		+ "was the last one that would ever arrive and the server stopped changing"
	)

	# Everybody voting closes it early.
	_v_director_end_to_end_director.rules.close_when_all_voted = true
	_v_director_end_to_end_director.ballot.eligible = 2
	_v_director_end_to_end_director.cast_one(&"p1", _v_director_end_to_end_director.ballot.option_ids()[0])
	_v_director_end_to_end_director.cast_one(&"p2", _v_director_end_to_end_director.ballot.option_ids()[0])
	_v_director_end_to_end_director.advance(0.1)
	_check(
		not _v_director_end_to_end_director.is_voting(),
		"and a ballot everybody has voted in closes without waiting out the timer"
	)

	_v_director_end_to_end_director.queue_free()
	_done()


func _test_fill_modes() -> void:
	_section("Five ways to fill a ballot, and each fills it differently")

	_v_fill_modes_source = DotVoteListSource.of(_choices(["a", "b", "c", "d", "e", "f"]))

	var sequential := _rules()
	sequential.fill = DotVoteRules.Fill.SEQUENTIAL
	sequential.max_options = 2
	sequential.nomination_slots = 0
	sequential.cooldown = 0
	sequential.include_extend = false

	_v_fill_modes_director = _make_director(sequential, _v_fill_modes_source)
	_v_fill_modes_director.begin(&"")

	var first := _v_fill_modes_director.build_options(4)
	var second := _v_fill_modes_director.build_options(4)

	_check(
		first.size() == 2 and second.size() == 2,
		"SEQUENTIAL offers two at a time"
	)
	_check(
		first[0].id != second[0].id,
		"and moves on, so everything gets its turn (%s then %s)"
			% [first[0].id, second[0].id],
		"a cursor that never advances is a rotation that offers the same two for ever"
	)

	_v_fill_modes_director.rules.fill = DotVoteRules.Fill.LEAST_RECENTLY_PLAYED
	_v_fill_modes_director.history.note_played(&"a", 0.0)
	_v_fill_modes_director.history.note_played(&"b", 0.0)
	_v_fill_modes_director.rules.cooldown = 0

	var by_age := _v_fill_modes_director.build_options(4)
	_check(
		by_age[0].id != &"b",
		"LEAST_RECENTLY_PLAYED puts the most recently played last (%s)" % by_age[0].id
	)

	_v_fill_modes_director.rules.fill = DotVoteRules.Fill.WEIGHTED
	_v_fill_modes_director.rules.max_options = 1

	for choice in _v_fill_modes_source.entries:
		choice.weight = 0.0

	_v_fill_modes_source.entries[3].weight = 10.0

	var weighted := _v_fill_modes_director.build_options(4)
	_check(
		weighted.size() == 1 and weighted[0].id == &"d",
		"WEIGHTED never picks a weight of zero",
		"a weight of 0 means 'never offer this', not 'offer this last'"
	)

	for choice in _v_fill_modes_source.entries:
		choice.weight = 1.0

	_test_fill_modes_2()


func _test_fill_modes_2() -> void:
	_v_fill_modes_director.rules.fill = DotVoteRules.Fill.MOST_NOMINATED
	_v_fill_modes_director.rules.max_options = 3
	_v_fill_modes_director.rules.nomination_slots = 0
	_check(
		_v_fill_modes_director.nominations.add(&"p1", &"f").ok
			and _v_fill_modes_director.nominations.add(&"p2", &"f").ok,
		"two players can want the same thing, which is what a popularity fill counts"
	)
	_v_fill_modes_director.nominations.add(&"p3", &"e")
	_check(
		not _v_fill_modes_director.nominations.add(&"p1", &"f").ok,
		"and one player cannot want it twice"
	)

	var nominated := _v_fill_modes_director.build_options(4)
	_check(
		nominated[0].id == &"f",
		"MOST_NOMINATED puts the most-wanted first (%s)" % nominated[0].id
	)
	_v_fill_modes_director.nominations.clear()

	# Everything on cooldown must not produce an empty ballot.
	_v_fill_modes_director.rules.fill = DotVoteRules.Fill.RANDOM
	_v_fill_modes_director.rules.cooldown = 64
	_v_fill_modes_director.rules.cooldown_max_fraction = 1.0
	_v_fill_modes_director.rules.max_options = 4

	for id in [&"a", &"b", &"c", &"d", &"e", &"f"]:
		_v_fill_modes_director.history.note_played(id, 0.0)

	var desperate := _v_fill_modes_director.build_options(4)
	_check(
		not desperate.is_empty(),
		"everything on cooldown drops the cooldown rather than the ballot (%d)"
			% desperate.size(),
		"offering nothing leaves the server where it is for ever with no error anywhere"
	)

	# A choice nobody may play is not offered, whatever the fill.
	_v_fill_modes_director.rules.cooldown = 0
	_v_fill_modes_source.entries[0].enabled = false
	_v_fill_modes_source.entries[1].min_players = 20

	var filtered := _v_fill_modes_director.build_options(4)
	var filtered_ids := PackedStringArray()

	for choice in filtered:
		filtered_ids.append(String(choice.id))

	_check(
		not filtered_ids.has("a") and not filtered_ids.has("b"),
		"a disabled choice and one wanting twenty players are both left off"
	)

	_v_fill_modes_director.queue_free()
	_done()


func _test_apply_moments() -> void:
	_section("A winner waits for the moment the rules asked for")

	var applied := []
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

	_v_apply_moments_director = _make_director(rules, source)
	_v_apply_moments_director.begin(&"a")
	source.current = &"a"

	for i in range(61):
		_v_apply_moments_director.advance(1.0)

	_check(_v_apply_moments_director.is_voting(), "the ballot opens with 40 seconds left")
	_v_apply_moments_director.cast_one(&"p1", &"b")

	for i in range(6):
		_v_apply_moments_director.advance(1.0)

	_check(
		_v_apply_moments_director.pending_id() == &"b",
		"the winner is decided and waiting (%s)" % _v_apply_moments_director.pending_id()
	)
	_check(
		applied.is_empty(),
		"and END_OF_TIME has not changed anything yet",
		"the whole point of a lead is that the vote finishes before the time does"
	)

	for i in range(40):
		_v_apply_moments_director.advance(1.0)

	_check(
		applied.size() == 1 and applied[0] == &"b",
		"and the change happens when the clock runs out"
	)

	# The delay a player reads the result in.
	_v_apply_moments_delayed = _rules()
	_v_apply_moments_delayed.apply_delay_sec = 5.0
	_v_apply_moments_delayed.apply = DotVoteRules.Apply.IMMEDIATE
	_v_apply_moments_delayed.include_extend = false
	_v_apply_moments_delayed.vote_duration_sec = 1.0
	_v_apply_moments_delayed.duration_sec = 600.0
	_v_apply_moments_delayed.cooldown = 0

	_test_apply_moments_2()


func _test_apply_moments_2() -> void:
	var delayed_applied := []
	var delayed_source := DotVoteListSource.of(_choices(["a", "b"]))
	delayed_source.apply_fn = func(id: StringName) -> DotResult:
		delayed_applied.append(id)
		return DotResult.success(id)

	var slow := _make_director(_v_apply_moments_delayed, delayed_source)
	slow.begin(&"a")
	slow.open_vote()
	slow.cast_one(&"p1", &"b")
	slow.advance(1.1)

	_check(
		delayed_applied.is_empty() and slow.pending_id() == &"b",
		"an apply delay holds the change while the result is on screen"
	)

	slow.advance(5.0)
	_check(delayed_applied.size() == 1, "and then it happens")

	# Advisory mode: everything runs, nothing changes. What a client does.
	var advisory_source := DotVoteListSource.of(_choices(["a", "b"]))
	advisory_source.apply_fn = func(id: StringName) -> DotResult:
		return DotResult.success(id)

	var advisory_rules := _rules()
	advisory_rules.include_extend = false
	advisory_rules.vote_duration_sec = 1.0
	advisory_rules.duration_sec = 600.0
	advisory_rules.cooldown = 0
	advisory_rules.apply = DotVoteRules.Apply.IMMEDIATE

	var advisory := _make_director(advisory_rules, advisory_source)
	advisory.auto_apply = false

	var told := []
	advisory.change_due.connect(func(id: StringName, _c: DotVoteChoice) -> void:
		told.append(id)
	)

	advisory.begin(&"a")
	advisory.open_vote()
	advisory.cast_one(&"p1", &"b")
	advisory.advance(1.1)

	_check(told.size() == 1 and told[0] == &"b", "an advisory director still decides")
	_check(
		advisory.current_id() == &"a",
		"and does NOT pretend the change happened",
		"a client that decided what it was playing would be a client that cheats"
	)

	_v_apply_moments_director.queue_free()
	slow.queue_free()
	advisory.queue_free()
	_done()


#
# Features the long-standing community map-choosers have; docs/parity.md has the table,
# each section here is one row group of it, run rather than read.


func _test_chooser_settings() -> void:
	_section("The map-chooser settings layer, validate and format like every other")

	var rules := DotVoteRules.new()
	rules.apply_dictionary({
		"on_no_votes": "random",
		"rtv_apply": "end_of_time",
		"rtv_after_decided": "deny",
		"end_vote": "false",
		"vote_warning_sec": "15",
	}, "file")

	_check(
		rules.on_no_votes == DotVoteRules.NoVotes.RANDOM
			and rules.rtv_apply == DotVoteRules.Apply.END_OF_TIME
			and rules.rtv_after_decided == DotVoteRules.RtvAfterDecided.DENY,
		"the new enums are written by name like the old ones"
	)
	_check(
		not rules.end_vote and is_equal_approx(rules.vote_warning_sec, 15.0),
		"and the switch and the countdown read from text, as env and argv deliver them"
	)

	var no_score := DotVoteRules.new()
	no_score.trigger = DotVoteRules.Trigger.SCORE_LIMIT
	_check(
		not no_score.validate().ok,
		"a score-limit trigger with no score limit is refused",
		"nothing would ever start a vote"
	)

	var lead := DotVoteRules.new()
	lead.score_limit = 5
	lead.vote_lead_score = 5
	_check(
		not lead.validate().ok,
		"and a score lead as large as the limit is refused",
		"the ballot would open at the first point"
	)

	var whole := DotVoteRules.new()
	whole.vote_lead_fraction = 1.0
	_check(not whole.validate().ok, "and so is a lead fraction of the whole limit")

	# The layering a game's map vote uses: code defaults < the running game's metadata
	# < a file < DOT_VOTE_* < --vote-*. DotConfig.load_layered with one layer in front.
	DirAccess.make_dir_recursive_absolute(DATA)
	var path := DATA.path_join("map_vote.json")
	DotPaths.write_json(path, {"max_extends": 1, "method": "instant_runoff"})

	_v_chooser_settings_game = DotVoteRules.new()
	_v_chooser_settings_game.extend_seconds = 300.0
	_v_chooser_settings_game.max_extends = 5

	OS.set_environment("DOT_VOTE_VOTE_DURATION_SEC", "45")
	_v_chooser_settings_layered = _v_chooser_settings_game.layer_over_defaults(path, {"extend_seconds": 900, "max_extends": 2})
	OS.unset_environment("DOT_VOTE_VOTE_DURATION_SEC")

	_test_chooser_settings_2()


func _test_chooser_settings_2() -> void:
	_check(_v_chooser_settings_layered.ok, "a game's rules layer over its own defaults", str(_v_chooser_settings_layered.error))
	_check(
		is_equal_approx(_v_chooser_settings_game.extend_seconds, 900.0),
		"the game's metadata overrides its code (%.0f)" % _v_chooser_settings_game.extend_seconds
	)
	_check(
		_v_chooser_settings_game.max_extends == 1 and _v_chooser_settings_game.method == DotVoteRules.Method.INSTANT_RUNOFF,
		"the file overrides the metadata (%d)" % _v_chooser_settings_game.max_extends,
		"what an operator writes beside the server is later than what ships beside the game"
	)
	_check(
		is_equal_approx(_v_chooser_settings_game.vote_duration_sec, 45.0),
		"and the environment overrides the file (%.0f)" % _v_chooser_settings_game.vote_duration_sec
	)

	var broken_path := DATA.path_join("broken_vote.json")
	DotPaths.write_json(broken_path, {"trigger": "score_limit", "max_extends": 7})

	var guarded := DotVoteRules.new()
	guarded.max_extends = 3
	var refused := guarded.layer_over_defaults(broken_path)

	_check(not refused.ok, "a file whose settings contradict each other is refused")
	_check(
		guarded.max_extends == 3 and guarded.trigger == DotVoteRules.Trigger.TIME_LIMIT,
		"and the game keeps its own defaults rather than half of the file (%d)"
			% guarded.max_extends,
		"a vote whose rules contradict each other is a vote that never opens"
	)

	var marked := DotVoteRules.new()
	_check(
		marked.marked_name("Kitsune", false) == "*Kitsune"
			and marked.marked_name("Kitsune", true) == "Kitsune",
		"an unofficial choice is marked and an official one is not"
	)

	marked.unofficial_marker = " (custom)"
	_check(
		marked.marked_name("Kitsune", false) == "Kitsune (custom)",
		"a marker with no %s is appended"
	)

	marked.unofficial_marker = "100%s"
	_check(
		marked.marked_name("Kitsune", false) == "100Kitsune",
		"and a marker with a stray percent sign still formats",
		"GDScript's % hands back the unformatted string on a bad format, silently"
	)

	var cues := DotVoteRules.new()
	cues.cue_countdown = "vote.count.%d"
	_check(
		cues.countdown_cue_id(3) == "vote.count.3" and cues.countdown_cue_id(7) == "",
		"a countdown cue is templated, and only the listed seconds have one"
	)
	_check(
		DotVoteRules.new().countdown_cue_id(3) == "",
		"and with no cue configured nothing is asked for"
	)

	_done()


func _test_countdown() -> void:
	_section("A ballot can be counted down to, out loud and by the second")

	var source := DotVoteListSource.of(_choices(["a", "b", "c"]))
	_v_countdown_rules = _rules()
	_v_countdown_rules.vote_warning_sec = 5.0
	_v_countdown_rules.include_extend = false
	_v_countdown_rules.cooldown = 0
	_v_countdown_rules.cue_warning = "vote.warning"
	_v_countdown_rules.cue_vote_start = "vote.start"
	_v_countdown_rules.cue_vote_end = "vote.end"
	_v_countdown_rules.cue_countdown = "vote.count.%d"

	_v_countdown_director = _make_director(_v_countdown_rules, source)
	_v_countdown_director.begin(&"a")

	var started := []
	_v_countdown_ticks = []
	_v_countdown_cues = []
	_v_countdown_said = []
	_v_countdown_director.countdown_started.connect(
		func(seconds: float, runoff: bool) -> void: started.append([seconds, runoff])
	)
	_v_countdown_director.countdown_tick.connect(
		func(left: int, _runoff: bool) -> void: _v_countdown_ticks.append(left)
	)
	_v_countdown_director.cue.connect(func(id: StringName) -> void: _v_countdown_cues.append(String(id)))
	_v_countdown_director.announce_fn = func(line: String) -> void: _v_countdown_said.append(line)

	_check(_v_countdown_director.start_vote().ok, "a vote is started")
	_check(
		_v_countdown_director.is_counting_down() and not _v_countdown_director.is_voting(),
		"and counts down rather than opening at once"
	)
	_check(
		started.size() == 1 and not bool(started[0][1]),
		"announcing the countdown once, as a ballot and not a runoff"
	)
	_check(
		not _v_countdown_director.nominate(&"p1", &"b").ok
			and _v_countdown_director.nomination_state() == DotVoteDirector.NominationState.VOTE_IN_PROGRESS,
		"a nomination during the countdown is refused",
		"it would miss the ballot it is counting down to"
	)

	_test_countdown_2()


func _test_countdown_2() -> void:
	for i in range(4):
		_v_countdown_director.advance(1.0)

	_check(not _v_countdown_director.is_voting(), "four seconds in, the ballot is not open yet")

	_v_countdown_director.advance(1.0)

	_check(_v_countdown_director.is_voting(), "and at five it is")
	_check(
		_v_countdown_ticks == [5, 4, 3, 2, 1],
		"every second was ticked, from five down to one (%s)" % str(_v_countdown_ticks),
		"the ballot opening is the zero"
	)
	_check(
		_v_countdown_cues.has("vote.warning") and _v_countdown_cues.has("vote.count.3") and _v_countdown_cues.has("vote.start"),
		"the warning, the countdown and the ballot each asked for their cue (%s)"
			% ", ".join(PackedStringArray(_v_countdown_cues))
	)

	var countdown_lines := 0

	for line: Variant in _v_countdown_said:
		if str(line).contains("starts in") or str(line).ends_with("…"):
			countdown_lines += 1

	_check(
		countdown_lines == 1,
		"only the start of the countdown is announced by default (%d lines)"
			% countdown_lines,
		"fifteen chat lines in fifteen seconds bury everything else anybody said"
	)

	_v_countdown_director.close_vote()
	_check(_v_countdown_cues.has("vote.end"), "and closing the ballot asks for its cue")

	# A stall must not skip a number.
	_v_countdown_stalled = _make_director(_v_countdown_rules, DotVoteListSource.of(_choices(["a", "b"])))
	_v_countdown_stalled.begin(&"a")
	_v_countdown_stalled_ticks = []
	_v_countdown_stalled.countdown_tick.connect(
		func(left: int, _runoff: bool) -> void: _v_countdown_stalled_ticks.append(left)
	)
	_v_countdown_stalled.start_vote()
	_v_countdown_stalled.advance(3.5)
	_v_countdown_stalled.advance(2.0)

	_test_countdown_3()


func _test_countdown_3() -> void:
	_check(
		_v_countdown_stalled_ticks == [5, 4, 3, 2, 1] and _v_countdown_stalled.is_voting(),
		"a server that stalls for three seconds still counts every one (%s)"
			% str(_v_countdown_stalled_ticks),
		"a sound layer counting down should not skip from five to two"
	)

	# The runoff has its own, shorter countdown.
	var runoff_rules := _rules()
	runoff_rules.method = DotVoteRules.Method.MAJORITY_RUNOFF
	runoff_rules.max_runoffs = 1
	runoff_rules.include_extend = false
	runoff_rules.close_when_all_voted = false
	runoff_rules.cooldown = 0
	runoff_rules.runoff_warning_sec = 2.0

	var runoff := _make_director(runoff_rules, DotVoteListSource.of(_choices(["a", "b", "c"])))
	runoff.begin(&"")
	var runoff_started := []
	runoff.countdown_started.connect(
		func(_s: float, is_runoff: bool) -> void: runoff_started.append(is_runoff)
	)
	runoff.open_vote()
	runoff.cast_one(&"p1", &"a")
	runoff.cast_one(&"p2", &"b")
	runoff.cast_one(&"p3", &"c")
	runoff.close_vote()

	_check(
		runoff.is_counting_down() and runoff_started == [true],
		"a runoff is counted down to as a runoff"
	)

	runoff.advance(2.0)
	_check(
		runoff.is_voting() and runoff.ballot.runoffs_held == 1,
		"and then opens as one"
	)

	_v_countdown_director.queue_free()
	_v_countdown_stalled.queue_free()
	runoff.queue_free()
	_done()
