extends "res://examples/selftest/tests_h.gd"

## Selftest sections, part i.

var _v_time_up_now: DotVoteDirector
var _v_time_up_held_applied: Array
var _v_time_up_held: DotVoteDirector
var _v_time_up_flat: DotVoteDirector
var _v_time_up_ended_applied: Array
var _v_time_up_ended: DotVoteDirector
var _v_time_up_ended_live: Array
var _v_time_up_capped: DotVoteDirector
var _v_time_up_late_applied: Array
var _v_time_up_late: DotVoteDirector
var _v_voter_names_said: Array[String]
var _v_voter_names_people: Callable
var _v_ballot_view_rules: DotVoteRules
var _v_ballot_view_director: DotVoteDirector
var _v_ballot_view_people: Callable
var _v_ballot_view_b_index: int


func _test_time_up() -> void:
	_section("When the time is up: change now, or play the round out")

	var defaults := DotVoteRules.new()
	_check(
		defaults.vote_lead_sec == 150.0 and defaults.duration_sec == 2700.0,
		"the ballot opens two and a half minutes before a forty-five-minute limit by default",
		"%.0f before %.0f" % [defaults.vote_lead_sec, defaults.duration_sec]
	)
	_check(
		defaults.time_up == DotVoteRules.TimeUp.CHANGE_NOW,
		"and the change happens the moment the time is up unless a server asks otherwise"
	)

	var layered := DotVoteRules.new()
	layered.apply_dictionary({"time_up": "finish_round", "finish_round_max_sec": 120, "ballot_input": "pointer"})
	_check(
		layered.time_up == DotVoteRules.TimeUp.FINISH_ROUND
			and layered.finish_round_max_sec == 120.0
			and layered.ballot_input == DotVoteRules.BallotInput.POINTER,
		"time_up and ballot_input are written by name in a file"
	)
	_check(
		"\n".join(layered.summary_lines()).contains("finish round, for at most 120s"),
		"and the summary says how long a round may hold the change",
		"\n".join(layered.summary_lines())
	)

	# The control: change now.
	var now_applied := []
	_v_time_up_now = _time_up_director(DotVoteRules.TimeUp.CHANGE_NOW, true, now_applied)
	_check(_v_time_up_now.pending_id() == &"b" and now_applied.is_empty(), "a winner is decided and waits for the clock")

	for i in range(40):
		_v_time_up_now.advance(1.0)

	_check(
		now_applied == [&"b"],
		"change_now: it changes the moment the time is up, mid-round", str(now_applied)
	)

	# Finish the round.
	_v_time_up_held_applied = []
	_v_time_up_held = _time_up_director(DotVoteRules.TimeUp.FINISH_ROUND, true, _v_time_up_held_applied)

	for i in range(40):
		_v_time_up_held.advance(1.0)

	_test_time_up_2()


func _test_time_up_2() -> void:
	_check(
		_v_time_up_held_applied.is_empty() and _v_time_up_held.is_finishing_round(),
		"finish_round: the time is up and the round in progress is played out", str(_v_time_up_held_applied)
	)
	_check(
		"\n".join(_v_time_up_held.describe_lines()).contains("finishing the round"),
		"and describe says so", "\n".join(_v_time_up_held.describe_lines())
	)

	for i in range(120):
		_v_time_up_held.advance(1.0)

	_check(_v_time_up_held_applied.is_empty(), "for as long as the round takes, with no cap set")

	_v_time_up_held.note_round_end()
	_v_time_up_held.advance(0.1)
	_check(
		_v_time_up_held_applied == [&"b"] and not _v_time_up_held.is_finishing_round(),
		"and the round ending is the change", str(_v_time_up_held_applied)
	)

	# No rounds to finish.
	var flat_applied := []
	_v_time_up_flat = _time_up_director(DotVoteRules.TimeUp.FINISH_ROUND, false, flat_applied)

	for i in range(40):
		_v_time_up_flat.advance(1.0)

	_check(
		flat_applied == [&"b"],
		"a host with no rounds has none to finish, and changes on time",
		"it would otherwise wait out the cap for a round end that never comes"
	)

	# A round-based game with no round live: warmup, waiting for players, between rounds.
	var live := [false]
	var warm_applied := []
	var warm := _time_up_director(DotVoteRules.TimeUp.FINISH_ROUND, true, warm_applied)
	warm.round_in_progress_fn = func() -> bool: return live[0]

	for i in range(40):
		warm.advance(1.0)

	_check(
		warm_applied == [&"b"] and not warm.is_finishing_round(),
		"a round-based game in warmup has no round to finish, and changes on time",
		"it held the change for finish_round_max_sec (for ever at 0): %s" % str(warm_applied)
	)

	_v_time_up_ended_applied = []
	_v_time_up_ended = _time_up_director(DotVoteRules.TimeUp.FINISH_ROUND, true, _v_time_up_ended_applied)
	_v_time_up_ended_live = [true]
	_v_time_up_ended.round_in_progress_fn = func() -> bool: return _v_time_up_ended_live[0]

	_test_time_up_3()


