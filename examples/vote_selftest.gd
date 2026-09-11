extends Node

## Proves the vote engine counts, refuses, expires and actually changes what is running.
##
## [codeblock]
## godot --headless --path . res://examples/vote_selftest.tscn
## [/codeblock]
##
## Exits non-zero on any failure.
##
## [b]Three of these sections matter more than the rest.[/b]
##
## "every setting is read by something" is a mechanical detector for this family's most
## repeated bug — an exported setting whose name occurs exactly once in its repository
## is a setting nothing reads, and one grep over the other addons found twenty-six of
## them. [DotVoteRules] declares more than forty settings in one resource, which is
## either the addon's best feature or twenty-six of that bug in a new repository. The
## check is the difference.
##
## The two integration sections run this addon against a real [code]DotGameManager[/code]
## and a real [code]DotMapCatalogue[/code], because "the two ends have never met" is how
## every expensive bug in this family has started: dot-map calling `ensure` on a client
## that offered `acquire`, the leaderboard reporter sending its file format as the wire,
## four call sites finding a null cloud client and none of them erroring. A vote that
## elects a winner and cannot make the server play it is exactly that shape.

const DATA := "user://dot_vote_selftest"

const CHECKS := 231

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


func _ready() -> void:
	DotLog.set_level(
		DotLog.Level.DEBUG if "--verbose" in OS.get_cmdline_user_args()
		else DotLog.Level.ERROR
	)
	_run.call_deferred()


func _run() -> void:
	print("dot-vote self-test")

	DotPaths.remove_tree(DATA)

	_test_choices()
	_test_rules_layering()
	_test_rules_validate()
	_test_history()
	_test_nominations()
	_test_counting()
	_test_tie_breaks()
	_test_quorum()
	_test_clock()
	_test_rtv()
	await _test_director_end_to_end()
	await _test_fill_modes()
	await _test_no_quorum_policies()
	await _test_apply_moments()
	_test_every_setting_is_read()
	await _test_real_game_manager()
	await _test_real_map_catalogue()

	DotPaths.remove_tree(DATA)

	print("")
	_check(
		_completed == _entered,
		"every section ran to its last line (%d of %d)" % [_completed, _entered],
		"a section that aborted stops adding checks and the total cannot show it"
	)

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	# The total the section counter cannot be. A runtime error inside a section aborts
	# that function, and the counter is satisfied because the section had already
	# announced itself. See docs/testing.md.
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


# --- Harness ---------------------------------------------------------------

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


# --- Choices ---------------------------------------------------------------

