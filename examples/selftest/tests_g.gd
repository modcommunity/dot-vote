extends "res://examples/selftest/tests_f.gd"

## Selftest sections, part g.

var _v_round_end_trigger_held: DotVoteDirector
var _v_round_end_trigger_timed: DotVoteDirector
var _v_round_end_trigger_scored: DotVoteDirector
var _v_manual_rtv_both: DotVoteDirector
var _v_manual_rtv_attempts: Array
var _v_manual_rtv_both_opened: Array
var _v_manual_rtv_busy: Array
var _v_manual_rtv_held: DotVoteDirector
var _v_manual_rtv_held_attempts: Array
var _v_manual_rtv_held_opened: Array
var _v_nothing_to_vote_for_opened: Array
var _v_nothing_to_vote_for_rules: DotVoteRules


func _test_round_end_trigger() -> void:
	_section("round_end holds a time or score ballot for the end of the round; time_limit does not")

	var rules := _rules()
	rules.trigger = DotVoteRules.Trigger.ROUND_END
	rules.duration_sec = 600.0
	rules.round_limit = 0
	rules.vote_lead_sec = 60.0

	_check(
		rules.validate().ok,
		"round_end with a time limit and no round limit validates",
		"it used to be refused: round_end demanded a round limit and did nothing else"
	)

	var none := _rules()
	none.trigger = DotVoteRules.Trigger.ROUND_END
	none.duration_sec = 0.0
	none.round_limit = 0
	none.score_limit = 0
	_check(not none.validate().ok, "round_end with no limit at all is still refused")

	var source := DotVoteListSource.of(_choices(["a", "b", "c"]))
	_v_round_end_trigger_held = _make_director(rules, source)
	_v_round_end_trigger_held.rules.include_extend = false
	_v_round_end_trigger_held.begin(&"a")
	_v_round_end_trigger_held.advance(545.0)

	_check(
		not _v_round_end_trigger_held.is_voting() and _v_round_end_trigger_held.is_waiting_for_round_end(),
		"inside the lead, round_end waits for the round rather than opening mid-fight"
	)
	_check(
		"\n".join(_v_round_end_trigger_held.describe_lines()).contains("round ends"),
		"and says so in describe", str(_v_round_end_trigger_held.describe_lines())
	)

	_v_round_end_trigger_held.advance(60.0)
	_check(
		not _v_round_end_trigger_held.is_voting(),
		"even once the time is up: the round in progress is finished first"
	)

	_test_round_end_trigger_2()


func _test_round_end_trigger_2() -> void:
	_v_round_end_trigger_held.note_round_end()
	_check(
		_v_round_end_trigger_held.is_voting() and not _v_round_end_trigger_held.is_waiting_for_round_end(),
		"and the round ending opens the ballot"
	)

	# The control. The same clock under time_limit opens at the lead, mid-round — which is
	# the difference this section exists to prove is real, and was not before.
	var timed_rules := _rules()
	timed_rules.trigger = DotVoteRules.Trigger.TIME_LIMIT
	timed_rules.duration_sec = 600.0
	timed_rules.vote_lead_sec = 60.0
	_v_round_end_trigger_timed = _make_director(timed_rules, DotVoteListSource.of(_choices(["a", "b", "c"])))
	_v_round_end_trigger_timed.rules.include_extend = false
	_v_round_end_trigger_timed.begin(&"a")
	_v_round_end_trigger_timed.advance(545.0)
	_check(
		_v_round_end_trigger_timed.is_voting() and not _v_round_end_trigger_timed.is_waiting_for_round_end(),
		"under time_limit the same clock opens the ballot at the lead, with no round ended"
	)

	# A score limit is held the same way.
	var scored_rules := _rules()
	scored_rules.trigger = DotVoteRules.Trigger.ROUND_END
	scored_rules.duration_sec = 0.0
	scored_rules.score_limit = 20
	scored_rules.vote_lead_score = 2
	_v_round_end_trigger_scored = _make_director(scored_rules, DotVoteListSource.of(_choices(["a", "b"])))
	_v_round_end_trigger_scored.rules.include_extend = false
	_v_round_end_trigger_scored.begin(&"a")
	_v_round_end_trigger_scored.note_score(19)
	_check(
		not _v_round_end_trigger_scored.is_voting() and _v_round_end_trigger_scored.is_waiting_for_round_end(),
		"a score inside its lead waits for the round too"
	)
	_v_round_end_trigger_scored.note_round_end()
	_check(_v_round_end_trigger_scored.is_voting(), "and opens when it ends")

	_test_round_end_trigger_3()


