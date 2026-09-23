@tool
class_name DotVoteChoice
extends Resource

## One thing that can be voted for: a game, a map, a mode, a mutator.
##
## [b]Deliberately not a game and not a map.[/b] It is an id, a name to show, and the
## handful of facts a ballot has to know to decide whether to offer it — how many
## players it wants, how long it runs for, whether it may be picked at random or only
## nominated. What the id [i]means[/i] is a [DotVoteSource]'s business, which is the
## only reason one vote system can drive dot-server's game list and dot-map's
## catalogue without naming either.
##
## The alternative — a vote that takes a [code]DotGameDescriptor[/code] — was rejected
## for the family's parse reason and then for a better one: a server that offers
## "Arena", "Arena (low gravity)" and "surf_beginner" on one ballot is offering three
## things of two different kinds, and a ballot that can only hold one kind cannot.
##
## [codeblock]
## var choice := DotVoteChoice.of(&"arena", "Arena")
## choice.time_limit_sec = 1800.0    # this one runs for half an hour
## choice.min_players = 4            # and is not offered to three people
## [/codeblock]

## Id, unique within a source. What a vote returns and what history is keyed on.
##
## [b]Never renamed.[/b] History, cooldowns and per-choice configuration are all keyed
## on it, so changing it makes a server think it has never played this.
@export var id: StringName = &""

## Name shown on the ballot. Falls back to [member id].
@export var display_name: String = ""

## Free-text line under the name, where a ballot has room for one.
@export var description: String = ""

## A tag a source or a game filters on — [code]&"map"[/code], [code]&"game"[/code],
## [code]&"casual"[/code].
##
## A [StringName] rather than an enum, for [DotMapDef]'s reason: this family should not
## have an opinion about what categories a server divides its content into.
@export var group: StringName = &""

@export_group("Availability")

## Whether it may be offered at all. An operator's off switch.
@export var enabled: bool = true

## Fewest players before it is offered. 0 = no floor.
##
## The point of a floor is a 32-player map on a server with four people on it: it is
## still a legal choice and it is a bad evening, so it comes off the ballot rather
## than out of the catalogue.
@export_range(0, 128, 1) var min_players: int = 0

## Most players before it stops being offered. 0 = no ceiling.
@export_range(0, 128, 1) var max_players: int = 0

## Never filled in at random — offered only when somebody nominates it.
##
## For the joke map, the 40-minute epic, the mode that needs organising. It stays
## reachable by name and stops arriving unasked at three in the morning.
@export var nominate_only: bool = false

## Whether this is one of the server's own, shipped choices rather than a custom one.
##
## [b]Informative only[/b] — nothing is refused for being unofficial. It is what
## [member DotVoteRules.unofficial_marker] marks on a ballot, which is how a player
## tells the map the game shipped with from the one a community uploaded last week.
## A source reads it from the thing's own metadata ([code]vote: {official: false}[/code]);
## true by default, because a server with no opinion should mark nothing.
@export var official: bool = true

@export_group("Duration")

## Seconds this choice runs for, overriding [member DotVoteRules.duration_sec].
##
## [b]Negative means "use the rules".[/b] Not zero: zero is a real and different
## setting — a choice with no time limit at all, which ends only by vote — and a
## server that wanted one and got the default instead would change away from it every
## twenty minutes with nothing to say why.
@export_range(-1.0, 21600.0, 1.0) var time_limit_sec: float = -1.0

## Rounds this choice runs for, overriding [member DotVoteRules.round_limit].
##
## Negative means "use the rules". Rounds and seconds are both limits and whichever
## arrives first ends it — a best-of-nine that overruns still ends, and a slow
## best-of-nine is not cut off at round four.
@export_range(-1, 512, 1) var round_limit: int = -1

@export_group("Selection")

## Relative likelihood under [constant DotVoteRules.Fill.WEIGHTED]. 0 excludes it.
@export_range(0.0, 100.0, 0.1) var weight: float = 1.0