func _test_choices() -> void:
	_section("A choice knows what it needs, and hands out copies of its metadata")

	var choice := DotVoteChoice.of(&"arena", "Arena")
	choice.min_players = 4
	choice.max_players = 16

	_check(not choice.available_for(3), "a floor keeps it off a nearly-empty server")
	_check(choice.available_for(8), "and lets it through when there are enough")
	_check(not choice.available_for(20), "a ceiling keeps it off a full one")

	choice.nominate_only = true
	_check(not choice.available_for(8), "nominate_only keeps it out of a random fill")
	_check(choice.available_for(8, true), "and lets it through when it was nominated")
	_check(
		not choice.available_for(2, true),
		"but a nomination does not overrule the player count",
		"somebody nominating a 16-player map for two has not made it a better idea"
	)

	choice.enabled = false
	_check(not choice.available_for(8, true), "and disabled means disabled")

	var limits := DotVoteChoice.of(&"epic")
	_check(
		is_equal_approx(limits.duration_for(1800.0), 1800.0),
		"a choice with no limit of its own takes the server's"
	)

	limits.time_limit_sec = 2400.0
	_check(
		is_equal_approx(limits.duration_for(1800.0), 2400.0),
		"and its own overrides it (%.0f)" % limits.duration_for(1800.0)
	)

	limits.time_limit_sec = 0.0
	_check(
		is_equal_approx(limits.duration_for(1800.0), 0.0),
		"a limit of ZERO means no limit, not 'use the default'",
		"a server that wanted a map with no clock and got 30 minutes would change "
		+ "away from it with nothing to say why"
	)

	limits.round_limit = 5
	_check(limits.rounds_for(0) == 5, "the same for rounds")
	_check(
		DotVoteChoice.of(&"x").cooldown_for(5) == 5,
		"and for the cooldown"
	)

	# The aliasing this family has now found in DotLeaderboardDef, DotTimerZone.payload,
	# three of DotTimerRecord's dictionaries and DotMapDef.meta. A Dictionary is a
	# reference in GDScript, so a to_dictionary() that hands out its own member gives
	# every caller the same object.
	var source_choice := DotVoteChoice.of(&"m")
	source_choice.meta = {"nested": {"tier": 3}}

	var dict := source_choice.to_dictionary()
	var nested: Dictionary = (dict["meta"] as Dictionary)["nested"]
	nested["tier"] = 9

	_check(
		int((source_choice.meta["nested"] as Dictionary)["tier"]) == 3,
		"to_dictionary() deep-copies meta rather than aliasing it",
		"got %d" % int((source_choice.meta["nested"] as Dictionary)["tier"])
	)

	var round_tripped := DotVoteChoice.from_dictionary(source_choice.to_dictionary())
	_check(round_tripped.id == &"m", "and a choice survives a round trip")

	var full := DotVoteChoice.of(&"n", "N")
	full.time_limit_sec = 90.0
	full.nominate_only = true
	full.weight = 2.5
	full.cooldown_override = 2

	var back := DotVoteChoice.from_dictionary(full.to_dictionary())
	_check(
		is_equal_approx(back.time_limit_sec, 90.0) and back.nominate_only
			and is_equal_approx(back.weight, 2.5) and back.cooldown_override == 2,
		"with every field that decides anything"
	)

	_done()


# --- Rules -----------------------------------------------------------------

