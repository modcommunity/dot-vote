extends "res://examples/selftest/tests_c.gd"

## Selftest sections, part d.

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