func _test_time_up_3() -> void:
	for i in range(40):
		_v_time_up_ended.advance(1.0)

	_check(
		_v_time_up_ended_applied.is_empty() and _v_time_up_ended.is_finishing_round(),
		"while the host says a round is live, finish_round still holds the change", str(_v_time_up_ended_applied)
	)

	_v_time_up_ended_live[0] = false
	_v_time_up_ended.advance(0.1)
	_check(
		_v_time_up_ended_applied == [&"b"],
		"and a round that stops being live without a round end (a reset to warmup) releases it",
		str(_v_time_up_ended_applied)
	)

	# The cap.
	var capped_applied := []
	_v_time_up_capped = _time_up_director(DotVoteRules.TimeUp.FINISH_ROUND, true, capped_applied, 30.0)

	for i in range(60):
		_v_time_up_capped.advance(1.0)

	_check(capped_applied.is_empty(), "a round may hold the change up to its cap")

	for i in range(15):
		_v_time_up_capped.advance(1.0)

	_check(
		capped_applied == [&"b"],
		"and not past it: a round that never ends cannot keep the map for ever", str(capped_applied)
	)

	# A ballot still open when the time runs out waits for the round too.
	_v_time_up_late_applied = []
	var late_source := DotVoteListSource.of(_choices(["a", "b"]))
	late_source.apply_fn = func(id: StringName) -> DotResult:
		_v_time_up_late_applied.append(id)
		return DotResult.success(id)
	var late_rules := _rules()
	late_rules.duration_sec = 100.0
	late_rules.vote_lead_sec = 0.0
	late_rules.vote_duration_sec = 10.0
	late_rules.include_extend = false
	late_rules.close_when_all_voted = false
	late_rules.apply = DotVoteRules.Apply.END_OF_TIME
	late_rules.time_up = DotVoteRules.TimeUp.FINISH_ROUND
	late_rules.finish_round_max_sec = 0.0
	late_rules.cooldown = 0
	_v_time_up_late = _make_director(late_rules, late_source)
	_v_time_up_late.round_based = true
	_v_time_up_late.begin(&"a")
	late_source.current = &"a"

	_test_time_up_4()


func _test_time_up_4() -> void:
	for i in range(101):
		_v_time_up_late.advance(1.0)

	_check(_v_time_up_late.is_voting(), "with no lead, the ballot opens when the time is up")
	_v_time_up_late.cast_one(&"p1", &"b")

	for i in range(20):
		_v_time_up_late.advance(1.0)

	_check(
		_v_time_up_late_applied.is_empty() and _v_time_up_late.pending_id() == &"b",
		"and its winner waits for the round in progress, not only a winner decided early"
	)
	_v_time_up_late.note_round_end()
	_v_time_up_late.advance(0.1)
	_check(_v_time_up_late_applied == [&"b"], "until it ends", str(_v_time_up_late_applied))

	# Around the clock.
	var forever_rules := _rules()
	forever_rules.duration_sec = 0.0
	forever_rules.rtv_delay_sec = 0.0
	forever_rules.rtv_min_players = 1
	forever_rules.rtv_fraction = 0.25
	var forever := _make_director(forever_rules, DotVoteListSource.of(_choices(["a", "b"])))
	forever.begin(&"a")

	for i in range(48):
		forever.advance(3600.0)

	_check(
		not forever.is_voting() and not forever.clock.is_expired(),
		"a limit of 0 runs for two days without a ballot"
	)
	forever.rock_the_vote(&"p1")
	_check(forever.is_voting(), "and a rock-the-vote still ends it")

	var zero_choice := _choices(["a", "b"])
	zero_choice[0].time_limit_sec = 0.0
	var per_choice := _make_director(_rules(), DotVoteListSource.of(zero_choice))
	per_choice.begin(&"a")
	per_choice.advance(100000.0)
	_check(
		not per_choice.clock.is_expired() and per_choice.clock.duration == 0.0,
		"and a choice's own time_limit_sec of 0 is around the clock under a server with a limit"
	)

	for d: DotVoteDirector in [_v_time_up_now, _v_time_up_held, _v_time_up_flat, _v_time_up_capped, _v_time_up_late, forever, per_choice]:
		d.queue_free()

	_done()