func _test_round_end_trigger_3() -> void:
	# A rock-the-vote does not wait: that is the players asking now.
	var rocked_rules := _rules()
	rocked_rules.trigger = DotVoteRules.Trigger.ROUND_END
	rocked_rules.round_limit = 5
	rocked_rules.rtv_delay_sec = 0.0
	rocked_rules.rtv_min_players = 1
	rocked_rules.rtv_fraction = 0.25
	var rocked := _make_director(rocked_rules, DotVoteListSource.of(_choices(["a", "b"])))
	rocked.begin(&"a")
	rocked.rock_the_vote(&"p1")
	_check(rocked.is_voting(), "a rock-the-vote under round_end opens at once")

	# A new map forgets a held ballot: it was owed to the one that just ended.
	_v_round_end_trigger_held.close_vote()
	_v_round_end_trigger_held.begin(&"b")
	_check(not _v_round_end_trigger_held.is_waiting_for_round_end(), "and a new choice forgets a held ballot")

	_v_round_end_trigger_held.queue_free()
	_v_round_end_trigger_timed.queue_free()
	_v_round_end_trigger_scored.queue_free()
	rocked.queue_free()

	# A host that feeds neither rounds nor scores takes out what it cannot drive, rather
	# than wait for a round end that never comes under an operator's `trigger: round_end`.
	var unfed := DotVoteRules.new()
	unfed.trigger = DotVoteRules.Trigger.ROUND_END
	unfed.round_limit = 4
	unfed.score_limit = 30
	unfed.apply = DotVoteRules.Apply.END_OF_ROUND
	unfed.rtv_apply = DotVoteRules.Apply.END_OF_ROUND
	var dropped := unfed.drop_unfed(false, false)
	_check(
		unfed.trigger == DotVoteRules.Trigger.TIME_LIMIT and unfed.round_limit == 0
			and unfed.score_limit == 0 and unfed.apply == DotVoteRules.Apply.IMMEDIATE
			and unfed.rtv_apply == DotVoteRules.Apply.IMMEDIATE and dropped.size() == 5,
		"a host that feeds no rounds or scores drops what it cannot drive, and says what",
		", ".join(dropped)
	)
	var fed := DotVoteRules.new()
	fed.trigger = DotVoteRules.Trigger.SCORE_LIMIT
	fed.score_limit = 30
	_check(fed.drop_unfed(true, true).is_empty() and fed.score_limit == 30,
		"and one that feeds them keeps every setting")
	_done()


func _test_ballot_options() -> void:
	_section("What is on a ballot: no vote, extend when it can happen, and the order")

	var rules := _rules()
	rules.include_extend = false
	rules.include_abstain = true

	var ballot := DotVoteBallot.of(rules)
	ballot.begin(_choices(["a", "b"]), 3)

	_check(ballot.option_ids().has(DotVoteBallot.ABSTAIN), "'no vote' is on the ballot")
	_check(
		not ballot.tally().has(DotVoteBallot.ABSTAIN),
		"and is not an option anything can be counted toward"
	)

	ballot.cast_vote(&"v1", _one(DotVoteBallot.ABSTAIN))
	ballot.cast_vote(&"v2", _one(&"b"))
	ballot.cast_vote(&"v3", _one(DotVoteBallot.ABSTAIN))

	_check(ballot.everybody_voted(), "an abstention is an answer, so the ballot can close")

	var abstained := ballot.resolve()
	_check(
		abstained.winner_id == &"b" and abstained.abstained == 2,
		"one vote beats two abstentions, which are reported (%d)" % abstained.abstained
	)

	var all_out := DotVoteBallot.of(rules)
	all_out.begin(_choices(["a", "b"]), 2)
	all_out.cast_vote(&"v1", _one(DotVoteBallot.ABSTAIN))
	_check(
		all_out.resolve().outcome == DotVoteResult.Outcome.EMPTY,
		"and a ballot where everybody abstained decided nothing"
	)

	var extend_rules := _rules()
	var spent := DotVoteBallot.of(extend_rules)
	spent.extend_available = false
	spent.begin(_choices(["a"]), 2)
	_check(
		not spent.option_ids().has(DotVoteBallot.EXTEND),
		"'extend' is left off a ballot once the extensions are used up",
		"an option that does nothing if it wins is not an option"
	)

	var early := DotVoteBallot.of(extend_rules)
	early.early = true
	early.begin(_choices(["a"]), 2)
	_check(
		early.option_ids().has(DotVoteBallot.KEEP)
			and not early.option_ids().has(DotVoteBallot.EXTEND),
		"a rock-the-vote ballot offers 'don't change' in place of 'extend'"
	)

	var no_keep := _rules()
	no_keep.early_vote_keep = false
	var early_extend := DotVoteBallot.of(no_keep)
	early_extend.early = true
	early_extend.begin(_choices(["a"]), 2)
	_check(
		early_extend.option_ids().has(DotVoteBallot.EXTEND)
			and not early_extend.option_ids().has(DotVoteBallot.KEEP),
		"unless the server says otherwise"
	)

	_test_ballot_options_2()


