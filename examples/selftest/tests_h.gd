extends "res://examples/selftest/tests_g.gd"

## Selftest sections, part h.

var _v_rtv_parity_director: DotVoteDirector
var _v_rtv_parity_keeper: DotVoteDirector
var _v_rtv_parity_forward: Array
var _v_rtv_parity_bringer: DotVoteDirector
var _v_hibernation_rules: DotVoteRules
var _v_hibernation_director: DotVoteDirector
var _v_hibernation_server: FakeHibernatingServer
var _v_empty_server_ids: Array
var _v_empty_server_stayed: int
var _v_clock_view_view: DotVoteClockView
var _v_clock_view_director: DotVoteDirector


func _test_rtv_parity() -> void:
	_section("Rocking the vote: when it changes, the interval, and after a decision")

	# The winner of a rock-the-vote ballot can wait for the end of the map.
	var applied := []
	var rules := _rules()
	rules.rtv_apply = DotVoteRules.Apply.END_OF_TIME
	_v_rtv_parity_director = _rtv_director(rules, applied)

	for i in range(20):
		_v_rtv_parity_director.advance(1.0)

	_v_rtv_parity_director.rock_the_vote(&"p1")
	_v_rtv_parity_director.rock_the_vote(&"p2")

	_check(_v_rtv_parity_director.is_voting(), "two of four rock the vote and a ballot opens")
	_check(
		_v_rtv_parity_director.ballot.option_ids().has(DotVoteBallot.KEEP)
			and not _v_rtv_parity_director.ballot.option_ids().has(DotVoteBallot.EXTEND),
		"offering 'don't change' rather than 'extend'"
	)

	_v_rtv_parity_director.cast_one(&"p1", &"b")

	for i in range(5):
		_v_rtv_parity_director.advance(1.0)

	_check(
		_v_rtv_parity_director.pending_id() == &"b" and applied.is_empty(),
		"b wins and waits, because rtv_apply is end_of_time"
	)
	_check(
		_v_rtv_parity_director.clock.running and not _v_rtv_parity_director.clock.is_expired(),
		"with the clock running again, or the moment it waits for would never come"
	)
	_check(_v_rtv_parity_director.has_end_vote_finished(), "and what is next counts as decided")

	for i in range(80):
		_v_rtv_parity_director.advance(1.0)

	_check(
		applied == [&"b"],
		"and it changes when the clock runs out (%s)" % str(applied)
	)

	_test_rtv_parity_2()


func _test_rtv_parity_2() -> void:
	# "Don't change" on a rock-the-vote ballot carries on where the clock was.
	var kept := []
	var keep_rules := _rules()
	keep_rules.rtv_interval_sec = 30.0
	_v_rtv_parity_keeper = _rtv_director(keep_rules, kept)

	for i in range(40):
		_v_rtv_parity_keeper.advance(1.0)

	_v_rtv_parity_keeper.rock_the_vote(&"p1")
	_v_rtv_parity_keeper.rock_the_vote(&"p2")
	_v_rtv_parity_keeper.cast_one(&"p1", DotVoteBallot.KEEP)

	for i in range(5):
		_v_rtv_parity_keeper.advance(1.0)

	_check(
		kept.is_empty() and not _v_rtv_parity_keeper.is_voting(),
		"'don't change' changes nothing"
	)
	_check(
		_v_rtv_parity_keeper.clock.remaining > 50.0 and _v_rtv_parity_keeper.clock.remaining < 61.0,
		"and the clock carries on from where it was, not from the top (%.0f left)"
			% _v_rtv_parity_keeper.clock.remaining,
		"restarting it would give an unpopular map a fresh limit for being voted on"
	)

	var again := _v_rtv_parity_keeper.rock_the_vote(&"p1")
	_check(
		not again.ok and again.code() == DotError.CODE_RATE_LIMITED,
		"and rocking the vote is refused for the interval after",
		str(again.error)
	)

	for i in range(31):
		_v_rtv_parity_keeper.advance(1.0)

	_check(_v_rtv_parity_keeper.rock_the_vote(&"p1").ok, "and allowed again once it has passed")

	# After a decision, rocking the vote brings it forward.
	_v_rtv_parity_forward = []
	var forward_rules := _rules()
	_v_rtv_parity_bringer = _rtv_director(forward_rules, _v_rtv_parity_forward)
	_v_rtv_parity_bringer.set_next(&"c")

	_test_rtv_parity_3()


