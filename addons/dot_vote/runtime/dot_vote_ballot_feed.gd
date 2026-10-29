class_name DotVoteBallotFeed
extends RefCounted

## Sends a [DotVoteBallotView] whenever the ballot it describes changes, and nothing otherwise; call [method poll] every tick after director.advance.
## Polled, not signal-driven: a voter who leaves is withdrawn by [method DotVoteDirector.forget_voter] without a signal. It does take [signal DotVoteDirector.vote_closed], since the result is gone by the next poll.
## Several feeds can run at once, each with its own [member title] and [member command], so a client can draw two ballots and answer each.

## What [method poll] sends: one [Dictionary], a [DotVoteBallotView] state with
## [member title] and [member command] added.
var send_fn: Callable = Callable()

## Who a voter is, for the avatars. See [method DotVoteBallotView.state_of].
## Also handed to [member DotVoteDirector.people_fn] when the director has none, so chat names the same player the ballot draws.
var people_fn: Callable = Callable():
	set(value):
		people_fn = value

		if director != null and not director.people_fn.is_valid():
			director.people_fn = value

## The heading a client draws over the ballot.
var title: String = "Vote"

## The console command a choice is typed as, without its prefix character. A client sends
## [code]!<command> <n>[/code], which is exactly what a player typing it sends.
var command: String = "votefor"

var director: DotVoteDirector = null

## The last state sent, so an unchanged ballot sends nothing. Empty: nothing sent yet.
var _last: Dictionary = {}

## A closed state waiting for the next [method poll], from [signal DotVoteDirector.vote_closed].
var _closed: Dictionary = {}


static func of(p_director: DotVoteDirector, p_send_fn: Callable) -> DotVoteBallotFeed:
	var feed := DotVoteBallotFeed.new()
	feed.director = p_director
	feed.send_fn = p_send_fn

	if p_director != null:
		p_director.vote_closed.connect(feed._on_closed)

	return feed


## Sends the ballot if it changed since the last send. Call once a tick.
func poll() -> void:
	if director == null or not send_fn.is_valid():
		return

	var state := current()
	var open := bool(state.get("open", false))

	if not _closed.is_empty():
		# A runoff closes one ballot and opens the next inside one tick; the closed state
		# would then be sent over a ballot that is already open again. Only a ballot that
		# is really gone says what won.
		if not open:
			state = _decorate(_closed.duplicate())
		_closed = {}
	elif not open and not bool(_last.get("open", false)):
		# Nothing open, and a client either never saw a ballot or has already been told
		# this one closed. A second "closed" would differ only in having no winner, and
		# would replace the result a client is still showing with nothing.
		return

	if not _last.is_empty() and DotVoteBallotView.same_ballot(state, _last):
		return

	_last = state
	send_fn.call(state)


## What a player who joins now should be shown: the open ballot, or an empty dictionary when
## there is none. For a host that sends to one player as they arrive.
func snapshot() -> Dictionary:
	var state := current()
	return state if bool(state.get("open", false)) else {}


func current() -> Dictionary:
	var people := people_fn

	if not people.is_valid() and director != null:
		people = director.people_fn

	return _decorate(DotVoteBallotView.state_of(director, people))


## Forgets what was sent, so the next [method poll] sends again. For a host whose clients
## were all replaced — a game change rebuilt their screens.
func reset() -> void:
	_last = {}
	_closed = {}


## What an operator asks of a feed that seems to send nothing: whether it can send at all,
## and what it last sent.
func describe() -> Dictionary:
	return {
		"title": title,
		"command": command,
		"director": director != null,
		"can_send": send_fn.is_valid(),
		"sent_open": bool(_last.get("open", false)),
		"sent_anything": not _last.is_empty(),
		"closed_waiting": not _closed.is_empty(),
	}


func _decorate(state: Dictionary) -> Dictionary:
	state["title"] = title
	state["command"] = command
	return state


func _on_closed(result: DotVoteResult) -> void:
	_closed = DotVoteBallotView.closed_state(director, result)
