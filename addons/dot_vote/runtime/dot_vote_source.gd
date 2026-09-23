class_name DotVoteSource
extends RefCounted

## Where the choices come from, and what "play this one" means.
##
## [b]The one seam that makes this addon general.[/b] Everything above it — the
## ballot, the clock, the nominations, the cooldown — works in ids. A source is the
## only thing that knows an id is a dot-server game, a dot-map map, a mode, or a row
## in somebody's database, and it is the only file that has to be written to point
## this at something new.
##
## Subclass it, or use [DotVoteListSource] and hand it a [Callable].
##
## [b]On [method apply] being awaited.[/b] Changing a game is a coroutine — it
## announces content, waits for every client to fetch it, then swaps — and changing a
## row in a list is not. [DotVoteDirector] awaits the result either way, which GDScript
## allows, so a source is free to be whichever it is.

## A short name for logs and console output.
func source_name() -> String:
	return "source"


## Everything that could be offered, in the source's own order.
##
## Called every time a ballot is filled rather than cached, because a server that adds
## a game at runtime — every module that does — would otherwise never offer it.
func choices() -> Array[DotVoteChoice]:
	return []


## What is running now, or [code]&""[/code].
func current_id() -> StringName:
	return &""


func find(id: StringName) -> DotVoteChoice:
	for choice in choices():
		if choice.id == id:
			return choice

	return null


func has(id: StringName) -> bool:
	return find(id) != null


func ids() -> Array[StringName]:
	var out: Array[StringName] = []

	for choice in choices():
		out.append(choice.id)

	return out


## Re-reads whatever this source caches. What an admin's "reload the list" asks for.
##
## [b]Most sources cache nothing[/b] — [method choices] is called fresh every time a
## ballot is filled, so a catalogue edited at runtime is already current — and the
## default says so rather than pretending to have done something. A source that reads a
## file overrides it.
func reload() -> DotResult:
	return DotResult.success(0)


## Whether this source can act on a result at all.
##
## [b]A source that only lists is legitimate[/b] and is what a client-side mirror of a
## server's vote is: it shows the ballot, it counts nothing, and the change arrives
## from the server. [DotVoteDirector] emits [signal DotVoteDirector.change_due] either
## way, so a host can always do it itself.
func supports_apply() -> bool:
	return false


## Switches to [param id]. May be a coroutine.
func apply(id: StringName) -> DotResult:
	return DotResult.fail(
		DotError.CODE_UNSUPPORTED,
		"%s cannot change what is running." % source_name(),
		"connect to DotVoteDirector.change_due and do it in the host"
	)


func describe() -> Dictionary:
	return {
		"source": source_name(),
		"choices": choices().size(),
		"current": String(current_id()) if current_id() != &"" else "-",
		"can_apply": supports_apply(),
	}