func _test_rtv_parity_3() -> void:
	_check(_v_rtv_parity_forward.is_empty(), "an admin sets what is next, and nothing changes yet")

	_v_rtv_parity_bringer.rock_the_vote(&"p1")
	_v_rtv_parity_bringer.rock_the_vote(&"p2")

	_check(
		_v_rtv_parity_forward == [&"c"],
		"and a passed rock-the-vote changes to it now (%s)" % str(_v_rtv_parity_forward)
	)

	var denied := []
	var deny_rules := _rules()
	deny_rules.rtv_after_decided = DotVoteRules.RtvAfterDecided.DENY
	var denier := _rtv_director(deny_rules, denied)
	denier.set_next(&"c")

	_check(
		not denier.rock_the_vote(&"p1").ok,
		"or is refused, when the server says a decision stands"
	)

	# An admin's forced rock-the-vote.
	var forced := []
	var forcer := _rtv_director(_rules(), forced)
	_check(forcer.force_rtv().ok and forcer.is_voting(), "an admin can rock the vote alone")

	var forced_after := []
	var decided := _rtv_director(_rules(), forced_after)
	decided.set_next(&"b")
	decided.force_rtv()
	decided.advance(0.1)
	_check(
		forced_after == [&"b"],
		"and with the next already decided, that brings it forward (%s)" % str(forced_after)
	)

	_v_rtv_parity_director.queue_free()
	_v_rtv_parity_keeper.queue_free()
	_v_rtv_parity_bringer.queue_free()
	denier.queue_free()
	forcer.queue_free()
	decided.queue_free()
	_done()


func _test_hibernation() -> void:
	_section("A hibernating server's clock waits, and starts again from the top when somebody joins")

	var applied := []
	var source := DotVoteListSource.of(_choices(["a", "b", "c"]))
	source.apply_fn = func(id: StringName) -> DotResult:
		applied.append(id)
		return DotResult.success(id)

	_v_hibernation_rules = _rules()
	_v_hibernation_rules.duration_sec = 100.0
	_v_hibernation_rules.vote_lead_sec = 20.0
	_v_hibernation_rules.apply = DotVoteRules.Apply.IMMEDIATE

	_check(_v_hibernation_rules.wake_restart, "waking starts the clock again by default")

	_v_hibernation_director = _make_director(_v_hibernation_rules, source)
	_v_hibernation_director.begin(&"a")
	source.current = &"a"

	_v_hibernation_server = FakeHibernatingServer.new()
	add_child(_v_hibernation_server)
	_check(_v_hibernation_director.follow_hibernation(_v_hibernation_server), "a server with hibernation_changed is followed")
	var plain := Node.new()
	_check(not _v_hibernation_director.follow_hibernation(plain), "and an object without it is not")
	plain.free()

	for i in range(30):
		_v_hibernation_director.advance(1.0)

	_v_hibernation_director.rock_the_vote(&"p1")
	_v_hibernation_director.extend(10.0)
	var before := _v_hibernation_director.clock.remaining

	_v_hibernation_server.sleep(true)
	_check(_v_hibernation_director.hibernating, "the server going to sleep reaches the director")

	for i in range(3600):
		_v_hibernation_director.advance(1.0)

	_check(
		is_equal_approx(_v_hibernation_director.clock.remaining, before),
		"an hour asleep does not move the clock (%.0f left, was %.0f)" % [_v_hibernation_director.clock.remaining, before],
		"the clock used to run on through an empty room and hand the first player a map with a minute left"
	)
	_check(
		not _v_hibernation_director.is_voting() and not _v_hibernation_director.clock.is_expired() and applied.is_empty(),
		"and opens no ballot and changes nothing"
	)

	_test_hibernation_2()


