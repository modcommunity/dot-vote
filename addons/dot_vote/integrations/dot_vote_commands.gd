class_name DotVoteCommands
extends RefCounted

## The console and chat commands, on a dot-server, in one call.
##
## [codeblock]
## DotVoteCommands.install(self, director)   # from a DotModule's _module_loaded
## [/codeblock]
##
## [b]Duck-typed, like everything else here.[/b] The host is anything with
## [code]add_command[/code] (a [code]DotModule[/code]) or [code]command[/code] (a
## [code]DotConsole[/code]), and a command context is anything with
## [code]reply[/code] and [code]args[/code] — so this file names no dot-server class
## and dot-vote stays installable without it.
##
## [b]Every name is configurable, and it has to be.[/b] dot-server already ships
## [code]vote[/code] and a votekick; a timer server's players type
## [code]!rtv[/code] and [code]!nominate[/code]; a player from the older shooters
## types [code]timeleft[/code] and [code]nextmap[/code]. Pass [member names] to rename any
## of them, or [member prefix] to move the lot out of the way.

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
}

## Which of the above are also typable in chat as [code]!name[/code].
##
## The players' four. The rest are an operator's and stay on the console, because a
## chat command that changes the map is one a compromised client can spam.
const CHAT := ["nominate", "rtv", "unrtv", "vote", "timeleft", "nextmap", "nominations"]

## Roles that need a permission, and which one.
const ADMIN := [
	"revote", "extend", "endvote", "setnext", "nominate_add", "forcertv", "reload",
]

var director: DotVoteDirector = null

## Prepended to every command name. [code]"sv_"[/code] gives [code]sv_rtv[/code].
var prefix: String = ""

## Per-role name overrides, e.g. [code]{"rtv": "rockthevote"}[/code].
var names: Dictionary = {}

## Permission an admin command needs. Empty makes them console-only.
##
## [b]`changemap`, which is dot-server's [code]DotAdminFlags.CHANGEMAP[/code][/b] — spelled
## out rather than named, because naming it would make this file fail to parse in a
## project without dot-server. It was [code]"changelevel"[/code], which is the name of a
## COMMAND and not a flag anybody holds: [code]DotAdminFlags.granted[/code] matches the
## string exactly, so every admin vote command was quietly root-only, and an operator
## who granted an admin the map flag found them refused with nothing saying why.
var admin_permission: String = "changemap"

## How a command context becomes a voter id.
##
## The default reads the session's userid, which is what dot-server keys a player on.
## A game with its own player ids overrides it.
var voter_fn: Callable = Callable()

## How what a player typed becomes a choice id: [code](text: String) -> StringName[/code].
##
## The default takes the text as it is. A game whose ids carry a prefix — arena's
## [code]map:dm_atrium[/code] beside [code]mode:koth[/code] — sets this, because a player
## types [code]!nominate dm_atrium[/code] and a command that refused it would be a
## command nobody can use. Every command that takes a name goes through it: nominate,
## unnominate, a vote by name, setnextmap and nominate_addmap.
var resolve_fn: Callable = Callable()

## Names actually registered, for a module that has to remove them again.
var registered: PackedStringArray = PackedStringArray()


static func install(host: Object, p_director: DotVoteDirector) -> DotVoteCommands:
	var commands := DotVoteCommands.new()
	commands.director = p_director
	commands.bind(host)
	return commands


func command_name(role: String) -> String:
	return prefix + str(names.get(role, DEFAULTS.get(role, role)))


## Registers everything on [param host].
func bind(host: Object) -> DotResult:
	if host == null or director == null:
		return DotResult.fail(
			DotError.CODE_INVALID, "A host and a director are both needed."
		)

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
		var full := command_name(str(role))

		var registered_command: Variant = host.call(
			adder, full, entry[0], entry[1], permission
		)

		if registered_command is Object and CHAT.has(role):
			if (registered_command as Object).has_method("with_chat"):
				(registered_command as Object).call("with_chat")

		registered.append(full)

	DotLog.info(CHANNEL, "commands registered", {"count": registered.size()})

	return DotResult.success(registered)


# --- Context helpers -------------------------------------------------------

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


# --- Players' commands -----------------------------------------------------

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

	_reply_result(ctx, result, "Nominated %s." % id)


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
##
## [b]The number matters more than it looks.[/b] A player typing a map name into chat
## gets it wrong, and a ballot is a numbered list on their screen — so [code]!votefor
## 2[/code] is what they will actually type, and refusing it makes voting by chat
## unusable.
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

	_reply_result(ctx, director.cast_one(_voter(ctx), choice), "Voted for %s." % choice)


func _cmd_timeleft(ctx: Object) -> void:
	_reply(ctx, director.clock.timeleft_line())


func _cmd_nextmap(ctx: Object) -> void:
	var pending := director.pending_id()

	if pending != &"":
		_reply(ctx, "Next: %s (voted for)." % pending)
		return

	var next := director.next_in_rotation()

	_reply(ctx, "Next: %s." % (String(next) if next != &"" else "undecided"))


# --- Operators' commands ---------------------------------------------------

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
		ctx, director.force_nominate(id, _voter(ctx)), "%s is on the next ballot." % id
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
##
## Both, because they answer different questions: the summary is "how does this server
## vote", and the dump is "why did it just do that".
func _cmd_rules(ctx: Object) -> void:
	var args := _args(ctx)

	if not args.is_empty() and args[0].to_lower() == "full":
		ctx.call("reply_lines", director.rules.describe_lines())
		return

	ctx.call("reply_lines", director.rules.summary_lines())
