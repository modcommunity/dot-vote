class_name DotVoteClockView
extends RefCounted

## The time left on a vote's clock, as somebody who is not running it sees it.
## A client has only the last thing it was told: a server keeps one as its record of what clients believe and asks [method is_stale] each tick, a client [method adopt]s [method state_of] and counts down itself, both with this file's arithmetic.
## Times are seconds on the caller's own clock, never compared across ends. A pure value object; logs nothing.

## Seconds of disagreement before a server resends. Above one second, because the state is
## whole seconds and a client that rounds the other way is a second out and not wrong.
const STALE_TOLERANCE_SEC := 1.5

## Seconds after which a running clock is sent again even though it agrees.
## The ends count on different clocks and [method is_stale] compares the server only with itself, so this one small message bounds client drift.
const RESYNC_SEC := 30.0

## Whether anything has been adopted. False is "never told", which a HUD answers
## differently from "told there is no clock".
var known: bool = false

## Whether there is a clock that ends anything. False on a server with no time limit, a
## vote that is off, or `trigger: manual` — whose host ends things itself, so a count
## reaching zero would be a promise nobody keeps.
var has_clock: bool = false

## Seconds left when [member _at] was the time.
var seconds_left: float = 0.0

## Whether it is counting. A clock stopped under a rock-the-vote ballot holds still.
var running: bool = false

var _at: float = 0.0


## What a client should show, taken from the director that owns the clock.
## [param director] may be null: a server with no vote has no clock to show.
static func state_of(director: DotVoteDirector) -> Dictionary:
	if director == null or director.clock == null or director.rules == null:
		return {"has_clock": false, "seconds_left": 0, "running": false}

	var clock := director.clock
	var shown := (
		director.rules.enabled
		and director.rules.trigger != DotVoteRules.Trigger.MANUAL
		and clock.duration > 0.0
	)

	return {
		"has_clock": shown,
		# Up, so a clock with half a second left says 0:01 rather than 0:00 while it is
		# still running — the moment it says zero is the moment it has run out.
		"seconds_left": int(ceil(maxf(clock.remaining, 0.0))) if shown else 0,
		"running": shown and clock.running and not clock.is_expired(),
	}


## Takes a state from [method state_of], as seen at [param now].
## Every field is defaulted, since a wire message missing one should show a plainer clock, not raise.
func adopt(state: Dictionary, now: float) -> void:
	known = true
	has_clock = bool(state.get("has_clock", false))
	seconds_left = maxf(float(state.get("seconds_left", 0)), 0.0) if has_clock else 0.0
	running = has_clock and bool(state.get("running", false))
	_at = now


## The state this view holds, in [method state_of]'s shape.
func to_state() -> Dictionary:
	return {
		"has_clock": has_clock,
		"seconds_left": int(ceil(seconds_left)),
		"running": running,
	}


## Seconds left at [param now], counted down from the last adoption. 0 with no clock.
func remaining_at(now: float) -> float:
	if not has_clock:
		return 0.0

	if not running:
		return seconds_left

	return maxf(seconds_left - maxf(now - _at, 0.0), 0.0)


## [code]m:ss[/code] at [param now], or empty when there is no clock — and empty is the
## point: a HUD that printed "no limit" beside every other number would be a HUD spending
## its space on something that is not happening.
func formatted_at(now: float) -> String:
	if not has_clock:
		return ""

	var total := int(ceil(remaining_at(now)))
	return "%d:%02d" % [total / 60, total % 60]


## Whether what this view shows at [param now] no longer matches [param director]'s clock.
## Covers: never told, a clock that appeared or went, one that stopped or started, or a count more than [constant STALE_TOLERANCE_SEC] out (extend, new map, kept map).
func is_stale(director: DotVoteDirector, now: float) -> bool:
	if not known:
		return true

	var truth := state_of(director)

	if bool(truth["has_clock"]) != has_clock or bool(truth["running"]) != running:
		return true

	if not has_clock:
		return false

	if running and now - _at >= RESYNC_SEC:
		return true

	return absf(float(truth["seconds_left"]) - remaining_at(now)) > STALE_TOLERANCE_SEC


func describe() -> Dictionary:
	return {
		"known": known,
		"has_clock": has_clock,
		"seconds_left": seconds_left,
		"running": running,
	}
