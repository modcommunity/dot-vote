extends SceneTree

## Layers [DotVoteRules] the way a game does and runs one real [DotVoteDirector] on them,
## then prints what its ballot did as one JSON line.
##
## [b]A child process, because one of the layers is the command line.[/b]
## [method DotConfig.apply_cli] reads the process's own arguments and nothing in a running
## suite can hand it new ones, so `vote_selftest`'s "every layer reaches a running ballot"
## starts this once per layer and reads the line back. Every other layer is run the same way
## so the four are measured by one path.
##
## [codeblock]
## godot --headless --path . --script res://examples/layer_probe.gd -- \
##     [--probe-file=<path>] [--probe-meta-<key>=<value> ...] [--vote-<key>=<value> ...]
## [/codeblock]
##
## The overlay is what a game passes from its game.yml `metadata: map_vote:`; the file is
## `user://cfg/<game>_vote.json`'s place; `DOT_VOTE_*` is read from the environment it is
## started with. Everything the ballot needs to be driven by hand is set AFTER layering and
## is none of the three settings under test.

# No `CHANNEL`: a probe that prints one line for a suite to read.


func _initialize() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	var file := ""
	var overlay := {}

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-file="):
			file = arg.trim_prefix("--probe-file=")
		elif arg.begins_with("--probe-meta-") and arg.contains("="):
			# One key per argument, and no JSON object: [method OS.execute] strips the
			# double quotes out of an argument, so `{"end_vote":false}` arrived here as
			# `{end_vote:false}` and parsed to nothing. A bare JSON VALUE survives.
			var pair := arg.trim_prefix("--probe-meta-").split("=", true, 1)
			var value: Variant = JSON.parse_string(pair[1])
			overlay[pair[0]] = value if value != null else pair[1]

	var rules := DotVoteRules.new()
	var layered := rules.layer_over_defaults(file, overlay)

	rules.apply_delay_sec = 0.0
	rules.trigger = DotVoteRules.Trigger.TIME_LIMIT
	rules.duration_sec = 100.0
	rules.vote_lead_sec = 20.0
	rules.cooldown = 0
	rules.apply = DotVoteRules.Apply.IMMEDIATE

	var choices: Array[DotVoteChoice] = []
	for id in ["a", "b", "c"]:
		choices.append(DotVoteChoice.of(StringName(id), id.capitalize()))

	var source := DotVoteListSource.of(choices)
	var director := DotVoteDirector.new()
	director.rules = rules
	director.source = source
	director.register_service = false
	director.self_advance = false
	director.player_count_fn = func() -> int: return 4
	root.add_child(director)
	await process_frame

	director.begin(&"a")
	source.current = &"a"

	for _i in range(90):
		director.advance(1.0)

	var opened := director.is_voting()
	var offered := opened and director.ballot != null and director.ballot.has_extend()
	var extended_by := -1.0

	if offered:
		var before := director.clock.remaining
		for voter in [&"v1", &"v2", &"v3", &"v4"]:
			var _cast := director.cast_one(voter, DotVoteBallot.EXTEND)
		var _result := director.close_vote()
		extended_by = director.clock.remaining - before

	print(JSON.stringify({
		"layered": layered.ok,
		"overlay": overlay,
		"end_vote": rules.end_vote,
		"include_extend": rules.include_extend,
		"extend_seconds": rules.extend_seconds,
		"opened": opened,
		"extend_offered": offered,
		"extended_by": snappedf(extended_by, 0.01),
	}))
	quit(0)
