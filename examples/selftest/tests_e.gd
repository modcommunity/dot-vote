extends "res://examples/selftest/tests_d.gd"

## Selftest sections, part e.

var _v_counting_approval_rules: DotVoteRules
var _v_clock_rules: DotVoteRules


func _test_counting() -> void:
	_section("Four ways of counting, and each one counts")

	var rules := _rules()
	rules.include_extend = false

	var ballot := DotVoteBallot.of(rules)
	ballot.begin(_choices(["a", "b", "c"]), 5)

	ballot.cast_vote(&"v1", _one(&"a"))
	ballot.cast_vote(&"v2", _one(&"a"))
	ballot.cast_vote(&"v3", _one(&"b"))

	var tally := ballot.tally()
	_check(
		is_equal_approx(float(tally[&"a"]), 2.0) and is_equal_approx(float(tally[&"c"]), 0.0),
		"a plurality tally includes the options nobody picked"
	)

	var result := ballot.resolve()
	_check(result.winner_id == &"a", "and the most votes wins")
	_check(result.outcome == DotVoteResult.Outcome.WINNER, "with a WINNER outcome")
	_check(result.votes_cast == 3 and result.eligible == 5, "turnout is recorded")
	_check(result.summary.contains("2 votes"), "and the summary says so", result.summary)
	_check(result.ordered()[0][0] == &"a", "the tally orders for a HUD")

	# A player who misclicks must be able to change their mind. It is also what makes
	# a live tally worth showing.
	var changeable := DotVoteBallot.of(rules)
	changeable.begin(_choices(["a", "b"]), 2)
	changeable.cast_vote(&"v1", _one(&"a"))
	changeable.cast_vote(&"v1", _one(&"b"))
	_check(
		is_equal_approx(float(changeable.tally()[&"b"]), 1.0)
			and is_equal_approx(float(changeable.tally()[&"a"]), 0.0),
		"a vote can be changed until the ballot closes"
	)

	var locked_rules := _rules()
	locked_rules.changeable_until_close = false
	var locked := DotVoteBallot.of(locked_rules)
	locked.begin(_choices(["a", "b"]), 2)
	locked.cast_vote(&"v1", _one(&"a"))
	_check(
		not locked.cast_vote(&"v1", _one(&"b")).ok,
		"unless the server says otherwise"
	)

	_check(
		not ballot.cast_vote(&"v9", _one(&"zzz")).ok,
		"a vote for something not on the ballot is refused"
	)

	# Approval.
	_v_counting_approval_rules = _rules()
	_v_counting_approval_rules.method = DotVoteRules.Method.APPROVAL
	_v_counting_approval_rules.include_extend = false
	_v_counting_approval_rules.approval_max_choices = 2

	_test_counting_2()


