extends "res://examples/selftest/selftest_base.gd"

## Selftest sections, part a.


func _test_subscribed_maps() -> void:
	_section("Subscribed maps join a list source for the current session only")
	var index := DotContentIndex.new()
	var pack := index.add_pack({
		"content_id": "someone/surf-pack", "version": "1.0.0", "prefix": "res://x/",
		"session": "solo", "source": "subscription",
		"provides": {"title": "Surf Pack", "entries": [
			{"kind": "map", "id": "surf_new", "name": "Surf New", "scene": "a.tscn", "map_kind": "surf"},
			{"kind": "map", "id": "bhop_new", "name": "Bhop New", "scene": "b.tscn", "map_kind": "bhop"},
			{"kind": "map", "id": "own_map", "name": "Pack Own", "scene": "c.tscn", "map_kind": "surf"},
			{"kind": "weapon", "id": "gun", "name": "Gun", "def": "g.tres"},
		]},
	})
	_check(pack.ok, "the fixture pack is indexed")

	var source := DotVoteListSource.new()
	source.add(DotVoteChoice.of(&"own_map", "Own Map"))
	_check(source.ids() == [&"own_map"], "a list that never opted in offers only its own")

	source.follow_content(index, PackedStringArray(["*"]))
	_check(source.has(&"surf_new") and source.has(&"bhop_new"), "solo: subscribed maps are offered")
	_check(not source.has(&"gun"), "a kind that is not a map is never offered")
	_check(source.find(&"surf_new").label() == "Surf New [Surf Pack]", "a delivered map is labelled with its pack")
	_check(source.find(&"own_map").label() == "Own Map" and source.find(&"own_map").pack_title == "",
		"and the existing id wins, bare")
	_check(source.ids().count(&"own_map") == 1, "a clashing id is offered once")

	var director := _make_director(DotVoteRules.new(), source)
	_check(director.ballot_name(source.find(&"surf_new")) == "Surf New [Surf Pack]",
		"a ballot prints the pack name")
	director.queue_free()

	source.follow_content(index, PackedStringArray(["surf"]))
	_check(source.has(&"surf_new") and not source.has(&"bhop_new"), "accepted kinds filter")
	source.follow_content(index, PackedStringArray())
	_check(source.ids() == [&"own_map"], "no accepted kinds means none")

	source.follow_content(index, PackedStringArray(["*"]))
	index.set_session(DotContentIndex.SESSION_ONLINE)
	_check(source.ids() == [&"own_map"], "online: no solo entry is ever offered")
	index.set_session(DotContentIndex.SESSION_SOLO)
	_check(source.has(&"surf_new"), "back in solo they return")

	index.tag_pack(&"someone/surf-pack", "1.0.0", DotContentIndex.SESSION_ONLINE)
	index.set_session(DotContentIndex.SESSION_ONLINE)
	_check(source.has(&"surf_new"), "a pack a server also requires is offered online")
	index.set_session(DotContentIndex.SESSION_SOLO)

	# The rotation filter and order cover the merged maps as they do the game's own.
	var listed := {&"own_map": true, &"bhop_new": true}
	source.in_rotation_fn = func(id: StringName) -> bool: return listed.has(id)
	source.rotation_order_fn = func() -> Array: return [&"bhop_new", &"own_map"]
	_check(source.ids() == [&"bhop_new", &"own_map"], "an unlisted pack map is off the list; the written order wins", str(source.ids()))
	var rot_director := _make_director(DotVoteRules.new(), source)
	rot_director.begin(&"own_map")
	_check(not rot_director.nominate(&"u1", &"surf_new").ok, "nominate refuses a pack map outside the rotation")
	_check(rot_director.nominate(&"u1", &"bhop_new").ok, "and takes one inside it")
	var drawn_ok := true
	for _i in 4:
		drawn_ok = drawn_ok and rot_director.next_in_rotation() != &"surf_new"
		rot_director.begin(rot_director.next_in_rotation())
	_check(drawn_ok, "the next-map draw never lands on it")
	rot_director.queue_free()
	source.in_rotation_fn = Callable()
	source.rotation_order_fn = Callable()
	_check(source.has(&"surf_new"), "with no rotation the pack map is offered again")

	source.unfollow_content()
	_check(source.ids() == [&"own_map"], "unfollowing removes them at once")
	_done()