## Plays this choice is excluded for after being played, overriding the rules.
##
## Negative uses [member DotVoteRules.cooldown]. For the one map everybody is sick of,
## without lengthening the cooldown on everything.
@export_range(-1, 64, 1) var cooldown_override: int = -1

@export_group("Metadata")

## Anything the game needs and this addon must not interpret.
##
## A source puts the thing itself in here — the descriptor, the map def — so a host
## that gets a winning [DotVoteChoice] back does not have to look it up again.
@export var meta: Dictionary = {}


static func of(p_id: StringName, p_display: String = "") -> DotVoteChoice:
	var choice := DotVoteChoice.new()
	choice.id = p_id
	choice.display_name = p_display
	return choice


func name_or_id() -> String:
	return display_name if display_name != "" else String(id)


## Whether this may appear on a ballot for a server with this many players.
##
## [param nominated] relaxes [member nominate_only] only — the player counts still
## apply, because somebody nominating a 32-player map for four people has not made it
## a better idea.
func available_for(players: int, nominated: bool = false) -> bool:
	if not enabled:
		return false

	if nominate_only and not nominated:
		return false

	if min_players > 0 and players < min_players:
		return false

	if max_players > 0 and players > max_players:
		return false

	return true


## The time limit to run this choice under, given the rules' default.
func duration_for(default_sec: float) -> float:
	return time_limit_sec if time_limit_sec >= 0.0 else default_sec


## The round limit to run this choice under, given the rules' default.
func rounds_for(default_rounds: int) -> int:
	return round_limit if round_limit >= 0 else default_rounds


## The cooldown to apply after this has been played, given the rules' default.
func cooldown_for(default_cooldown: int) -> int:
	return cooldown_override if cooldown_override >= 0 else default_cooldown


func to_dictionary() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"description": description,
		"group": String(group),
		"enabled": enabled,
		"min_players": min_players,
		"max_players": max_players,
		"nominate_only": nominate_only,
		"official": official,
		"time_limit_sec": time_limit_sec,
		"round_limit": round_limit,
		"weight": weight,
		"cooldown_override": cooldown_override,
		# Duplicated, and this is not defensive tidiness. A Dictionary is a reference in
		# GDScript, so handing out the member means a caller that writes into what it was
		# given writes into the choice — the exact aliasing that made every scoped
		# DotLeaderboardDef on a server share one object, and that DotTimerZone.payload
		# and DotMapDef.meta each had a copy of.
		"meta": meta.duplicate(true),
	}


static func from_dictionary(data: Dictionary) -> DotVoteChoice:
	var choice := DotVoteChoice.new()

	choice.id = StringName(str(data.get("id", "")))
	choice.display_name = str(data.get("display_name", data.get("name", "")))
	choice.description = str(data.get("description", ""))
	choice.group = StringName(str(data.get("group", "")))
	choice.enabled = bool(data.get("enabled", true))
	choice.min_players = int(data.get("min_players", 0))
	choice.max_players = int(data.get("max_players", 0))
	choice.nominate_only = bool(data.get("nominate_only", false))
	choice.official = bool(data.get("official", true))
	choice.time_limit_sec = float(data.get("time_limit_sec", -1.0))
	choice.round_limit = int(data.get("round_limit", -1))
	choice.weight = float(data.get("weight", 1.0))
	choice.cooldown_override = int(data.get("cooldown_override", -1))

	var meta_in: Variant = data.get("meta", {})
	choice.meta = (meta_in as Dictionary).duplicate(true) if meta_in is Dictionary else {}

	return choice


func describe() -> Dictionary:
	return {
		"id": String(id),
		"name": name_or_id(),
		"group": String(group) if group != &"" else "-",
		"limit": "default" if time_limit_sec < 0.0 else "%ds" % int(time_limit_sec),
		"enabled": enabled,
	}


func _to_string() -> String:
	return "DotVoteChoice(%s)" % id