func _test_counting_2() -> void:
	var approval := DotVoteBallot.of(_v_counting_approval_rules)
	approval.begin(_choices(["a", "b", "c"]), 3)
	approval.cast_vote(&"v1", [&"a", &"b"] as Array[StringName])
	approval.cast_vote(&"v2", [&"b", &"c"] as Array[StringName])
	approval.cast_vote(&"v3", [&"a", &"b", &"c"] as Array[StringName])

	var approved := approval.tally()
	_check(
		is_equal_approx(float(approved[&"b"]), 3.0),
		"approval counts every entry on a ballot (%.0f)" % float(approved[&"b"])
	)
	_check(
		is_equal_approx(float(approved[&"c"]), 1.0),
		"and the third preference of a capped ballot is dropped",
		"approval_max_choices of 2 means two, or the cap is decoration"
	)
	_check(approval.resolve().winner_id == &"b", "and the most approvals wins")

	# Plurality given a ranked ballot.
	var ranked_at_plurality := DotVoteBallot.of(_rules())
	ranked_at_plurality.begin(_choices(["a", "b"]), 2)
	ranked_at_plurality.cast_vote(&"v1", [&"b", &"a"] as Array[StringName])
	_check(
		is_equal_approx(float(ranked_at_plurality.tally()[&"b"]), 1.0)
			and is_equal_approx(float(ranked_at_plurality.tally()[&"a"]), 0.0),
		"a ranked ballot sent to a plurality server counts as its first preference",
		"refusing it would make one client unusable against half the configurations"
	)

	# Instant runoff: nobody has a majority on the first count, and the transfer
	# decides it. The classic case, and the one a plurality gets wrong.
	var irv_rules := _rules()
	irv_rules.method = DotVoteRules.Method.INSTANT_RUNOFF
	irv_rules.include_extend = false

	var irv := DotVoteBallot.of(irv_rules)
	irv.begin(_choices(["a", "b", "c"]), 5)
	irv.cast_vote(&"v1", [&"a"] as Array[StringName])
	irv.cast_vote(&"v2", [&"a"] as Array[StringName])
	irv.cast_vote(&"v3", [&"b"] as Array[StringName])
	irv.cast_vote(&"v4", [&"b"] as Array[StringName])
	irv.cast_vote(&"v5", [&"c", &"b"] as Array[StringName])

	var irv_result := irv.resolve()
	_check(
		irv_result.winner_id == &"b",
		"an instant runoff transfers the eliminated ballots (won: %s)"
			% irv_result.winner_id,
		"a plurality would have tied a and b at 2 and given it to a"
	)
	_check(
		irv_result.rounds.size() == 2,
		"and records every round for an announcement (%d)" % irv_result.rounds.size()
	)

	_test_counting_3()


func _test_counting_3() -> void:
	# Majority runoff: no majority on the first count, so the top two go again.
	var majority_rules := _rules()
	majority_rules.method = DotVoteRules.Method.MAJORITY_RUNOFF
	majority_rules.include_extend = false
	majority_rules.max_runoffs = 1

	var majority := DotVoteBallot.of(majority_rules)
	majority.begin(_choices(["a", "b", "c"]), 5)
	majority.cast_vote(&"v1", _one(&"a"))
	majority.cast_vote(&"v2", _one(&"a"))
	majority.cast_vote(&"v3", _one(&"b"))
	majority.cast_vote(&"v4", _one(&"b"))
	majority.cast_vote(&"v5", _one(&"c"))

	var first_round := majority.resolve()
	_check(
		first_round.outcome == DotVoteResult.Outcome.RUNOFF,
		"no majority sends the top two to a runoff"
	)
	_check(
		first_round.runoff_ids.size() == 2 and first_round.runoff_ids.has(&"b"),
		"carrying exactly the leaders"
	)

	majority.begin_runoff(first_round.runoff_ids)
	_check(
		majority.option_ids().size() == 2 and majority.voter_count() == 0,
		"a runoff clears the ballots",
		"a runoff asks a different question and the old votes answer the old one"
	)

	majority.cast_vote(&"v1", _one(&"a"))
	majority.cast_vote(&"v2", _one(&"a"))
	majority.cast_vote(&"v3", _one(&"b"))

	var second_round := majority.resolve()
	_check(second_round.winner_id == &"a", "and the runoff decides it")
	_check(
		majority.runoffs_held == 1,
		"with the runoff counted, so it cannot go round for ever"
	)

	# Weighted ballots.
	var weighted := DotVoteBallot.of(_rules())
	weighted.begin(_choices(["a", "b"]), 3)
	weighted.cast_vote(&"v1", _one(&"a"))
	weighted.cast_vote(&"v2", _one(&"b"))
	weighted.cast_vote(&"v3", _one(&"b"))
	weighted.weights[&"v1"] = 3.0
	_check(
		weighted.resolve().winner_id == &"a",
		"a weighted vote outvotes two unweighted ones"
	)

	_done()


