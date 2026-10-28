extends "res://examples/selftest/tests_b.gd"

## Selftest sections, part c.

var _v_admin_and_queries_director: DotVoteDirector
var _v_admin_and_queries_removed: Array
var _v_real_game_manager_server: Node
var _v_real_game_manager_descriptor_script: GDScript
var _v_real_game_manager_games: Object
var _v_real_game_manager_source: DotVoteGameSource
var _v_real_game_manager_director: DotVoteDirector
var _v_real_map_catalogue_catalogue: Object
var _v_real_map_catalogue_session: Node
var _v_real_map_catalogue_source: DotVoteMapSource
var _v_real_map_catalogue_rules: DotVoteRules
var _v_real_map_catalogue_director: DotVoteDirector


func _test_admin_and_queries() -> void:
	_section("Admins set, force and remove; everything can be asked")

	var source := DotVoteListSource.of(_choices(["a", "b", "c", "d", "e"]))
	var rules := _rules()
	rules.include_extend = false
	rules.nomination_slots = 0
	rules.cooldown = 2
	rules.cooldown_max_fraction = 1.0
	# Off, so what blocks a vote below is the thing being tested and not the cooldown
	# every closed ballot starts — a check that passes for the wrong reason is blind.
	rules.vote_cooldown_sec = 0.0

	_v_admin_and_queries_director = _make_director(rules, source)
	_v_admin_and_queries_removed = []
	_v_admin_and_queries_director.nomination_removed.connect(
		func(voter: StringName, id: StringName, reason: StringName) -> void:
			_v_admin_and_queries_removed.append([String(voter), String(id), String(reason)])
	)
	_v_admin_and_queries_director.begin(&"b")
	_v_admin_and_queries_director.begin(&"a")

	var nominatable := _v_admin_and_queries_director.nominatable_ids()
	_check(
		not nominatable.has(&"a") and not nominatable.has(&"b") and nominatable.has(&"c"),
		"what can be nominated leaves out what is running and what was just played"
	)
	_check(
		_v_admin_and_queries_director.excluded_ids().has(&"b"),
		"and what is excluded for having been played can be asked"
	)
	_check(_v_admin_and_queries_director.nomination_state() == DotVoteDirector.NominationState.YES, "nominating is open")

	_v_admin_and_queries_director.nominate(&"p1", &"c")
	_v_admin_and_queries_director.nominate(&"p1", &"d")
	_check(
		_v_admin_and_queries_removed.size() == 1 and _v_admin_and_queries_removed[0] == ["p1", "c", "replaced"],
		"replacing a nomination reports the one it replaced (%s)" % str(_v_admin_and_queries_removed)
	)

	_v_admin_and_queries_director.withdraw_nomination(&"p1", &"d")
	_check(
		_v_admin_and_queries_removed.size() == 2 and _v_admin_and_queries_removed[1][2] == "withdrawn",
		"and withdrawing one reports it"
	)

	_test_admin_and_queries_2()


func _test_admin_and_queries_2() -> void:
	_v_admin_and_queries_director.nominate(&"p2", &"c")
	_check(_v_admin_and_queries_director.remove_nomination(&"c") == 1, "an admin removes a nomination")
	_check(_v_admin_and_queries_removed[-1][2] == "admin", "and that is reported as an admin's")

	_v_admin_and_queries_director.nominate(&"p3", &"e")
	_v_admin_and_queries_director.forget_voter(&"p3")
	_check(
		_v_admin_and_queries_director.nominated_ids() == ([&"e"] as Array[StringName]),
		"a player leaving keeps their nomination by default"
	)
	_v_admin_and_queries_director.rules.nominations_forget_leavers = true
	_v_admin_and_queries_director.forget_voter(&"p3")
	_check(
		_v_admin_and_queries_director.nominated_ids().is_empty() and _v_admin_and_queries_removed[-1][2] == "voter_left",
		"or takes it with them when the server says so"
	)

	_v_admin_and_queries_director.rules.nominations_enabled = false
	_check(
		_v_admin_and_queries_director.nomination_state() == DotVoteDirector.NominationState.DISABLED,
		"nominations turned off say so"
	)
	_check(
		_v_admin_and_queries_director.force_nominate(&"d").ok,
		"and an admin can still put something on the next ballot"
	)
	_check(
		_v_admin_and_queries_director.nominated_list().size() == 1 and bool(_v_admin_and_queries_director.nominated_list()[0]["forced"]),
		"which is listed with who put it there"
	)
	_v_admin_and_queries_director.rules.nominations_enabled = true

	_check(_v_admin_and_queries_director.can_start_vote(), "a vote could start")
	_v_admin_and_queries_director.open_vote()
	_check(
		_v_admin_and_queries_director.ballot.option_ids().has(&"d"),
		"the forced choice is on the ballot even with no places reserved for nominations"
	)
	_check(
		_v_admin_and_queries_removed[-1][2] == "ballot",
		"and the ballot taking it is reported as the reason it came off the list"
	)
	_check(not _v_admin_and_queries_director.can_start_vote(), "and no other vote could start during it")
	_check(
		not _v_admin_and_queries_director.set_next(&"c").ok,
		"an admin cannot set what is next while the players are deciding it"
	)
	_v_admin_and_queries_director.close_vote()

	_test_admin_and_queries_3()


