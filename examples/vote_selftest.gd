extends "res://examples/selftest/tests_c.gd"

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

var _v_votebans_rig: Array
var _v_votebans_bans: DotVoteBans
var _v_votebans_banned: Array
var _v_votebans_res: DotResult
var _v_map_menu_applied: Array
var _v_map_menu_source: DotVoteListSource
var _v_map_menu_rules: DotVoteRules
var _v_map_menu_director: DotVoteDirector
var _v_map_menu_announced: Array
var _v_map_menu_console: Node
var _v_map_menu_commands: DotVoteCommands
var _v_map_menu_sent: Array
var _v_map_menu_replies: PackedStringArray
var _v_map_menu_player: Object
var _v_map_menu_moderator: Object
var _v_map_menu_now_ids: Array
var _v_choices_limits: DotVoteChoice
var _v_rules_layering_rules: DotVoteRules
var _v_nominations_rules: DotVoteRules
var _v_nominations_noms: DotVoteNominations
var _v_counting_approval_rules: DotVoteRules
var _v_clock_rules: DotVoteRules
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


func _test_votebans() -> void:
	_section("A voteban: enabled, by role, passes on yes, fails on no or time, and the game may start one")

	_v_votebans_rig = _ban_rig(6)
	_v_votebans_bans = _v_votebans_rig[0]
	_v_votebans_banned = _v_votebans_rig[1]

	_v_votebans_res = _v_votebans_bans.start(&"p1", &"p2", "griefing")
	_check(_v_votebans_res.ok and _v_votebans_bans.is_open(), "a player starts a voteban on another", str(_v_votebans_res.error.message if not _v_votebans_res.ok else ""))
	_check(not _v_votebans_bans.start(&"p3", &"p4").ok, "a second voteban is refused while one is open")
	# 5 eligible, 0.6 -> 3 yes. The starter is the first.
	_check(_v_votebans_bans.yes_needed() == 3, "the pass threshold is a share of everybody but the target (%d)" % _v_votebans_bans.yes_needed())
	_check(not _v_votebans_bans.vote(&"p2", true).ok, "the target cannot vote on their own ban")
	_v_votebans_bans.vote(&"p3", true)
	_check(_v_votebans_bans.is_open() and _v_votebans_banned.is_empty(), "two yes of three needed leaves it open")
	_v_votebans_bans.vote(&"p4", true)
	_check(not _v_votebans_bans.is_open() and _v_votebans_banned.size() == 1 and _v_votebans_banned[0][0] == &"p2" and is_equal_approx(_v_votebans_banned[0][1], 60.0),
			"the third yes passes it and bans the target for the cvar's length")

	# Same target again soon: cooldown.
	_check(not _v_votebans_bans.start(&"p3", &"p2").ok, "the same target is not voted on again inside the cooldown")
	_v_votebans_bans.advance(121.0)
	_check(_v_votebans_bans.start(&"p3", &"p2").ok, "after the cooldown it may be")
	_v_votebans_bans.cancel()

	# Immune role.
	_v_votebans_rig = _ban_rig(6)
	_v_votebans_bans = _v_votebans_rig[0]
	_check(not _v_votebans_bans.start(&"p1", &"p0").ok, "an immune role cannot be voted against")
	_check(not _v_votebans_bans.start(&"", &"p0").ok, "not even by the game")

	# Per role: only staff may start.
	_v_votebans_bans.rules.start_roles = PackedStringArray(["admin"])
	_check(not _v_votebans_bans.start(&"p1", &"p2").ok, "a role that may not start one is refused")
	_check(_v_votebans_bans.start(&"p0", &"p2").ok, "a role that may, may")
	_v_votebans_bans.cancel()

	# Off per server.
	_v_votebans_rig = _ban_rig(6)
	_v_votebans_bans = _v_votebans_rig[0]
	_v_votebans_bans.rules.enabled = false
	_check(not _v_votebans_bans.start(&"p1", &"p2").ok and not _v_votebans_bans.start(&"", &"p2").ok, "with the server's switch off nothing starts one, the game included")

	# No wins, time loses.
	_v_votebans_rig = _ban_rig(6)
	_v_votebans_bans = _v_votebans_rig[0]
	_v_votebans_banned = _v_votebans_rig[1]
	_v_votebans_bans.start(&"p1", &"p2")
	_v_votebans_bans.vote(&"p3", false)
	_v_votebans_bans.vote(&"p4", false)
	_v_votebans_bans.vote(&"p5", false)
	_check(not _v_votebans_bans.is_open() and _v_votebans_banned.is_empty(), "enough no votes to make the threshold impossible fails it at once")
	_v_votebans_bans = (_ban_rig(6))[0]
	_v_votebans_banned = []
	_v_votebans_bans.ban_fn = func(t: StringName, m: float, r: String) -> void: _v_votebans_banned.append(t)
	_v_votebans_bans.start(&"p1", &"p2")
	_v_votebans_bans.advance(31.0)
	_check(not _v_votebans_bans.is_open() and _v_votebans_banned.is_empty(), "silence is a no: the clock running out bans nobody")

	_test_votebans_2()


