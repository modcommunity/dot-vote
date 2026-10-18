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

## The file [method load_json] last read, so [method reload] can read it again.
var loaded_from: String = ""

## [code]func() -> Array[/code]: the list as the host has it NOW, re-read into [member entries]
## when a choice begins and before every ballot (see [method before_ballot]). Each item is a
## [DotVoteChoice], an [code][id, name][/code] pair, or a bare id.
##
## [b]For a catalogue that grows after the director is built[/b] — maps or courses
## delivered after boot. Copied into [member entries] once, such a list held only what
## existed at setup, a list of one never opened a ballot, and every game had to remember
## to refresh it by hand after each delivery. Unset, [member entries] is the list, as it
## always was.
var entries_fn: Callable = Callable()

## The index [method follow_content] reads, or null.
var content_index: DotContentIndex = null

## The [code]map_kind[/code]s [method follow_content] accepts; "*" is every kind, empty none.
var content_kinds: PackedStringArray = PackedStringArray()


static func of(choices: Array[DotVoteChoice]) -> DotVoteListSource:
	# Not this class's own name. A script that names itself in an expression, loaded after
	# its base, cuts Godot 4.7.2's exit teardown short and leaks every script loaded before
	# it. See docs/gdscript-hazards.md, "A script that names itself".
	var source := new()
	source.entries = choices.duplicate()
	return source


## Builds one from ids alone, for a server whose choices need no configuration.
static func of_ids(ids: Array) -> DotVoteListSource:
	var source := new()

	for id: Variant in ids:
		source.entries.append(DotVoteChoice.of(StringName(str(id))))

	return source


func source_name() -> String:
	return label


func choices() -> Array[DotVoteChoice]:
	if content_index == null:
		return entries

	var out: Array[DotVoteChoice] = entries.duplicate()
	var seen := {}

	for choice in entries:
		seen[choice.id] = true

	# Read from the index on every call, never copied: the index filters by its CURRENT
	# session, so an online session shows no solo entry the moment it is set, with no
	# signal to miss. The game's own ids are in [member entries] and always win.
	for entry in content_index.entries(&"map"):
		var choice := _choice_from_entry(entry)

		if choice == null or seen.has(choice.id):
			continue

		seen[choice.id] = true
		out.append(choice)

	return out


## Merges the maps subscribed packs provide into this list, for the index's current session
## only. Opt-in: a source that never calls this offers exactly its own list. An empty
## [param accepted_kinds] accepts none and "*" every [code]map_kind[/code], the same as
## [code]DotMapCatalogue.follow_content[/code]. The index is dot-core's, so this adds no
## dependency on dot-map.
func follow_content(index: DotContentIndex, accepted_kinds: PackedStringArray = PackedStringArray()) -> void:
	content_index = index
	content_kinds = accepted_kinds


## Stops merging; the delivered choices leave the list at once.
func unfollow_content() -> void:
	content_index = null
	content_kinds = PackedStringArray()


func _choice_from_entry(entry: DotContentEntry) -> DotVoteChoice:
	var map_kind := str(entry.raw.get("map_kind", ""))

	if entry.id == "" or map_kind == "" \
			or not (content_kinds.has("*") or content_kinds.has(map_kind)):
		return null

	var choice := DotVoteChoice.of(StringName(entry.id), entry.name)
	choice.pack_title = entry.pack_title
	choice.group = StringName(map_kind)
	choice.min_players = int(entry.raw.get("min_players", 0))
	choice.max_players = int(entry.raw.get("max_players", 0))
	choice.meta = {"entry_key": entry.key, "content_id": entry.content_id}
	return choice


func current_id() -> StringName:
	return current


func add(choice: DotVoteChoice) -> DotResult:
	if choice == null or choice.id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "A choice needs an id.")

	if _owns(choice.id):
		return DotResult.fail(
			DotError.CODE_STATE, "'%s' is already in the list." % choice.id
		)

	entries.append(choice)

	return DotResult.success(choice)


func _owns(id: StringName) -> bool:
	for choice in entries:
		if choice.id == id:
			return true

	return false


func remove(id: StringName) -> bool:
	for i in range(entries.size()):
		if entries[i].id == id:
			entries.remove_at(i)
			return true

	return false


func before_ballot() -> void:
	if entries_fn.is_valid():
		var _read := refresh()


## Reads [member entries_fn] into [member entries]. Anything but an array keeps the list
## there was and says why; a list shorter than before is taken as it is, because a map
## an operator removed should leave the ballot.
func refresh() -> DotResult:
	if not entries_fn.is_valid():
		return DotResult.fail(DotError.CODE_STATE, "This list is not read from anywhere.")

	var listed: Variant = entries_fn.call()

	if not (listed is Array):
		DotLog.warn(CHANNEL, "the list function returned no list; keeping the old one", {
			"source": label, "kept": entries.size(),
		})
		return DotResult.fail(
			DotError.CODE_INVALID, "%s's list function did not return an array." % label
		)

	var read: Array[DotVoteChoice] = []
	var seen := {}

	for item: Variant in (listed as Array):
		var choice: DotVoteChoice = null

		if item is DotVoteChoice:
			choice = item as DotVoteChoice
		elif item is Array and not (item as Array).is_empty():
			var row: Array = item
			choice = DotVoteChoice.of(
				StringName(str(row[0])), str(row[1]) if row.size() > 1 else ""
			)
		elif item != null:
			choice = DotVoteChoice.of(StringName(str(item)))

		if choice == null or choice.id == &"" or seen.has(choice.id):
			continue

		seen[choice.id] = true
		read.append(choice)

	if read.size() != entries.size():
		DotLog.debug(CHANNEL, "the list changed size", {
			"source": label, "was": entries.size(), "now": read.size(),
		})

	entries = read

	return DotResult.success(entries.size())


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

	loaded_from = path

	DotLog.info(CHANNEL, "choices loaded", {"path": path, "count": entries.size()})

	return DotResult.success(entries.size())


## Reads the list again: [member entries_fn] when there is one, else the file
## [method load_json] last read. Nothing to do for a list that was built in code, and that
## is not an error.
func reload() -> DotResult:
	if entries_fn.is_valid():
		return refresh()

	if loaded_from == "":
		return DotResult.success(entries.size())

	return load_json(loaded_from)


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