func _test_describe() -> void:
	_section("The feed and the commands say what they are wired to")
	var feed := DotVoteBallotFeed.new()
	var d := feed.describe()
	_check(not bool(d["can_send"]) and not bool(d["director"]), "an unwired feed says it cannot send")
	_check(not bool(d["sent_anything"]), "and that it has sent nothing")
	feed.send_fn = func(_state: Dictionary) -> void: pass
	feed.title = "Pick"
	d = feed.describe()
	_check(bool(d["can_send"]) and d["title"] == "Pick", "a wired feed reports its sender and title")
	var commands := DotVoteCommands.new()
	commands.prefix = "!"
	d = commands.describe()
	_check(d["prefix"] == "!" and not bool(d["director"]), "the commands report their prefix and a missing director")
	_check((d["registered"] as Array).is_empty(), "and that nothing is registered yet")
	_done()


func _test_cfg_layout() -> void:
	_section("vote.yml: cfg/addons/dot_vote wins over the flat file, cfg/server/addons/dot_vote wins over both")

	var legacy := DATA.path_join("legacy_cfg")
	var addon_dir := "user://cfg/addons/dot_vote"
	var server_dir := "user://cfg/server/addons/dot_vote"
	DotPaths.remove_tree(addon_dir)
	DotPaths.remove_tree(server_dir)
	DotCfgLegacy.reset()

	_write_text(legacy.path_join("vote.yml"), "duration_sec: 900\nrtv_fraction: 0.4\n")
	var rules := DotVoteRules.new()
	var res := rules.load_cfg("vote.yml", legacy)
	_check(res.ok and is_equal_approx(rules.duration_sec, 900.0), "only the flat file: it is still read")
	_check(DotCfgLegacy.warned_count() == 1, "and warned once")
	DotVoteRules.new().load_cfg("vote.yml", legacy)
	_check(DotCfgLegacy.warned_count() == 1, "a second load does not warn again")

	_write_text(addon_dir.path_join("vote.yml"), "duration_sec: 1200\n")
	rules = DotVoteRules.new()
	res = rules.load_cfg("vote.yml", legacy)
	_check(
		res.ok and is_equal_approx(rules.duration_sec, 1200.0),
		"the new path wins over the flat file"
	)
	_check(
		is_equal_approx(rules.rtv_fraction, DotVoteRules.new().rtv_fraction),
		"and the two are never merged"
	)

	_write_text(server_dir.path_join("vote.yml"), "duration_sec: 1500\n")
	rules = DotVoteRules.new()
	res = rules.load_cfg("vote.yml", legacy)
	_check(res.ok and is_equal_approx(rules.duration_sec, 1500.0), "the operator's server layer wins")

	_write_text(addon_dir.path_join("vote.yml"), "duration_sec: 1200\nrtv_fraction: 0.5\n")
	rules = DotVoteRules.new()
	rules.load_cfg("vote.yml", legacy)
	_check(is_equal_approx(rules.rtv_fraction, 0.5), "a key only the addon layer sets still applies")

	DotPaths.remove_tree(addon_dir)
	DotPaths.remove_tree(server_dir)
	DotPaths.remove_tree(legacy)
	DotCfgLegacy.reset()
	_write_text("user://cfg/server/dot_vote/vote.yml", "duration_sec: 1700\n")
	rules = DotVoteRules.new()
	res = rules.load_cfg("vote.yml", legacy)
	_check(res.ok and is_equal_approx(rules.duration_sec, 1700.0), "the old cfg/server/dot_vote/ still loads")
	_check(DotCfgLegacy.warned_count() == 1, "and warns once")
	DotPaths.remove_tree("user://cfg/server/dot_vote")
	DotCfgLegacy.reset()
	_done()