func _test_ballot_options_2() -> void:
	var first_rules := _rules()
	first_rules.include_extend = false
	first_rules.include_keep = true
	first_rules.pseudo_options_first = true
	first_rules.tie_break = DotVoteRules.TieBreak.BALLOT_ORDER

	var first := DotVoteBallot.of(first_rules)
	first.begin(_choices(["a", "b"]), 2)
	_check(first.option_ids()[0] == DotVoteBallot.KEEP, "'don't change' can be listed first")

	first.cast_vote(&"v1", _one(&"a"))
	first.cast_vote(&"v2", _one(DotVoteBallot.KEEP))
	_check(
		first.resolve().winner_id == &"a",
		"and still loses a tie a choice listed after it",
		"moving an option up a menu must not make every tie go to the status quo"
	)

	var cut_rules := _rules()
	cut_rules.include_extend = false
	cut_rules.method = DotVoteRules.Method.MAJORITY_RUNOFF
	cut_rules.runoff_options = 2
	cut_rules.max_runoffs = 1

	var cut := DotVoteBallot.of(cut_rules)
	cut.begin(_choices(["a", "b", "c", "d"]), 7)
	for pair: Array in [["v1", "a"], ["v2", "a"], ["v3", "b"], ["v4", "b"],
			["v5", "c"], ["v6", "c"], ["v7", "d"]]:
		cut.cast_vote(StringName(pair[0]), _one(StringName(pair[1])))

	var three_way := cut.resolve()
	_check(
		three_way.outcome == DotVoteResult.Outcome.RUNOFF and three_way.runoff_ids.size() == 3,
		"three tied at the runoff line all go through, not two of them (%d)"
			% three_way.runoff_ids.size(),
		"cutting a tie by menu position drops an option for being lower on a list"
	)

	var low_rules := cut_rules.duplicate() as DotVoteRules
	low_rules.majority_fraction = 0.4

	var low := DotVoteBallot.of(low_rules)
	low.begin(_choices(["a", "b", "c"]), 7)
	for pair: Array in [["v1", "a"], ["v2", "a"], ["v3", "a"], ["v4", "b"],
			["v5", "b"], ["v6", "c"], ["v7", "c"]]:
		low.cast_vote(StringName(pair[0]), _one(StringName(pair[1])))

	_check(
		low.resolve().winner_id == &"a",
		"a runoff threshold below a half takes a 3-of-7 leader without one"
	)

	_test_ballot_options_3()