func _test_tie_breaks() -> void:
	_section("Every tie is broken by a rule a player watching can predict")

	# Extend leading on equal votes is not extend winning.
	var extend_rules := _rules()
	extend_rules.include_extend = true
	extend_rules.extend_needs_majority = true

	var tied_with_extend := DotVoteBallot.of(extend_rules)
	tied_with_extend.begin(_choices(["a"]), 2)
	tied_with_extend.cast_vote(&"v1", _one(&"a"))
	tied_with_extend.cast_vote(&"v2", _one(DotVoteBallot.EXTEND))

	var extend_tie := tied_with_extend.resolve()
	_check(
		extend_tie.winner_id == &"a",
		"a tie between extend and something new goes to the new thing",
		"a server that ties toward the status quo never changes anything"
	)

	var extend_wins := DotVoteBallot.of(extend_rules)
	extend_wins.begin(_choices(["a"]), 3)
	extend_wins.cast_vote(&"v1", _one(&"a"))
	extend_wins.cast_vote(&"v2", _one(DotVoteBallot.EXTEND))
	extend_wins.cast_vote(&"v3", _one(DotVoteBallot.EXTEND))
	_check(
		extend_wins.resolve().outcome == DotVoteResult.Outcome.EXTEND,
		"and extend wins outright when it actually leads"
	)

	var lenient := _rules()
	lenient.extend_needs_majority = false
	var lenient_ballot := DotVoteBallot.of(lenient)
	lenient_ballot.begin(_choices(["a"]), 2)
	lenient_ballot.cast_vote(&"v1", _one(&"a"))
	lenient_ballot.cast_vote(&"v2", _one(DotVoteBallot.EXTEND))
	_check(
		lenient_ballot.resolve().outcome == DotVoteResult.Outcome.EXTEND,
		"and with extend_needs_majority off the incumbent keeps a tie instead",
		"a setting that reads differently and behaves identically is the bug this "
		+ "whole family keeps finding"
	)

	var keep_rules := _rules()
	keep_rules.include_extend = false
	keep_rules.include_keep = true
	var keep := DotVoteBallot.of(keep_rules)
	keep.begin(_choices(["a"]), 3)
	keep.cast_vote(&"v1", _one(DotVoteBallot.KEEP))
	keep.cast_vote(&"v2", _one(DotVoteBallot.KEEP))
	keep.cast_vote(&"v3", _one(&"a"))
	_check(
		keep.resolve().outcome == DotVoteResult.Outcome.KEEP,
		"'none of these' is a separate answer from 'extend'"
	)

	_test_tie_breaks_2()


func _test_tie_breaks_2() -> void:
	# The five tie-breaks, on the same 1-1 tie.
	var order_rules := _rules()
	order_rules.include_extend = false
	order_rules.tie_break = DotVoteRules.TieBreak.BALLOT_ORDER

	var by_order := DotVoteBallot.of(order_rules)
	by_order.begin(_choices(["first", "second"]), 2)
	by_order.cast_vote(&"v1", _one(&"first"))
	by_order.cast_vote(&"v2", _one(&"second"))

	var ordered_result := by_order.resolve()
	_check(ordered_result.winner_id == &"first", "BALLOT_ORDER takes the earlier option")
	_check(
		ordered_result.tie_break != "" and ordered_result.tied_ids.size() == 2,
		"and says it was a tie, so the announcement can explain itself",
		"a 4-4 tally with an unexplained winner reads as a rigged vote"
	)
	_check(
		ordered_result.summary.contains("tie"),
		"in the summary a player sees",
		ordered_result.summary
	)

	var nom_rules := _rules()
	nom_rules.include_extend = false
	nom_rules.tie_break = DotVoteRules.TieBreak.NOMINATION_ORDER

	var noms := DotVoteNominations.of(nom_rules)
	noms.add(&"alice", &"second")
	noms.add(&"bob", &"first")

	var by_nomination := DotVoteBallot.of(nom_rules)
	by_nomination.nominations = noms
	by_nomination.begin(_choices(["first", "second"]), 2)
	by_nomination.cast_vote(&"v1", _one(&"first"))
	by_nomination.cast_vote(&"v2", _one(&"second"))
	_check(
		by_nomination.resolve().winner_id == &"second",
		"NOMINATION_ORDER takes whichever was nominated first"
	)

	var lrp_rules := _rules()
	lrp_rules.include_extend = false
	lrp_rules.tie_break = DotVoteRules.TieBreak.LEAST_RECENTLY_PLAYED

	var history := DotVoteHistory.of(lrp_rules)
	history.note_played(&"second", 0.0)
	history.note_played(&"first", 0.0)

	var by_age := DotVoteBallot.of(lrp_rules)
	by_age.history = history
	by_age.begin(_choices(["first", "second"]), 2)
	by_age.cast_vote(&"v1", _one(&"first"))
	by_age.cast_vote(&"v2", _one(&"second"))
	_check(
		by_age.resolve().winner_id == &"second",
		"LEAST_RECENTLY_PLAYED takes the one longest unplayed"
	)

	_test_tie_breaks_3()


