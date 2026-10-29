class_name DotVoteResult
extends RefCounted

## What a ballot decided, and how; returned by [method DotVoteBallot.resolve], never null.
## The "how" lets the announcement say why ("Arena wins (tie, nominated first)"), the difference between a rule and a coin flip to anyone watching.

## What the ballot came to.
enum Outcome {
	## [member winner_id] won.
	WINNER,
	## The current choice was extended.
	EXTEND,
	## The players chose to stay as they are, without extending.
	KEEP,
	## No winner yet: [member runoff_ids] go to another ballot.
	RUNOFF,
	## Too few people voted. [member winner_id] is the leader, if there was one.
	NO_QUORUM,
	## Nothing was on the ballot, or nobody voted at all.
	EMPTY,
}

var outcome: Outcome = Outcome.EMPTY

## The winning id, or [code]&""[/code].
var winner_id: StringName = &""

## The winning choice, when the ballot held one. Null for extend, keep and empty.
var winner: DotVoteChoice = null

## Final counts, by id. Includes zero-vote options, so a tally renders in full.
var counts: Dictionary = {}

## Per-round counts under [constant DotVoteRules.Method.INSTANT_RUNOFF], first round
## first. Empty for every other method.
var rounds: Array = []

## Ids that go to a runoff, under [constant Outcome.RUNOFF].
var runoff_ids: Array[StringName] = []

## Ballots cast, and how many people could have cast one.
##
## [member votes_cast] includes abstentions: an abstainer was asked and answered.
var votes_cast: int = 0
var eligible: int = 0

## Ballots cast as "no vote". Counted toward nothing; see
## [member DotVoteRules.include_abstain].
var abstained: int = 0

## Whether the ballot was decided by a tie-break, and by which one; empty when nothing was tied.
var tie_break: String = ""

## The ids that were tied, when one was.
var tied_ids: Array[StringName] = []

## A sentence for the players. Always set.
var summary: String = ""


static func empty(why: String = "Nothing was on the ballot.") -> DotVoteResult:
	var result := DotVoteResult.new()
	result.outcome = Outcome.EMPTY
	result.summary = why
	return result


func turnout() -> float:
	if eligible <= 0:
		return 0.0
	return float(votes_cast) / float(eligible)


## Whether anything actually changes as a result of this.
## Extend, keep, no-quorum-with-KEEP and empty all mean "carry on"; branching on [member winner_id] would unload the running game.
func changes_choice() -> bool:
	return outcome == Outcome.WINNER and winner_id != &""


## The counts as an ordered list of [code][id, votes][/code], most first, for a HUD or chat line.
## Ties keep ballot order so two renderings never disagree.
func ordered() -> Array:
	var order := {}
	var i := 0

	for id: Variant in counts:
		order[id] = i
		i += 1

	var out := []

	for id: Variant in counts:
		out.append([id, int(counts[id])])

	out.sort_custom(func(a: Array, b: Array) -> bool:
		if int(a[1]) != int(b[1]):
			return int(a[1]) > int(b[1])
		return int(order.get(a[0], 0)) < int(order.get(b[0], 0))
	)

	return out


func describe() -> Dictionary:
	return {
		"outcome": Outcome.keys()[outcome],
		"winner": String(winner_id) if winner_id != &"" else "-",
		"votes": "%d of %d" % [votes_cast, eligible],
		"abstained": abstained,
		"turnout": "%.0f%%" % (turnout() * 100.0),
		"tie_break": tie_break if tie_break != "" else "-",
		"counts": counts,
	}


func _to_string() -> String:
	return "DotVoteResult(%s, %s)" % [Outcome.keys()[outcome], summary]