func _test_hibernation_2() -> void:
	_v_hibernation_server.sleep(false)
	_check(not _v_hibernation_director.hibernating, "the first player in wakes it")
	_check(
		is_equal_approx(_v_hibernation_director.clock.remaining, 100.0),
		"to the configured limit, not what was left (%.0f)" % _v_hibernation_director.clock.remaining
	)
	_check(
		_v_hibernation_director.clock.extends_used == 0 and _v_hibernation_director.clock.rtv_votes() == 0,
		"with every extend back and nobody's rock-the-vote carried over"
	)
	_check(
		_v_hibernation_director.history.describe() == _history_after_one_play(_v_hibernation_rules, &"a"),
		"and no second entry in the history, which would shorten every cooldown"
	)

	for i in range(10):
		_v_hibernation_director.advance(1.0)

	_check(is_equal_approx(_v_hibernation_director.clock.remaining, 90.0), "and it counts again once awake")

	# A server already asleep when the vote is built is followed from where it is.
	var asleep_server := FakeHibernatingServer.new()
	asleep_server.asleep = true
	add_child(asleep_server)
	var late := _make_director(_rules(), DotVoteListSource.of(_choices(["a", "b"])))
	late.begin(&"a")
	late.follow_hibernation(asleep_server)
	_check(late.hibernating, "a director following a server that is already asleep starts asleep")

	# wake_restart off resumes rather than restarts.
	var resume_rules := _rules()
	resume_rules.duration_sec = 100.0
	resume_rules.vote_lead_sec = 20.0
	resume_rules.wake_restart = false
	var resumer := _make_director(resume_rules, DotVoteListSource.of(_choices(["a", "b"])))
	resumer.begin(&"a")

	for i in range(40):
		resumer.advance(1.0)

	resumer.set_hibernating(true)
	resumer.advance(500.0)
	resumer.set_hibernating(false)
	_check(
		is_equal_approx(resumer.clock.remaining, 60.0),
		"wake_restart off resumes where it froze (%.0f)" % resumer.clock.remaining
	)

	for node: Node in [_v_hibernation_director, late, resumer, _v_hibernation_server, asleep_server]:
		node.queue_free()

	_done()


func _test_empty_server() -> void:
	_section("A server that does not hibernate changes map on its own when nobody is there")

	_check(
		DotVoteRules.new().empty_choice == DotVoteRules.EmptyChoice.RANDOM,
		"an empty server's limit draws at random by default"
	)

	_v_empty_server_ids = ["a", "b", "c", "d", "e"]
	var drawn := {}
	var all_good := true

	for seed_value in range(1, 25):
		var applied := _empty_run(DotVoteRules.EmptyChoice.RANDOM, _v_empty_server_ids, seed_value)

		if applied.size() != 1 or applied[0] == &"a" or not _v_empty_server_ids.has(String(applied[0])):
			all_good = false

		if not applied.is_empty():
			drawn[applied[0]] = true

	_check(
		all_good,
		"every run changes exactly once, to something in the rotation that is not what was running",
		"before this an empty server's due vote waited for a voter for ever"
	)
	_check(
		drawn.size() >= 3,
		"and the draw is random: %d different maps over 24 seeds (%s)" % [drawn.size(), ", ".join(drawn.keys())]
	)

	_v_empty_server_stayed = 0

	for seed_value in range(1, 25):
		if _empty_run(DotVoteRules.EmptyChoice.RANDOM, ["a", "b"], seed_value, true) != [&"b"]:
			_v_empty_server_stayed += 1

	_test_empty_server_2()


func _test_empty_server_2() -> void:
	_check(
		_v_empty_server_stayed == 0,
		"never the map that was running, even where a ballot may offer it (%d of 24 did not move)" % _v_empty_server_stayed
	)
	_check(
		_empty_run(DotVoteRules.EmptyChoice.ROTATION, _v_empty_server_ids, 1) == [&"b"],
		"rotation takes the next in order instead"
	)
	_check(
		_empty_run(DotVoteRules.EmptyChoice.WAIT, _v_empty_server_ids, 1).is_empty(),
		"and wait changes nothing, as before"
	)

	# Before the limit: nothing happens at the lead, because nobody is there to ask.
	var applied := []
	var source := DotVoteListSource.of(_choices(_v_empty_server_ids))
	source.apply_fn = func(id: StringName) -> DotResult:
		applied.append(id)
		return DotResult.success(id)
	var rules := _rules()
	rules.duration_sec = 100.0
	rules.vote_lead_sec = 20.0
	rules.allow_single_voter_auto = true
	var players := [0]
	var director := _make_director(rules, source)
	director.player_count_fn = func() -> int: return players[0]
	director.begin(&"a")
	source.current = &"a"

	for i in range(90):
		director.advance(1.0)

	_check(
		not director.is_voting() and applied.is_empty(),
		"no ballot opens at the lead with nobody to put it to"
	)

	# Somebody arrives between the lead and the limit: the owed ballot opens for them, and
	# the empty draw is not taken over their heads.
	players[0] = 1
	director.advance(1.0)
	_check(director.is_voting() or director.is_counting_down(), "somebody arriving before the limit gets the vote")
	director.queue_free()

	_empty_server_lonely()

	_done()