func _test_admin_and_queries_3() -> void:
	var busy := [true]
	_v_admin_and_queries_director.busy_fn = func() -> bool: return busy[0]
	_check(not _v_admin_and_queries_director.can_start_vote(), "another vote on screen blocks this one")

	var waited := _v_admin_and_queries_director.open_vote()
	_check(not waited.ok, "and opening refuses rather than stacking two menus")

	_v_admin_and_queries_director._vote_due_pending = true
	_v_admin_and_queries_director.advance(0.5)
	_check(not _v_admin_and_queries_director.is_voting(), "a due vote waits while the other one is up")

	busy[0] = false
	_v_admin_and_queries_director.advance(0.5)
	_check(_v_admin_and_queries_director.is_voting(), "and opens as soon as it is gone")
	_v_admin_and_queries_director.close_vote()

	# A host's own start_vote (a MANUAL game's round ballot) refused for the other vote is
	# owed too. It said "this one will follow it" and was dropped: a minigame opens its
	# round's ballot once, so the server's game vote on screen cost that round its ballot.
	busy[0] = true
	_v_admin_and_queries_director._cooldown_remaining = 0.0
	var asked := _v_admin_and_queries_director.start_vote(DotVoteClock.REASON_MANUAL)
	_v_admin_and_queries_director.advance(0.5)
	_check(
		not asked.ok and not _v_admin_and_queries_director.is_voting() and not _v_admin_and_queries_director.is_counting_down(),
		"a host's start_vote waits while another vote is up"
	)
	busy[0] = false
	_v_admin_and_queries_director.advance(0.5)
	_check(
		_v_admin_and_queries_director.is_voting() or _v_admin_and_queries_director.is_counting_down(),
		"and follows it without the host asking again",
		"refused for busy was dropped: a MANUAL game's round ballot never came"
	)
	_v_admin_and_queries_director.cancel_countdown()
	if _v_admin_and_queries_director.is_voting():
		_v_admin_and_queries_director.close_vote()

	var picked := _v_admin_and_queries_director.open_vote(DotVoteClock.REASON_MANUAL, [&"c", &"e", &"nonsense"] as Array[StringName])
	_check(
		picked.ok and _v_admin_and_queries_director.ballot.option_ids() == ([&"c", &"e"] as Array[StringName]),
		"an admin can hand-pick a ballot, and an unknown id is dropped rather than fatal"
	)
	_v_admin_and_queries_director.close_vote()

	_test_admin_and_queries_4()


