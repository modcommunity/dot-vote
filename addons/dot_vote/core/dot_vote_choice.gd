@tool
class_name DotVoteChoice
extends Resource

## One thing that can be voted for: a game, a map, a mode, a mutator.
## Deliberately an id, a name and the facts a ballot needs, not a game or a map; what the id means is a [DotVoteSource]'s business.
## That is how one vote system drives dot-server's game list and dot-map's catalogue without naming either.

## Id, unique within a source; history, cooldowns and per-choice configuration are keyed on it, so never rename it.
@export var id: StringName = &""

## Name shown on the ballot. Falls back to [member id].
@export var display_name: String = ""

## The pack a subscription delivered this from, or empty for a choice the game names
## itself. Shown beside the name ([method label]); never part of the id.
@export var pack_title: String = ""

## Free-text line under the name, where a ballot has room for one.
@export var description: String = ""

## A tag a source or a game filters on, such as [code]&"map"[/code] or [code]&"casual"[/code].
## A [StringName], not an enum: the family has no opinion on a server's categories.
@export var group: StringName = &""

@export_group("Availability")

## Whether it may be offered at all. An operator's off switch.
@export var enabled: bool = true

## Fewest players before it is offered. 0 = no floor.
## A 32-player map for four people is legal but a bad evening, so it leaves the ballot, not the catalogue.
@export_range(0, 128, 1) var min_players: int = 0

## Most players before it stops being offered. 0 = no ceiling.
@export_range(0, 128, 1) var max_players: int = 0

## Never filled in at random, offered only when somebody nominates it.
## For the joke map or the 40-minute epic.
@export var nominate_only: bool = false

## Whether this is one of the server's own shipped choices; informative only, nothing is refused for it.
## Read from the thing's metadata ([code]vote: {official: false}[/code]); true by default so a server with no opinion marks nothing.
@export var official: bool = true

@export_group("Duration")

## Seconds this choice runs for, overriding [member DotVoteRules.duration_sec].
## Negative means "use the rules"; zero is a real setting (no limit, ends only by vote).
@export_range(-1.0, 21600.0, 1.0) var time_limit_sec: float = -1.0

## Rounds this choice runs for, overriding [member DotVoteRules.round_limit]; negative uses the rules.
## Whichever of rounds and seconds arrives first ends it.
@export_range(-1, 512, 1) var round_limit: int = -1

@export_group("Selection")

## Relative likelihood under [constant DotVoteRules.Fill.WEIGHTED]. 0 excludes it.
@export_range(0.0, 100.0, 0.1) var weight: float = 1.0

## Plays this choice is excluded for after being played; negative uses [member DotVoteRules.cooldown].
@export_range(-1, 64, 1) var cooldown_override: int = -1

@export_group("Metadata")

## Anything the game needs and this addon must not interpret.
## A source puts the thing itself here so a host need not look the winner up again.
@export var meta: Dictionary = {}


static func of(p_id: StringName, p_display: String = "") -> DotVoteChoice:
	var choice := DotVoteChoice.new()
	choice.id = p_id
	choice.display_name = p_display
	return choice


func name_or_id() -> String:
	return display_name if display_name != "" else String(id)


## What a menu, ballot or list prints: "Name [Pack]" for a delivered choice, the bare
## name otherwise. Searching by name keeps using [method name_or_id].
func label() -> String:
	if pack_title == "":
		return name_or_id()

	return "%s [%s]" % [name_or_id(), pack_title]


## Whether this may appear on a ballot for a server with this many players.
## [param nominated] relaxes [member nominate_only] only; the player counts still apply.
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
		"pack_title": pack_title,
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
		# Duplicated: a Dictionary is a reference, so handing out the member would let a
		# caller write into the choice.
		"meta": meta.duplicate(true),
	}


static func from_dictionary(data: Dictionary) -> DotVoteChoice:
	var choice := DotVoteChoice.new()

	choice.id = StringName(str(data.get("id", "")))
	choice.display_name = str(data.get("display_name", data.get("name", "")))
	choice.pack_title = str(data.get("pack_title", ""))
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
		"name": label(),
		"group": String(group) if group != &"" else "-",
		"limit": "default" if time_limit_sec < 0.0 else "%ds" % int(time_limit_sec),
		"enabled": enabled,
	}


func _to_string() -> String:
	return "DotVoteChoice(%s)" % id
