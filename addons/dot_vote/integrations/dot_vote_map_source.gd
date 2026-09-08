class_name DotVoteMapSource
extends DotVoteSource

## Votes over the maps in a [code]DotMapCatalogue[/code].
##
## The same shape as [DotVoteGameSource] and for the same reason: this file names no
## dot-map class, so dot-vote installs in a project that has never heard of dot-map.
## The catalogue and the session arrive as [Object]s and are duck-typed.
##
## [codeblock]
## var source := DotVoteMapSource.of(session.catalogue, session)
## director.source = source
## [/codeblock]
##
## [b]dot-map already has a vote of its own, and this does not replace it.[/b]
## [code]DotMapVote[/code] and [code]DotMapTimeLimit[/code] are a plurality ballot, a
## countdown and a rock-the-vote, wired into two games, and a server happy with them
## needs nothing here. This is what a server wants when it needs an instant runoff, a
## quorum, per-map time limits, nominations with caps, a cooldown in minutes, or any
## of the other forty settings in [DotVoteRules] — and it is the same engine the games
## on the same server vote with, which is the actual argument for it.
##
## [b]Per-map settings live in the map's [code]meta[/code][/b], under a
## [code]vote[/code] key — the same convention as the game source, so an operator
## learns it once:
##
## [codeblock]
## {"id": "surf_kitsune", "meta": {"vote": {"time_limit_sec": 3600, "weight": 2.0}}}
## [/codeblock]

const CHANNEL := "vote.maps"

## The metadata key per-map vote settings are read from.
const META_KEY := "vote"

## A [code]DotMapCatalogue[/code]. Duck-typed.
var catalogue: Object = null

## A [code]DotMapSession[/code], for [method apply]. Optional: without one this source
## lists and the host does the change.
var session: Object = null

## Only offer maps of these kinds. Empty offers every kind.
##
## What a surf-only server sets. The alternative is an operator maintaining a second
## catalogue that is a subset of the first, which is two lists of maps and therefore
## two lists of maps that disagree.
var kinds: Array[StringName] = []

## Map ids never offered.
var excluded: Array[StringName] = []


static func of(p_catalogue: Object, p_session: Object = null) -> DotVoteMapSource:
	var source := DotVoteMapSource.new()
	source.catalogue = p_catalogue
	source.session = p_session
	return source


## Builds one from a [code]DotMapSession[/code] alone, taking its catalogue.
static func from_session(p_session: Object) -> DotVoteMapSource:
	if p_session == null:
		return DotVoteMapSource.of(null, null)

	return DotVoteMapSource.of(p_session.get("catalogue") as Object, p_session)


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

	# A map's expected length is a time limit that is a property of the MAP, which is
	# the whole reason DotVoteChoice carries one. A ten-minute bhop map and a
	# forty-minute surf map on one rotation under one global limit is a server that
	# cuts half its maps short and leaves the rest empty for twenty minutes.
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
