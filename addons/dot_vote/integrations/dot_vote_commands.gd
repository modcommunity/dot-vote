class_name DotVoteCommands
extends RefCounted

## The console and chat commands, on a dot-server, in one call: [code]DotVoteCommands.install(self, director)[/code] from a DotModule's _module_loaded.
## Duck-typed so dot-vote installs without dot-server: the host has [code]add_command[/code] or [code]command[/code], a context has [code]reply[/code] and [code]args[/code].
## Every name is configurable ([member names], [member prefix]) because dot-server already ships [code]vote[/code] and players of other servers type different words.

const CHANNEL := "vote.commands"

## Default command names, by role. Override any of them through [member names].
const DEFAULTS := {
	"nominate": "nominate",
	"unnominate": "unnominate",
	"nominations": "nominations",
	"rtv": "rtv",
	"unrtv": "unrtv",
	"vote": "votefor",
	"timeleft": "timeleft",
	"nextmap": "nextmap",
	"revote": "revote",
	"extend": "extend",
	"endvote": "endvote",
	"votestatus": "votestatus",
	"voterules": "voterules",
	"setnext": "setnextmap",
	"nominate_add": "nominate_addmap",
	"forcertv": "forcertv",
	"reload": "votereload",
	"mapmenu": "mapmenu",
}

## Which of the above are also typable in chat as [code]!name[/code].
## The players' commands only; a chat command that changes the map could be spammed by a compromised client.
const CHAT := ["nominate", "rtv", "unrtv", "vote", "timeleft", "nextmap", "nominations"]

## Roles that need a permission, and which one.
const ADMIN := [
	"revote", "extend", "endvote", "setnext", "nominate_add", "forcertv", "reload",
]

var director: DotVoteDirector = null

## The map menu's server half (`mapmenu`, `sv_map_menu_flag`), installed by [method bind]
## so every game with a vote has it. See [DotVoteMapMenu]; a game sets its `change_fn`.
var map_menu: DotVoteMapMenu = null

## Install the map menu with the rest. Off for a vote over something that is not a map (a
## server's next game, where M has nothing to change).
var with_map_menu: bool = true

## Prepended to every command name. [code]"sv_"[/code] gives [code]sv_rtv[/code].
var prefix: String = ""

## Per-role name overrides, e.g. [code]{"rtv": "rockthevote"}[/code]. A value may be a list:
## the first name is the one help shows, the rest are aliases (`{"rtv": ["rtv", "rock"]}`).
var names: Dictionary = {}

## Where an operator's `commands:` block comes from: [code]() -> Dictionary[/code] with `prefix`
## and `names`, e.g. dot-map's `DotMapRotationFile.commands`. Read once by [method bind], after
## the game's own settings, so the file wins. Duck-typed so this addon names no other.
var spec_fn: Callable = Callable()

## What a player types before a command in chat (the server's first `chat_command_prefixes`).
## Only for text shown to players: help, hints and the ballot's line.
var chat_prefix: String = "!"

## Names refused because something else had them, for [method describe].
var skipped: PackedStringArray = PackedStringArray()

## Permission an admin command needs. Empty makes them console-only.
## `changemap` is [code]DotAdminFlags.CHANGEMAP[/code], spelled out so the file parses without dot-server; [code]DotAdminFlags.granted[/code] matches the string exactly.
var admin_permission: String = "changemap"

## How a command context becomes a voter id; the default reads the session's userid, which dot-server keys a player on.
var voter_fn: Callable = Callable()

## How what a player typed becomes a choice id: [code](text: String) -> StringName[/code].
## For a game whose ids carry a prefix ([code]map:dm_atrium[/code]); every command that takes a name goes through it.
var resolve_fn: Callable = Callable()

## Names actually registered, for a module that has to remove them again.
var registered: PackedStringArray = PackedStringArray()


static func install(host: Object, p_director: DotVoteDirector) -> DotVoteCommands:
	var commands := DotVoteCommands.new()
	commands.director = p_director
	commands.bind(host)
	return commands


## Which commands are registered and under what prefix, for "why does !rtv do nothing".
func describe() -> Dictionary:
	return {
		"prefix": prefix,
		"director": director != null,
		"map_menu": map_menu != null,
		"admin_permission": admin_permission,
		"registered": Array(registered),
		"skipped": Array(skipped),
		"aliases": _aliases_by_role(),
	}


## The name help and hints show for a role: the primary, prefix included.
func command_name(role: String) -> String:
	return DotCommandNames.all_of(prefix, names, DEFAULTS, role)[0]


## Every name a role answers to, the primary first.
func command_names(role: String) -> PackedStringArray:
	return DotCommandNames.all_of(prefix, names, DEFAULTS, role)


## What a player types in chat for a role, e.g. [code]!game_rtv[/code].
func typed(role: String) -> String:
	return DotCommandNames.typed(chat_prefix, command_name(role))


func _aliases_by_role() -> Dictionary:
	var out := {}
	for role: Variant in names:
		var all := command_names(str(role))
		if all.size() > 1:
			out[str(role)] = Array(all.slice(1))
	return out