func _test_ballot_options_3() -> void:
	# Shuffled, and reproducibly so.
	var shuffle_a := _rules()
	shuffle_a.shuffle_ballot = true
	shuffle_a.fill = DotVoteRules.Fill.SEQUENTIAL
	shuffle_a.include_extend = false
	shuffle_a.max_options = 6
	shuffle_a.nomination_slots = 0
	shuffle_a.cooldown = 0
	shuffle_a.fill_seed = 99

	var shuffle_b := shuffle_a.duplicate() as DotVoteRules

	var left := _make_director(shuffle_a, DotVoteListSource.of(_choices(["a", "b", "c", "d", "e", "f"])))
	var right := _make_director(shuffle_b, DotVoteListSource.of(_choices(["a", "b", "c", "d", "e", "f"])))
	left.begin(&"")
	right.begin(&"")
	left.open_vote()
	right.open_vote()

	var order := PackedStringArray()
	for id in left.ballot.option_ids():
		order.append(String(id))

	_check(
		", ".join(order) != "a, b, c, d, e, f" and order.size() == 6,
		"a shuffled ballot is not in the source's order (%s)" % ", ".join(order)
	)
	_check(
		left.ballot.option_ids() == right.ballot.option_ids(),
		"and two directors with the same seed shuffle it the same way",
		"a client following along must show the numbers the server counts"
	)

	# Custom maps are marked where the players see them.
	var custom := DotVoteChoice.of(&"surf_new", "Surf New")
	custom.official = false
	var marked_source := DotVoteListSource.of([custom, DotVoteChoice.of(&"shipped", "Shipped")] as Array[DotVoteChoice])
	var marked_rules := _rules()
	marked_rules.include_extend = false
	marked_rules.cooldown = 0

	var marker := _make_director(marked_rules, marked_source)
	var said := []
	marker.announce_fn = func(line: String) -> void: said.append(line)
	marker.begin(&"")
	marker.open_vote()

	_check(
		said.size() == 1 and str(said[0]).contains("*Surf New")
			and not str(said[0]).contains("*Shipped"),
		"an unofficial choice is marked on the ballot and an official one is not",
		str(said)
	)
	_check(
		not marker.is_official(&"surf_new") and marker.is_official(&"shipped"),
		"and whether one is official can be asked"
	)

	left.queue_free()
	right.queue_free()
	marker.queue_free()
	_done()


func _test_manual_rtv() -> void:
	_section("MANUAL leaves the scheduled ballot to the host, and a rock-the-vote still opens one")

	# The rocked ballot opens with nobody else asking for it.
	var applied := []
	var rules := _rules()
	rules.trigger = DotVoteRules.Trigger.MANUAL
	var director := _rtv_director(rules, applied)
	var opened := []
	director.vote_opened.connect(func(_o: Array, _s: float) -> void: opened.append(true))

	for i in range(20):
		director.advance(1.0)

	director.rock_the_vote(&"p1")
	director.rock_the_vote(&"p2")

	_check(
		director.is_voting() and opened.size() == 1,
		"under MANUAL a passed rock-the-vote opens its ballot",
		"state %s, %d opened" % [director.describe().get("state", "?"), opened.size()]
	)
	_check(director.ballot.early, "as a rock-the-vote ballot (no extend, 'don't change' offered)")

	# The schedule is still the host's: a limit reaching its lead and running out opens nothing.
	var lead := _rtv_director(_manual_rules(), [])
	var lead_opened := []
	lead.vote_opened.connect(func(_o: Array, _s: float) -> void: lead_opened.append(true))

	for i in range(120):
		lead.advance(1.0)

	_check(
		lead.clock.is_expired() and lead_opened.is_empty() and not lead.is_voting(),
		"while the limit reaching its lead, and running out, opens nothing under MANUAL"
	)
	_check(lead.start_vote(DotVoteClock.REASON_MANUAL).ok and lead.is_voting(), "until the host asks")

	# A game that still opens the rocked ballot itself does not get a second one.
	_v_manual_rtv_both = _rtv_director(_manual_rules(), [])
	_v_manual_rtv_attempts = []
	_v_manual_rtv_both_opened = []
	_v_manual_rtv_both.vote_opened.connect(func(_o: Array, _s: float) -> void: _v_manual_rtv_both_opened.append(true))
	_game_rtv_workaround(_v_manual_rtv_both, _v_manual_rtv_attempts)
	_v_manual_rtv_both.rock_the_vote(&"p1")
	_v_manual_rtv_both.rock_the_vote(&"p2")

	_test_manual_rtv_2()


