class_name DotVoteSource
extends RefCounted

## Where the choices come from, and what "play this one" means.
## The one seam that makes the addon general: everything above works in ids, and only a source knows an id is a game, a map or a database row. Subclass it, or hand [DotVoteListSource] a [Callable].
## [method apply] may be a coroutine; [DotVoteDirector] awaits the result either way.

## A short name for logs and console output.
func source_name() -> String:
	return "source"


## Everything that could be offered, in the source's own order.
## Called on every ballot fill, not cached, so a game added at runtime is offered.
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


## Re-reads whatever this source caches, for an admin's "reload the list".
## Most sources cache nothing, so the default does nothing; a source that reads a file overrides it.
func reload() -> DotResult:
	return DotResult.success(0)


## Called by [DotVoteDirector] when a choice begins and before a ballot is filled; nothing by default.
## [DotVoteListSource] re-reads its [member DotVoteListSource.entries_fn] here.
func before_ballot() -> void:
	pass


## Whether this source can act on a result at all.
## A source that only lists is legitimate (a client-side mirror of a server's vote); [signal DotVoteDirector.change_due] is emitted either way.
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
