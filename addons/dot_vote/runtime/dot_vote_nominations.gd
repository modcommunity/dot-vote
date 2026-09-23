class_name DotVoteNominations
extends RefCounted

## What players have asked to be on the next ballot.
##
## Held separately from the ballot because they outlive it: nominations accumulate for
## the whole of a map and are consumed the moment a vote opens. Keeping them on the
## ballot object would mean losing every one of them each time a vote failed for want
## of a quorum.
##
## [b]Order is preserved and is load-bearing.[/b] It is what fills the reserved places
## in order, and it is the tie-break a player watching can predict: the first thing
## nominated wins a tie, which everybody can see coming.

const CHANNEL := "vote.nominations"

## Why a nomination came off the list. What [signal removed] carries.
const REASON_WITHDRAWN := &"withdrawn"
const REASON_REPLACED := &"replaced"
const REASON_LEFT := &"voter_left"
const REASON_BALLOT := &"ballot"
const REASON_CLEARED := &"cleared"
const REASON_ADMIN := &"admin"

## A nomination came off the list, and why.
##
## [b]Every path that removes one emits it[/b] — withdrawn, replaced by the same
## player's next, taken onto a ballot, cleared by a new map, removed by an admin. A menu
## that greys out what is already nominated needs to hear about all of them, and one
## that heard about only some would keep an entry greyed out for the rest of the map.
signal removed(voter: StringName, id: StringName, reason: StringName)

## One nomination: [code]{id, voter, admin}[/code], in the order they arrived.
var entries: Array[Dictionary] = []

var rules: DotVoteRules = null


static func of(p_rules: DotVoteRules) -> DotVoteNominations:
	var nominations := DotVoteNominations.new()
	nominations.rules = p_rules
	return nominations


## Records a nomination.
##
## Caps and duplicates only — whether the thing is currently running, or on cooldown,
## or exists at all, is decided by [DotVoteDirector], which is the only object that
## knows. Splitting it this way keeps this class testable with no source at all.
##
## [param forced] is an admin putting something on the next ballot outright: it ignores
## every cap and the off switch, and [method forced_ids] keeps it out of the places
## reserved for players, so forcing one map on does not cost the players a nomination.
func add(
	voter: StringName,
	id: StringName,
	is_admin: bool = false,
	forced: bool = false
) -> DotResult:
	if rules == null:
		return DotResult.fail(DotError.CODE_STATE, "No rules.")

	if forced:
		if not forced_ids().has(id):
			entries.append({"id": id, "voter": voter, "admin": true, "forced": true})
		return DotResult.success(id)

	if not rules.nominations_enabled:
		return DotResult.fail(
			DotError.CODE_UNSUPPORTED, "Nominations are turned off on this server."
		)

	var bypass := is_admin and rules.admin_nominations_bypass

	if by_voter(voter).has(id):
		# The same player, the same thing, twice. Not support — somebody pressing a key
		# again because nothing visible happened.
		return DotResult.fail(
			DotError.CODE_STATE, "You have already nominated %s." % id
		)

	if has_id(id) and not rules.nomination_seconding:
		return DotResult.fail(
			DotError.CODE_STATE, "%s is already nominated." % id
		)

	if not bypass:
		if rules.nominations_max > 0 and entries.size() >= rules.nominations_max:
			return DotResult.fail(
				DotError.CODE_STATE,
				"The nomination list is full (%d)." % rules.nominations_max
			)

		var mine := by_voter(voter)

		if mine.size() >= rules.nominations_per_player:
			# Replaced rather than refused when they are allowed exactly one, because
			# "you already nominated something" is not what a player who has changed
			# their mind wants to hear, and withdrawing first is a command nobody knows.
			if rules.nominations_per_player == 1:
				remove(voter, mine[0], REASON_REPLACED)
			else:
				return DotResult.fail(
					DotError.CODE_STATE,
					"You may only nominate %d at a time." % rules.nominations_per_player,
					"withdraw one first"
				)

	entries.append({"id": id, "voter": voter, "admin": is_admin})

	DotLog.debug(CHANNEL, "nominated", {
		"id": String(id), "by": String(voter), "total": entries.size()
	})

	return DotResult.success(id)