func _test_tie_breaks_3() -> void:
	var never_rules := _rules()
	never_rules.include_extend = false
	never_rules.tie_break = DotVoteRules.TieBreak.LEAST_RECENTLY_PLAYED

	var thin_history := DotVoteHistory.of(never_rules)
	thin_history.note_played(&"first", 0.0)

	var by_never := DotVoteBallot.of(never_rules)
	by_never.history = thin_history
	by_never.begin(_choices(["first", "second"]), 2)
	by_never.cast_vote(&"v1", _one(&"first"))
	by_never.cast_vote(&"v2", _one(&"second"))
	_check(
		by_never.resolve().winner_id == &"second",
		"and something NEVER played beats something played once",
		"'never' is the longest possible gap, not a missing value"
	)

	var random_rules := _rules()
	random_rules.include_extend = false
	random_rules.tie_break = DotVoteRules.TieBreak.RANDOM
	random_rules.tie_break_seed = 12345

	var seed_before := random_rules.tie_break_seed
	var by_chance := DotVoteBallot.of(random_rules)
	by_chance.begin(_choices(["first", "second"]), 2)
	by_chance.cast_vote(&"v1", _one(&"first"))
	by_chance.cast_vote(&"v2", _one(&"second"))
	var drawn := by_chance.resolve()
	_check(drawn.winner_id != &"", "RANDOM draws one of them")
	_check(
		random_rules.tie_break_seed != seed_before,
		"and advances its seed deterministically, so a client can follow along"
	)

	var runoff_rules := _rules()
	runoff_rules.include_extend = false
	runoff_rules.tie_break = DotVoteRules.TieBreak.RUNOFF
	runoff_rules.max_runoffs = 1

	var by_runoff := DotVoteBallot.of(runoff_rules)
	by_runoff.begin(_choices(["first", "second"]), 2)
	by_runoff.cast_vote(&"v1", _one(&"first"))
	by_runoff.cast_vote(&"v2", _one(&"second"))

	var runoff_result := by_runoff.resolve()
	_check(
		runoff_result.outcome == DotVoteResult.Outcome.RUNOFF,
		"RUNOFF puts the tied options to another vote"
	)
	_check(
		not runoff_result.summary.contains("wins"),
		"and does NOT announce a winner it is about to hold another vote about",
		runoff_result.summary
	)

	_done()


