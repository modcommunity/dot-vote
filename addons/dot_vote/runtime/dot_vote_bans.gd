class_name DotVoteBans
extends RefCounted

## A vote to ban one player: yes or no, one at a time, enabled per server and per role.
##
## [codeblock]
## var bans := DotVoteBans.new()
## bans.voters_fn = func() -> Array: return humans_playing()          # ids
## bans.role_fn = func(id: StringName) -> String: return "admin" if is_admin(id) else "player"
## bans.ban_fn = func(target: StringName, minutes: float, reason: String) -> void: ...
## bans.rules.bind(self)                   # the sv_voteban* cvars
## bans.bind_commands(self)                # voteban, voteban_yes, voteban_no
## # A game that wants one, for a reason of its own (the one API):
## bans.start(&"", target, "team damage")  # &"" is the game, not a player
## # and from its own tick:
## bans.advance(delta)
## [/codeblock]
##
## [b]Why it is its own thing and not a ballot.[/b] [DotVoteDirector] is an engine over
## choices that become the next map; this is one question about one person, with its own
## clock, its own eligibility (everybody but the target) and a consequence (a ban) that is the
## game's to carry out. It holds no ban list: [member ban_fn] is the game's, and dot-server's
## [code]DotBanManager[/code] is what it calls there. Nothing here names a dot-server class.
##
## [b]Who decides what.[/b] [member rules] holds every policy (the cvars). [member role_fn]
## names a role for a player and the rules say which roles may start one and which are
## immune. A start from the game ([constant GAME] as starter) skips the start role and the
## starter's cooldown, never the target's immunity or the cooldown on the target: an automatic
## trigger must not be a way to ban a moderator, nor to run the same vote every second.
##
## [b]It passes when enough say yes, not when the clock runs out.[/b] The yes needed is
## [code]ceil(threshold * eligible)[/code], fixed when the vote opens (a player leaving shrinks
## the electorate, so it is recomputed); it passes the moment that many have said yes and
## fails the moment that many yes can no longer happen, or when the time runs out. Silence is
## therefore a no, which is the safe way round for a ban.

const CHANNEL := "vote.bans"

## The starter of a vote the game opened itself.
const GAME := &""

const DEFAULTS := {"voteban": "voteban", "yes": "voteban_yes", "no": "voteban_no"}

signal started(target: StringName, starter: StringName, reason: String)
signal cast(voter: StringName, yes: bool)
signal passed(target: StringName, minutes: float, reason: String)
signal failed(target: StringName, why: String)

var rules: DotVoteBanRules = DotVoteBanRules.new()

## () -> Array of the ids of everybody who may vote (every human playing).
var voters_fn: Callable = Callable()
## (id) -> String. A player's role; "player" when unset.
var role_fn: Callable = Callable()
## (id) -> String. What a line calls them; the id when unset.
var name_fn: Callable = Callable()
## (target, minutes, reason) -> anything. The game bans them; may be a coroutine.
var ban_fn: Callable = Callable()
## (line) -> void. What the players are told.
var announce_fn: Callable = Callable()
## (ctx) -> id of the player behind a command; (text) -> id of the player a command names.
var voter_fn: Callable = Callable()
var resolve_fn: Callable = Callable()
## () -> float, seconds on the game's clock. Defaults to the engine's.
var clock_fn: Callable = Callable()

## Command names by role ("voteban", "yes", "no"), and a prefix for all of them.
var names: Dictionary = {}
var prefix: String = ""

var _open: bool = false
var _target: StringName = &""
var _starter: StringName = &""
var _reason: String = ""
var _eligible: Array = []
var _yes: Dictionary = {}
var _no: Dictionary = {}
var _left: float = 0.0
var _last_by: Dictionary = {}
var _last_on: Dictionary = {}
var _now: float = 0.0


func is_open() -> bool:
	return _open


func target() -> StringName:
	return _target


func command_name(role: String) -> String:
	return prefix + str(names.get(role, DEFAULTS.get(role, role)))