func _test_votebans_2() -> void:
	# Too few voters.
	_v_votebans_rig = _ban_rig(3)
	_v_votebans_bans = _v_votebans_rig[0]
	_check(not _v_votebans_bans.start(&"p1", &"p2").ok, "a server with too few other players refuses (min voters)")

	# The game's own: no starter, no starter yes, its reason carried to the ban.
	_v_votebans_rig = _ban_rig(6)
	_v_votebans_bans = _v_votebans_rig[0]
	_v_votebans_banned = _v_votebans_rig[1]
	_v_votebans_res = _v_votebans_bans.start(DotVoteBans.GAME, &"p2", "team damage")
	_check(_v_votebans_res.ok and _v_votebans_bans.is_open(), "the game starts one with a reason")
	_v_votebans_bans.vote(&"p1", true)
	_v_votebans_bans.vote(&"p3", true)
	_v_votebans_bans.vote(&"p4", true)
	_check(_v_votebans_banned.size() == 1 and "team damage" in str(_v_votebans_banned[0][2]), "its reason is on the ban")

	# A voter leaving shrinks the electorate.
	_v_votebans_rig = _ban_rig(5)
	_v_votebans_bans = _v_votebans_rig[0]
	_v_votebans_banned = _v_votebans_rig[1]
	_v_votebans_bans.rules.min_voters = 2
	_v_votebans_bans.start(&"p1", &"p2")
	_v_votebans_bans.forget_voter(&"p4")
	_v_votebans_bans.forget_voter(&"p3")
	_v_votebans_bans.forget_voter(&"p0")
	_check(_v_votebans_bans.yes_needed() == 1 and not _v_votebans_bans.is_open() and _v_votebans_banned.size() == 1, "a leaver shrinks the electorate and the threshold with it")

	# cvars on a real console.
	if ResourceLoader.exists("res://addons/dot_server/console/dot_console.gd"):
		var console: Object = load("res://addons/dot_server/console/dot_console.gd").new()
		_v_votebans_rig = _ban_rig(6)
		_v_votebans_bans = _v_votebans_rig[0]
		var bound := _v_votebans_bans.bind_commands(console)
		_check(bound.ok, "the commands and cvars register on a console", str(bound.error.message if not bound.ok else ""))
		var cv: Variant = console.call("find_cvar", "sv_voteban_minutes")
		_check(cv is Object, "sv_voteban_minutes is a cvar")
		if cv is Object:
			(cv as Object).call("set_value", "15")
			_v_votebans_bans.rules.refresh()
			_check(is_equal_approx(_v_votebans_bans.rules.ban_minutes, 15.0), "and the console's value is the ban's length")
		console.free()
	else:
		_check(false, "dot-server is present so the voteban cvars can be run", "addons/dot_server is not linked")

	_done()