func _test_rules_validate() -> void:
	_section("A configuration that could not work is refused at boot")

	var rules := DotVoteRules.new()
	_check(rules.validate().ok, "the shipped defaults validate")

	var reserved := DotVoteRules.new()
	reserved.max_options = 4
	reserved.nomination_slots = 6
	_check(
		not reserved.validate().ok,
		"reserving more places than the ballot has is refused",
		"every place would be reserved and nothing would ever be filled in"
	)

	var no_clock := DotVoteRules.new()
	no_clock.trigger = DotVoteRules.Trigger.TIME_LIMIT
	no_clock.duration_sec = 0.0
	no_clock.rtv_enabled = false
	_check(
		not no_clock.validate().ok,
		"a time-limit trigger with no time limit and no rock-the-vote is refused",
		"nothing would ever open a vote, silently"
	)

	var around_the_clock := DotVoteRules.new()
	around_the_clock.trigger = DotVoteRules.Trigger.TIME_LIMIT
	around_the_clock.duration_sec = 0.0
	_check(
		around_the_clock.validate().ok,
		"but no time limit WITH rock-the-vote validates: around the clock until the players ask",
		str(around_the_clock.validate().error.message if not around_the_clock.validate().ok else "")
	)

	var early := DotVoteRules.new()
	early.duration_sec = 120.0
	early.vote_lead_sec = 180.0
	_check(
		not early.validate().ok,
		"a lead longer than the limit is refused",
		"the ballot would open the instant the map started"
	)

	var late_rtv := DotVoteRules.new()
	late_rtv.duration_sec = 300.0
	late_rtv.rtv_delay_sec = 600.0
	_check(
		not late_rtv.validate().ok,
		"an rtv delay longer than the limit is refused",
		"rocking the vote would be refused for the whole of every map"
	)

	var dead := DotVoteRules.new()
	dead.trigger = DotVoteRules.Trigger.RTV_ONLY
	dead.rtv_enabled = false
	_check(
		not dead.validate().ok,
		"and so is rtv_only with rock-the-vote turned off"
	)

	_check(
		DotVoteRules.new().summary_lines().size() >= 6,
		"the rules summarise themselves for a console"
	)
	_check(
		DotVoteRules.new().describe_lines().size() >= 40,
		"and dump every key when asked in full"
	)

	_done()


func _test_history() -> void:
	_section("A cooldown stops the same three things being played for ever")

	var rules := _rules()
	rules.cooldown = 2
	rules.cooldown_max_fraction = 1.0

	var history := DotVoteHistory.of(rules)
	history.note_played(&"a", 0.0)
	history.note_played(&"b", 0.0)
	history.note_played(&"c", 0.0)

	_check(history.on_cooldown(&"c", 10), "the last thing played is on cooldown")
	_check(history.on_cooldown(&"b", 10), "and the one before it")
	_check(not history.on_cooldown(&"a", 10), "and the one before that is not")
	_check(history.plays_since(&"a") == 2, "how long ago is reportable")
	_check(history.times_played(&"a") == 1, "and so is how often")

	# dot-map's rotation learned this the hard way: a cooldown longer than the pool
	# excludes everything, and a rotation that offers nothing leaves the server where
	# it is for ever with no error anywhere.
	var deep := _rules()
	deep.cooldown = 8
	deep.cooldown_max_fraction = 0.5

	var small := DotVoteHistory.of(deep)
	for id in [&"a", &"b", &"c", &"d"]:
		small.note_played(id, 0.0)

	var excluded := 0
	for id in [&"a", &"b", &"c", &"d"]:
		if small.on_cooldown(id, 4):
			excluded += 1

	_check(
		excluded == 2,
		"a cooldown of 8 over a pool of 4 excludes 2, not 4 (excluded %d)" % excluded,
		"otherwise everything is on cooldown and the ballot is empty"
	)

	var per_choice := DotVoteChoice.of(&"d")
	per_choice.cooldown_override = 0
	_check(
		not small.on_cooldown(&"d", 4, -1.0, per_choice),
		"a choice can shorten its own cooldown"
	)

	var minutes := _rules()
	minutes.cooldown_mode = DotVoteRules.Cooldown.MINUTES
	minutes.cooldown_minutes = 30.0

	var timed := DotVoteHistory.of(minutes)
	timed.note_played(&"m", 1000.0)

	_check(timed.on_cooldown(&"m", 0, 1000.0), "a cooldown in minutes starts hot")
	_check(
		is_equal_approx(timed.cooldown_remaining(&"m", 1000.0), 1800.0),
		"and says how much is left (%.0f)" % timed.cooldown_remaining(&"m", 1000.0)
	)
	_check(not timed.on_cooldown(&"m", 0, 3000.0), "and cools off with the clock")
	_check(
		not timed.on_cooldown(&"never_played", 0, 1000.0),
		"something never played is never on cooldown"
	)

	var saved := DotVoteHistory.of(rules)
	saved.from_dictionary(history.to_dictionary())
	_check(
		saved.plays_since(&"a") == 2 and saved.times_played(&"a") == 1,
		"and history survives a save and a load"
	)

	_done()


