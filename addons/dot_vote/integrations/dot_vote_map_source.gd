class_name DotVoteMapSource
extends DotVoteSource

## Votes over the maps in a [code]DotMapCatalogue[/code].
## Same shape as [DotVoteGameSource], naming no dot-map class; the catalogue and session are duck-typed.
## It does not replace dot-map's own [code]DotMapVote[/code]; it is for runoffs, quorums, per-map limits and the other [DotVoteRules] settings. Per-map settings sit in the map's [code]meta.vote[/code].

const CHANNEL := "vote.maps"

## The metadata key per-map vote settings are read from.
const META_KEY := "vote"

## A [code]DotMapCatalogue[/code]. Duck-typed.
var catalogue: Object = null

## A [code]DotMapSession[/code], for [method apply]. Optional: without one this source
## lists and the host does the change.
var session: Object = null

## Only offer maps of these kinds. Empty offers every kind.
## For a surf-only server, instead of a second catalogue that would disagree with the first.
var kinds: Array[StringName] = []

## Map ids never offered.
var excluded: Array[StringName] = []


static func of(p_catalogue: Object, p_session: Object = null) -> DotVoteMapSource:
	# Not this class's own name. A script that names itself in an expression, loaded after
	# its base, cuts Godot 4.7.2's exit teardown short and leaks every script loaded before
	# it. See docs/gdscript-hazards.md, "A script that names itself".
	var source := new()
	source.catalogue = p_catalogue
	source.session = p_session
	return source


## Builds one from a [code]DotMapSession[/code] alone, taking its catalogue.
static func from_session(p_session: Object) -> DotVoteMapSource:
	if p_session == null:
		return of(null, null)

	return of(p_session.get("catalogue") as Object, p_session)


func source_name() -> String:
	return "maps"


func is_usable() -> bool:
	return catalogue != null and (catalogue.get("maps") is Array)


func choices() -> Array[DotVoteChoice]:
	var out: Array[DotVoteChoice] = []

	if catalogue == null:
		return out

	var maps: Variant = catalogue.get("maps")

	if not (maps is Array):
		DotLog.warn(CHANNEL, "the catalogue has no maps array", {
			"catalogue": str(catalogue)
		})
		return out

	for map: Variant in (maps as Array):
		if map == null or not (map is Object):
			continue

		var choice := _to_choice(map as Object)

		if choice != null:
			out.append(choice)

	return out


func _to_choice(map: Object) -> DotVoteChoice:
	var id := StringName(str(map.get("id")))

	if id == &"" or excluded.has(id):
		return null

	# Outside the server's active map rotation (maps.yml): installed and loadable by `map`,
	# never on a ballot or a nomination. Duck-typed like everything here; a catalogue whose
	# maps have no such property (null) offers every map as it always did.
	var listed: Variant = map.get("in_rotation")
	if listed != null and not bool(listed):
		return null

	var kind := StringName(str(map.get("kind")))

	if not kinds.is_empty() and not kinds.has(kind):
		return null

	var choice := DotVoteChoice.new()
	choice.id = id
	choice.display_name = str(map.get("display_name"))
	choice.description = str(map.get("description"))
	choice.group = kind
	choice.min_players = int(map.get("min_players"))
	choice.max_players = int(map.get("max_players"))

	var enabled: Variant = map.get("enabled")
	choice.enabled = bool(enabled) if enabled != null else true

	# A map's expected length is a property of the MAP, which is why DotVoteChoice carries a
	# time limit; one global limit would cut a ten-minute map and drag a forty-minute one.
	var expected := int(map.get("expected_seconds"))

	if expected > 0:
		choice.time_limit_sec = float(expected)

	choice.meta = {"map": map}

	var meta: Variant = map.get("meta")

	if meta is Dictionary:
		_apply_meta(choice, (meta as Dictionary).get(META_KEY, {}))

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

	if settings.has("cooldown"):
		choice.cooldown_override = int(settings["cooldown"])

	if settings.has("enabled"):
		choice.enabled = bool(settings["enabled"])

	# Whether this is one of the server's own. Read from the thing's metadata rather than
	# from a list of official ids beside it, for this file's usual reason: a second list
	# keyed on ids is a list that goes stale the first time something is renamed.
	if settings.has("official"):
		choice.official = bool(settings["official"])


func current_id() -> StringName:
	if session == null:
		return &""

	var map: Variant = session.get("current")

	if map == null or not (map is Object):
		return &""

	return StringName(str((map as Object).get("id")))


func supports_apply() -> bool:
	return session != null and session.has_method("change_to")


## Changes the map. A coroutine: a delivered map is fetched before the world swaps.
func apply(id: StringName) -> DotResult:
	if not supports_apply():
		return DotResult.fail(
			DotError.CODE_STATE,
			"No map session to change with.",
			"give DotVoteMapSource a session, or let the host act on change_due"
		)

	DotLog.info(CHANNEL, "changing map by vote", {"to": String(id)})

	var result: Variant = await session.call("change_to", id)

	if result is DotResult:
		return result as DotResult

	return DotResult.success(id)


func describe() -> Dictionary:
	var out := super.describe()
	out["usable"] = is_usable()
	out["kinds"] = kinds.size()
	out["can_change"] = supports_apply()
	return out