func _test_clock() -> void:
	_section("The clock warns, leads the vote, and fires exactly once")

	_v_clock_rules = _rules()
	_v_clock_rules.duration_sec = 100.0
	_v_clock_rules.vote_lead_sec = 20.0
	_v_clock_rules.warn_at_sec = PackedStringArray(["50", "10"])

	var clock := DotVoteClock.of(_v_clock_rules)

	var warnings := []
	var votes_due := []
	var expiries := []
	# Captured through Arrays: a GDScript lambda captures locals by value, so a
	# counter incremented inside a handler stays zero outside it and the test reports
	# a failure for a signal that fired perfectly.
	clock.warning.connect(func(left: float) -> void: warnings.append(left))
	clock.vote_due.connect(func(reason: StringName) -> void: votes_due.append(reason))
	clock.expired.connect(func(reason: StringName) -> void: expiries.append(reason))

	clock.start(DotVoteChoice.of(&"m"))
	_check(clock.running and is_equal_approx(clock.remaining, 100.0), "the clock starts")

	for i in range(45):
		clock.advance(1.0)

	_check(warnings.size() == 0, "no warning before the first mark")

	for i in range(10):
		clock.advance(1.0)

	_check(warnings.size() == 1, "one warning at 50 (got %d)" % warnings.size())

	for i in range(30):
		clock.advance(1.0)

	_check(
		votes_due.size() == 1,
		"the ballot is due 20 seconds before the end, not at the end",
		"a ballot that opens at expiry either runs late or gives players ten seconds"
	)
	_check(warnings.size() == 1, "and the second mark has not been reached yet")

	for i in range(30):
		clock.advance(1.0)

	_check(warnings.size() == 2, "the warning at 10 fires as it passes")
	_check(expiries.size() == 1, "it expires once")
	_check(
		votes_due.size() == 1,
		"and does not ask for a second vote on every tick after zero",
		"an unlatched limit opens a ballot a hundred times a second"
	)
	_check(clock.is_expired() and not clock.running, "and stays expired")

	_test_clock_2()


func _test_clock_2() -> void:
	# A lead of zero is a real configuration and must still open a ballot.
	var no_lead := _rules()
	no_lead.duration_sec = 10.0
	no_lead.vote_lead_sec = 0.0
	no_lead.warn_at_sec = PackedStringArray()

	var abrupt := DotVoteClock.of(no_lead)
	var abrupt_due := []
	abrupt.vote_due.connect(func(_r: StringName) -> void: abrupt_due.append(1))
	abrupt.start()

	for i in range(12):
		abrupt.advance(1.0)

	_check(
		abrupt_due.size() == 1,
		"a lead of zero still asks the players when the time is up",
		"otherwise a server with no lead expires and nobody is ever asked"
	)

	# Per-choice limits: the whole point of "each game has a time limit".
	var long_map := DotVoteChoice.of(&"epic")
	long_map.time_limit_sec = 2400.0

	var per_choice := DotVoteClock.of(_v_clock_rules)
	per_choice.start(long_map)
	_check(
		is_equal_approx(per_choice.duration, 2400.0),
		"a choice's own limit overrides the server's (%.0f)" % per_choice.duration
	)

	var unlimited := DotVoteChoice.of(&"forever")
	unlimited.time_limit_sec = 0.0
	var endless := DotVoteClock.of(_v_clock_rules)
	endless.start(unlimited)

	for i in range(500):
		endless.advance(1.0)

	_check(
		not endless.is_expired(),
		"and a choice with no limit never expires on the clock"
	)
	_check(
		endless.elapsed >= 500.0,
		"while still counting elapsed time, which the rtv delay needs (%.0f)"
			% endless.elapsed
	)

	_test_clock_3()


func _test_clock_3() -> void:
	# Rounds.
	var round_rules := _rules()
	round_rules.duration_sec = 0.0
	round_rules.round_limit = 5
	round_rules.vote_lead_rounds = 1

	var rounds := DotVoteClock.of(round_rules)
	var round_due := []
	rounds.vote_due.connect(func(_r: StringName) -> void: round_due.append(1))
	rounds.start()

	for i in range(3):
		rounds.note_round_end()

	_check(round_due.is_empty(), "three rounds of five is not yet a vote")
	rounds.note_round_end()
	_check(round_due.size() == 1, "the fourth of five is, with a lead of one round")
	_check(not rounds.is_expired(), "and the round limit has not been reached")
	_check(rounds.note_round_end(), "the fifth ends it")

	# Extending.
	var extend_rules := _rules()
	extend_rules.duration_sec = 60.0
	extend_rules.extend_seconds = 30.0
	extend_rules.max_extends = 2

	var extendable := DotVoteClock.of(extend_rules)
	extendable.start()

	for i in range(60):
		extendable.advance(1.0)

	_check(extendable.is_expired(), "it expires")
	_check(extendable.extend(), "and can be extended")
	_check(
		not extendable.is_expired() and is_equal_approx(extendable.remaining, 30.0),
		"which clears the latch and gives it a fresh ending (%.0f)" % extendable.remaining
	)
	_check(extendable.extend(), "and again")
	_check(
		not extendable.extend(),
		"but not a third time, because extend wins by default",
		"an unbounded extend runs one map until everybody else has left"
	)
	_check(extendable.extends_left() == 0, "and it says so")

	_done()