## Registers everything on [param host].
func bind(host: Object) -> DotResult:
	if host == null or director == null:
		return DotResult.fail(
			DotError.CODE_INVALID, "A host and a director are both needed."
		)

	if spec_fn.is_valid():
		var from_file: Variant = spec_fn.call()
		if from_file is Dictionary:
			DotCommandNames.apply(self, from_file)

	var adder := ""

	if host.has_method("add_command"):
		adder = "add_command"
	elif host.has_method("command"):
		adder = "command"
	else:
		return DotResult.fail(
			DotError.CODE_UNSUPPORTED,
			"That host has no way to register a command.",
			"expected a DotModule (add_command) or a DotConsole (command)"
		)

	var table := {
		"nominate": [_cmd_nominate, "Nominate something for the next vote"],
		"unnominate": [_cmd_unnominate, "Withdraw your nomination"],
		"nominations": [_cmd_nominations, "What has been nominated"],
		"rtv": [_cmd_rtv, "Rock the vote"],
		"unrtv": [_cmd_unrtv, "Take back your rock-the-vote"],
		"vote": [_cmd_vote, "Vote for an option, by name or by number"],
		"timeleft": [_cmd_timeleft, "How long is left"],
		"nextmap": [_cmd_nextmap, "What is on next"],
		"revote": [_cmd_revote, "Open a vote now"],
		"extend": [_cmd_extend, "Extend what is running"],
		"endvote": [_cmd_endvote, "Close the open vote now"],
		"votestatus": [_cmd_status, "The state of the vote system"],
		"voterules": [_cmd_rules, "The configured voting rules"],
		"setnext": [_cmd_setnext, "Set what plays next, as though a vote had chosen it"],
		"nominate_add": [_cmd_nominate_add, "Put something on the next ballot, whatever the caps"],
		"forcertv": [_cmd_forcertv, "Rock the vote on everybody's behalf"],
		"reload": [_cmd_reload, "Re-read the list of choices"],
	}

	for role: Variant in table:
		var entry: Array = table[role]
		var permission := admin_permission if ADMIN.has(role) else ""

		for full in command_names(str(role)):
			if not DotCommandNames.available(host, full, registered, str(role), "vote"):
				skipped.append(full)
				continue

			var registered_command: Variant = host.call(
				adder, full, entry[0], entry[1], permission
			)

			if registered_command is Object and CHAT.has(role):
				if (registered_command as Object).has_method("with_chat"):
					(registered_command as Object).call("with_chat")

			registered.append(full)

	if with_map_menu:
		if map_menu == null:
			map_menu = DotVoteMapMenu.new()
		map_menu.commands = self
		map_menu.bind(host, adder)

	DotLog.info(CHANNEL, "commands registered", {"count": registered.size()})

	return DotResult.success(registered)



func _voter(ctx: Object) -> StringName:
	if voter_fn.is_valid():
		return StringName(str(voter_fn.call(ctx)))

	var session: Variant = ctx.get("session")

	if session != null and session is Object:
		var userid: Variant = (session as Object).get("userid")

		if userid != null:
			return StringName("u%s" % str(userid))

	return &"console"


func _resolve(text: String) -> StringName:
	if resolve_fn.is_valid():
		return StringName(str(resolve_fn.call(text)))

	return StringName(text)


func _args(ctx: Object) -> PackedStringArray:
	var args: Variant = ctx.get("args")

	return args as PackedStringArray if args is PackedStringArray else PackedStringArray()


func _reply(ctx: Object, text: String) -> void:
	ctx.call("reply", text)


func _reply_result(ctx: Object, result: DotResult, ok_text: String) -> void:
	if result.ok:
		_reply(ctx, ok_text)
		return

	# The detail is included deliberately. "You cannot nominate that" is an argument
	# with the server; "played 2 maps ago, cooldown is 5" is an answer.
	var detail := result.error.detail if result.error != null else ""

	_reply(ctx, "%s%s" % [
		result.error.message if result.error != null else "Refused.",
		" (%s)" % detail if detail != "" else "",
	])



func _cmd_nominate(ctx: Object) -> void:
	var args := _args(ctx)

	if args.is_empty():
		# Only what could actually be nominated: listing the map that is running, or the
		# one played twenty minutes ago, is offering a player something the next line
		# refuses.
		var listed := PackedStringArray()

		for id in director.nominatable_ids():
			listed.append(String(id))

		_reply(ctx, "Usage: %s <name>. Available: %s" % [
			command_name("nominate"),
			", ".join(listed) if not listed.is_empty() else "nothing right now",
		])
		return

	var id := _resolve(args[0])
	var result := director.nominate(_voter(ctx), id)

	# The label, as the ballot and "Voted for" print it: the id is what the player TYPED, or
	# what resolve_fn made of it, and the game ballot's ids are descriptor ids such as
	# `hungry_classic` beside a line saying "nominated Hungario: Classic".
	_reply_result(ctx, result, "Nominated %s." % director.option_label(id))