func _test_quorum() -> void:
	_section("A vote three people noticed does not decide for thirty")

	var rules := _rules()
	rules.include_extend = false
	rules.quorum = 0.5

	var ballot := DotVoteBallot.of(rules)
	ballot.begin(_choices(["a", "b"]), 10)
	ballot.cast_vote(&"v1", _one(&"a"))
	ballot.cast_vote(&"v2", _one(&"a"))

	var result := ballot.resolve()
	_check(
		result.outcome == DotVoteResult.Outcome.NO_QUORUM,
		"two of ten is not a quorum of half"
	)
	_check(
		result.winner_id == &"a",
		"the leader is still reported, so the host can take it if it wants"
	)
	_check(
		is_equal_approx(result.turnout(), 0.2),
		"and the turnout is reported (%.0f%%)" % (result.turnout() * 100.0)
	)

	var met := DotVoteBallot.of(rules)
	met.begin(_choices(["a", "b"]), 4)
	met.cast_vote(&"v1", _one(&"a"))
	met.cast_vote(&"v2", _one(&"a"))
	_check(
		met.resolve().outcome == DotVoteResult.Outcome.WINNER,
		"and half of four is"
	)

	var nobody := DotVoteBallot.of(rules)
	nobody.begin(_choices(["a"]), 4)
	_check(
		nobody.resolve().outcome == DotVoteResult.Outcome.EMPTY,
		"nobody voting at all is EMPTY rather than a quorum failure",
		"an empty server is not a server that ignored a vote"
	)

	_done()


func _test_no_quorum_policies() -> void:
	_section("What a server does when too few people voted, three ways")

	for policy: Variant in [
		DotVoteRules.NoQuorum.KEEP,
		DotVoteRules.NoQuorum.WINNER_ANYWAY,
		DotVoteRules.NoQuorum.ROTATION,
	]:
		var applied := []
		var source := DotVoteListSource.of(_choices(["a", "b", "c"]))
		source.apply_fn = func(id: StringName) -> DotResult:
			applied.append(id)
			return DotResult.success(id)

		var rules := _rules()
		rules.quorum = 0.9
		rules.on_no_quorum = policy as DotVoteRules.NoQuorum
		rules.include_extend = false
		rules.vote_duration_sec = 5.0
		rules.duration_sec = 60.0
		rules.vote_lead_sec = 0.0
		rules.cooldown = 0
		rules.apply = DotVoteRules.Apply.IMMEDIATE

		var director := _make_director(rules, source)
		director.begin(&"a")
		source.current = &"a"

		director.open_vote()
		# Deliberately NOT the next in order: with the leader and the rotation's own
		# answer the same thing, ROTATION would pass for the wrong reason.
		director.cast_one(&"p1", &"c")

		for i in range(6):
			director.advance(1.0)

		match policy:
			DotVoteRules.NoQuorum.KEEP:
				_check(
					applied.is_empty() and director.current_id() == &"a",
					"KEEP stays where it is"
				)
				_check(
					not director.clock.is_expired(),
					"and restarts the clock, or the next tick opens another ballot"
				)
			DotVoteRules.NoQuorum.WINNER_ANYWAY:
				_check(
					applied.size() == 1 and applied[0] == &"c",
					"WINNER_ANYWAY takes the leader (%s)" % str(applied)
				)
			_:
				_check(
					applied.size() == 1 and applied[0] == &"b",
					"ROTATION ignores the ballot and takes the next in order (%s)"
						% str(applied),
					"the point of the setting is that a ballot too few voted in "
					+ "should not choose"
				)

		director.queue_free()

	_done()