func _test_rules_layering() -> void:
	_section("Every rule is settable from a file, the environment or the command line")

	var rules := DotVoteRules.new()

	_check(
		rules.config_keys().size() >= 40,
		"there are %d settings" % rules.config_keys().size()
	)

	rules.apply_dictionary({"duration_sec": 900, "rtv_fraction": 0.5}, "file")
	_check(
		is_equal_approx(rules.duration_sec, 900.0)
			and is_equal_approx(rules.rtv_fraction, 0.5),
		"a dictionary layer applies"
	)

	rules.apply_dictionary({"max-options": "8", "closeWhenAllVoted": "false"}, "file")
	_check(
		rules.max_options == 8 and not rules.close_when_all_voted,
		"and matches keys written in kebab-case or camelCase"
	)

	# An enum written by name. Godot exports one as an integer, and a config file full
	# of integers is a file nobody can read or diff.
	rules.apply_dictionary({"method": "instant_runoff", "fill": "WEIGHTED"}, "file")
	_check(
		rules.method == DotVoteRules.Method.INSTANT_RUNOFF,
		"an enum can be written by name (method: instant_runoff)"
	)
	_check(
		rules.fill == DotVoteRules.Fill.WEIGHTED,
		"in any case, and with dashes or spaces"
	)
	_check(
		rules.enum_name("method") == "instant_runoff",
		"and reads back as its name for a console reply",
		rules.enum_name("method")
	)

	rules.apply_dictionary({"tie_break": "2"}, "file")
	_check(
		rules.tie_break == DotVoteRules.TieBreak.LEAST_RECENTLY_PLAYED,
		"a numeric enum still works, for a config written by a program"
	)

	var before := rules.method
	rules.apply_dictionary({"method": "borda_count"}, "file")
	_check(
		rules.method == before,
		"an unknown enum name is refused rather than silently taken as zero",
		"zero is PLURALITY, so a typo would quietly change how the server counts"
	)

	_check(
		DotVoteRules.enum_names_for("apply").has("end_of_round"),
		"the legal names are reportable, for a settings screen"
	)
	_check(
		DotVoteRules.enum_names_for("duration_sec").is_empty(),
		"and nothing is reported for a setting that is not an enum"
	)

	# The warning marks are text precisely so this works: an environment variable and
	# a command-line argument are strings.
	rules.apply_dictionary({"warn_at_sec": "120,60,10"}, "env")
	var marks := rules.warn_marks()
	_check(
		marks.size() == 3 and is_equal_approx(marks[0], 120.0)
			and is_equal_approx(marks[2], 10.0),
		"warning marks read from a comma-separated string, largest first"
	)

	rules.apply_dictionary({"warn_at_sec": "60,banana,10"}, "env")
	_check(
		rules.warn_marks().size() == 2,
		"and one unreadable mark costs one warning rather than the whole list"
	)

	_check(rules.env_prefix() == "DOT_VOTE_", "the environment prefix is declared")
	_check(rules.cli_prefix() == "--vote-", "and so is the command-line one")

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
	_check(
		not no_clock.validate().ok,
		"a time-limit trigger with no time limit is refused",
		"nothing would ever open a vote, silently"
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


# --- History ---------------------------------------------------------------

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


# --- Nominations -----------------------------------------------------------

func _test_nominations() -> void:
	_section("Nominations are capped, deduplicated and kept in order")

	var rules := _rules()
	rules.nominations_per_player = 1
	rules.nominations_max = 3

	var noms := DotVoteNominations.of(rules)

	_check(noms.add(&"alice", &"a").ok, "a player nominates")
	_check(
		not noms.add(&"alice", &"a").ok,
		"and the same player cannot nominate it twice",
		"pressing a key again because nothing visible happened is not support"
	)
	_check(
		noms.add(&"bob", &"a").ok,
		"but another player may second it, which is what a popularity fill counts"
	)
	_check(int(noms.counts()[&"a"]) == 2, "and it is counted twice")

	var strict := _rules()
	strict.nomination_seconding = false
	var no_seconds := DotVoteNominations.of(strict)
	no_seconds.add(&"alice", &"a")
	_check(
		not no_seconds.add(&"bob", &"a").ok,
		"a server can refuse seconding and get SourceMod's behaviour instead"
	)

	_check(noms.add(&"alice", &"b").ok, "a second nomination from one player…")
	_check(
		noms.by_voter(&"alice") == ([&"b"] as Array[StringName]),
		"…REPLACES their own first when they may only have one",
		"'you already nominated something' is not what somebody who has changed "
		+ "their mind wants to hear, and withdrawing first is a command nobody knows"
	)
	_check(
		noms.has_id(&"a"),
		"without taking away the other player's, which was never theirs to withdraw"
	)

	# alice holds b; bob still holds the second on a.
	_check(noms.remove(&"bob", &"a"), "a player withdraws their own")
	_check(
		not noms.remove(&"bob", &"b"),
		"and cannot withdraw somebody else's"
	)
	_check(
		not noms.has_id(&"a"),
		"and the last nomination of a thing withdrawn takes it off the list"
	)

	_check(noms.add(&"carol", &"c").ok, "another player nominates")
	_check(noms.add(&"dave", &"d").ok, "and another")
	_check(
		not noms.add(&"erin", &"e").ok,
		"and the list fills up (%d of %d)" % [noms.size(), rules.nominations_max]
	)
	_check(
		noms.add(&"erin", &"e", true).ok,
		"an admin's nomination bypasses the cap"
	)

	var ordered := noms.ordered_ids()
	_check(
		ordered[0] == &"b" and ordered[1] == &"c" and ordered[2] == &"d",
		"nomination order is preserved, which is what fills the reserved places",
		", ".join(DotVoteBallot._as_strings(ordered))
	)
	_check(noms.first_index(&"c") == 1, "and is reportable as a tie-break key")
	_check(
		noms.first_index(&"never") > 1000,
		"something never nominated sorts behind everything nominated"
	)

	var counts := noms.counts()
	_check(int(counts.get(&"b", 0)) == 1, "counts are per id, for a most-nominated fill")

	_check(noms.remove_voter(&"alice") == 1, "everything one player nominated can go")

	var off := _rules()
	off.nominations_enabled = false
	_check(
		not DotVoteNominations.of(off).add(&"alice", &"a").ok,
		"and nominations can be turned off entirely"
	)

	var many := _rules()
	many.nominations_per_player = 2
	many.nominations_max = 0

	var multi := DotVoteNominations.of(many)
	_check(multi.add(&"alice", &"a").ok and multi.add(&"alice", &"b").ok,
		"a server can allow more than one each")
	_check(
		not multi.add(&"alice", &"c").ok,
		"and the third is refused rather than replacing anything",
		"replacing is only right when there is exactly one to replace"
	)

	_done()


# --- Counting --------------------------------------------------------------

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
	var approval_rules := _rules()
	approval_rules.method = DotVoteRules.Method.APPROVAL
	approval_rules.include_extend = false
	approval_rules.approval_max_choices = 2

	var approval := DotVoteBallot.of(approval_rules)
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


# --- Extend, keep and ties -------------------------------------------------

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


# --- The clock -------------------------------------------------------------

func _test_clock() -> void:
	_section("The clock warns, leads the vote, and fires exactly once")

	var rules := _rules()
	rules.duration_sec = 100.0
	rules.vote_lead_sec = 20.0
	rules.warn_at_sec = PackedStringArray(["50", "10"])

	var clock := DotVoteClock.of(rules)

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

	var per_choice := DotVoteClock.of(rules)
	per_choice.start(long_map)
	_check(
		is_equal_approx(per_choice.duration, 2400.0),
		"a choice's own limit overrides the server's (%.0f)" % per_choice.duration
	)

	var unlimited := DotVoteChoice.of(&"forever")
	unlimited.time_limit_sec = 0.0
	var endless := DotVoteClock.of(rules)
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


# --- The director ----------------------------------------------------------

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


func _test_director_end_to_end() -> void:
	_section("A whole vote: nominate, rock it, count it, and change what is running")

	var applied := []
	var source := DotVoteListSource.of(_choices(["alpha", "bravo", "charlie", "delta"]))
	source.apply_fn = func(id: StringName) -> DotResult:
		applied.append(id)
		return DotResult.success(id)

	var rules := _rules()
	rules.duration_sec = 100.0
	rules.vote_lead_sec = 20.0
	rules.vote_duration_sec = 10.0
	rules.include_extend = false
	rules.close_when_all_voted = false
	rules.rtv_delay_sec = 0.0
	rules.apply = DotVoteRules.Apply.IMMEDIATE

	var director := _make_director(rules, source)

	var opened := []
	var changed := []
	director.vote_opened.connect(func(options: Array, _s: float) -> void:
		opened.append(options)
	)
	director.change_due.connect(func(id: StringName, _c: DotVoteChoice) -> void:
		changed.append(id)
	)

	director.begin(&"alpha")
	source.current = &"alpha"

	_check(director.current_id() == &"alpha", "the director knows what is running")
	_check(
		director.history.plays_since(&"alpha") == 0,
		"and records it as played, so it goes on cooldown"
	)

	var nominated := director.nominate(&"p1", &"delta")
	_check(nominated.ok, "a player nominates something", str(nominated.error))
	_check(
		not director.nominate(&"p2", &"alpha").ok,
		"and cannot nominate what is already running",
		"'play this again' is what extending is for"
	)
	_check(
		not director.nominate(&"p2", &"nonsense").ok,
		"nor something that does not exist"
	)

	for i in range(81):
		director.advance(1.0)

	_check(director.is_voting(), "the ballot opens 20 seconds before the end")
	_check(opened.size() == 1, "and says so once")

	var options := director.ballot.option_ids()
	_check(options.has(&"delta"), "the nomination is on it")
	_check(
		not options.has(&"alpha"),
		"and what is currently running is not",
		"having both it and 'extend' on a ballot splits the vote of the people "
		+ "who want the same thing"
	)
	_check(
		director.nominations.size() == 0,
		"the nominations are consumed by the ballot rather than carried into the next"
	)

	director.cast_one(&"p1", &"delta")
	director.cast_one(&"p2", &"delta")
	director.cast_one(&"p3", &"bravo")

	_check(director.ballot.voter_count() == 3, "three of four vote")

	for i in range(11):
		director.advance(1.0)

	_check(not director.is_voting(), "the ballot closes on its own clock")
	_check(changed.size() == 1 and changed[0] == &"delta", "delta wins")
	_check(
		applied.size() == 1 and applied[0] == &"delta",
		"and the source is actually asked to play it",
		"a vote that elects a winner and cannot make the server play it is the "
		+ "family's own 'the two ends never met'"
	)
	_check(
		director.current_id() == &"delta",
		"the director follows the change and restarts the clock"
	)
	_check(
		director.clock.remaining > 95.0,
		"with a fresh clock (%.0f of 100)" % director.clock.remaining
	)

	# Rocking the vote opens a ballot rather than changing blind.
	director.rules.rtv_min_players = 2
	director.rules.rtv_fraction = 0.5

	director.rock_the_vote(&"p1")
	_check(not director.is_voting(), "one of four is not enough to rock the vote")
	director.rock_the_vote(&"p2")

	_check(
		not director.is_voting(),
		"two of four passes it, but the last vote's cooldown is still running"
	)

	for i in range(int(rules.vote_cooldown_sec) + 1):
		director.advance(1.0)

	_check(
		director.is_voting(),
		"and the ballot opens as soon as the cooldown is up",
		"the clock fires ONCE and latches, so a vote_due refused by the cooldown "
		+ "was the last one that would ever arrive and the server stopped changing"
	)

	# Everybody voting closes it early.
	director.rules.close_when_all_voted = true
	director.ballot.eligible = 2
	director.cast_one(&"p1", director.ballot.option_ids()[0])
	director.cast_one(&"p2", director.ballot.option_ids()[0])
	director.advance(0.1)
	_check(
		not director.is_voting(),
		"and a ballot everybody has voted in closes without waiting out the timer"
	)

	director.queue_free()
	_done()


func _test_fill_modes() -> void:
	_section("Five ways to fill a ballot, and each fills it differently")

	var source := DotVoteListSource.of(_choices(["a", "b", "c", "d", "e", "f"]))

	var sequential := _rules()
	sequential.fill = DotVoteRules.Fill.SEQUENTIAL
	sequential.max_options = 2
	sequential.nomination_slots = 0
	sequential.cooldown = 0
	sequential.include_extend = false

	var director := _make_director(sequential, source)
	director.begin(&"")

	var first := director.build_options(4)
	var second := director.build_options(4)

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

	director.rules.fill = DotVoteRules.Fill.LEAST_RECENTLY_PLAYED
	director.history.note_played(&"a", 0.0)
	director.history.note_played(&"b", 0.0)
	director.rules.cooldown = 0

	var by_age := director.build_options(4)
	_check(
		by_age[0].id != &"b",
		"LEAST_RECENTLY_PLAYED puts the most recently played last (%s)" % by_age[0].id
	)

	director.rules.fill = DotVoteRules.Fill.WEIGHTED
	director.rules.max_options = 1

	for choice in source.entries:
		choice.weight = 0.0

	source.entries[3].weight = 10.0

	var weighted := director.build_options(4)
	_check(
		weighted.size() == 1 and weighted[0].id == &"d",
		"WEIGHTED never picks a weight of zero",
		"a weight of 0 means 'never offer this', not 'offer this last'"
	)

	for choice in source.entries:
		choice.weight = 1.0

	director.rules.fill = DotVoteRules.Fill.MOST_NOMINATED
	director.rules.max_options = 3
	director.rules.nomination_slots = 0
	_check(
		director.nominations.add(&"p1", &"f").ok
			and director.nominations.add(&"p2", &"f").ok,
		"two players can want the same thing, which is what a popularity fill counts"
	)
	director.nominations.add(&"p3", &"e")
	_check(
		not director.nominations.add(&"p1", &"f").ok,
		"and one player cannot want it twice"
	)

	var nominated := director.build_options(4)
	_check(
		nominated[0].id == &"f",
		"MOST_NOMINATED puts the most-wanted first (%s)" % nominated[0].id
	)
	director.nominations.clear()

	# Everything on cooldown must not produce an empty ballot.
	director.rules.fill = DotVoteRules.Fill.RANDOM
	director.rules.cooldown = 64
	director.rules.cooldown_max_fraction = 1.0
	director.rules.max_options = 4

	for id in [&"a", &"b", &"c", &"d", &"e", &"f"]:
		director.history.note_played(id, 0.0)

	var desperate := director.build_options(4)
	_check(
		not desperate.is_empty(),
		"everything on cooldown drops the cooldown rather than the ballot (%d)"
			% desperate.size(),
		"offering nothing leaves the server where it is for ever with no error anywhere"
	)

	# A choice nobody may play is not offered, whatever the fill.
	director.rules.cooldown = 0
	source.entries[0].enabled = false
	source.entries[1].min_players = 20

	var filtered := director.build_options(4)
	var filtered_ids := PackedStringArray()

	for choice in filtered:
		filtered_ids.append(String(choice.id))

	_check(
		not filtered_ids.has("a") and not filtered_ids.has("b"),
		"a disabled choice and one wanting twenty players are both left off"
	)

	director.queue_free()
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

	var director := _make_director(rules, source)
	director.begin(&"a")
	source.current = &"a"

	for i in range(61):
		director.advance(1.0)

	_check(director.is_voting(), "the ballot opens with 40 seconds left")
	director.cast_one(&"p1", &"b")

	for i in range(6):
		director.advance(1.0)

	_check(
		director.pending_id() == &"b",
		"the winner is decided and waiting (%s)" % director.pending_id()
	)
	_check(
		applied.is_empty(),
		"and END_OF_TIME has not changed anything yet",
		"the whole point of a lead is that the vote finishes before the time does"
	)

	for i in range(40):
		director.advance(1.0)

	_check(
		applied.size() == 1 and applied[0] == &"b",
		"and the change happens when the clock runs out"
	)

	# The delay a player reads the result in.
	var delayed := _rules()
	delayed.apply_delay_sec = 5.0
	delayed.apply = DotVoteRules.Apply.IMMEDIATE
	delayed.include_extend = false
	delayed.vote_duration_sec = 1.0
	delayed.duration_sec = 600.0
	delayed.cooldown = 0

	var delayed_applied := []
	var delayed_source := DotVoteListSource.of(_choices(["a", "b"]))
	delayed_source.apply_fn = func(id: StringName) -> DotResult:
		delayed_applied.append(id)
		return DotResult.success(id)

	var slow := _make_director(delayed, delayed_source)
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

	director.queue_free()
	slow.queue_free()
	advisory.queue_free()
	_done()


# --- The settings sweep ----------------------------------------------------

## Fails for any setting nothing reads.
##
## [b]This family's most repeated bug has a mechanical detector[/b] — an exported
## setting whose name occurs exactly once in its repository is a setting nothing reads
## — and one grep across the other addons found twenty-six of them: a whole
## [code]Dot2DConfig[/code] nothing consulted, a [code]DotTeam.spawn_tag[/code] that
## left every team spawning in the other team's base, a replay recorder with a
## documented ceiling and no ceiling.
##
## [DotVoteRules] puts more than forty settings in one resource, which makes this addon
## either the best answer to that or twenty-six new instances of it. So the detector
## runs here rather than in somebody's terminal a year from now.
func _test_every_setting_is_read() -> void:
	_section("Every setting is read by something")

	var sources := {}
	_read_scripts("res://addons/dot_vote", sources)

	_check(sources.size() >= 12, "%d scripts scanned" % sources.size())

	var rules := DotVoteRules.new()
	var declarations := str(sources.get("res://addons/dot_vote/core/dot_vote_rules.gd", ""))
	var unread := PackedStringArray()

	for key in rules.config_keys():
		if _reads_setting(key, sources, declarations):
			continue

		unread.append(key)

	_check(
		unread.is_empty(),
		"all %d settings are read somewhere" % rules.config_keys().size(),
		"declared and read by nothing: %s" % ", ".join(unread)
	)

	_done()


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
##
## Two ways count. Outside the rules themselves a setting is reached through a
## variable called [code]rules[/code] — [code]rules.max_options[/code],
## [code]director.rules.apply[/code] — and inside them it is a bare identifier on a
## line that is not its own declaration. Matching a bare identifier everywhere would
## be the wrong check: [DotVoteChoice] has an [code]enabled[/code] too, and a sweep
## that counted it would report [member DotVoteRules.enabled] as read by a file that
## has never heard of it.
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


# --- The integrations ------------------------------------------------------

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
	var server: Node = server_script.new()
	server.name = "Server"
	server.set("config", config)
	server.set("config_file", "")
	server.set("auto_boot", false)
	add_child(server)

	var booted: Variant = await server.call("boot")

	if not _check(
		booted is DotResult and (booted as DotResult).ok,
		"the server boots",
		str(booted)
	):
		server.queue_free()
		_done()
		return

	var descriptor_script: GDScript = load(
		"res://addons/dot_server/game/dot_game_descriptor.gd"
	)
	var games: Object = server.get("games")

	for entry: Array in [["world_a", "World A", 1800], ["world_b", "World B", 60]]:
		var descriptor: Object = descriptor_script.new()
		descriptor.set("game_id", entry[0])
		descriptor.set("display_name", entry[1])
		descriptor.set("version", "1.0.0")
		descriptor.set("scene", "res://examples/fixtures/%s.tscn" % entry[0])
		# The per-game settings a vote reads, written beside the game rather than in a
		# table of ids somewhere else. This is what "each game has a time limit" is.
		descriptor.set("metadata", {"vote": {"time_limit_sec": entry[2], "weight": 2.0}})
		games.call("add_game", descriptor)

	var loaded: Variant = await games.call("change_game", "world_a", "boot")
	_check(
		loaded is DotResult and (loaded as DotResult).ok,
		"and loads a game",
		str(loaded)
	)

	var source := DotVoteGameSource.of(games)

	_check(source.is_usable(), "the game source recognises a real game manager")
	_check(source.choices().size() == 2, "and reads both games out of it")
	_check(
		source.current_id() == &"world_a",
		"and knows which one is running (%s)" % source.current_id(),
		"a source that cannot see the current game offers it on its own ballot"
	)

	var world_b := source.find(&"world_b")
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

	var excluding := DotVoteGameSource.of(games)
	excluding.excluded = [&"world_a"] as Array[StringName]
	_check(
		excluding.choices().size() == 1,
		"a lobby can be kept off the ballot entirely"
	)

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

	var director := _make_director(rules, source)
	director.begin(&"world_a")

	_check(
		is_equal_approx(director.clock.duration, 1800.0),
		"the running game's own limit is what the clock counts (%.0f)"
			% director.clock.duration,
		"a thirty-minute game and a one-minute game under one global limit is a "
		+ "server that cuts half its content short"
	)

	director.open_vote()
	_check(
		director.ballot.option_ids().has(&"world_b"),
		"the other game is on the ballot"
	)

	director.cast_one(&"p1", &"world_b")
	director.close_vote()

	_check(director.pending_id() == &"world_b", "and wins")

	var applied: DotResult = await director.apply_pending()

	_check(applied.ok, "the change goes through a real change_game", str(applied.error))
	_check(
		source.current_id() == &"world_b",
		"and the SERVER is now running the game the players voted for (%s)"
			% source.current_id(),
		"this is the join the whole addon exists for: a ballot that elects a winner "
		+ "and cannot make the server play it is the family's own 'two ends never met'"
	)
	_check(
		director.current_id() == &"world_b",
		"and the director followed it, so the new game's clock is running"
	)
	_check(
		is_equal_approx(director.clock.duration, 60.0),
		"under the NEW game's time limit (%.0f)" % director.clock.duration
	)

	# The console and chat commands, on the real console this server booted with.
	var replies := PackedStringArray()
	var console: Object = server.get("console")
	var commands := DotVoteCommands.install(console, director)

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

	var renamed := DotVoteCommands.new()
	renamed.director = director
	renamed.prefix = "sv_"
	renamed.names = {"rtv": "rockthevote"}
	_check(
		renamed.command_name("rtv") == "sv_rockthevote",
		"every command name is configurable (%s)" % renamed.command_name("rtv"),
		"dot-server already ships a `vote`, and a timer server's players type !rtv"
	)

	director.queue_free()
	server.queue_free()
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
	var catalogue: Object = catalogue_script.new()

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
		catalogue.call("add", map)

	var session_script: GDScript = load(
		"res://addons/dot_map/runtime/dot_map_session.gd"
	)
	var session: Node = session_script.new()
	session.name = "Maps"
	session.set("catalogue", catalogue)
	session.set("world_ref", DotNodeRef.of_created(&"World", Node))
	add_child(session)
	await get_tree().process_frame

	# _ready builds its own empty catalogue when it finds none, so it goes back on
	# afterwards. The alternative is a catalogue_path, and a suite that writes a JSON
	# file to test an object it already has is testing the file.
	session.set("catalogue", catalogue)

	var first: Variant = await session.call("change_to", &"map_one")
	_check(
		first is DotResult and (first as DotResult).ok,
		"a real map loads",
		str(first)
	)

	var source := DotVoteMapSource.of(catalogue, session)

	_check(source.is_usable(), "the map source recognises a real catalogue")
	_check(source.choices().size() == 2, "and reads both maps out of it")
	_check(
		source.current_id() == &"map_one",
		"and knows which one is loaded (%s)" % source.current_id()
	)
	_check(source.supports_apply(), "and can change it, having been given a session")

	var one := source.find(&"map_one")
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

	var surf_only := DotVoteMapSource.of(catalogue, session)
	surf_only.kinds = [&"surf"] as Array[StringName]
	_check(
		surf_only.choices().size() == 1,
		"a surf-only server offers only surf maps",
		"the alternative is a second catalogue that is a subset of the first, "
		+ "which is two lists of maps that disagree"
	)

	var rules := _rules()
	rules.duration_sec = 600.0
	rules.vote_lead_sec = 0.0
	rules.include_extend = false
	rules.cooldown = 0
	rules.min_players_to_vote = 1

	var director := _make_director(rules, source)
	director.begin(&"map_one")

	_check(
		is_equal_approx(director.clock.duration, 900.0),
		"the loaded map's own limit is what the clock counts (%.0f)"
			% director.clock.duration
	)

	director.open_vote()
	director.cast_one(&"p1", &"map_two")
	director.close_vote()

	var applied: DotResult = await director.apply_pending()

	_check(applied.ok, "the change goes through a real change_to", str(applied.error))
	_check(
		source.current_id() == &"map_two",
		"and the SESSION is now on the map the players voted for (%s)"
			% source.current_id()
	)
	_check(
		is_equal_approx(director.clock.duration, rules.duration_sec),
		"a map with no expected length falls back to the server's limit (%.0f)"
			% director.clock.duration
	)

	var listing_only := DotVoteMapSource.of(catalogue)
	_check(
		not listing_only.supports_apply(),
		"a source with no session lists and changes nothing"
	)
	_check(
		not (await listing_only.apply(&"map_two")).ok,
		"and says so rather than pretending"
	)

	director.queue_free()
	session.queue_free()
	await get_tree().process_frame

	_done()