## M in every game: the server half, on a real dot-server console with real contexts, so the
## permission check is dot-server's own and not a fake that agrees with this file.
func _test_map_menu() -> void:
	_section("The map menu: the owner's flag changes, anybody else votes")

	if not ResourceLoader.exists("res://addons/dot_server/console/dot_console.gd"):
		_check(false, "dot-server is present so the map menu can be run", "addons/dot_server is not linked")
		_done()
		return

	_v_map_menu_applied = []
	_v_map_menu_source = DotVoteListSource.of(_choices(["atrium", "yard", "docks", "foundry"]))
	_v_map_menu_source.apply_fn = func(id: StringName) -> DotResult:
		_v_map_menu_applied.append(id)
		return DotResult.success(id)
	_v_map_menu_source.entries[2].group = &"capture"
	_v_map_menu_source.entries[3].meta = {"thumbnail": "res://maps/foundry.png"}
	_v_map_menu_rules = _rules()
	_v_map_menu_rules.vote_cooldown_sec = 0.0
	_v_map_menu_rules.rtv_delay_sec = 0.0
	_v_map_menu_director = _make_director(_v_map_menu_rules, _v_map_menu_source)
	_v_map_menu_director.begin(&"atrium")
	_v_map_menu_announced = []
	_v_map_menu_director.announce_fn = func(line: String) -> void: _v_map_menu_announced.append(line)

	_v_map_menu_console = (load("res://addons/dot_server/console/dot_console.gd") as GDScript).new()
	add_child(_v_map_menu_console)
	_v_map_menu_commands = DotVoteCommands.install(_v_map_menu_console, _v_map_menu_director)
	_v_map_menu_sent = []
	_v_map_menu_commands.map_menu.notice_fn = func(_ctx: Object, data: Dictionary) -> bool:
		_v_map_menu_sent.append(data)
		return true
	var cmd: Variant = _v_map_menu_console.call("find_command", "mapmenu")
	_check(cmd != null and str((cmd as Object).get("permission")) == "", "`mapmenu` is registered, open to everybody: the gate is inside")
	_check(_v_map_menu_commands.map_menu.cvar != null and _v_map_menu_commands.map_menu.required_flag() == "generic",
		"with sv_map_menu_flag, staff (generic) by default")

	var ctx_script: GDScript = load("res://addons/dot_server/console/dot_cmd_context.gd")
	_v_map_menu_replies = PackedStringArray()
	_v_map_menu_player = ctx_script.new()
	_v_map_menu_player.set("source", 3)
	_v_map_menu_player.set("reply_sink", func(t: String) -> void: _v_map_menu_replies.append(t))
	_v_map_menu_moderator = ctx_script.new()
	_v_map_menu_moderator.set("source", 3)
	_v_map_menu_moderator.set("permissions", PackedStringArray(["generic", "kick", "mute"]))
	_v_map_menu_moderator.set("reply_sink", func(t: String) -> void: _v_map_menu_replies.append(t))

	await _test_map_menu_2()