func _test_score_limit() -> void:
	_section("A score limit ends a choice the way a frag limit does, and extends")

	var rules := _rules()
	rules.trigger = DotVoteRules.Trigger.SCORE_LIMIT
	rules.duration_sec = 0.0
	rules.score_limit = 30
	rules.vote_lead_score = 5
	rules.extend_score = 10

	_check(rules.validate().ok, "a score-limited server with no clock validates")

	var clock := DotVoteClock.of(rules)
	var due := []
	var moved := []
	clock.vote_due.connect(func(reason: StringName) -> void: due.append(reason))
	clock.score_limit_changed.connect(func(limit: int) -> void: moved.append(limit))
	clock.start()

	_check(not clock.note_score(24), "24 of 30 is nothing yet")
	_check(due.is_empty(), "and no ballot is due")

	clock.note_score(25)
	_check(
		due == [DotVoteClock.REASON_SCORE],
		"five short of the limit, the ballot is due, and says why"
	)
	_check(clock.note_score(30), "and reaching the limit ends it")
	_check(clock.is_expired(), "once")

	_check(clock.extend(), "a score-limited choice extends")
	_check(
		clock.score_limit == 40 and moved == [40],
		"by extend_score, and says so to a host enforcing its own limit (%d)"
			% clock.score_limit
	)
	_check(clock.timeleft_line().contains("30 of 40"), "and reports it", clock.timeleft_line())

	var source := DotVoteListSource.of(_choices(["a", "b"]))
	var director := _make_director(_rules(), source)
	director.rules.trigger = DotVoteRules.Trigger.SCORE_LIMIT
	director.rules.duration_sec = 0.0
	director.rules.score_limit = 20
	director.rules.vote_lead_score = 2
	director.rules.include_extend = false
	director.begin(&"a")
	director.note_score(18)

	_check(director.is_voting(), "the director opens the ballot off a reported score")

	director.queue_free()
	_done()


func _test_lead_fraction() -> void:
	_section("The ballot can open at a fraction of the limit rather than a fixed lead")

	var rules := _rules()
	rules.duration_sec = 100.0
	rules.vote_lead_sec = 5.0
	rules.vote_lead_fraction = 0.3
	rules.extend_seconds = 100.0

	var clock := DotVoteClock.of(rules)
	var due := []
	clock.vote_due.connect(func(_r: StringName) -> void: due.append(1))
	clock.start()

	for i in range(69):
		clock.advance(1.0)

	_check(due.is_empty(), "with 31 of 100 left nothing is due")

	clock.advance(1.0)
	_check(due.size() == 1, "with 30 of 100 left, a third of the limit, it is")

	clock.extend()
	_check(
		is_equal_approx(clock.lead_seconds(), 60.0),
		"and an extended limit is asked again at the same point of its new length (%.0f)"
			% clock.lead_seconds()
	)

	_done()