func _test_admin_and_queries_4() -> void:
	_check(not _v_admin_and_queries_director.has_end_vote_finished(), "nothing is decided yet")
	_check(_v_admin_and_queries_director.set_next(&"c").ok, "an admin sets what is next")
	_check(
		_v_admin_and_queries_director.has_end_vote_finished() and _v_admin_and_queries_director.pending_id() == &"c",
		"which counts as the end-of-map vote having finished"
	)
	_check(
		_v_admin_and_queries_director.nomination_state() == DotVoteDirector.NominationState.VOTE_COMPLETE,
		"and closes nominations, which could no longer reach any ballot"
	)
	_check(
		_v_admin_and_queries_director.start_vote(DotVoteClock.REASON_MANUAL, true).ok and _v_admin_and_queries_director.is_voting(),
		"an admin's forced vote replaces the decision"
	)
	_v_admin_and_queries_director.close_vote()

	# A list read from a file re-reads it on request.
	var path := DATA.path_join("choices.json")
	var listed := DotVoteListSource.of(_choices(["x", "y"]))
	listed.save_json(path)

	var reloading := DotVoteListSource.new()
	reloading.load_json(path)
	var reloader := _make_director(_rules(), reloading)

	DotVoteListSource.of(_choices(["x", "y", "z"])).save_json(path)
	_check(
		reloader.reload().ok and reloading.choices().size() == 3,
		"an operator edits the list on disk and the reload reads it (%d)"
			% reloading.choices().size()
	)

	var full_rules := _rules()
	full_rules.nominations_max = 1
	var full := _make_director(full_rules, DotVoteListSource.of(_choices(["a", "b", "c"])))
	full.begin(&"a")
	full.nominate(&"p1", &"b")
	_check(
		full.nomination_state() == DotVoteDirector.NominationState.FULL,
		"and a full list says it is full"
	)

	_v_admin_and_queries_director.queue_free()
	reloader.queue_free()
	full.queue_free()
	_done()


## A real dot-server game manager, voted over and actually changed.
##
## [b]Nothing here names a dot-server class.[/b] Every object is built by loading its
## script and every field is set reflectively — which is not a trick to make the suite
## run without dot-server installed (though it does): it is exactly the path
## [DotVoteGameSource] takes, so this section fails if the duck typing is wrong, which
## is the only way it can be wrong.
func _test_real_game_manager() -> void:
	_section("A real dot-server game manager, voted over and actually changed")

	if not ResourceLoader.exists("res://addons/dot_server/server/dot_server.gd"):
		# Said out loud rather than skipped quietly. "0 failures" from a suite that ran
		# nothing is how a family ships two ends that never met.
		_check(
			false,
			"dot-server is present so the game vote can be run",
			"addons/dot_server is not linked; this integration is NOT covered"
		)
		_done()
		return

	var config_script: GDScript = load("res://addons/dot_server/server/dot_server_config.gd")
	var config: Object = config_script.new()
	config.set("hostname", "dot-vote self-test")
	config.set("port", 27531)
	config.set("max_players", 8)
	config.set("tickrate", 30)
	config.set("rcon_password", "dot-vote-selftest-rcon-password")
	config.set("a2s_enabled", false)
	config.set("query_enabled", false)
	config.set("hibernate_when_empty", false)
	config.set("admins_path", DATA.path_join("admins.json"))
	config.set("bans_path", DATA.path_join("bans.json"))
	config.set("audit_log_path", DATA.path_join("audit.jsonl"))
	# The addon ships a server.cfg the search path would find, which is correct
	# layering and would make this assert against whatever it contains.
	config.set("startup_config", "")
	config.set("autoexec_config", "")

	var server_script: GDScript = load("res://addons/dot_server/server/dot_server.gd")
	_v_real_game_manager_server = server_script.new()
	_v_real_game_manager_server.name = "Server"
	_v_real_game_manager_server.set("config", config)
	_v_real_game_manager_server.set("config_file", "")
	_v_real_game_manager_server.set("auto_boot", false)
	add_child(_v_real_game_manager_server)

	var booted: Variant = await _v_real_game_manager_server.call("boot")

	if not _check(
		booted is DotResult and (booted as DotResult).ok,
		"the server boots",
		str(booted)
	):
		_v_real_game_manager_server.queue_free()
		_done()
		return

	_v_real_game_manager_descriptor_script = load(
		"res://addons/dot_server/game/dot_game_descriptor.gd"
	)
	_v_real_game_manager_games = _v_real_game_manager_server.get("games")

	await _test_real_game_manager_2()


