class_name DotVoteBanRules
extends RefCounted

## Every policy of a voteban, as plain values that an operator's cvars overwrite.
##
## [b]Why this is not part of [DotVoteRules].[/b] That is the ballot engine's policy over
## choices (maps, games); a voteban is a yes or no about one player, shares none of its
## clocks, and a server that never wants one should not carry fifty-five settings with it.
## [method bind] registers one cvar per setting and [method refresh] reads them back, so a
## change at the console applies to the next vote, never to the one in progress.
##
## A role is a word the game gives a player through [member DotVoteBans.role_fn] ("player",
## "staff", "admin", whatever the game has). `*` in a role list is everybody.

const CVARS := {
	"enabled": ["sv_voteban", "1", "1: players may vote to ban a player. 0: no voteban, not even one a game starts."],
	"start_roles": ["sv_voteban_start_roles", "*", "Roles that may start a voteban, comma separated. * is everybody; empty is nobody (a game may still start one)."],
	"immune_roles": ["sv_voteban_immune_roles", "staff,admin", "Roles that cannot be voted against, comma separated. Empty: nobody is immune."],
	"ban_minutes": ["sv_voteban_minutes", "60", "How long a passed voteban bans, in minutes. 0 is permanent."],
	"threshold": ["sv_voteban_threshold", "0.6", "The share of the eligible voters (everybody but the target) whose yes passes it."],
	"cooldown_sec": ["sv_voteban_cooldown", "120", "Seconds before the same player may start another, or the same target be voted on again."],
	"vote_sec": ["sv_voteban_seconds", "30", "How long a voteban stays open."],
	"min_voters": ["sv_voteban_min_voters", "3", "The fewest eligible voters (everybody but the target) a voteban needs. Fewer: refused."],
}

var enabled: bool = true
var start_roles: PackedStringArray = PackedStringArray(["*"])
var immune_roles: PackedStringArray = PackedStringArray(["staff", "admin"])
var ban_minutes: float = 60.0
var threshold: float = 0.6
var cooldown_sec: float = 120.0
var vote_sec: float = 30.0
var min_voters: int = 3

## setting -> the cvar object, for the settings a console holds.
var _cvars: Dictionary = {}


## Registers every cvar on [param host] (a DotModule or a console, duck-typed) and keeps them.
## One cvar per server: a second bind reads the one already there.
func bind(host: Object) -> void:
	for setting: String in CVARS:
		var spec: Array = CVARS[setting]
		var made: Object = DotVoteMapMenu._bind_cvar(host, spec[0], str(spec[1]), str(spec[2]))
		if made != null:
			_cvars[setting] = made
	refresh()


## Reads each bound cvar into its setting. Cheap; called before every decision.
func refresh() -> void:
	for setting: String in _cvars:
		var c: Object = _cvars[setting]
		if c == null or not is_instance_valid(c) or not c.has_method("get_string"):
			continue
		var text := str(c.call("get_string")).strip_edges()
		match setting:
			"enabled": enabled = text not in ["0", "false", "off", ""]
			"start_roles": start_roles = _roles(text)
			"immune_roles": immune_roles = _roles(text)
			"ban_minutes": ban_minutes = maxf(text.to_float(), 0.0)
			"threshold": threshold = clampf(text.to_float(), 0.05, 1.0)
			"cooldown_sec": cooldown_sec = maxf(text.to_float(), 0.0)
			"vote_sec": vote_sec = maxf(text.to_float(), 5.0)
			"min_voters": min_voters = maxi(text.to_int(), 1)


static func _roles(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in text.split(",", false):
		out.append(part.strip_edges().to_lower())
	return out


func may_start(role: String) -> bool:
	return "*" in start_roles or role.to_lower() in start_roles


func is_immune(role: String) -> bool:
	return "*" in immune_roles or role.to_lower() in immune_roles


func describe() -> Dictionary:
	return {"enabled": enabled, "start_roles": ",".join(start_roles), "immune_roles": ",".join(immune_roles),
			"ban_minutes": ban_minutes, "threshold": threshold, "cooldown_sec": cooldown_sec,
			"vote_sec": vote_sec, "min_voters": min_voters, "cvars": _cvars.size()}