func _test_manual_rtv_2() -> void:
	_check(
		_v_manual_rtv_both.is_voting() and _v_manual_rtv_both_opened.size() == 1,
		"a game's own rtv handler on top: one ballot (%d opened)" % _v_manual_rtv_both_opened.size()
	)
	_check(_v_manual_rtv_attempts.is_empty(), "the game's handler finds it open and stands aside")

	for i in range(10):
		_v_manual_rtv_both.advance(1.0)

	_check(_v_manual_rtv_both_opened.size() == 1, "and nothing opens a second one later (%d)" % _v_manual_rtv_both_opened.size())

	# With a countdown first the ballot is not open yet when the game's handler runs, and its
	# start_vote is refused rather than starting another.
	var warned_rules := _manual_rules()
	warned_rules.vote_warning_sec = 3.0
	var warned := _rtv_director(warned_rules, [])
	var warned_attempts := []
	var countdowns := []
	var warned_opened := []
	warned.countdown_started.connect(func(_s: float, _r: bool) -> void: countdowns.append(true))
	warned.vote_opened.connect(func(_o: Array, _s: float) -> void: warned_opened.append(true))
	_game_rtv_workaround(warned, warned_attempts)
	warned.rock_the_vote(&"p1")
	warned.rock_the_vote(&"p2")

	_check(
		countdowns.size() == 1 and warned_attempts.size() == 1
			and not (warned_attempts[0] as DotResult).ok,
		"with a countdown: one countdown, and the game's start_vote is refused"
	)

	for i in range(10):
		warned.advance(1.0)

	_check(
		warned_opened.size() == 1 and countdowns.size() == 1,
		"and exactly one ballot opens when it ends (%d)" % warned_opened.size()
	)

	# Refused for the moment (another vote on screen): retried by the director, once.
	_v_manual_rtv_busy = [true]
	_v_manual_rtv_held = _rtv_director(_manual_rules(), [])
	_v_manual_rtv_held.busy_fn = func() -> bool: return _v_manual_rtv_busy[0]
	_v_manual_rtv_held_attempts = []
	_v_manual_rtv_held_opened = []
	_v_manual_rtv_held.vote_opened.connect(func(_o: Array, _s: float) -> void: _v_manual_rtv_held_opened.append(true))
	_game_rtv_workaround(_v_manual_rtv_held, _v_manual_rtv_held_attempts)
	_v_manual_rtv_held.rock_the_vote(&"p1")
	_v_manual_rtv_held.rock_the_vote(&"p2")

	_test_manual_rtv_3()


func _test_manual_rtv_3() -> void:
	_check(
		not _v_manual_rtv_held.is_voting() and _v_manual_rtv_held_attempts.size() == 1,
		"a rocked ballot that cannot open yet is refused to the game as well"
	)

	_v_manual_rtv_busy[0] = false
	_v_manual_rtv_held.advance(1.0)

	_check(
		_v_manual_rtv_held.is_voting() and _v_manual_rtv_held_opened.size() == 1,
		"and opens once when it can, without the game asking again"
	)

	# An admin's force_rtv under MANUAL is unchanged.
	var forced := _rtv_director(_manual_rules(), [])
	forced.force_rtv()
	_check(forced.is_voting(), "an admin's force_rtv still opens one under MANUAL")

	# Every other trigger: a rocked ballot opens as before, and the lead does what it did.
	for trigger: DotVoteRules.Trigger in [
		DotVoteRules.Trigger.TIME_LIMIT,
		DotVoteRules.Trigger.ROUND_END,
		DotVoteRules.Trigger.RTV_ONLY,
	]:
		var trig_name: String = DotVoteRules.Trigger.keys()[trigger]
		var trig_rules := _rules()
		trig_rules.trigger = trigger
		var rocked := _rtv_director(trig_rules, [])
		var rocked_opened := []
		rocked.vote_opened.connect(func(_o: Array, _s: float) -> void: rocked_opened.append(true))
		rocked.rock_the_vote(&"p1")
		rocked.rock_the_vote(&"p2")
		_check(
			rocked.is_voting() and rocked_opened.size() == 1,
			"%s: a passed rock-the-vote opens one ballot" % trig_name
		)

		var lead_rules := _rules()
		lead_rules.trigger = trigger
		var timed := _rtv_director(lead_rules, [])

		for i in range(91):
			timed.advance(1.0)

		var expected := trigger == DotVoteRules.Trigger.TIME_LIMIT
		_check(
			timed.is_voting() == expected,
			"%s: the limit's lead %s" % [trig_name, "opens the ballot" if expected else "does not open it mid-round"]
		)

	_done()