func _test_real_game_manager_2() -> void:
	for entry: Array in [["world_a", "World A", 1800], ["world_b", "World B", 60]]:
		var descriptor: Object = _v_real_game_manager_descriptor_script.new()
		descriptor.set("game_id", entry[0])
		descriptor.set("display_name", entry[1])
		descriptor.set("version", "1.0.0")
		descriptor.set("scene", "res://examples/fixtures/%s.tscn" % entry[0])
		# The per-game settings a vote reads, written beside the game rather than in a
		# table of ids somewhere else. This is what "each game has a time limit" is.
		descriptor.set("metadata", {"vote": {"time_limit_sec": entry[2], "weight": 2.0}})
		_v_real_game_manager_games.call("add_game", descriptor)

	var loaded: Variant = await _v_real_game_manager_games.call("change_game", "world_a", "boot")
	_check(
		loaded is DotResult and (loaded as DotResult).ok,
		"and loads a game",
		str(loaded)
	)

	# The real server's hibernation, followed through its signal and switched by its cvar.
	var follower := _make_director(_rules(), DotVoteListSource.of(_choices(["a", "b"])))
	follower.begin(&"a")
	_check(follower.follow_hibernation(_v_real_game_manager_server), "a real DotServer's hibernation can be followed")
	_check(not follower.hibernating, "and this one, booted with it off, is awake")
	_v_real_game_manager_server.get("console").call("execute", "sv_hibernate_when_empty 1")
	_check(follower.hibernating, "sv_hibernate_when_empty 1 on the empty server puts the vote's clock to sleep")
	_v_real_game_manager_server.get("console").call("execute", "sv_hibernate_when_empty 0")
	_check(not follower.hibernating, "and 0 wakes it")
	follower.queue_free()

	_v_real_game_manager_source = DotVoteGameSource.of(_v_real_game_manager_games)

	_check(_v_real_game_manager_source.is_usable(), "the game source recognises a real game manager")
	_check(_v_real_game_manager_source.choices().size() == 2, "and reads both games out of it")
	_check(
		_v_real_game_manager_source.current_id() == &"world_a",
		"and knows which one is running (%s)" % _v_real_game_manager_source.current_id(),
		"a source that cannot see the current game offers it on its own ballot"
	)

	var world_b := _v_real_game_manager_source.find(&"world_b")
	_check(
		world_b != null and is_equal_approx(world_b.time_limit_sec, 60.0),
		"a game's own time limit comes off its descriptor metadata"
	)
	_check(
		world_b != null and is_equal_approx(world_b.weight, 2.0),
		"and so does its weight"
	)
	_check(
		world_b != null and world_b.meta.has("descriptor"),
		"and the descriptor itself rides along, so a host need not look it up again"
	)

	var excluding := DotVoteGameSource.of(_v_real_game_manager_games)
	excluding.excluded = [&"world_a"] as Array[StringName]
	_check(
		excluding.choices().size() == 1,
		"a lobby can be kept off the ballot entirely"
	)

	await _test_real_game_manager_3()


func _test_real_game_manager_3() -> void:
	var rules := _rules()
	rules.duration_sec = 600.0
	rules.vote_lead_sec = 0.0
	rules.include_extend = false
	rules.vote_duration_sec = 5.0
	rules.cooldown = 0
	rules.min_players_to_vote = 1
	# Held until the clock runs out, so `apply_pending` below is what drives the real
	# `change_game` — which is a coroutine, and awaiting one through Object.call is
	# the assumption this whole integration rests on.
	rules.apply = DotVoteRules.Apply.END_OF_TIME

	_v_real_game_manager_director = _make_director(rules, _v_real_game_manager_source)
	_v_real_game_manager_director.begin(&"world_a")

	_check(
		is_equal_approx(_v_real_game_manager_director.clock.duration, 1800.0),
		"the running game's own limit is what the clock counts (%.0f)"
			% _v_real_game_manager_director.clock.duration,
		"a thirty-minute game and a one-minute game under one global limit is a "
		+ "server that cuts half its content short"
	)

	_v_real_game_manager_director.open_vote()
	_check(
		_v_real_game_manager_director.ballot.option_ids().has(&"world_b"),
		"the other game is on the ballot"
	)

	_v_real_game_manager_director.cast_one(&"p1", &"world_b")
	_v_real_game_manager_director.close_vote()

	_check(_v_real_game_manager_director.pending_id() == &"world_b", "and wins")

	var applied: DotResult = await _v_real_game_manager_director.apply_pending()

	_check(applied.ok, "the change goes through a real change_game", str(applied.error))
	_check(
		_v_real_game_manager_source.current_id() == &"world_b",
		"and the SERVER is now running the game the players voted for (%s)"
			% _v_real_game_manager_source.current_id(),
		"this is the join the whole addon exists for: a ballot that elects a winner "
		+ "and cannot make the server play it is the family's own 'two ends never met'"
	)
	_check(
		_v_real_game_manager_director.current_id() == &"world_b",
		"and the director followed it, so the new game's clock is running"
	)
	_check(
		is_equal_approx(_v_real_game_manager_director.clock.duration, 60.0),
		"under the NEW game's time limit (%.0f)" % _v_real_game_manager_director.clock.duration
	)

	# What a game's own map vote layers over its defaults: the running game's metadata,
	# found through the registry with nothing named. Duck typing that is wrong returns an
	# empty dictionary, which is indistinguishable from a game with nothing configured —
	# so it is asserted against a real manager rather than trusted.
	var running := DotVoteGameSource.running_game_metadata("vote")
	_check(
		int(running.get("time_limit_sec", 0)) == 60,
		"a game can read its own metadata off the running descriptor (%s)" % str(running),
		"the layer between a game's code defaults and its operator's file"
	)

	await _test_real_game_manager_4()