## Every line about a player names them. The director printed the voter id, so every game's
## chat read "[Server] u1 nominated Arena." while the ballot beside it drew the name.
func _test_voter_names() -> void:
	_section("A line about a player names the player, not their id")

	_v_voter_names_said = []
	_v_voter_names_people = func(voter: StringName) -> Dictionary:
		return {"name": "Alice", "avatar": ""} if voter == &"p1" else {}

	# No resolver: a host from before people_fn still works, and names the id.
	var bare := _rtv_director(_rules(), [])
	bare.announce_fn = func(line: String) -> void: _v_voter_names_said.append(line)
	bare.nominate(&"p1", &"b")
	_check(
		_v_voter_names_said.size() == 1 and _v_voter_names_said[0] == "p1 nominated B.",
		"without people_fn a nomination names the id, as before (%s)" % str(_v_voter_names_said)
	)
	bare.queue_free()

	var named := _rtv_director(_rules(), [])
	named.announce_fn = func(line: String) -> void: _v_voter_names_said.append(line)
	named.people_fn = _v_voter_names_people
	_v_voter_names_said.clear()
	named.nominate(&"p1", &"b")
	_check(
		_v_voter_names_said.size() == 1 and _v_voter_names_said[0] == "Alice nominated B.",
		"with people_fn a nomination names the player (%s)" % str(_v_voter_names_said),
		"chat said 'u1 nominated Arena.'"
	)
	_v_voter_names_said.clear()
	named.rock_the_vote(&"p1")
	_check(
		_v_voter_names_said.size() == 1 and _v_voter_names_said[0].begins_with("Alice wants a vote"),
		"so does rocking the vote (%s)" % str(_v_voter_names_said)
	)
	_v_voter_names_said.clear()
	named.nominate(&"p9", &"c")
	_check(
		_v_voter_names_said.size() == 1 and _v_voter_names_said[0] == "p9 nominated C.",
		"somebody people_fn has no name for falls back to their id (%s)" % str(_v_voter_names_said)
	)
	_check(
		named.display_name(&"p1") == "Alice" and named.display_name(&"zz") == "zz",
		"display_name is the name, or the id when there is none"
	)
	named.queue_free()

	_test_voter_names_2()


func _test_voter_names_2() -> void:
	# The feed's people_fn, which every host already set for the avatars, reaches the
	# director's lines without a second assignment.
	var fed := _rtv_director(_rules(), [])
	fed.announce_fn = func(line: String) -> void: _v_voter_names_said.append(line)
	var feed := DotVoteBallotFeed.of(fed, func(_state: Dictionary) -> void: pass)
	feed.people_fn = _v_voter_names_people
	_v_voter_names_said.clear()
	fed.nominate(&"p1", &"b")
	_check(
		fed.people_fn.is_valid() and _v_voter_names_said.size() == 1 and _v_voter_names_said[0] == "Alice nominated B.",
		"a feed's people_fn is handed to a director that has none (%s)" % str(_v_voter_names_said)
	)
	fed.queue_free()

	# A director that has its own keeps it: the feed only fills a gap.
	var own := _rtv_director(_rules(), [])
	own.announce_fn = func(line: String) -> void: _v_voter_names_said.append(line)
	own.people_fn = func(_voter: StringName) -> Dictionary: return {"name": "Bob"}
	var own_feed := DotVoteBallotFeed.of(own, func(_state: Dictionary) -> void: pass)
	own_feed.people_fn = _v_voter_names_people
	_v_voter_names_said.clear()
	own.nominate(&"p1", &"b")
	_check(
		_v_voter_names_said.size() == 1 and _v_voter_names_said[0] == "Bob nominated B.",
		"a director's own people_fn is not replaced by the feed's (%s)" % str(_v_voter_names_said)
	)
	own.queue_free()

	# And a feed with none draws the ballot's voters with the director's.
	var drawn_rules := _rules()
	drawn_rules.ballot_show_voters = true
	var drawn := _rtv_director(drawn_rules, [])
	drawn.people_fn = _v_voter_names_people
	var drawn_feed := DotVoteBallotFeed.of(drawn, func(_state: Dictionary) -> void: pass)
	drawn.start_vote()
	drawn.cast_one(&"p1", drawn.ballot.option_ids()[0] if drawn.ballot != null and not drawn.ballot.option_ids().is_empty() else &"a")
	var state := drawn_feed.current()
	_check(
		str((state.get("people", {}) as Dictionary).get("p1", {}).get("name", "")) == "Alice",
		"a feed without people_fn draws voters with the director's (%s)" % str(state.get("people", {}))
	)
	drawn.queue_free()

	_done()