func _test_map_menu_2() -> void:
	_v_map_menu_console.call("execute", "mapmenu", _v_map_menu_player)
	var offer: Dictionary = _v_map_menu_sent.back() if not _v_map_menu_sent.is_empty() else {}
	var maps: Array = offer.get("maps", [])
	_check(maps.size() == 4 and bool(maps[0]["current"]) and str(maps[2].get("mode", "")) == "Capture"
		and str(maps[3].get("thumbnail", "")) == "res://maps/foundry.png",
		"the list: every map, the current one marked, a mode and a picture where the choice has them")
	_check(offer.get("allowed") == false and offer.get("vote") == true and offer.get("flag") == "generic",
		"a player without the flag is offered a vote, and told which flag it would take")

	_v_map_menu_console.call("execute", "mapmenu", _v_map_menu_moderator)
	_check(bool((_v_map_menu_sent.back() as Dictionary).get("allowed", false)), "a moderator (generic) is allowed to change it")
	_v_map_menu_console.call("execute", "mapmenu yard", _v_map_menu_moderator)
	await get_tree().process_frame
	_check(_v_map_menu_applied == [&"yard"], "and choosing changes it through the game's own apply (%s)" % str(_v_map_menu_applied))
	_check(str(((_v_map_menu_sent.back() as Dictionary).get("result", {}) as Dictionary).get("how", "")) == "changed"
		and _v_map_menu_replies[_v_map_menu_replies.size() - 1] == "Changing to Yard." and _v_map_menu_announced.size() == 1,
		"said to the moderator on screen and in chat, and announced to everybody")

	_v_map_menu_director.begin(&"yard")
	_v_map_menu_now_ids = []
	_v_map_menu_commands.map_menu.change_fn = func(id: StringName) -> DotResult:
		_v_map_menu_now_ids.append(id)
		return DotResult.success(id)
	_v_map_menu_console.call("execute", "mapmenu docks", _v_map_menu_moderator)
	await get_tree().process_frame
	_check(_v_map_menu_now_ids == [&"docks"] and _v_map_menu_applied.size() == 1, "a game's change_fn (change now, not next round) is used when it gives one")

	_v_map_menu_console.call("execute", "sv_map_menu_flag changemap", null)
	_v_map_menu_console.call("execute", "mapmenu foundry", _v_map_menu_moderator)
	await get_tree().process_frame
	var result: Dictionary = (_v_map_menu_sent.back() as Dictionary).get("result", {})
	_check(_v_map_menu_now_ids.size() == 1 and str(result.get("how", "")) == "voted" and _v_map_menu_director.nominated_ids().has(&"foundry"),
		"the owner narrows it to changemap: the moderator's choice is now a nomination (%s)" % str(result.get("text", "")))
	_check(str(result.get("text", "")).contains("Rocked the vote"), "and their rock-the-vote")

	_v_map_menu_rules.enabled = false
	_v_map_menu_console.call("execute", "mapmenu atrium", _v_map_menu_player)
	await get_tree().process_frame
	result = (_v_map_menu_sent.back() as Dictionary).get("result", {})
	_check(str(result.get("how", "")) == "refused" and str(result.get("text", "")).contains("'changemap'")
		and str(result.get("text", "")).contains("voting is off"), "with voting off a player is refused, and told why")
	_v_map_menu_console.call("execute", "mapmenu nowhere", _v_map_menu_moderator)
	await get_tree().process_frame
	var refusal: Dictionary = (_v_map_menu_sent.back() as Dictionary).get("result", {})
	_check(str(refusal.get("how", "")) == "refused" and str(refusal.get("text", "")).contains("not on offer here now"),
		"a map not on offer is refused, and the text says the list may be out of date (%s)" % str(refusal.get("text", "")))
	# A source that knows why says so: arena's team mode on a map with no team spawns.
	var reasoned := _ReasonSource.new()
	reasoned.entries = _v_map_menu_source.entries
	_v_map_menu_director.source = reasoned
	_v_map_menu_console.call("execute", "mapmenu nowhere", _v_map_menu_moderator)
	await get_tree().process_frame
	refusal = (_v_map_menu_sent.back() as Dictionary).get("result", {})
	_check(str(refusal.get("how", "")) == "refused" and str(refusal.get("text", "")) == "nowhere cannot run here.",
		"a source's unavailable_reason is the refusal's text (%s)" % str(refusal.get("text", "")))
	_v_map_menu_director.source = _v_map_menu_source
	_v_map_menu_rules.enabled = true

	await _test_map_menu_3()


