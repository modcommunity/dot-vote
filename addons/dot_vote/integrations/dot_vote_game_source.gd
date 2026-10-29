class_name DotVoteGameSource
extends DotVoteSource

## Votes over the games a [code]DotGameManager[/code] can run.
## It names no dot-server class, so the addon installs without dot-server: the manager arrives as an [Object], duck-typed.
## Per-game settings sit in the descriptor's metadata under a [code]vote[/code] key ([code]time_limit_sec[/code], [code]weight[/code], [code]nominate_only[/code], [code]group[/code]).

const CHANNEL := "vote.games"

## The metadata key per-game vote settings are read from.
const META_KEY := "vote"

## A [code]DotGameManager[/code]. Duck-typed; see the class documentation.
var manager: Object = null

## Game ids never offered, whatever the manager says.
## For a lobby, so a server does not offer "vote to go back to the menu".
var excluded: Array[StringName] = []

## Game ids in the order [method choices] lists them, the others after, in manager order.
## What a fixed cycle is: the director's "next in rotation" walks the source's order.
var order: Array[StringName] = []


static func of(p_manager: Object) -> DotVoteGameSource:
	# Not this class's own name. A script that names itself in an expression, loaded after
	# its base, cuts Godot 4.7.2's exit teardown short and leaks every script loaded before
	# it. See docs/gdscript-hazards.md, "A script that names itself".
	var source := new()
	source.manager = p_manager
	return source


## Finds the game manager in [DotRegistry], for a host that has one but no reference.
static func from_registry() -> DotVoteGameSource:
	return of(DotRegistry.get_service(&"dot_game_manager"))


## What the RUNNING game's descriptor carries under [param key], or an empty dictionary.
## For a module that must read its own game's [code]game.yml[/code] without naming the host's config class; duck-typed through [DotRegistry].
## A copy, so a caller that layers it does not write into the descriptor.
static func running_game_metadata(key: String) -> Dictionary:
	var manager: Object = DotRegistry.get_service(&"dot_game_manager")

	if manager == null or not manager.has_method("current"):
		return {}

	var descriptor: Variant = manager.call("current")

	if descriptor == null or not (descriptor is Object):
		return {}

	var metadata: Variant = (descriptor as Object).get("metadata")

	if not (metadata is Dictionary):
		return {}

	var section: Variant = (metadata as Dictionary).get(key, {})

	return (section as Dictionary).duplicate(true) if section is Dictionary else {}


func source_name() -> String:
	return "games"


## Whether the object handed over is actually a game manager.
## Said out loud when not, since a quietly empty source looks like a server with no games.
func is_usable() -> bool:
	return (
		manager != null
		and manager.has_method("change_game")
		and manager.has_method("current")
	)


func choices() -> Array[DotVoteChoice]:
	var out: Array[DotVoteChoice] = []

	if manager == null:
		return out

	var games: Variant = manager.get("games")

	if not (games is Array):
		DotLog.warn(CHANNEL, "the game manager has no games array", {
			"manager": str(manager)
		})
		return out

	for descriptor: Variant in (games as Array):
		if descriptor == null or not (descriptor is Object):
			continue

		var choice := _to_choice(descriptor as Object)

		if choice != null:
			out.append(choice)

	if not order.is_empty():
		var rank := func(c: DotVoteChoice) -> int:
			var at := order.find(c.id)
			return at if at >= 0 else order.size()
		# Stable by construction: ties compare equal and keep manager order.
		var keyed: Array = []
		for i in range(out.size()):
			keyed.append([rank.call(out[i]), i, out[i]])
		keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		out.clear()
		for k: Array in keyed:
			out.append(k[2])

	return out


func _to_choice(descriptor: Object) -> DotVoteChoice:
	var id := StringName(str(descriptor.get("game_id")))

	if id == &"" or excluded.has(id):
		return null

	var choice := DotVoteChoice.new()
	choice.id = id
	choice.display_name = str(descriptor.get("display_name"))
	choice.group = &"game"
	choice.min_players = int(descriptor.get("min_players"))
	choice.max_players = int(descriptor.get("max_players"))

	# The descriptor itself rides along, so a host acting on a winner does not have to
	# look it up again — and so a game change can read the version and the content key
	# straight off the thing the players voted for.
	choice.meta = {"descriptor": descriptor}

	var metadata: Variant = descriptor.get("metadata")

	if metadata is Dictionary:
		_apply_meta(choice, (metadata as Dictionary).get(META_KEY, {}))

	return choice


func _apply_meta(choice: DotVoteChoice, raw: Variant) -> void:
	if not (raw is Dictionary):
		return

	var settings := raw as Dictionary

	if settings.has("time_limit_sec"):
		choice.time_limit_sec = float(settings["time_limit_sec"])

	if settings.has("round_limit"):
		choice.round_limit = int(settings["round_limit"])

	if settings.has("weight"):
		choice.weight = float(settings["weight"])

	if settings.has("nominate_only"):
		choice.nominate_only = bool(settings["nominate_only"])

	if settings.has("enabled"):
		choice.enabled = bool(settings["enabled"])

	# Whether this is one of the server's own. Read from the thing's metadata rather than
	# from a list of official ids beside it, for this file's usual reason: a second list
	# keyed on ids is a list that goes stale the first time something is renamed.
	if settings.has("official"):
		choice.official = bool(settings["official"])

	if settings.has("cooldown"):
		choice.cooldown_override = int(settings["cooldown"])

	if settings.has("group"):
		choice.group = StringName(str(settings["group"]))

	if settings.has("description"):
		choice.description = str(settings["description"])

	# min_players and max_players are read off the descriptor's own fields above,
	# which dot-server already has — but a game whose SLOTS are 32 and which is no fun
	# below 6 needs to say both, and only one of them is a dot-server concept.
	if settings.has("min_players"):
		choice.min_players = int(settings["min_players"])

	if settings.has("max_players"):
		choice.max_players = int(settings["max_players"])


func current_id() -> StringName:
	if manager == null or not manager.has_method("current"):
		return &""

	var descriptor: Variant = manager.call("current")

	if descriptor == null or not (descriptor is Object):
		return &""

	return StringName(str((descriptor as Object).get("game_id")))


func supports_apply() -> bool:
	return is_usable()


## Changes the game. A coroutine: a game change waits for every client to fetch the
## content before it swaps.
func apply(id: StringName) -> DotResult:
	if not is_usable():
		return DotResult.fail(
			DotError.CODE_STATE,
			"No usable game manager.",
			"DotVoteGameSource was given %s" % (
				"nothing" if manager == null else str(manager)
			)
		)

	DotLog.info(CHANNEL, "changing game by vote", {"to": String(id)})

	var result: Variant = await manager.call("change_game", String(id), "vote")

	if result is DotResult:
		return result as DotResult

	return DotResult.success(id)


func describe() -> Dictionary:
	var out := super.describe()
	out["usable"] = is_usable()
	out["excluded"] = excluded.size()
	return out