func _test_list_fn() -> void:
	_section("A list read from the host when a ballot opens reaches maps delivered after boot")

	var catalogue: Array = [["a", "Alpha"]]
	var source := DotVoteListSource.new()
	source.entries_fn = func() -> Array: return catalogue
	var director := _make_director(_manual_rules(), source)
	director.begin(&"a")
	source.current = &"a"

	_check(source.entries.size() == 1, "begin reads it: one map at boot")
	_check(
		not director.start_vote(DotVoteClock.REASON_MANUAL).ok and not director.is_voting(),
		"and one map is nothing to vote for"
	)

	catalogue.append(["b", "Bravo"])
	catalogue.append(DotVoteChoice.of(&"c", "Charlie"))
	catalogue.append(&"d")
	catalogue.append(["b", "Bravo again"])

	var opened := director.start_vote(DotVoteClock.REASON_MANUAL)
	var ids := director.ballot.option_ids()

	_check(
		opened.ok and director.is_voting(),
		"two maps delivered later: the next ballot opens without the game refreshing anything"
	)
	_check(
		ids.has(&"b") and ids.has(&"c") and ids.has(&"d"),
		"with the delivered maps on it, from pairs, choices and bare ids (%s)" % str(ids)
	)
	_check(
		source.entries.size() == 4 and source.find(&"b").display_name == "Bravo",
		"a repeated id is listed once, the first time"
	)

	# A broken function keeps the list there was.
	var broken := DotVoteListSource.of(_choices(["x", "y"]))
	broken.entries_fn = func() -> Variant: return null
	_check(
		not broken.refresh().ok and broken.entries.size() == 2,
		"a function that returns no list keeps the old one"
	)

	# reload() reads it too, for an operator's "reload the list".
	catalogue.remove_at(0)
	_check(
		source.reload().ok and not source.has(&"a"),
		"reload() reads the function, and a map taken away leaves the list"
	)

	# Unset, a list is what it always was.
	var plain := DotVoteListSource.of(_choices(["p", "q"]))
	plain.before_ballot()
	_check(
		plain.entries.size() == 2 and not plain.refresh().ok,
		"without a function, entries is the list and nothing re-reads it"
	)

	_done()


func _test_single_voter_auto() -> void:
	_section("An automatic ballot needs two voters; a manual one does not")

	var rules := _rules()
	rules.duration_sec = 600.0
	rules.vote_warning_sec = 0.0
	rules.vote_cooldown_sec = 0.0
	var director := _make_director(rules, DotVoteListSource.of(_choices(["a", "b", "c"])))
	director.begin(&"a")

	director.player_count_fn = func() -> int: return 1
	director.start_vote(DotVoteClock.REASON_TIME)
	_check(not director.is_voting(), "one human: the timed ballot is passed over")

	# A loading or ghost peer is a player but not a voter.
	director.player_count_fn = func() -> int: return 3
	director.voters_fn = func() -> Array: return [&"p1"]
	director.start_vote(DotVoteClock.REASON_TIME)
	_check(not director.is_voting(), "three sessions, one voter: passed over")

	director.player_count_fn = func() -> int: return 2
	director.start_vote(DotVoteClock.REASON_RTV)
	_check(not director.is_voting(), "a human and a bot: a passed rock-the-vote is passed over")

	director.voters_fn = func() -> Array: return [&"p1", &"p2"]
	director.start_vote(DotVoteClock.REASON_TIME)
	_check(director.is_voting(), "two voters: it opens")
	director.close_vote()

	director.voters_fn = func() -> Array: return [&"p1"]
	rules.allow_single_voter_auto = true
	var again := director.start_vote(DotVoteClock.REASON_TIME)
	_check(director.is_voting(), "allow_single_voter_auto: a lone voter gets the ballot", str(again.error))
	director.close_vote()

	rules.allow_single_voter_auto = false
	director.start_vote(DotVoteClock.REASON_MANUAL)
	_check(director.is_voting(), "a manual vote by a lone voter still opens")
	director.queue_free()

	_done()


