class_name DotVoteListSource
extends DotVoteSource

## A source built from an explicit list, optionally loaded from JSON.
##
## What a game uses when the things being voted for are the game's own business rather
## than dot-server's or dot-map's: modes, mutators, difficulties, team sizes. Also what
## every test in this addon uses, which is the more important reason it exists — a
## suite that can only run against a real [DotGameManager] is a suite that mostly does
## not run.
##
## [codeblock]
## var source := DotVoteListSource.new()
## source.add(DotVoteChoice.of(&"classic", "Classic"))
## source.add(DotVoteChoice.of(&"frenzy", "Frenzy"))
## source.apply_fn = func(id: StringName) -> DotResult:
##     return game.set_mode(id)
## [/codeblock]

const CHANNEL := "vote.list"

## The choices, in ballot order.
var entries: Array[DotVoteChoice] = []

## What is running now. Set it yourself, or let [method apply] set it.
var current: StringName = &""

## What "play this" does. Takes a [StringName], returns a [DotResult]. May be a
## coroutine.
##
## Unset means this source only lists, and [DotVoteDirector] will emit
## [signal DotVoteDirector.change_due] for the host to act on.
var apply_fn: Callable = Callable()

## A name for logs.
var label: String = "list"


static func of(choices: Array[DotVoteChoice]) -> DotVoteListSource:
	var source := DotVoteListSource.new()
	source.entries = choices.duplicate()
	return source


## Builds one from ids alone, for a server whose choices need no configuration.
static func of_ids(ids: Array) -> DotVoteListSource:
	var source := DotVoteListSource.new()

	for id: Variant in ids:
		source.entries.append(DotVoteChoice.of(StringName(str(id))))

	return source


func source_name() -> String:
	return label


func choices() -> Array[DotVoteChoice]:
	return entries


func current_id() -> StringName:
	return current


func add(choice: DotVoteChoice) -> DotResult:
	if choice == null or choice.id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "A choice needs an id.")

	if has(choice.id):
		return DotResult.fail(
			DotError.CODE_STATE, "'%s' is already in the list." % choice.id
		)

	entries.append(choice)

	return DotResult.success(choice)


func remove(id: StringName) -> bool:
	for i in range(entries.size()):
		if entries[i].id == id:
			entries.remove_at(i)
			return true

	return false


func supports_apply() -> bool:
	return apply_fn.is_valid()


func apply(id: StringName) -> DotResult:
	if not has(id):
		return DotResult.fail(
			DotError.CODE_INVALID, "'%s' is not in the list." % id
		)

	if not apply_fn.is_valid():
		return super.apply(id)

	var result: Variant = await apply_fn.call(id)

	if result is DotResult and not (result as DotResult).ok:
		return result as DotResult

	current = id

	return DotResult.success(id)


## Reads a list of choices from a JSON file.
##
## The format is an array of the dictionaries [method DotVoteChoice.to_dictionary]
## produces, or an object with a [code]"choices"[/code] key holding one — so a file
## written by hand can carry a comment field beside the list without this refusing it.
func load_json(path: String) -> DotResult:
	if not FileAccess.file_exists(path):
		return DotResult.fail(
			DotError.CODE_IO, "No choice list at %s." % path
		)

	var text := FileAccess.get_file_as_string(path)

	if text == "":
		return DotResult.fail(
			DotError.CODE_IO,
			"Could not read %s." % path,
			error_string(FileAccess.get_open_error())
		)

	var parsed: Variant = JSON.parse_string(text)
	var list: Variant = parsed

	if parsed is Dictionary:
		list = (parsed as Dictionary).get("choices", [])

	if not (list is Array):
		return DotResult.fail(
			DotError.CODE_PARSE,
			"%s is not a list of choices." % path,
			"expected an array, or an object with a 'choices' array"
		)

	entries.clear()

	for entry: Variant in (list as Array):
		if entry is Dictionary:
			entries.append(DotVoteChoice.from_dictionary(entry as Dictionary))

	DotLog.info(CHANNEL, "choices loaded", {"path": path, "count": entries.size()})

	return DotResult.success(entries.size())


func to_json(pretty: bool = true) -> String:
	var list := []

	for choice in entries:
		list.append(choice.to_dictionary())

	return JSON.stringify({"choices": list}, "\t" if pretty else "")


func save_json(path: String) -> DotResult:
	var dir := path.get_base_dir()

	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		return DotResult.fail(
			DotError.CODE_IO,
			"Could not write %s." % path,
			error_string(FileAccess.get_open_error())
		)

	file.store_string(to_json())
	file.close()

	DotWeb.sync_filesystem()

	return DotResult.success(path)