func _test_ballot_view() -> void:
	_section("A ballot as a screen draws it: options, counts, who chose what, and how to choose")

	_v_ballot_view_rules = _rules()
	_v_ballot_view_rules.include_extend = false
	_v_ballot_view_rules.close_when_all_voted = false
	_v_ballot_view_rules.max_options = 3
	_v_ballot_view_rules.fill = DotVoteRules.Fill.SEQUENTIAL
	_v_ballot_view_director = _make_director(_v_ballot_view_rules, DotVoteListSource.of(_choices(["a", "b", "c", "d"])))
	_v_ballot_view_director.begin(&"d")

	_check(
		DotVoteBallotView.state_of(_v_ballot_view_director) == {"open": false},
		"no ballot is a closed one"
	)

	_v_ballot_view_director.start_vote()
	_v_ballot_view_director.cast_one(&"u1", &"b")
	_v_ballot_view_director.cast_one(&"u2", &"b")
	_v_ballot_view_director.cast_one(&"u3", &"a")

	_v_ballot_view_people = func(voter: StringName) -> Dictionary:
		return {"name": "player %s" % voter, "avatar": "https://example.invalid/%s.png" % voter}

	var state := DotVoteBallotView.state_of(_v_ballot_view_director, _v_ballot_view_people)
	var options: Array = state.get("options", [])
	var ids := options.map(func(o: Dictionary) -> String: return o["id"])
	_v_ballot_view_b_index = ids.find("b")

	_check(
		bool(state["open"]) and options.size() == 3,
		"an open ballot carries its options", str(ids)
	)
	_check(
		ids == _v_ballot_view_director.ballot.option_ids().map(func(id: StringName) -> String: return String(id)),
		"in the order a typed number indexes"
	)
	_check(
		_v_ballot_view_b_index >= 0 and float(options[_v_ballot_view_b_index]["votes"]) == 2.0,
		"with the counts", str(options)
	)
	_check(
		int(state["voters"]["u1"]) == _v_ballot_view_b_index and int(state["voters"]["u3"]) == ids.find("a"),
		"and who voted for what, by option index", str(state.get("voters"))
	)
	_check(
		str(state["people"]["u1"]["avatar"]).ends_with("u1.png"),
		"and who they are, from the host"
	)
	_check(
		state["input"] == "both" and float(state["seconds"]) > 0.0 and not bool(state["multi"]),
		"and how a player chooses, and how long they have", str(state)
	)

	_test_ballot_view_2()


func _test_ballot_view_2() -> void:
	_v_ballot_view_rules.ballot_show_voters = false
	var secret := DotVoteBallotView.state_of(_v_ballot_view_director, _v_ballot_view_people)
	_check(
		not secret.has("voters") and not secret.has("people") and secret["options"].size() == 3,
		"a secret ballot sends the counts and nobody's name"
	)
	_v_ballot_view_rules.ballot_show_voters = true

	# The feed.
	var sent := []
	var feed := DotVoteBallotFeed.of(_v_ballot_view_director, func(s: Dictionary) -> void: sent.append(s))
	feed.title = "Vote for the next map"
	feed.command = "votefor"
	feed.poll()
	_check(
		sent.size() == 1 and sent[0]["title"] == "Vote for the next map" and sent[0]["command"] == "votefor",
		"a feed sends the open ballot with its title and command", str(sent.size())
	)

	_v_ballot_view_director.advance(1.0)
	feed.poll()
	_check(sent.size() == 1, "and sends nothing while only the time changes", str(sent.size()))

	_v_ballot_view_director.cast_one(&"u3", &"b")
	feed.poll()
	_check(
		sent.size() == 2 and int(sent[1]["voters"]["u3"]) == _v_ballot_view_b_index,
		"a changed vote is sent, so the avatar moves"
	)

	_v_ballot_view_director.forget_voter(&"u3")
	feed.poll()
	_check(
		sent.size() == 3 and not sent[2]["voters"].has("u3"),
		"a voter who left is taken off the board, though forgetting them emits nothing"
	)

	_v_ballot_view_director.close_vote()
	feed.poll()
	_check(
		sent.size() == 4 and not bool(sent[3]["open"]) and sent[3].get("winner", "") == _v_ballot_view_director.option_label(&"b"),
		"closing sends what won, once", str(sent.back())
	)
	feed.poll()
	_check(sent.size() == 4, "and nothing after")

	var quiet := []
	var idle := DotVoteBallotFeed.of(_v_ballot_view_director, func(s: Dictionary) -> void: quiet.append(s))
	idle.poll()
	_check(quiet.is_empty(), "a feed that never saw a ballot has nothing to take down")

	_v_ballot_view_director.queue_free()
	_done()