func _test_map_menu_3() -> void:
	# Fail closed: an empty value is staff, and letting everybody in is a word the owner writes.
	_v_map_menu_console.call("execute", "sv_map_menu_flag \"\"", null)
	_v_map_menu_console.call("execute", "mapmenu", _v_map_menu_player)
	_check(_v_map_menu_commands.map_menu.required_flag() == "generic" and not bool((_v_map_menu_sent.back() as Dictionary).get("allowed", true)),
		"an empty flag is staff only: it fails closed, never 'anybody'")
	_v_map_menu_console.call("execute", "sv_map_menu_flag anyone", null)
	_v_map_menu_console.call("execute", "mapmenu", _v_map_menu_player)
	_check(_v_map_menu_commands.map_menu.required_flag() == "anyone" and bool((_v_map_menu_sent.back() as Dictionary).get("allowed", false)),
		"'anyone' lets anybody change it")
	_v_map_menu_console.call("execute", "sv_map_menu_flag generic", null)
	var unbound := DotVoteMapMenu.new()
	unbound.flag = ""
	_check(unbound.required_flag() == "generic" and not unbound.is_staff(_v_map_menu_player),
		"a menu with no cvar registered and no flag set is staff only too")

	await _test_map_menu_humans(_v_map_menu_console, _v_map_menu_commands, _v_map_menu_director, _v_map_menu_rules, _v_map_menu_sent, _v_map_menu_now_ids, _v_map_menu_player, _v_map_menu_moderator)

	# A server with hundreds of maps: one notice carries 8 KB, so the list goes out in parts
	# a client puts back together, every part under the limit and no row lost.
	var many: Array = []
	for i in 400:
		many.append({"id": "surf_long_map_name_%03d" % i, "name": "Surf: A Long Map Name %d" % i, "mode": "Surf", "detail": "tier %d" % (i % 6), "current": false})
	var parts := DotVoteMapMenu.chunks_of(many)
	var counted := 0
	var biggest := 0
	for part: Array in parts:
		counted += part.size()
		biggest = maxi(biggest, var_to_bytes({"maps": part, "allowed": true, "flag": "generic", "vote": true, "where": "this server", "part": 1, "parts": parts.size()}).size())
	_check(parts.size() > 1 and counted == 400 and biggest < 8192,
		"a long list goes out in parts, each under a notice's 8 KB, none lost (%d parts, %d bytes at most)" % [parts.size(), biggest])

	_v_map_menu_console.queue_free()
	_v_map_menu_director.queue_free()
	_done()


## Who is a human, and how many: the lone player, two of them, the owner's minimum, a majority,
## and the host. The live bug of 2026-10-14 was a guest's M choice changing a public server's map.
func _test_map_menu_humans(console: Node, commands: DotVoteCommands, director: DotVoteDirector,
		rules: DotVoteRules, sent: Array, now_ids: Array, player: Object, moderator: Object) -> void:
	var menu := commands.map_menu
	var guest_session := DotClientSession.new(5, 7)
	player.set("session", guest_session)
	var here := [1]
	menu.humans_fn = func() -> int: return here[0]
	var last := func() -> Dictionary: return (sent.back() as Dictionary).get("result", {})

	director.begin(&"atrium")
	var before := now_ids.size()
	_check(menu.alone_cvar != null and menu.alone_allowed() and menu.vote_min_cvar != null and menu.min_voters() == 2,
		"sv_map_menu_alone (1) and sv_map_menu_vote_min (2) are registered with their defaults")
	console.call("execute", "mapmenu", player)
	_check(bool((sent.back() as Dictionary).get("allowed", false)) and bool((sent.back() as Dictionary).get("alone", false)),
		"alone on the server, a guest is offered the change, and told it is because they are alone")
	console.call("execute", "mapmenu docks", player)
	await get_tree().process_frame
	_check(now_ids.size() == before + 1 and str(last.call().get("how", "")) == "changed",
		"alone with sv_map_menu_alone 1, a guest's choice changes the map (%s)" % str(last.call().get("text", "")))

	director.begin(&"atrium")
	director.open_vote()
	before = now_ids.size()
	console.call("execute", "mapmenu docks", player)
	await get_tree().process_frame
	_check(now_ids.size() == before + 1 and not director.is_voting() and str(last.call().get("how", "")) == "changed",
		"alone, an open ballot is called off and the choice changes the map (%s)" % str(last.call().get("text", "")))

	console.call("execute", "sv_map_menu_alone 0", null)
	director.begin(&"docks")
	before = now_ids.size()
	console.call("execute", "mapmenu foundry", player)
	await get_tree().process_frame
	var text := str(last.call().get("text", ""))
	_check(now_ids.size() == before and not director.is_voting() and director.clock.rtv_votes() == 0
		and text.contains("needs a vote of the players here") and text.contains("only one"),
		"alone with sv_map_menu_alone 0: no change, no vote, and a clear line (%s)" % text)

	console.call("execute", "sv_map_menu_alone 1", null)
	here[0] = 2
	director.begin(&"docks")
	before = now_ids.size()
	console.call("execute", "mapmenu", player)
	_check(not bool((sent.back() as Dictionary).get("allowed", true)), "with a second human here the guest is offered a vote, not the change")
	console.call("execute", "mapmenu foundry", player)
	await get_tree().process_frame
	text = str(last.call().get("text", ""))
	_check(now_ids.size() == before and not director.is_voting() and director.clock.rtv_votes() == 1 and text.contains("Rocked the vote"),
		"two humans, sv_map_menu_alone 1: the guest's choice is a nomination and one rock, no change (%s)" % text)

	await _map_menu_humans_more(
		console, director, rules, now_ids, player, moderator, menu, guest_session, here, last
	)