func _test_real_game_manager_4() -> void:
	# The console and chat commands, on the real console this server booted with.
	var replies := PackedStringArray()
	var console: Object = _v_real_game_manager_server.get("console")
	var commands := DotVoteCommands.install(console, _v_real_game_manager_director)

	_check(
		commands.registered.size() >= 12,
		"%d commands registered on a real console" % commands.registered.size()
	)
	_check(
		console.call("find_command", "rtv") != null,
		"including rtv"
	)
	_check(
		console.call("find_command", "timeleft") != null,
		"and timeleft"
	)

	var ctx_script: GDScript = load(
		"res://addons/dot_server/console/dot_cmd_context.gd"
	)
	var ctx: Object = ctx_script.new()
	ctx.set("reply_sink", func(text: String) -> void: replies.append(text))

	console.call("execute", "timeleft", ctx)
	_check(
		replies.size() == 1 and replies[0].contains("left"),
		"and `timeleft` answers with the clock (%s)"
			% (replies[0] if not replies.is_empty() else "nothing"),
		"a command registered and never reachable is the shape of half this "
		+ "file's reasons for existing"
	)

	replies.clear()
	console.call("execute", "nominate world_a", ctx)
	_check(
		not replies.is_empty(),
		"and `nominate` answers rather than failing silently",
		replies[0] if not replies.is_empty() else "nothing"
	)

	var setnext_command: Variant = console.call("find_command", "setnextmap")
	_check(
		setnext_command != null
			and str((setnext_command as Object).get("permission")) == "changemap",
		"the admin commands are there, behind the map flag an admin actually holds",
		"they asked for 'changelevel', which is a command and not a flag: root-only"
	)
	_check(
		console.call("find_command", "forcertv") != null
			and console.call("find_command", "nominate_addmap") != null
			and console.call("find_command", "votereload") != null,
		"including forcing a rock-the-vote, adding a nomination and reloading the list"
	)

	_real_game_manager_commands(console, _v_real_game_manager_director, _v_real_game_manager_source, ctx_script, ctx, replies, commands)

	_v_real_game_manager_director.queue_free()
	_v_real_game_manager_server.queue_free()
	await get_tree().process_frame

	_done()


## A real dot-map catalogue and session, voted over and actually changed.
func _test_real_map_catalogue() -> void:
	_section("A real dot-map catalogue, voted over and actually changed")

	if not ResourceLoader.exists("res://addons/dot_map/core/dot_map_catalogue.gd"):
		_check(
			false,
			"dot-map is present so the map vote can be run",
			"addons/dot_map is not linked; this integration is NOT covered"
		)
		_done()
		return

	var def_script: GDScript = load("res://addons/dot_map/core/dot_map_def.gd")
	var catalogue_script: GDScript = load(
		"res://addons/dot_map/core/dot_map_catalogue.gd"
	)
	_v_real_map_catalogue_catalogue = catalogue_script.new()

	for entry: Array in [
		["map_one", "Map One", "surf", 900],
		["map_two", "Map Two", "bhop", 0],
	]:
		var map: Object = def_script.new()
		map.set("id", StringName(entry[0]))
		map.set("display_name", entry[1])
		map.set("kind", StringName(entry[2]))
		map.set("version", "1.0.0")
		map.set("scene_path", "res://examples/fixtures/%s.tscn" % entry[0])
		map.set("expected_seconds", entry[3])
		_v_real_map_catalogue_catalogue.call("add", map)

	var session_script: GDScript = load(
		"res://addons/dot_map/runtime/dot_map_session.gd"
	)
	_v_real_map_catalogue_session = session_script.new()
	_v_real_map_catalogue_session.name = "Maps"
	_v_real_map_catalogue_session.set("catalogue", _v_real_map_catalogue_catalogue)
	_v_real_map_catalogue_session.set("world_ref", DotNodeRef.of_created(&"World", Node))
	add_child(_v_real_map_catalogue_session)
	await get_tree().process_frame

	# _ready builds its own empty catalogue when it finds none, so it goes back on
	# afterwards. The alternative is a catalogue_path, and a suite that writes a JSON
	# file to test an object it already has is testing the file.
	_v_real_map_catalogue_session.set("catalogue", _v_real_map_catalogue_catalogue)

	var first: Variant = await _v_real_map_catalogue_session.call("change_to", &"map_one")
	_check(
		first is DotResult and (first as DotResult).ok,
		"a real map loads",
		str(first)
	)

	_v_real_map_catalogue_source = DotVoteMapSource.of(_v_real_map_catalogue_catalogue, _v_real_map_catalogue_session)

	await _test_real_map_catalogue_2()


