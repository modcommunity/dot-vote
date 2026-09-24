class_name DotVoteClockView
extends RefCounted

## The time left on a vote's clock, as somebody who is not running it sees it.
##
## [b]A client does not have the clock; it has the last thing it was told about it.[/b]
## The games that put a map's time left on their HUD drew it from their own map session,
## which on a client is a clock started when the client loaded the map and advanced by
## nothing the server decides — so an extend never reached it, a `trigger: rtv_only`
## server showed a limit it did not have, and the number was only ever right by
## coincidence. The vote owns
## the clock that ends a map, so the vote is what a HUD has to be told about.
##
## [b]One class for both ends, and that is what keeps them in step.[/b] A server keeps one
## of these as its record of what clients believe, and asks [method is_stale] each tick:
## the clock was extended, restarted, stopped for a ballot, or has simply drifted. Only then
## does it send [method state_of] again. A client [method adopt]s the same dictionary and
## counts it down itself between messages. Both ends extrapolate with this file's
## arithmetic, so the server's idea of what a client shows cannot differ from what the
## client shows.
##
## [codeblock]
## # server, once a tick
## if view.is_stale(director, now):
##     view.adopt(DotVoteClockView.state_of(director), now)
##     send_to_everyone(view.to_state())
## # client, when a message arrives, and every frame
## view.adopt(state, Time.get_ticks_msec() / 1000.0)
## label.text = view.formatted_at(Time.get_ticks_msec() / 1000.0)
## [/codeblock]
##
## [b]Times are seconds on the caller's own clock.[/b] A server passes simulated time and a
## client passes wall time; neither is ever compared with the other, only with itself.
##
## A pure value object: it returns what it knows and logs nothing.

## Seconds of disagreement before a server resends. Above one second, because the state is
## whole seconds and a client that rounds the other way is a second out and not wrong.
const STALE_TOLERANCE_SEC := 1.5

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
##
## [param director] is duck-typed in the sense that null is allowed: a server with no vote
## has no clock to show, and says so.
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
##
## Every field is defaulted: this is what a wire message is decoded into, and a message
## missing a field should show a plainer clock rather than raise.
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


## Whether what this view shows at [param now] is no longer what [param director]'s clock
## says: never told, a clock that appeared or went, one that stopped or started, or a
## count more than [constant STALE_TOLERANCE_SEC] out — which is what an extend, a new
## map and a ballot that kept the map all look like from here.
func is_stale(director: DotVoteDirector, now: float) -> bool:
	if not known:
		return true

	var truth := state_of(director)

	if bool(truth["has_clock"]) != has_clock or bool(truth["running"]) != running:
		return true

	if not has_clock:
		return false

	return absf(float(truth["seconds_left"]) - remaining_at(now)) > STALE_TOLERANCE_SEC


func describe() -> Dictionary:
	return {
		"known": known,
		"has_clock": has_clock,
		"seconds_left": seconds_left,
		"running": running,
	}