func _map_menu_humans_more(
	console: Node, director: DotVoteDirector, rules: DotVoteRules, now_ids: Array,
	player: Object, moderator: Object, menu: Object, guest_session: DotClientSession,
	here: Array, last: Callable
) -> void:
	var before := 0
	var text := ""
	console.call("execute", "sv_map_menu_vote_min 3", null)
	director.begin(&"docks")
	console.call("execute", "mapmenu yard", player)
	await get_tree().process_frame
	text = str(last.call().get("text", ""))
	_check(director.clock.rtv_votes() == 0 and text.contains("takes 3 players"),
		"the owner's sv_map_menu_vote_min 3 holds two humans to a nomination (%s)" % text)
	console.call("execute", "sv_map_menu_vote_min 1", null)
	_check(menu.min_voters() == 2, "and sv_map_menu_vote_min never goes below 2")
	console.call("execute", "sv_map_menu_vote_min 2", null)

	# Rules that would pass one rock on a server of four (bots counted, a low fraction): the
	# menu still wants most of the humans.
	var fraction := rules.rtv_fraction
	rules.rtv_fraction = 0.25
	here[0] = 4
	director.begin(&"docks")
	console.call("execute", "mapmenu yard", player)
	await get_tree().process_frame
	text = str(last.call().get("text", ""))
	_check(not director.is_voting() and director.clock.rtv_votes() == 0 and text.contains("most of the 4 players"),
		"a rock the rules would pass on one of four humans is not made from the menu (%s)" % text)
	rules.rtv_fraction = fraction

	# The listen host's own player (no transport) owns the server.
	here[0] = 3
	console.call("execute", "sv_map_menu_alone 0", null)
	director.begin(&"docks")
	before = now_ids.size()
	guest_session.local = true
	console.call("execute", "mapmenu yard", player)
	await get_tree().process_frame
	_check(now_ids.size() == before + 1 and str(last.call().get("how", "")) == "changed",
		"the host's own player (a local session) changes it, with others here and no flag")
	guest_session.local = false

	# Staff change it with others here.
	director.begin(&"yard")
	before = now_ids.size()
	console.call("execute", "mapmenu docks", moderator)
	await get_tree().process_frame
	_check(now_ids.size() == before + 1, "and staff (generic) change it with others here")

	console.call("execute", "sv_map_menu_alone 1", null)
	menu.humans_fn = Callable()
	player.set("session", null)

	_map_menu_late_flag()