## Opens a vote to ban [param target]. [param starter] is [constant GAME] for the game's own.
## A [DotResult] so a refusal says why (CODE_FORBIDDEN, CODE_STATE, CODE_INVALID, CODE_STATE).
func start(starter: StringName, target_id: StringName, reason: String = "") -> DotResult:
	rules.refresh()
	if not rules.enabled:
		return DotResult.fail(DotError.CODE_STATE, "Votebans are off on this server.")
	if _open:
		return DotResult.fail(DotError.CODE_STATE, "A voteban is already open.")
	if target_id == &"" or target_id == starter:
		return DotResult.fail(DotError.CODE_INVALID, "Name another player to vote against.")
	if starter != GAME and not rules.may_start(_role(starter)):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "You may not start a voteban here.")
	if rules.is_immune(_role(target_id)):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "%s cannot be voted against." % _name(target_id))
	var now := _clock()
	if starter != GAME and _last_by.has(starter) and now - float(_last_by[starter]) < rules.cooldown_sec:
		return DotResult.fail(DotError.CODE_RATE_LIMITED, "Wait %d s before starting another." % ceili(rules.cooldown_sec - (now - float(_last_by[starter]))))
	if _last_on.has(target_id) and now - float(_last_on[target_id]) < rules.cooldown_sec:
		return DotResult.fail(DotError.CODE_RATE_LIMITED, "%s was voted on a moment ago." % _name(target_id))
	var eligible: Array = []
	if voters_fn.is_valid():
		for id: Variant in voters_fn.call():
			if StringName(str(id)) != target_id:
				eligible.append(StringName(str(id)))
	if eligible.size() < rules.min_voters:
		return DotResult.fail(DotError.CODE_STATE, "Needs at least %d other players." % rules.min_voters)
	if starter != GAME and not (starter in eligible):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only players here may start a voteban.")

	_open = true
	_target = target_id
	_starter = starter
	_reason = reason
	_eligible = eligible
	_yes = {}
	_no = {}
	_left = rules.vote_sec
	_last_on[target_id] = now
	if starter != GAME:
		_last_by[starter] = now
		_yes[starter] = true
	DotLog.info(CHANNEL, "voteban opened", {"target": String(target_id), "starter": String(starter), "reason": reason})
	started.emit(target_id, starter, reason)
	_say("%s started a vote to ban %s%s. %s to vote." % [
		_name(starter) if starter != GAME else "The game", _name(target_id),
		(" (" + reason + ")") if reason != "" else "", "%s / %s" % [command_name("yes"), command_name("no")]])
	_settle()
	return DotResult.success(target_id)


## One yes or no from [param voter]; changing your mind is allowed.
func vote(voter: StringName, yes: bool) -> DotResult:
	if not _open:
		return DotResult.fail(DotError.CODE_STATE, "No voteban is open.")
	if not (voter in _eligible):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "You cannot vote on this one.")
	_yes.erase(voter)
	_no.erase(voter)
	if yes:
		_yes[voter] = true
	else:
		_no[voter] = true
	cast.emit(voter, yes)
	_settle()
	return DotResult.success(yes)


## A voter who left: they no longer count in the electorate.
func forget_voter(voter: StringName) -> void:
	if not _open:
		return
	_eligible.erase(voter)
	_yes.erase(voter)
	_no.erase(voter)
	_settle()


## Closes an open vote with nothing decided (the target left, the map changed).
func cancel(why: String = "cancelled") -> void:
	if _open:
		_finish(false, why)


func advance(delta: float) -> void:
	_now += delta
	if not _open:
		return
	_left -= delta
	if _left <= 0.0:
		_finish(false, "not enough yes votes in time")


func yes_needed() -> int:
	return maxi(ceili(rules.threshold * float(_eligible.size())), 1)


func _settle() -> void:
	if not _open:
		return
	if _eligible.size() < 1:
		_finish(false, "nobody left to vote")
		return
	var need := yes_needed()
	if _yes.size() >= need:
		_finish(true, "")
	elif _yes.size() + (_eligible.size() - _yes.size() - _no.size()) < need:
		_finish(false, "too many no votes")


