class_name DotVoteBallotFeed
extends RefCounted

## Sends a [DotVoteBallotView] whenever the ballot it describes changes, and nothing
## otherwise.
##
## [codeblock]
## feed = DotVoteBallotFeed.of(director, func(state: Dictionary) -> void:
##     server.broadcast_notice(DotNotice.make(&"", "", -1.0, &"map_ballot", state)))
## feed.title = "Vote for the next map"
## feed.command = "votefor"
## # every tick, after director.advance
## feed.poll()
## [/codeblock]
##
## [b]Polled rather than driven by the director's signals[/b], for the reason dot-server-
## deploy's HUD line is: not everything that changes a ballot emits. A voter who leaves is
## withdrawn by [method DotVoteDirector.forget_voter] without a signal, and a feed that only
## listened to [signal DotVoteDirector.vote_cast] would keep their avatar on the board until
## somebody else voted. One snapshot a tick is a few options and a few dozen voters, compared
## by hash; it is sent only when it differs.
##
## [b]The one signal it does take is [signal DotVoteDirector.vote_closed][/b], because the
## result — what won — is gone from the director by the next poll.
##
## Several feeds can run in one process — the game vote and a game's map vote — and each
## carries its own [member title] and [member command], which is what lets a client draw two
## ballots at once and send each choice to the vote it belongs to.

## What [method poll] sends: one [Dictionary], a [DotVoteBallotView] state with
## [member title] and [member command] added.
var send_fn: Callable = Callable()

## Who a voter is, for the avatars. See [method DotVoteBallotView.state_of].
var people_fn: Callable = Callable()

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
	return _decorate(DotVoteBallotView.state_of(director, people_fn))


## Forgets what was sent, so the next [method poll] sends again. For a host whose clients
## were all replaced — a game change rebuilt their screens.
func reset() -> void:
	_last = {}
	_closed = {}


func _decorate(state: Dictionary) -> Dictionary:
	state["title"] = title
	state["command"] = command
	return state


func _on_closed(result: DotVoteResult) -> void:
	_closed = DotVoteBallotView.closed_state(director, result)