func _map_menu_late_flag() -> void:
	# `+sv_map_menu_flag anyone` on a server's command line runs before any module registers
	# the cvar; the menu applies it when it does (play.sh's local server relies on it).
	var argv := _ArgvConsole.new()
	var flag_cvar: Object = (load("res://addons/dot_server/console/dot_convar.gd") as GDScript).new(DotVoteMapMenu.FLAG_CVAR, "generic")
	DotVoteMapMenu._from_command_line(argv, flag_cvar, DotVoteMapMenu.FLAG_CVAR)
	_check(str(flag_cvar.call("get_string")) == "anyone", "a value given on the command line reaches the cvar when it is registered late")


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

	_v_choices_limits = DotVoteChoice.of(&"epic")
	_check(
		is_equal_approx(_v_choices_limits.duration_for(1800.0), 1800.0),
		"a choice with no limit of its own takes the server's"
	)

	_v_choices_limits.time_limit_sec = 2400.0
	_check(
		is_equal_approx(_v_choices_limits.duration_for(1800.0), 2400.0),
		"and its own overrides it (%.0f)" % _v_choices_limits.duration_for(1800.0)
	)

	_v_choices_limits.time_limit_sec = 0.0
	_check(
		is_equal_approx(_v_choices_limits.duration_for(1800.0), 0.0),
		"a limit of ZERO means no limit, not 'use the default'",
		"a server that wanted a map with no clock and got 30 minutes would change "
		+ "away from it with nothing to say why"
	)

	_test_choices_2()


func _test_choices_2() -> void:
	_v_choices_limits.round_limit = 5
	_check(_v_choices_limits.rounds_for(0) == 5, "the same for rounds")
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


func _test_rules_layering() -> void:
	_section("Every rule is settable from a file, the environment or the command line")

	_v_rules_layering_rules = DotVoteRules.new()

	_check(
		_v_rules_layering_rules.config_keys().size() >= 40,
		"there are %d settings" % _v_rules_layering_rules.config_keys().size()
	)

	_v_rules_layering_rules.apply_dictionary({"duration_sec": 900, "rtv_fraction": 0.5}, "file")
	_check(
		is_equal_approx(_v_rules_layering_rules.duration_sec, 900.0)
			and is_equal_approx(_v_rules_layering_rules.rtv_fraction, 0.5),
		"a dictionary layer applies"
	)

	_v_rules_layering_rules.apply_dictionary({"max-options": "8", "closeWhenAllVoted": "false"}, "file")
	_check(
		_v_rules_layering_rules.max_options == 8 and not _v_rules_layering_rules.close_when_all_voted,
		"and matches keys written in kebab-case or camelCase"
	)

	# An enum written by name. Godot exports one as an integer, and a config file full
	# of integers is a file nobody can read or diff.
	_v_rules_layering_rules.apply_dictionary({"method": "instant_runoff", "fill": "WEIGHTED"}, "file")
	_check(
		_v_rules_layering_rules.method == DotVoteRules.Method.INSTANT_RUNOFF,
		"an enum can be written by name (method: instant_runoff)"
	)
	_check(
		_v_rules_layering_rules.fill == DotVoteRules.Fill.WEIGHTED,
		"in any case, and with dashes or spaces"
	)
	_check(
		_v_rules_layering_rules.enum_name("method") == "instant_runoff",
		"and reads back as its name for a console reply",
		_v_rules_layering_rules.enum_name("method")
	)

	_test_rules_layering_2()