func remove(
	voter: StringName,
	id: StringName,
	reason: StringName = REASON_WITHDRAWN
) -> bool:
	for i in range(entries.size()):
		if entries[i]["id"] == id and entries[i]["voter"] == voter:
			entries.remove_at(i)
			removed.emit(voter, id, reason)
			return true

	return false


## Drops every nomination of [param id], whoever made it. For an admin. Returns how many.
func remove_id(id: StringName, reason: StringName = REASON_ADMIN) -> int:
	var count := 0

	for i in range(entries.size() - 1, -1, -1):
		if entries[i]["id"] == id:
			var voter: StringName = entries[i]["voter"]
			entries.remove_at(i)
			removed.emit(voter, id, reason)
			count += 1

	return count


## Drops everything one player nominated. For a player who disconnects.
##
## Whether a host calls this is a real choice and this addon does not make it: a
## nomination is a request for the server, not for the person, and a player who
## nominated a map and then crashed usually still wants it played. [DotVoteDirector]
## leaves nominations alone on disconnect and withdraws rock-the-votes, which is the
## asymmetry the two mechanisms actually have.
func remove_voter(voter: StringName, reason: StringName = REASON_LEFT) -> int:
	var count := 0

	for i in range(entries.size() - 1, -1, -1):
		if entries[i]["voter"] == voter:
			var id: StringName = entries[i]["id"]
			entries.remove_at(i)
			removed.emit(voter, id, reason)
			count += 1

	return count


func has_id(id: StringName) -> bool:
	for entry in entries:
		if entry["id"] == id:
			return true

	return false


func by_voter(voter: StringName) -> Array[StringName]:
	var out: Array[StringName] = []

	for entry in entries:
		if entry["voter"] == voter and not bool(entry.get("forced", false)):
			out.append(entry["id"])

	return out


## Ids an admin forced onto the next ballot, in the order they were forced.
func forced_ids() -> Array[StringName]:
	var out: Array[StringName] = []

	for entry in entries:
		if bool(entry.get("forced", false)) and not out.has(entry["id"]):
			out.append(entry["id"])

	return out


## Nominated ids in nomination order, each once. Forced ones are not here; see
## [method forced_ids].
func ordered_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var seen := {}

	for entry in entries:
		var id: StringName = entry["id"]

		if seen.has(id) or bool(entry.get("forced", false)):
			continue

		seen[id] = true
		out.append(id)

	return out


## id -> how many people nominated it, for [constant DotVoteRules.Fill.MOST_NOMINATED].
##
## Meaningful only because seconding is allowed — see
## [member DotVoteRules.nomination_seconding].
func counts() -> Dictionary:
	var out := {}

	for entry in entries:
		var id: StringName = entry["id"]
		out[id] = int(out.get(id, 0)) + 1

	return out


## Where this first appeared, or a large number when it was never nominated.
##
## The large number rather than -1 is what makes it usable directly as a sort key:
## anything nominated sorts ahead of anything that was not, with no branch.
func first_index(id: StringName) -> int:
	var ordered := ordered_ids()
	var index := ordered.find(id)

	return index if index >= 0 else 0x7FFFFFFF


func size() -> int:
	return entries.size()


## Empties the list, reporting each entry. Oldest first, which is the order they arrived.
func clear(reason: StringName = REASON_CLEARED) -> void:
	var gone := entries.duplicate()
	entries.clear()

	for entry in gone:
		removed.emit(entry["voter"], entry["id"], reason)


## Every nomination as [code]{id, voter, admin}[/code], in order. A copy.
func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	for entry in entries:
		out.append(entry.duplicate())

	return out


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	if entries.is_empty():
		out.append("nothing nominated")
		return out

	var tally := counts()

	for id in ordered_ids():
		out.append("%-24s %d nomination%s" % [
			String(id), int(tally[id]), "" if int(tally[id]) == 1 else "s"
		])

	return out