func _empty_server_lonely() -> void:
	# A one-map server has nowhere to go and carries on with a fresh clock.
	var lonely_applied := []
	var lonely_source := DotVoteListSource.of(_choices(["a"]))
	lonely_source.apply_fn = func(id: StringName) -> DotResult:
		lonely_applied.append(id)
		return DotResult.success(id)
	var lonely_rules := _rules()
	lonely_rules.duration_sec = 100.0
	var lonely := _make_director(lonely_rules, lonely_source)
	lonely.player_count_fn = func() -> int: return 0
	lonely.begin(&"a")

	for i in range(101):
		lonely.advance(1.0)

	_check(
		lonely_applied.is_empty() and not lonely.clock.is_expired() and lonely.clock.remaining > 90.0,
		"a server with one map carries on with a fresh clock rather than sitting expired (%s)" % lonely.clock.formatted_remaining()
	)
	lonely.queue_free()


func _test_no_votes() -> void:
	_section("A ballot nobody voted in, three ways")

	for policy: Variant in [
		DotVoteRules.NoVotes.KEEP,
		DotVoteRules.NoVotes.RANDOM,
		DotVoteRules.NoVotes.ROTATION,
	]:
		var applied := []
		var source := DotVoteListSource.of(_choices(["a", "b", "c", "d"]))
		source.apply_fn = func(id: StringName) -> DotResult:
			applied.append(id)
			return DotResult.success(id)

		var rules := _rules()
		rules.on_no_votes = policy as DotVoteRules.NoVotes
		rules.include_extend = true
		rules.duration_sec = 600.0
		rules.cooldown = 0
		rules.apply = DotVoteRules.Apply.IMMEDIATE

		var director := _make_director(rules, source)
		director.begin(&"a")
		source.current = &"a"
		director.open_vote()

		var result := director.close_vote()

		match policy:
			DotVoteRules.NoVotes.KEEP:
				_check(
					applied.is_empty() and result.outcome == DotVoteResult.Outcome.EMPTY,
					"KEEP stays where it is"
				)
			DotVoteRules.NoVotes.RANDOM:
				_check(
					applied.size() == 1 and applied[0] != &"a"
						and result.outcome == DotVoteResult.Outcome.WINNER,
					"RANDOM draws one of the ballot's options (%s)" % str(applied)
				)
				_check(
					result.summary.contains("Nobody voted"),
					"and the result says why, before it is announced",
					result.summary
				)
			_:
				_check(
					applied == [&"b"],
					"ROTATION takes the next in order (%s)" % str(applied)
				)

		director.queue_free()

	_test_no_votes_2()


func _test_no_votes_2() -> void:
	# The same at the end of a map, through the clock, with players present and nobody
	# voting: keep is the default and restarts the clock (what players see as "it
	# extended"); random picks one of the ballot's maps instead, never Extend.
	_check(DotVoteRules.new().on_no_votes == DotVoteRules.NoVotes.KEEP, "keep is the default")

	for policy: Variant in [DotVoteRules.NoVotes.KEEP, DotVoteRules.NoVotes.RANDOM]:
		var applied := []
		var source := DotVoteListSource.of(_choices(["a", "b", "c", "d"]))
		source.apply_fn = func(id: StringName) -> DotResult:
			applied.append(id)
			return DotResult.success(id)

		var rules := _rules()
		rules.on_no_votes = policy as DotVoteRules.NoVotes
		rules.include_extend = true
		rules.duration_sec = 100.0
		rules.vote_lead_sec = 30.0
		rules.vote_warning_sec = 0.0
		rules.vote_duration_sec = 10.0
		rules.cooldown = 0
		rules.apply = DotVoteRules.Apply.END_OF_TIME

		var director := _make_director(rules, source)
		director.begin(&"a")
		source.current = &"a"

		for i in range(75):
			director.advance(1.0)

		var opened := director.is_voting()

		for i in range(30):
			director.advance(1.0)

		if policy == DotVoteRules.NoVotes.KEEP:
			_check(
				opened and applied.is_empty() and not director.clock.is_expired()
					and director.clock.remaining > 60.0,
				"at the end of a map, keep stays on it with a fresh clock (%s left)" % director.clock.formatted_remaining()
			)
		else:
			_check(
				opened and applied.size() == 1 and applied[0] != &"a"
					and applied[0] != DotVoteBallot.EXTEND and applied[0] != DotVoteBallot.KEEP,
				"at the end of a map, random picks one of the ballot's maps, never Extend (%s)" % str(applied)
			)

		director.queue_free()

	_done()