func _cmd_unnominate(ctx: Object) -> void:
	var args := _args(ctx)

	if args.is_empty():
		_reply(ctx, "Usage: %s <name>" % command_name("unnominate"))
		return

	if director.withdraw_nomination(_voter(ctx), _resolve(args[0])):
		_reply(ctx, "Withdrawn.")
		return

	_reply(ctx, "You have not nominated that.")


func _cmd_nominations(ctx: Object) -> void:
	ctx.call("reply_lines", director.nominations.describe_lines())


func _cmd_rtv(ctx: Object) -> void:
	var result := director.rock_the_vote(_voter(ctx))
	var needed := director.clock.rtv_needed(director.player_count())

	_reply_result(ctx, result, "Rocked. %d of %d." % [
		director.clock.rtv_votes(), needed
	])


func _cmd_unrtv(ctx: Object) -> void:
	if director.clock.unrock(_voter(ctx)):
		_reply(ctx, "Taken back. %d of %d." % [
			director.clock.rtv_votes(),
			director.clock.rtv_needed(director.player_count()),
		])
		return

	_reply(ctx, "You had not rocked the vote.")


## Votes by name, or by the number shown on the ballot.
## Players type the number from their screen, not a map name.
func _cmd_vote(ctx: Object) -> void:
	var args := _args(ctx)

	if not director.is_voting():
		_reply(ctx, "There is no vote running.")
		return

	var options := director.ballot.option_ids()

	if args.is_empty():
		var lines := PackedStringArray()

		for i in range(options.size()):
			lines.append("%d. %s" % [i + 1, director.option_label(options[i])])

		ctx.call("reply_lines", lines)
		return

	var choice: StringName = &""
	var text := args[0]

	if text.is_valid_int():
		var index := text.to_int() - 1

		if index < 0 or index >= options.size():
			_reply(ctx, "There is no option %s." % text)
			return

		choice = options[index]
	else:
		choice = _resolve(text)

	# The label, never the id: a no-change option's id is `__keep__`, which is what
	# chat printed until the reply named the line on the ballot ("Don't change").
	_reply_result(ctx, director.cast_one(_voter(ctx), choice), "Voted for %s." % director.option_label(choice))


func _cmd_timeleft(ctx: Object) -> void:
	_reply(ctx, director.clock.timeleft_line())


func _cmd_nextmap(ctx: Object) -> void:
	var pending := director.pending_id()

	if pending != &"":
		_reply(ctx, "Next: %s (voted for)." % pending)
		return

	var next := director.next_in_rotation()

	_reply(ctx, "Next: %s." % (String(next) if next != &"" else "undecided"))



## An admin's "vote now". Through the countdown if there is one, and replacing a change
## already decided, because an admin asking for a vote has decided the last one does
## not stand.
func _cmd_revote(ctx: Object) -> void:
	var result := director.start_vote(DotVoteClock.REASON_MANUAL, true)

	_reply_result(
		ctx, result, "Vote starting." if director.is_counting_down() else "Vote opened."
	)


func _cmd_setnext(ctx: Object) -> void:
	var args := _args(ctx)

	if args.is_empty():
		_reply(ctx, "Usage: %s <name>" % command_name("setnext"))
		return

	var id := _resolve(args[0])
	_reply_result(ctx, director.set_next(id), "Next: %s." % id)


func _cmd_nominate_add(ctx: Object) -> void:
	var args := _args(ctx)

	if args.is_empty():
		_reply(ctx, "Usage: %s <name>" % command_name("nominate_add"))
		return

	var id := _resolve(args[0])
	_reply_result(
		ctx, director.force_nominate(id, _voter(ctx)),
		"%s is on the next ballot." % director.option_label(id)
	)


func _cmd_forcertv(ctx: Object) -> void:
	_reply_result(ctx, director.force_rtv(), "Rocked.")


func _cmd_reload(ctx: Object) -> void:
	var result := director.reload()
	var count := director.source.choices().size() if director.source != null else 0

	_reply_result(ctx, result, "Reloaded: %d choices." % count)


func _cmd_extend(ctx: Object) -> void:
	var args := _args(ctx)
	var seconds := -1.0

	if not args.is_empty() and args[0].is_valid_float():
		seconds = args[0].to_float()

	_reply_result(
		ctx, director.extend(seconds), "Extended. %s." % director.clock.timeleft_line()
	)


func _cmd_endvote(ctx: Object) -> void:
	if not director.is_voting():
		_reply(ctx, "There is no vote running.")
		return

	var result := director.close_vote()

	_reply(ctx, result.summary)


func _cmd_status(ctx: Object) -> void:
	ctx.call("reply_lines", director.describe_lines())


## The summary, or every one of the forty-odd settings with [code]full[/code].
## The summary says how the server votes; the dump says why it just did that.
func _cmd_rules(ctx: Object) -> void:
	var args := _args(ctx)

	if not args.is_empty() and args[0].to_lower() == "full":
		ctx.call("reply_lines", director.rules.describe_lines())
		return

	ctx.call("reply_lines", director.rules.summary_lines())