func _test_nothing_to_vote_for() -> void:
	_section("A vote with nothing else to choose is not held")

	_v_nothing_to_vote_for_opened = [0]
	_v_nothing_to_vote_for_rules = _rules()
	_v_nothing_to_vote_for_rules.duration_sec = 60.0
	_v_nothing_to_vote_for_rules.vote_lead_sec = 0.0
	_v_nothing_to_vote_for_rules.include_extend = true

	# The only choice is the one running: a ballot could only be Extend.
	var lonely := _make_director(_v_nothing_to_vote_for_rules, DotVoteListSource.of(_choices(["solo"])))
	lonely.vote_opened.connect(func(_o: Array, _s: float) -> void: _v_nothing_to_vote_for_opened[0] += 1)
	lonely.begin(&"solo")

	for i in range(61):
		lonely.advance(1.0)

	_check(_v_nothing_to_vote_for_opened[0] == 0, "the only choice's limit running out opens no ballot")
	_check(not lonely.is_voting() and not lonely.is_counting_down(), "and nothing counts down to one")
	_check(
		not lonely.clock.is_expired() and lonely.clock.remaining > 50.0,
		"and the clock starts again rather than sitting expired (%.0fs)" % lonely.clock.remaining
	)
	_check(lonely.can_start_vote(), "with no retry left owing")
	_check(
		not lonely.start_vote(DotVoteClock.REASON_MANUAL).ok,
		"and an admin asking for a vote is told there is nothing to vote for"
	)
	lonely.queue_free()

	# The same thing installed twice under two ids: a player sees one name on both.
	var twice := _choices(["g2g", "owner_g2g", "arena"])
	twice[0].display_name = "g2gfast"
	twice[1].display_name = "G2gfast"
	var named := _make_director(_v_nothing_to_vote_for_rules, DotVoteListSource.of(twice))
	named.begin(&"g2g")
	var offered := named.build_options(4).map(func(c: DotVoteChoice) -> StringName: return c.id)
	_check(
		offered == [&"arena"],
		"a choice named like the running one is not offered as another (%s)" % str(offered)
	)
	named.queue_free()

	_test_nothing_to_vote_for_2()


func _test_nothing_to_vote_for_2() -> void:
	var only_twice := _choices(["g2g", "owner_g2g"])
	only_twice[0].display_name = "g2gfast"
	only_twice[1].display_name = "g2gfast "
	_v_nothing_to_vote_for_opened[0] = 0
	var dup := _make_director(_v_nothing_to_vote_for_rules, DotVoteListSource.of(only_twice))
	dup.vote_opened.connect(func(_o: Array, _s: float) -> void: _v_nothing_to_vote_for_opened[0] += 1)
	dup.begin(&"g2g")

	for i in range(61):
		dup.advance(1.0)

	_check(_v_nothing_to_vote_for_opened[0] == 0, "so a second install of the only game opens no ballot either")

	var included := _v_nothing_to_vote_for_rules.duplicate() as DotVoteRules
	included.include_current = true
	dup.rules = included
	var back := dup.build_options(4).map(func(c: DotVoteChoice) -> StringName: return c.id)
	_check(
		back.has(&"owner_g2g"),
		"unless include_current asks for what is running (%s)" % str(back)
	)
	dup.queue_free()

	# The last alternative goes during the countdown: the ballot is not opened over Extend.
	var warned := _v_nothing_to_vote_for_rules.duplicate() as DotVoteRules
	warned.vote_warning_sec = 5.0
	var pair := _choices(["a", "b"])
	_v_nothing_to_vote_for_opened[0] = 0
	var racing := _make_director(warned, DotVoteListSource.of(pair))
	racing.vote_opened.connect(func(_o: Array, _s: float) -> void: _v_nothing_to_vote_for_opened[0] += 1)
	racing.begin(&"a")
	_check(racing.start_vote(DotVoteClock.REASON_MANUAL).ok, "with two choices the countdown starts")
	pair[1].min_players = 10

	for i in range(6):
		racing.advance(1.0)

	_check(
		_v_nothing_to_vote_for_opened[0] == 0 and not racing.is_voting(),
		"and when the other needs more players by its end, no ballot opens"
	)
	_check(racing.can_start_vote(), "and nothing is left owing")
	racing.queue_free()

	_done()
