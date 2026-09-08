class_name DotVoteHistory
extends RefCounted

## What has been played, and what may not be offered again yet.
##
## [b]The cooldown is the whole design.[/b] Without one a server plays its three most
## popular maps for ever, because a vote is a popularity contest and popularity does
## not change between rounds. Every server in this genre grows a "recently played"
## exclusion, and the number that matters is how far back it remembers: too few and
## the thing you have just played is on the menu again, too many and a small server
## has nothing left to offer.
##
## Generalised from dot-map's rotation, and with the clamp that made that one honest:
## a cooldown longer than the pool is shortened rather than allowed to exclude
## everything, because a rotation that offers nothing leaves the server where it is
## for ever with no error anywhere.

const CHANNEL := "vote.history"

## Most recently played first.
var played: Array[StringName] = []

## id -> Unix seconds it was last played, for [constant DotVoteRules.Cooldown.MINUTES].
var last_played_at: Dictionary = {}

## Total plays per id, for a "least played" fill and for a console report.
var play_counts: Dictionary = {}

var rules: DotVoteRules = null


static func of(p_rules: DotVoteRules) -> DotVoteHistory:
	var history := DotVoteHistory.new()
	history.rules = p_rules
	return history


## Records something as played. [param now_sec] is injectable so a test can run a
## month of cooldowns in a millisecond, exactly as the clock is advanced by hand.
func note_played(id: StringName, now_sec: float = -1.0) -> void:
	if id == &"":
		return

	played.push_front(id)

	var limit := rules.history_limit if rules != null else 64

	while played.size() > limit:
		played.pop_back()

	last_played_at[id] = (
		now_sec if now_sec >= 0.0 else Time.get_unix_time_from_system()
	)
	play_counts[id] = int(play_counts.get(id, 0)) + 1


## How many things have been played since this one, or -1 for never.
func plays_since(id: StringName) -> int:
	var index := played.find(id)
	return index if index >= 0 else -1


func times_played(id: StringName) -> int:
	return int(play_counts.get(id, 0))


## Whether this is still on cooldown.
##
## [param pool_size] is how much there is to choose from. Passing it is what lets the
## depth be clamped; passing 0 says "do not clamp", which is right for a check against
## one specific nomination rather than against a ballot being filled.
func on_cooldown(
	id: StringName,
	pool_size: int = 0,
	now_sec: float = -1.0,
	choice: DotVoteChoice = null
) -> bool:
	if rules == null:
		return false

	if rules.cooldown_mode == DotVoteRules.Cooldown.MINUTES:
		if rules.cooldown_minutes <= 0.0:
			return false

		if not last_played_at.has(id):
			return false

		var now := now_sec if now_sec >= 0.0 else Time.get_unix_time_from_system()
		var elapsed := now - float(last_played_at[id])

		return elapsed < rules.cooldown_minutes * 60.0

	var depth := rules.cooldown

	if choice != null:
		depth = choice.cooldown_for(rules.cooldown)

	if depth <= 0:
		return false

	# Never exclude more than the configured share of the pool. A cooldown of eight on
	# a rotation of six otherwise excludes everything, and the honest answer is to
	# remember less rather than to offer nothing.
	if pool_size > 0:
		depth = mini(depth, maxi(int(floor(float(pool_size) * rules.cooldown_max_fraction)), 0))

	var index := played.find(id)

	return index >= 0 and index < depth


## Seconds until this comes off cooldown, or 0. Only meaningful in MINUTES mode.
func cooldown_remaining(id: StringName, now_sec: float = -1.0) -> float:
	if rules == null or rules.cooldown_mode != DotVoteRules.Cooldown.MINUTES:
		return 0.0

	if not last_played_at.has(id):
		return 0.0

	var now := now_sec if now_sec >= 0.0 else Time.get_unix_time_from_system()
	var elapsed := now - float(last_played_at[id])

	return maxf(rules.cooldown_minutes * 60.0 - elapsed, 0.0)


func clear() -> void:
	played.clear()
	last_played_at.clear()
	play_counts.clear()


func to_dictionary() -> Dictionary:
	var recent := PackedStringArray()

	for id in played:
		recent.append(String(id))

	return {
		"played": recent,
		# Duplicated for the family's aliasing reason: a Dictionary is a reference, and
		# a caller that saves this and then writes into it would be writing into the
		# history itself.
		"last_played_at": last_played_at.duplicate(true),
		"play_counts": play_counts.duplicate(true),
	}


func from_dictionary(data: Dictionary) -> void:
	clear()

	var recent: Variant = data.get("played", [])

	if recent is Array or recent is PackedStringArray:
		for entry: Variant in recent:
			played.append(StringName(str(entry)))

	var times: Variant = data.get("last_played_at", {})

	if times is Dictionary:
		for key: Variant in (times as Dictionary):
			last_played_at[StringName(str(key))] = float((times as Dictionary)[key])

	var counts: Variant = data.get("play_counts", {})

	if counts is Dictionary:
		for key: Variant in (counts as Dictionary):
			play_counts[StringName(str(key))] = int((counts as Dictionary)[key])


func describe() -> Dictionary:
	return {
		"played": played.size(),
		"last": String(played[0]) if not played.is_empty() else "-",
		"distinct": play_counts.size(),
	}