func _test_real_map_catalogue_2() -> void:
	_check(_v_real_map_catalogue_source.is_usable(), "the map source recognises a real catalogue")
	_check(_v_real_map_catalogue_source.choices().size() == 2, "and reads both maps out of it")
	_check(
		_v_real_map_catalogue_source.current_id() == &"map_one",
		"and knows which one is loaded (%s)" % _v_real_map_catalogue_source.current_id()
	)
	_check(_v_real_map_catalogue_source.supports_apply(), "and can change it, having been given a session")

	var one := _v_real_map_catalogue_source.find(&"map_one")
	_check(
		one != null and is_equal_approx(one.time_limit_sec, 900.0),
		"a map's expected length becomes its time limit",
		"a ten-minute bhop map and a forty-minute surf map under one global limit "
		+ "is a server that cuts half its maps short and empties on the rest"
	)
	_check(
		one != null and one.group == &"surf",
		"and its kind becomes its group, so a ballot can be filtered"
	)

	# maps.yml: a map outside the active rotation is installed but never on a ballot or a
	# nomination (the source reads DotMapDef.in_rotation, duck-typed).
	var off_map: Variant = _v_real_map_catalogue_catalogue.call("get_map", &"map_two")
	off_map.set("in_rotation", false)
	_check(
		_v_real_map_catalogue_source.choices().size() == 1 and _v_real_map_catalogue_source.find(&"map_two") == null and _v_real_map_catalogue_source.find(&"map_one") != null,
		"a map outside the map rotation is left out of the ballot and nominations"
	)
	off_map.set("in_rotation", true)

	var surf_only := DotVoteMapSource.of(_v_real_map_catalogue_catalogue, _v_real_map_catalogue_session)
	surf_only.kinds = [&"surf"] as Array[StringName]
	_check(
		surf_only.choices().size() == 1,
		"a surf-only server offers only surf maps",
		"the alternative is a second catalogue that is a subset of the first, "
		+ "which is two lists of maps that disagree"
	)

	_v_real_map_catalogue_rules = _rules()
	_v_real_map_catalogue_rules.duration_sec = 600.0
	_v_real_map_catalogue_rules.vote_lead_sec = 0.0
	_v_real_map_catalogue_rules.include_extend = false
	_v_real_map_catalogue_rules.cooldown = 0
	_v_real_map_catalogue_rules.min_players_to_vote = 1

	_v_real_map_catalogue_director = _make_director(_v_real_map_catalogue_rules, _v_real_map_catalogue_source)
	_v_real_map_catalogue_director.begin(&"map_one")

	_check(
		is_equal_approx(_v_real_map_catalogue_director.clock.duration, 900.0),
		"the loaded map's own limit is what the clock counts (%.0f)"
			% _v_real_map_catalogue_director.clock.duration
	)

	await _test_real_map_catalogue_3()