func _test_clock_view() -> void:
	_section("A client's view of the clock follows an extend, and shows none when there is none")

	_v_clock_view_view = DotVoteClockView.new()
	_check(
		not _v_clock_view_view.known and _v_clock_view_view.formatted_at(0.0) == "",
		"a view never told anything shows nothing"
	)
	_check(
		not bool(DotVoteClockView.state_of(null)["has_clock"]),
		"a server with no vote has no clock to show"
	)

	var source := DotVoteListSource.of(_choices(["a", "b", "c"]))
	var rules := _rules()
	rules.duration_sec = 300.0
	rules.vote_lead_sec = 30.0
	rules.extend_seconds = 120.0
	_v_clock_view_director = _make_director(rules, source)
	_v_clock_view_director.self_advance = false
	_v_clock_view_director.begin(&"a")

	_check(_v_clock_view_view.is_stale(_v_clock_view_director, 0.0), "and is stale against a running clock")
	_v_clock_view_view.adopt(DotVoteClockView.state_of(_v_clock_view_director), 0.0)
	_check(
		_v_clock_view_view.has_clock and _v_clock_view_view.running and _v_clock_view_view.formatted_at(0.0) == "5:00",
		"adopted, it shows the clock's own limit (%s)" % _v_clock_view_view.formatted_at(0.0)
	)
	_check(
		_v_clock_view_view.formatted_at(10.0) == "4:50",
		"and counts itself down between messages (%s)" % _v_clock_view_view.formatted_at(10.0)
	)

	for i in range(10):
		_v_clock_view_director.advance(1.0)

	_check(
		not _v_clock_view_view.is_stale(_v_clock_view_director, 10.0),
		"ten seconds on, both ends agree and nothing needs sending"
	)

	# And a running clock that agrees is still re-sent every RESYNC_SEC, because the two
	# ends count on different clocks and nothing else would correct a server that fell
	# behind real time. A separate director, so the extension below starts from ten.
	var steady := _make_director(rules, DotVoteListSource.of(_choices(["a", "b"])))
	steady.self_advance = false
	steady.begin(&"a")
	var steady_view := DotVoteClockView.new()
	steady_view.adopt(DotVoteClockView.state_of(steady), 0.0)
	for i in range(29):
		steady.advance(1.0)
	var quiet_at_29 := not steady_view.is_stale(steady, 29.0)
	steady.advance(1.0)
	_check(
		quiet_at_29 and steady_view.is_stale(steady, DotVoteClockView.RESYNC_SEC),
		"a clock that agrees stays quiet, and is re-sent every %d s anyway" % int(DotVoteClockView.RESYNC_SEC)
	)
	steady.queue_free()

	_test_clock_view_2()


func _test_clock_view_2() -> void:
	_check(_v_clock_view_director.clock.extend(), "the clock is extended")
	_check(
		_v_clock_view_view.is_stale(_v_clock_view_director, 10.0),
		"which makes the view stale",
		"a client would go on showing the old limit"
	)
	_v_clock_view_view.adopt(DotVoteClockView.state_of(_v_clock_view_director), 10.0)
	_check(
		_v_clock_view_view.formatted_at(10.0) == "6:50",
		"and once re-sent it shows the extension (%s)" % _v_clock_view_view.formatted_at(10.0)
	)

	_v_clock_view_director.clock.stop()
	_check(_v_clock_view_view.is_stale(_v_clock_view_director, 11.0), "a clock that stops is stale too")
	_v_clock_view_view.adopt(DotVoteClockView.state_of(_v_clock_view_director), 11.0)
	_check(
		_v_clock_view_view.formatted_at(40.0) == _v_clock_view_view.formatted_at(11.0),
		"and a stopped clock holds still on the client (%s)" % _v_clock_view_view.formatted_at(40.0)
	)

	var none := _rules()
	none.duration_sec = 0.0
	none.trigger = DotVoteRules.Trigger.RTV_ONLY
	var clockless := _make_director(none, DotVoteListSource.of(_choices(["a", "b"])))
	clockless.begin(&"a")
	var told := DotVoteClockView.new()
	told.adopt(DotVoteClockView.state_of(clockless), 0.0)
	_check(
		told.known and not told.has_clock and told.formatted_at(0.0) == "",
		"an rtv-only vote with no limit is told, and shows no clock"
	)

	var manual := _rules()
	manual.duration_sec = 600.0
	manual.trigger = DotVoteRules.Trigger.MANUAL
	var host_decides := _make_director(manual, DotVoteListSource.of(_choices(["a", "b"])))
	host_decides.begin(&"a")
	_check(
		not bool(DotVoteClockView.state_of(host_decides)["has_clock"]),
		"nor does a manual one, whose count reaching zero ends nothing"
	)

	_done()
