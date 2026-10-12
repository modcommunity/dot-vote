class_name DotVoteMapMenu
extends RefCounted

## The server half of the map menu every game has on M: `mapmenu` lists the maps to a
## player, and `mapmenu <id>` changes to one for a player holding the flag the owner named,
## or starts a vote for it for anybody else.
##
## [codeblock]
## # Installed by DotVoteCommands.bind with the rest; a game only says how to change NOW:
## commands.map_menu.change_fn = func(id: StringName) -> DotResult: return world.change_map_now(id)
## commands.map_menu.rows_fn = func(rows: Array) -> Array: return decorate(rows)   # optional
## [/codeblock]
##
## [b]Why the menu's server half is here.[/b] Every game in the family already has a
## [DotVoteDirector] over a source that knows its maps (or courses, layouts, routes, houses)
## and how to apply one, and installs [DotVoteCommands] on its module. The vote fallback is
## the director's own nominate and rock-the-vote. Putting the menu next to them gives every
## game the server half with no wiring at all, and the one thing a game may want to say, how
## to change immediately rather than at the end of the round, is one callable.
##
## [b]The flag is the owner's.[/b] `sv_map_menu_flag` names it, `generic` by default: the
## flag every staff group holds from moderator up, so "moderator or above" without this addon
## having an opinion about what a moderator is. `changemap` narrows it to admins; an empty
## value lets anybody change the map (a private server among friends). Read on every request,
## so a change at the console applies to the next M press.
##
## [b]The client reads a notice, not chat.[/b] The answer is a notice on the `map_menu` topic
## with the list in `data` (dot-server's notice is the one message a server can send the
## client application whatever game it shows), and the result of a choice is a notice too and
## a reply line, so a client older than the menu still reads what happened in its chat.
## Nothing here names dot-server: the context, the session and the server are duck-typed, the
## server is found as `dot_server` in [DotRegistry], and the notice script is loaded by path.

const CHANNEL := "vote.map_menu"

const TOPIC := &"map_menu"
const FLAG_CVAR := "sv_map_menu_flag"
## dot-server's `DotAdminFlags.GENERIC`, spelled out (see [DotVoteCommands.admin_permission]).
const DEFAULT_FLAG := "generic"

## Rows sent at most: a notice carries 8 KB and a page is seven rows.
const MAX_ROWS := 80

const NOTICE_SCRIPT := "res://addons/dot_server/net/dot_notice.gd"

## The commands this belongs to, held weakly: they hold this ([member DotVoteCommands.map_menu]),
## and two RefCounted holding each other are never freed.
var commands: DotVoteCommands:
	get:
		return _commands.get_ref() as DotVoteCommands if _commands != null else null
	set(value):
		_commands = weakref(value) if value != null else null
var _commands: WeakRef = null

## The flag used when there is no console to hold the cvar (a suite, a bare director).
var flag: String = DEFAULT_FLAG

## The cvar, when the host could register one.
var cvar: Object = null

## `func(id: StringName) -> DotResult` (may await): change to [param id] now. Unset is the
## source's own apply, which in a round-based game is often "next round".
var change_fn: Callable = Callable()

## `func(rows: Array) -> Array`: a game decorating the rows (a mode line, a thumbnail) or
## replacing them. Each row is `{id, name, mode, detail, thumbnail, current}`.
var rows_fn: Callable = Callable()

## `func(ctx: Object, data: Dictionary) -> bool`: how the answer reaches the player. Unset
## sends a `map_menu` notice through the server registered as `dot_server`.
var notice_fn: Callable = Callable()

## What the picker's heading calls this place.
var where: String = "this server"

## The last answers, for a suite and describe().
var last_offer: Dictionary = {}
var last_result: Dictionary = {}


## Registers `mapmenu` (typable in chat, gated inside rather than by the console, because a
## player without the flag still gets the list and the vote) and the flag's cvar.
func bind(host: Object, adder: String) -> void:
	var full := commands.command_name("mapmenu")
	var registered_command: Variant = host.call(adder, full, _cmd, "The map menu: list the maps, or change to one", "")
	if registered_command is Object and (registered_command as Object).has_method("with_chat"):
		(registered_command as Object).call("with_chat")
	commands.registered.append(full)

	var cvar_adder := "add_cvar" if host.has_method("add_cvar") else ("cvar" if host.has_method("cvar") else "")
	if cvar_adder != "":
		var made: Variant = host.call(cvar_adder, FLAG_CVAR, DEFAULT_FLAG,
			"The admin flag that may change the map from the M menu; anybody else gets a vote. Empty: everybody.")
		if made is Object:
			cvar = made


## The flag a direct change needs right now.
func required_flag() -> String:
	if cvar != null and is_instance_valid(cvar) and cvar.has_method("get_string"):
		return str(cvar.call("get_string")).strip_edges().to_lower()
	return flag


## Whether the player behind [param ctx] may change the map directly.
func may_change(ctx: Object) -> bool:
	var needed := required_flag()
	if needed == "":
		return true
	if ctx.has_method("has_permission"):
		return bool(ctx.call("has_permission", needed))
	return false


func vote_available() -> bool:
	return commands.director != null and commands.director.rules != null and commands.director.rules.enabled