func _test_real_map_catalogue_3() -> void:
	_v_real_map_catalogue_director.open_vote()
	_v_real_map_catalogue_director.cast_one(&"p1", &"map_two")
	_v_real_map_catalogue_director.close_vote()

	var applied: DotResult = await _v_real_map_catalogue_director.apply_pending()

	_check(applied.ok, "the change goes through a real change_to", str(applied.error))
	_check(
		_v_real_map_catalogue_source.current_id() == &"map_two",
		"and the SESSION is now on the map the players voted for (%s)"
			% _v_real_map_catalogue_source.current_id()
	)
	_check(
		is_equal_approx(_v_real_map_catalogue_director.clock.duration, _v_real_map_catalogue_rules.duration_sec),
		"a map with no expected length falls back to the server's limit (%.0f)"
			% _v_real_map_catalogue_director.clock.duration
	)

	# Nobody on the server, hibernation off, and the limit runs out: the session moves to
	# the other map on its own, through the same real change_to a vote uses.
	var nobody := DotVoteRules.new()
	nobody.apply_delay_sec = 0.0
	nobody.duration_sec = 60.0
	nobody.vote_lead_sec = 10.0
	nobody.cooldown = 0
	var empty_director := _make_director(nobody, _v_real_map_catalogue_source)
	empty_director.player_count_fn = func() -> int: return 0
	empty_director.begin(&"map_two")

	for i in range(61):
		empty_director.advance(1.0)

	for i in range(5):
		await get_tree().process_frame

	_check(
		_v_real_map_catalogue_source.current_id() == &"map_one",
		"an empty server's limit changes the real session to another map (%s)" % _v_real_map_catalogue_source.current_id()
	)
	empty_director.queue_free()

	var listing_only := DotVoteMapSource.of(_v_real_map_catalogue_catalogue)
	_check(
		not listing_only.supports_apply(),
		"a source with no session lists and changes nothing"
	)
	_check(
		not (await listing_only.apply(&"map_two")).ok,
		"and says so rather than pretending"
	)

	_v_real_map_catalogue_director.queue_free()
	_v_real_map_catalogue_session.queue_free()
	await get_tree().process_frame

	_done()


