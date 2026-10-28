extends "res://examples/selftest/tests_i.gd"

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
## them. [DotVoteRules] declares eighty settings in one resource, which is
## either the addon's best feature or twenty-six of that bug in a new repository. The
## check is the difference.
##
## The two integration sections run this addon against a real [code]DotGameManager[/code]
## and a real [code]DotMapCatalogue[/code], because "the two ends have never met" is how
## every expensive bug in this family has started: dot-map calling `ensure` on a client
## that offered `acquire`, the leaderboard reporter sending its file format as the wire,
## four call sites finding a null cloud client and none of them erroring. A vote that
## elects a winner and cannot make the server play it is exactly that shape.

const CHECKS := 605


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
	_test_cfg_layout()
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
	_test_chooser_settings()
	_test_countdown()
	_test_score_limit()
	_test_round_end_trigger()
	_test_lead_fraction()
	_test_ballot_options()
	_test_nothing_to_vote_for()
	_test_single_voter_auto()
	_test_rtv_parity()
	_test_manual_rtv()
	_test_list_fn()
	_test_subscribed_maps()
	_test_end_vote_switch()
	_test_no_votes()
	_test_hibernation()
	_test_empty_server()
	_test_admin_and_queries()
	_test_clock_view()
	_test_time_up()
	_test_ballot_view()
	_test_voter_names()
	_test_every_setting_is_read()
	_test_every_layer_reaches_a_ballot()
	await _test_real_game_manager()
	await _test_real_map_catalogue()
	await _test_map_menu()
	_test_describe()

	DotPaths.remove_tree(DATA)

	print("")
	_check(
		_completed == _entered,
		"every section ran to its last line (%d of %d)" % [_completed, _entered],
		"a section that aborted stops adding checks and the total cannot show it"
	)

	print("")
	_test_votebans()
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