## `end_vote`, `include_extend` and `extend_seconds`, each set through each of the four
## layers a game reads, change what a running director's ballot does.
func _test_every_layer_reaches_a_ballot() -> void:
	_section("Every config layer reaches a running ballot, the command line in a child process")

	var project := ProjectSettings.globalize_path("res://")
	var file_path := ProjectSettings.globalize_path(DATA + "/probe_vote.json")
	var _made := DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())

	var probe := func(extra: PackedStringArray, env: Dictionary) -> Dictionary:
		for key: String in env:
			OS.set_environment(key, env[key])
		var args := PackedStringArray([
			"--headless", "--path", project, "--script", "res://examples/layer_probe.gd", "--",
		])
		args.append_array(extra)
		var out := []
		var _code := OS.execute(OS.get_executable_path(), args, out, true)
		for key: String in env:
			OS.unset_environment(key)
		var found := {}
		for line: String in "\n".join(PackedStringArray(out)).split("\n"):
			var parsed: Variant = JSON.parse_string(line.strip_edges()) \
				if line.strip_edges().begins_with("{") else null
			if parsed is Dictionary:
				found = parsed
		return found

	var control: Dictionary = probe.call(PackedStringArray(), {})
	_check(
		control.get("opened") == true and control.get("extend_offered") == true
			and is_equal_approx(float(control.get("extended_by", -1.0)), 600.0),
		"with no layer, a ballot opens at the lead, offers Extend, and Extend adds 600 s",
		str(control)
	)

	# [setting, value as a layer writes it, what the ballot shows, what it should show]
	var cases := [
		["end_vote", "false", false, "opened", false],
		["include_extend", "false", false, "extend_offered", false],
		["extend_seconds", "90", 90, "extended_by", 90.0],
	]

	for case: Array in cases:
		var key: String = case[0]

		for layer in ["game.yml metadata", "the JSON file", "DOT_VOTE_*", "--vote-*"]:
			var extra := PackedStringArray()
			var env := {}

			match layer:
				"game.yml metadata":
					extra.append("--probe-meta-%s=%s" % [key, JSON.stringify(case[2])])
				"the JSON file":
					var f := FileAccess.open(file_path, FileAccess.WRITE)
					f.store_string(JSON.stringify({key: case[2]}))
					f.close()
					extra.append("--probe-file=" + file_path)
				"DOT_VOTE_*":
					env["DOT_VOTE_" + key.to_upper()] = case[1]
				"--vote-*":
					extra.append("--vote-%s=%s" % [key, case[1]])

			var got: Dictionary = probe.call(extra, env)
			var seen: Variant = got.get(case[3])
			var want: Variant = case[4]
			var same: bool = is_equal_approx(float(seen), float(want)) \
				if want is float else seen == want
			_check(
				got.get("layered") == true and same,
				"%s from %s: the ballot's %s is %s" % [key, layer, case[3], str(want)],
				str(got)
			)

	var _gone := DirAccess.remove_absolute(file_path)
	_done()


func _test_end_vote_switch() -> void:
	_section("The end-of-map vote is a switch, and off still ends the map")

	for trigger: Variant in [DotVoteRules.Trigger.TIME_LIMIT, DotVoteRules.Trigger.RTV_ONLY]:
		var applied := []
		var source := DotVoteListSource.of(_choices(["a", "b", "c"]))
		source.apply_fn = func(id: StringName) -> DotResult:
			applied.append(id)
			return DotResult.success(id)

		var rules := _rules()
		rules.trigger = trigger as DotVoteRules.Trigger
		rules.end_vote = trigger != DotVoteRules.Trigger.TIME_LIMIT
		rules.duration_sec = 100.0
		rules.vote_lead_sec = 20.0
		rules.cooldown = 0
		rules.apply = DotVoteRules.Apply.IMMEDIATE

		var director := _make_director(rules, source)
		director.begin(&"a")
		source.current = &"a"

		for i in range(90):
			director.advance(1.0)

		var label := "end_vote off" if trigger == DotVoteRules.Trigger.TIME_LIMIT \
			else "rtv_only"

		_check(
			not director.is_voting() and not director.end_vote_enabled(),
			"%s: no ballot opens when the lead is reached" % label,
			"rtv_only used to open one at the lead anyway, with a clock running"
		)

		for i in range(11):
			director.advance(1.0)

		_check(
			applied == [&"b"],
			"%s: and the map still ends, on the rotation (%s)" % [label, str(applied)]
		)

		director.queue_free()

	var default_director := _make_director(_rules(), DotVoteListSource.of(_choices(["a"])))
	_check(default_director.end_vote_enabled(), "and it is on by default")
	default_director.queue_free()

	_done()