func _finish(pass_it: bool, why: String) -> void:
	_open = false
	var who := _target
	var reason := _reason
	_last_on[who] = _clock()
	if pass_it:
		var minutes := rules.ban_minutes
		DotLog.info(CHANNEL, "voteban passed", {"target": String(who), "minutes": minutes, "yes": _yes.size(), "of": _eligible.size()})
		_say("The vote passed: %s is banned%s." % [_name(who), (" for %d minutes" % int(minutes)) if minutes > 0.0 else ""])
		passed.emit(who, minutes, reason)
		if ban_fn.is_valid():
			ban_fn.call(who, minutes, "Voted off: " + (reason if reason != "" else "voteban"))
	else:
		DotLog.info(CHANNEL, "voteban failed", {"target": String(who), "why": why})
		_say("The vote to ban %s failed." % _name(who))
		failed.emit(who, why)


func _role(id: StringName) -> String:
	return str(role_fn.call(id)) if role_fn.is_valid() else "player"


func _name(id: StringName) -> String:
	return str(name_fn.call(id)) if name_fn.is_valid() else String(id)


func _say(line: String) -> void:
	if announce_fn.is_valid():
		announce_fn.call(line)


func _clock() -> float:
	return float(clock_fn.call()) if clock_fn.is_valid() else _now


func describe() -> Dictionary:
	return {"open": _open, "target": String(_target), "yes": _yes.size(), "no": _no.size(),
			"eligible": _eligible.size(), "needed": yes_needed() if _open else 0, "rules": rules.describe()}


# --- Commands ---------------------------------------------------------------------------

## Registers `voteban <player> [reason]`, `voteban_yes` and `voteban_no` (typable in chat),
## and the cvars. [param host] is a DotModule (add_command) or console (command).
func bind_commands(host: Object) -> DotResult:
	if host == null:
		return DotResult.fail(DotError.CODE_INVALID, "A host is needed.")
	rules.bind(host)
	var adder := "add_command" if host.has_method("add_command") else ("command" if host.has_method("command") else "")
	if adder == "":
		return DotResult.fail(DotError.CODE_INVALID, "The host has no add_command or command.")
	var table := [
		["voteban", _cmd_start, "Start a vote to ban a player: voteban <player> [reason]"],
		["yes", _cmd_yes, "Vote yes on the open voteban"],
		["no", _cmd_no, "Vote no on the open voteban"],
	]
	for entry: Array in table:
		var registered: Variant = host.call(adder, command_name(entry[0]), entry[1], entry[2], "")
		if registered is Object and (registered as Object).has_method("with_chat"):
			(registered as Object).call("with_chat")
	return DotResult.success(true)


func _voter(ctx: Object) -> StringName:
	if voter_fn.is_valid():
		return StringName(str(voter_fn.call(ctx)))
	var session: Variant = ctx.get("session")
	if session is Object and (session as Object).get("userid") != null:
		return StringName("u%s" % str((session as Object).get("userid")))
	return &"console"


func _reply(ctx: Object, result: DotResult, ok_text: String) -> void:
	ctx.call("reply", ok_text if result.ok else result.error.message)


func _cmd_start(ctx: Object) -> void:
	var args: Variant = ctx.get("args")
	var words: PackedStringArray = args if args is PackedStringArray else PackedStringArray()
	if words.is_empty():
		ctx.call("reply", "Usage: %s <player> [reason]" % command_name("voteban"))
		return
	var who := StringName(str(resolve_fn.call(words[0]))) if resolve_fn.is_valid() else StringName(words[0])
	if who == &"":
		ctx.call("reply", "No player called %s." % words[0])
		return
	var reason := " ".join(words.slice(1))
	_reply(ctx, start(_voter(ctx), who, reason), "Vote started.")


func _cmd_yes(ctx: Object) -> void:
	_reply(ctx, vote(_voter(ctx), true), "Voted yes.")


func _cmd_no(ctx: Object) -> void:
	_reply(ctx, vote(_voter(ctx), false), "Voted no.")