## The list: every enabled choice of the director's source, the current one marked.
func rows() -> Array:
	var director := commands.director
	var out: Array = []
	if director == null or director.source == null:
		return out
	var current := director.current_id()
	if current == &"":
		current = director.source.current_id()
	for choice in director.source.choices():
		if choice == null or not choice.enabled:
			continue
		var row := {"id": String(choice.id), "name": director.option_label(choice.id), "current": choice.id == current}
		if String(choice.group) != "":
			row["mode"] = String(choice.group).capitalize()
		if choice.description != "":
			row["detail"] = choice.description
		var thumb := _thumbnail(choice)
		if thumb != "":
			row["thumbnail"] = thumb
		out.append(row)
	if rows_fn.is_valid():
		var decorated: Variant = rows_fn.call(out)
		if decorated is Array:
			out = decorated
	if out.size() > MAX_ROWS:
		out = out.slice(0, MAX_ROWS)
	return out


static func _thumbnail(choice: DotVoteChoice) -> String:
	if choice.meta.has("thumbnail"):
		return str(choice.meta["thumbnail"])
	var map: Variant = choice.meta.get("map")
	if map is Object:
		var meta: Variant = (map as Object).get("meta")
		if meta is Dictionary and (meta as Dictionary).has("thumbnail"):
			return str((meta as Dictionary)["thumbnail"])
	return ""


## What the player behind [param ctx] is offered.
func offer(ctx: Object) -> Dictionary:
	last_offer = {"maps": rows(), "allowed": may_change(ctx), "flag": required_flag(), "vote": vote_available(), "where": where}
	return last_offer


## The player behind [param ctx] chose [param id]: a change when allowed, a vote when not.
## Returns `{ok, text, how}`, `how` one of `changed`, `voted`, `refused`.
func choose(ctx: Object, id: StringName) -> Dictionary:
	var director := commands.director
	if director == null or director.source == null or not director.source.has(id):
		return _result(false, "There is no map called '%s'." % id, "refused")
	var label := director.option_label(id)

	if may_change(ctx):
		if director.is_voting():
			return _result(false, "A vote is open; it decides. %s closes it first." % commands.command_name("endvote"), "refused")
		var changed: DotResult = null
		if change_fn.is_valid():
			changed = await change_fn.call(id)
		elif director.source.supports_apply():
			changed = await director.source.apply(id)
			if changed.ok and director.begin_on_apply:
				director.begin(id)
		else:
			changed = DotResult.fail(DotError.CODE_UNSUPPORTED, "This game cannot change the map from here.")
		if changed == null or not changed.ok:
			return _result(false, changed.error.message if changed != null and changed.error != null else "The change failed.", "refused")
		DotLog.info(CHANNEL, "map changed from the menu", {"map": String(id), "by": _who(ctx)})
		if director.announce_fn.is_valid():
			director.announce_fn.call("%s changed the map to %s." % [_who(ctx), label])
		return _result(true, "Changing to %s." % label, "changed")

	var needed := required_flag()
	if not vote_available():
		return _result(false, "Changing the map here needs the '%s' permission, and voting is off." % needed, "refused")
	var voter := commands._voter(ctx)
	if director.is_voting():
		if director.ballot != null and director.ballot.option_ids().has(id):
			var cast := director.cast_one(voter, id)
			return _result(cast.ok, "Voted for %s." % label if cast.ok else cast.error.message, "voted" if cast.ok else "refused")
		return _result(false, "A vote is open and %s is not on it." % label, "refused")

	var parts := PackedStringArray()
	var nominated := director.nominate(voter, id)
	if nominated.ok:
		parts.append("Nominated %s." % label)
	else:
		parts.append("Could not nominate %s: %s" % [label, nominated.error.message])
	var rocked := director.rock_the_vote(voter)
	if rocked.ok:
		parts.append("Rocked the vote: %d of %d." % [director.clock.rtv_votes(), director.clock.rtv_needed(director.player_count())])
	else:
		parts.append(rocked.error.message)
	return _result(nominated.ok or rocked.ok, " ".join(parts), "voted" if nominated.ok or rocked.ok else "refused")


func _result(ok: bool, text: String, how: String) -> Dictionary:
	last_result = {"ok": ok, "text": text, "how": how}
	return last_result


func _who(ctx: Object) -> String:
	if ctx.has_method("caller_label"):
		return str(ctx.call("caller_label"))
	return "An admin"


func _cmd(ctx: Object) -> void:
	var args := commands._args(ctx)
	if args.is_empty():
		var data := offer(ctx)
		if not _send(ctx, data):
			# A console, or a client with no notices: the list as lines.
			var lines := PackedStringArray()
			for r: Dictionary in data["maps"]:
				lines.append("%s%s  (%s)" % ["* " if bool(r.get("current", false)) else "  ", r["name"], r["id"]])
			ctx.call("reply_lines", lines)
		return
	var result: Dictionary = await choose(ctx, commands._resolve(args[0]))
	ctx.call("reply", str(result["text"]))
	var _sent := _send(ctx, {"result": result})


func _send(ctx: Object, data: Dictionary) -> bool:
	if notice_fn.is_valid():
		return bool(notice_fn.call(ctx, data))
	var session: Variant = ctx.get("session")
	if not (session is Object) or not ResourceLoader.exists(NOTICE_SCRIPT):
		return false
	var server: Object = DotRegistry.get_service(&"dot_server")
	if server == null or not server.has_method("send_notice"):
		return false
	var notice: Object = (load(NOTICE_SCRIPT) as GDScript).call("make", &"", "", -1.0, TOPIC, data)
	return bool(server.call("send_notice", session, notice))


func describe() -> Dictionary:
	return {"flag": required_flag(), "cvar": cvar != null, "change_fn": change_fn.is_valid(),
		"last_offer": (last_offer.get("maps", []) as Array).size() if last_offer.has("maps") else 0,
		"last_result": last_result.get("how", "")}
