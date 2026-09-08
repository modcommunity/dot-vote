@tool
extends EditorPlugin

## Editor entry point for dot-vote. Registers inspector types only.
##
## No autoloads. A vote director is a tempting singleton and it is the wrong shape for
## the family's usual reason: a test that runs a server and a client in one process
## needs two of them — one deciding and one mirroring — and a server that votes over
## its games AND over its maps needs two as well, which is exactly the arrangement this
## addon was built to allow.

const _ICON := "res://addons/dot_vote/icon_placeholder.svg"

const _TYPES := [
	[
		"DotVoteDirector",
		"Node",
		"res://addons/dot_vote/runtime/dot_vote_director.gd",
	],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