func _test_rtv() -> void:
	_section("Rocking the vote is a fraction of the people who are actually here")

	var rules := _rules()
	rules.duration_sec = 600.0
	rules.rtv_fraction = 0.6
	rules.rtv_min_players = 2
	rules.rtv_delay_sec = 60.0

	var clock := DotVoteClock.of(rules)
	clock.start()

	var early := clock.rock_the_vote(&"p1", 10)
	_check(
		not early.ok and early.code() == DotError.CODE_RATE_LIMITED,
		"rocking the vote is refused for the first minute",
		"otherwise the first thing that happens on every new map is somebody rtv-ing"
	)
	_check(
		early.error.message.contains("seconds"),
		"and says how long is left",
		early.error.message
	)

	for i in range(61):
		clock.advance(1.0)

	_check(clock.rtv_ready(), "and is allowed after the delay")
	_check(clock.rtv_needed(10) == 6, "six of ten is 60%% (%d)" % clock.rtv_needed(10))
	_check(clock.rtv_needed(1) == 0, "one player alone cannot, with a minimum of two")

	_check(clock.rock_the_vote(&"p1", 5).ok, "a player rocks the vote")
	_check(
		not clock.rock_the_vote(&"p1", 5).ok,
		"and typing it twice does not count twice",
		"otherwise two people end a map on a six-player server"
	)
	_check(clock.rtv_votes() == 1, "the tally is one")

	clock.rock_the_vote(&"p2", 5)
	_check(not clock.is_expired(), "two of five is not yet three")

	clock.unrock(&"p2")
	_check(clock.rtv_votes() == 1, "a player who leaves takes their vote with them")

	clock.rock_the_vote(&"p2", 5)
	clock.rock_the_vote(&"p3", 5)
	_check(clock.is_expired(), "and three of five ends it")

	_test_rtv_2()


func _test_rtv_2() -> void:
	var admin_rules := _rules()
	admin_rules.duration_sec = 600.0
	admin_rules.rtv_delay_sec = 0.0
	admin_rules.rtv_admin_instant = true

	var admin_clock := DotVoteClock.of(admin_rules)
	admin_clock.start()
	admin_clock.rock_the_vote(&"admin", 20, true)
	_check(admin_clock.is_expired(), "an admin can pass it alone when configured to")

	var keep_rules := _rules()
	keep_rules.duration_sec = 600.0
	keep_rules.rtv_delay_sec = 0.0
	keep_rules.rtv_forgets_leavers = false

	var stubborn := DotVoteClock.of(keep_rules)
	stubborn.start()
	stubborn.rock_the_vote(&"p1", 10)
	stubborn.unrock(&"p1")
	_check(
		stubborn.rtv_votes() == 1,
		"and a server can configure votes to survive a disconnect"
	)

	var off := _rules()
	off.rtv_enabled = false
	var silent := DotVoteClock.of(off)
	silent.start()
	_check(
		not silent.rock_the_vote(&"p1", 10).ok,
		"rocking the vote can be turned off entirely"
	)
	_check(silent.rtv_needed(10) == 0, "and then nothing can pass it")

	# Extending clears the tally: the people who wanted out have just been outvoted.
	var reset_rules := _rules()
	reset_rules.duration_sec = 600.0
	reset_rules.rtv_delay_sec = 0.0

	var reset_clock := DotVoteClock.of(reset_rules)
	reset_clock.start()
	reset_clock.rock_the_vote(&"p1", 10)
	reset_clock.extend()
	_check(
		reset_clock.rtv_votes() == 0,
		"an extend clears the rock-the-vote tally",
		"carrying it forward ends the map again the moment one more person agrees"
	)

	_done()