## The command-resolution half of the real game manager section, split out for size.
func _real_game_manager_commands(
	console: Object, director: DotVoteDirector, source: DotVoteGameSource,
	ctx_script: GDScript, ctx: Object, replies: PackedStringArray,
	commands: DotVoteCommands
) -> void:
	# What a player types is resolved before it reaches the director. Arena's ids carry a
	# `map:` prefix nobody types; without resolve_fn a bare name is an id nothing has.
	var resolving := DotVoteCommands.new()
	resolving.director = director
	resolving.prefix = "t_"
	resolving.resolve_fn = func(text: String) -> StringName:
		return StringName("world_" + text)
	resolving.bind(console)

	console.call("execute", "t_unnominate a", ctx)
	_check(
		not director.nominated_ids().has(&"world_a"),
		"a bare name withdraws the nomination it resolves to"
	)
	console.call("execute", "t_nominate a", ctx)
	_check(
		director.nominated_ids().has(&"world_a"),
		"and nominates it, through resolve_fn (%s)" % str(director.nominated_ids()),
		"without it `a` is an id no source has, and the command refuses what a player typed"
	)

	var renamed := DotVoteCommands.new()
	renamed.director = director
	renamed.prefix = "sv_"
	renamed.names = {"rtv": "rockthevote"}
	_check(
		renamed.command_name("rtv") == "sv_rockthevote",
		"every command name is configurable (%s)" % renamed.command_name("rtv"),
		"dot-server already ships a `vote`, and a timer server's players type !rtv"
	)

	# Aliases, a file-supplied block, and a collision that is a skip and never a steal.
	var aliased := DotVoteCommands.new()
	aliased.director = director
	aliased.prefix = "al_"
	aliased.names = {"rtv": ["rockthevote", "rock"]}
	aliased.spec_fn = func() -> Dictionary:
		return {"names": {"timeleft": PackedStringArray(["left", "tl"])}}
	aliased.chat_prefix = "/"
	var aliased_bound := aliased.bind(console)
	_check(aliased_bound.ok and console.call("find_command", "al_rockthevote") != null
			and console.call("find_command", "al_rock") != null,
		"a role answers to its name and its aliases")
	_check(console.call("find_command", "al_left") != null and console.call("find_command", "al_tl") != null
			and console.call("find_command", "al_timeleft") == null,
		"a `commands:` block from spec_fn replaces the role's name")
	_check(aliased.command_name("rtv") == "al_rockthevote" and aliased.typed("rtv") == "/al_rockthevote",
		"help shows the first name behind the first chat prefix (%s)" % aliased.typed("rtv"))
	_check(Array(aliased.describe()["aliases"]["rtv"]) == ["al_rock"], "describe lists the aliases")

	var clashing := DotVoteCommands.new()
	clashing.director = director
	clashing.prefix = "al_"
	clashing.names = {"rtv": "rock", "nominate": ["nom", "sv_rtv"]}
	var rock_before: Object = console.call("find_command", "al_rock")
	clashing.bind(console)
	_check(console.call("find_command", "al_rock") == rock_before and clashing.skipped.has("al_rock"),
		"a name another command holds is skipped and the holder keeps it (%s)" % [clashing.skipped])
	_check(console.call("find_command", "al_nom") != null and not clashing.registered.has("al_rock"),
		"while its alias beside the clash still registers")

	# The map menu takes a rename, aliases and the collision check like the rest.
	var menu_named := DotVoteCommands.new()
	menu_named.director = director
	menu_named.prefix = "mm_"
	menu_named.names = {"mapmenu": ["menu", "mm"]}
	menu_named.bind(console)
	_check(console.call("find_command", "mm_menu") != null and console.call("find_command", "mm_mm") != null
			and console.call("find_command", "mm_mapmenu") == null,
		"mapmenu answers to its configured name and alias")
	var menu_clash := DotVoteCommands.new()
	menu_clash.director = director
	menu_clash.prefix = "mm_"
	menu_clash.names = {"mapmenu": ["menu"]}
	var menu_before: Object = console.call("find_command", "mm_menu")
	menu_clash.bind(console)
	_check(console.call("find_command", "mm_menu") == menu_before and menu_clash.skipped.has("mm_menu"),
		"and a mapmenu name another command holds is skipped, not stolen")

	# The reply to a vote names what the player saw on the ballot. It printed the id,
	# so a click on "Don't change" came back in chat as "Voted for __keep__.".
	var keep_rules := _rules()
	keep_rules.include_keep = true
	keep_rules.include_extend = false
	keep_rules.close_when_all_voted = false
	var keeper := _make_director(keep_rules, DotVoteListSource.of(_choices(["a", "b", "c"])))
	keeper.begin(&"c")
	keeper.start_vote()
	var keep_commands := DotVoteCommands.new()
	keep_commands.director = keeper
	keep_commands.prefix = "k_"
	keep_commands.bind(console)
	var keep_at := keeper.ballot.option_ids().find(DotVoteBallot.KEEP) if keeper.is_voting() else -1
	replies.clear()
	console.call("execute", "k_votefor %d" % (keep_at + 1), ctx)
	var keep_reply := replies[0] if not replies.is_empty() else "nothing"
	_check(
		keep_at >= 0 and keep_reply.contains("Don't change") and not keep_reply.contains("__"),
		"a vote's reply names the option's label, not its id (%s)" % keep_reply,
		"chat said 'Voted for __keep__.' after a click on Don't change"
	)
	keeper.queue_free()

	# The same for a nomination: it replied with the id, so a game ballot's nomination
	# came back as 'Nominated hungry_classic.' under 'u1 nominated Hungario: Classic.'.
	var nom_rules := _rules()
	nom_rules.include_extend = false
	var nominee := _make_director(nom_rules, DotVoteListSource.of(_choices(["big_bowl", "small_bowl", "x"])))
	nominee.begin(&"x")
	var nom_commands := DotVoteCommands.new()
	nom_commands.director = nominee
	nom_commands.prefix = "n_"
	nom_commands.bind(console)
	replies.clear()
	console.call("execute", "n_nominate big_bowl", ctx)
	var nom_reply := replies[0] if not replies.is_empty() else "nothing"
	_check(
		nom_reply.contains("Big Bowl") and not nom_reply.contains("big_bowl"),
		"a nomination's reply names the option's label, not its id (%s)" % nom_reply,
		"chat said 'Nominated hungry_classic.' for Hungario: Classic"
	)
	replies.clear()
	var admin_ctx: Object = ctx_script.new()
	admin_ctx.set("reply_sink", func(text: String) -> void: replies.append(text))
	admin_ctx.set("permissions", PackedStringArray(["changemap"]))
	console.call("execute", "n_nominate_addmap small_bowl", admin_ctx)
	var add_reply := replies[0] if not replies.is_empty() else "nothing"
	_check(
		add_reply.contains("Small Bowl") and not add_reply.contains("small_bowl"),
		"an admin's nominate_add names the label too (%s)" % add_reply
	)
	nominee.queue_free()