func _test_rules_layering_2() -> void:
	_v_rules_layering_rules.apply_dictionary({"tie_break": "2"}, "file")
	_check(
		_v_rules_layering_rules.tie_break == DotVoteRules.TieBreak.LEAST_RECENTLY_PLAYED,
		"a numeric enum still works, for a config written by a program"
	)

	var before := _v_rules_layering_rules.method
	_v_rules_layering_rules.apply_dictionary({"method": "borda_count"}, "file")
	_check(
		_v_rules_layering_rules.method == before,
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
	_v_rules_layering_rules.apply_dictionary({"warn_at_sec": "120,60,10"}, "env")
	var marks := _v_rules_layering_rules.warn_marks()
	_check(
		marks.size() == 3 and is_equal_approx(marks[0], 120.0)
			and is_equal_approx(marks[2], 10.0),
		"warning marks read from a comma-separated string, largest first"
	)

	_v_rules_layering_rules.apply_dictionary({"warn_at_sec": "60,banana,10"}, "env")
	_check(
		_v_rules_layering_rules.warn_marks().size() == 2,
		"and one unreadable mark costs one warning rather than the whole list"
	)

	_check(_v_rules_layering_rules.env_prefix() == "DOT_VOTE_", "the environment prefix is declared")
	_check(_v_rules_layering_rules.cli_prefix() == "--vote-", "and so is the command-line one")

	_done()


func _test_nominations() -> void:
	_section("Nominations are capped, deduplicated and kept in order")

	_v_nominations_rules = _rules()
	_v_nominations_rules.nominations_per_player = 1
	_v_nominations_rules.nominations_max = 3

	_v_nominations_noms = DotVoteNominations.of(_v_nominations_rules)

	_check(_v_nominations_noms.add(&"alice", &"a").ok, "a player nominates")
	_check(
		not _v_nominations_noms.add(&"alice", &"a").ok,
		"and the same player cannot nominate it twice",
		"pressing a key again because nothing visible happened is not support"
	)
	_check(
		_v_nominations_noms.add(&"bob", &"a").ok,
		"but another player may second it, which is what a popularity fill counts"
	)
	_check(int(_v_nominations_noms.counts()[&"a"]) == 2, "and it is counted twice")

	var strict := _rules()
	strict.nomination_seconding = false
	var no_seconds := DotVoteNominations.of(strict)
	no_seconds.add(&"alice", &"a")
	_check(
		not no_seconds.add(&"bob", &"a").ok,
		"a server can refuse seconding and get SourceMod's behaviour instead"
	)

	_check(_v_nominations_noms.add(&"alice", &"b").ok, "a second nomination from one player…")
	_check(
		_v_nominations_noms.by_voter(&"alice") == ([&"b"] as Array[StringName]),
		"…REPLACES their own first when they may only have one",
		"'you already nominated something' is not what somebody who has changed "
		+ "their mind wants to hear, and withdrawing first is a command nobody knows"
	)
	_check(
		_v_nominations_noms.has_id(&"a"),
		"without taking away the other player's, which was never theirs to withdraw"
	)

	# alice holds b; bob still holds the second on a.
	_check(_v_nominations_noms.remove(&"bob", &"a"), "a player withdraws their own")
	_check(
		not _v_nominations_noms.remove(&"bob", &"b"),
		"and cannot withdraw somebody else's"
	)
	_check(
		not _v_nominations_noms.has_id(&"a"),
		"and the last nomination of a thing withdrawn takes it off the list"
	)

	_test_nominations_2()


func _test_nominations_2() -> void:
	_check(_v_nominations_noms.add(&"carol", &"c").ok, "another player nominates")
	_check(_v_nominations_noms.add(&"dave", &"d").ok, "and another")
	_check(
		not _v_nominations_noms.add(&"erin", &"e").ok,
		"and the list fills up (%d of %d)" % [_v_nominations_noms.size(), _v_nominations_rules.nominations_max]
	)
	_check(
		_v_nominations_noms.add(&"erin", &"e", true).ok,
		"an admin's nomination bypasses the cap"
	)

	var ordered := _v_nominations_noms.ordered_ids()
	_check(
		ordered[0] == &"b" and ordered[1] == &"c" and ordered[2] == &"d",
		"nomination order is preserved, which is what fills the reserved places",
		", ".join(DotVoteBallot._as_strings(ordered))
	)
	_check(_v_nominations_noms.first_index(&"c") == 1, "and is reportable as a tie-break key")
	_check(
		_v_nominations_noms.first_index(&"never") > 1000,
		"something never nominated sorts behind everything nominated"
	)

	var counts := _v_nominations_noms.counts()
	_check(int(counts.get(&"b", 0)) == 1, "counts are per id, for a most-nominated fill")

	_check(_v_nominations_noms.remove_voter(&"alice") == 1, "everything one player nominated can go")

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
# Everything below is a feature the long-standing community map-choosers have and this
# addon did not, or had in a shape an operator could not reach. The parity table is in
# docs/parity.md; each section here is one row group of it, run rather than read.


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
