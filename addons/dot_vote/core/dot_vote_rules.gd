@tool
class_name DotVoteRules
extends "res://addons/dot_vote/core/dot_vote_rules_settings.gd"

## Every policy decision this addon makes, in one place: [DotVoteBallot], [DotVoteClock] and [DotVoteNominations] hold state, these fields say what they do.
## A [DotConfig], so it layers as everywhere: defaults < vote.json / vote.yml < server vote.yml < DOT_VOTE_* < --vote-*. Enums are written by name in files ([method apply_dictionary] translates).
## The defaults run a public server untouched: thirty minutes, rock the vote at 60% of two or more, six options with four kept for nominations, plurality.


func env_prefix() -> String:
	return "DOT_VOTE_"


func cli_prefix() -> String:
	return "--vote-"


## Enum settings, by property name, so a config file can name them in words.
## One table read by [method enum_names_for], the settings UI and [code]describe_lines[/code].
const ENUMS := {
	"trigger": Trigger,
	"fill": Fill,
	"method": Method,
	"tie_break": TieBreak,
	"on_no_quorum": NoQuorum,
	"apply": Apply,
	"cooldown_mode": Cooldown,
	"rtv_outcome": RtvOutcome,
	"rtv_apply": Apply,
	"rtv_after_decided": RtvAfterDecided,
	"on_no_votes": NoVotes,
	"empty_choice": EmptyChoice,
	"time_up": TimeUp,
	"ballot_input": BallotInput,
}


## Applies a layer, translating enum names to their values first.
## Integers still work, for configs written by a program.
func apply_dictionary(
	d: Dictionary,
	layer_name: String = "dict",
	allow_sensitive: bool = true
) -> PackedStringArray:
	return super.apply_dictionary(
		_translate_enums(d), layer_name, allow_sensitive
	)


func _translate_enums(d: Dictionary) -> Dictionary:
	var out := {}

	for raw_key: Variant in d:
		var value: Variant = d[raw_key]
		var key := _match_key(str(raw_key), config_keys())

		if key != "" and ENUMS.has(key) and (
			typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME
		):
			var text := str(value).strip_edges()

			# A numeric string is left alone for _coerce to read as the integer it is.
			if not text.is_valid_int():
				var table: Dictionary = ENUMS[key]
				var wanted := text.to_upper().replace("-", "_").replace(" ", "_")

				if table.has(wanted):
					out[raw_key] = int(table[wanted])
					continue

				DotLog.warn(RULES_CHANNEL, "unknown value for an enum setting", {
					"key": key,
					"value": text,
					"known": ", ".join(enum_names_for(key)),
				})

		out[raw_key] = value

	return out


## The legal names for an enum setting, lower case. Empty for anything else.
static func enum_names_for(key: String) -> PackedStringArray:
	var out := PackedStringArray()

	if not ENUMS.has(key):
		return out

	var table: Dictionary = ENUMS[key]

	for name: Variant in table:
		out.append(str(name).to_lower())

	return out


## The name of an enum setting's current value, for a log line or a console reply.
func enum_name(key: String) -> String:
	if not ENUMS.has(key):
		return ""

	var table: Dictionary = ENUMS[key]
	var current := int(get(key))

	for name: Variant in table:
		if int(table[name]) == current:
			return str(name).to_lower()

	return str(current)


## The warning marks, as seconds, largest first.
## Parsed from the text field [member warn_at_sec]; an unreadable entry is dropped with a warning, not the whole configuration.
func warn_marks() -> PackedFloat32Array:
	var out := PackedFloat32Array()

	for entry in warn_at_sec:
		var text := entry.strip_edges()

		if text == "":
			continue

		if not text.is_valid_float():
			DotLog.warn(RULES_CHANNEL, "ignoring an unreadable warning mark", {
				"value": text
			})
			continue

		var seconds := text.to_float()

		if seconds > 0.0:
			out.append(seconds)

	var sorted := Array(out)
	sorted.sort()
	sorted.reverse()

	return PackedFloat32Array(sorted)


## Whether a countdown second has a cue, per [member cue_countdown_at].
## Parsed on every ask, as the field is text a console command may change.
func has_countdown_cue(seconds_left: int) -> bool:
	if cue_countdown == "":
		return false

	for entry in cue_countdown_at:
		var text := entry.strip_edges()

		if text.is_valid_int() and text.to_int() == seconds_left:
			return true

	return false


## The cue id for one second of a countdown, or empty.
func countdown_cue_id(seconds_left: int) -> String:
	if not has_countdown_cue(seconds_left):
		return ""

	return cue_countdown % seconds_left if cue_countdown.contains("%d") else cue_countdown


## A choice's name as a ballot shows it, marked when it is unofficial.
## Uses [code]replace[/code], not [code]%[/code]: a stray [code]%[/code] in the marker would fail to format silently.
func marked_name(display: String, official: bool) -> String:
	if official or unofficial_marker == "":
		return display

	if unofficial_marker.contains("%s"):
		return unofficial_marker.replace("%s", display)

	return display + unofficial_marker


## Layers a game's own vote configuration onto these rules: code defaults < overlay (game metadata) < file < DOT_VOTE_* < --vote-*.
## A result that does not validate is refused as a whole and the defaults are put back, since rules that contradict each other mean a vote that never opens.
func layer_over_defaults(file_path: String, overlay: Dictionary = {}) -> DotResult:
	var defaults := to_dictionary()

	if not overlay.is_empty():
		apply_dictionary(overlay, "game metadata")

	var overlay_unknown := unknown_keys.duplicate()
	var loaded := load_layered(file_path)

	# load_layered starts its own list of unknown keys; the overlay's are kept in front
	# of them, so a typo in game.yml is reported exactly like a typo in the file.
	overlay_unknown.append_array(unknown_keys)
	unknown_keys = overlay_unknown

	if loaded.ok:
		return loaded

	apply_dictionary(defaults, "defaults")

	return loaded


## Applies [param file_name] from `cfg/addons/dot_vote/`, then the operator's `cfg/server/addons/dot_vote/`.
## A flat [param legacy_dir]/[param file_name] is still read (one WARN) while no new copy exists.
func apply_cfg_file(file_name: String = "vote.yml", legacy_dir: String = "res://cfg") -> DotResult:
	return DotAddonConfig.apply_file(CFG_ADDON, file_name, legacy_dir, apply_dictionary)


## [method apply_cfg_file], then `DOT_VOTE_*`, `--vote-*` and validation: [method DotConfig.load_layered] for the yml layout.
func load_cfg(file_name: String = "vote.yml", legacy_dir: String = "res://cfg") -> DotResult:
	unknown_keys = PackedStringArray()
	var file_res := apply_cfg_file(file_name, legacy_dir)
	if not file_res.ok:
		return file_res
	apply_env()
	apply_cli()
	var valid := validate()
	if not valid.ok:
		return valid.wrap("Configuration is invalid.")
	return DotResult.success(self)


## Takes out what a host cannot drive, and says what it took.
## A round or score trigger the host never feeds would wait for ever. Those fall back to [constant Trigger.TIME_LIMIT], the limits to 0, and end-of-round apply to [constant Apply.IMMEDIATE]; ERROR logs the result.
func drop_unfed(feeds_rounds: bool, feeds_score: bool) -> PackedStringArray:
	var dropped := PackedStringArray()

	if not feeds_rounds:
		if trigger == Trigger.ROUND_END:
			trigger = Trigger.TIME_LIMIT
			dropped.append("trigger: round_end")
		if round_limit > 0:
			dropped.append("round_limit: %d" % round_limit)
			round_limit = 0
		if apply == Apply.END_OF_ROUND:
			apply = Apply.IMMEDIATE
			dropped.append("apply: end_of_round")
		if rtv_apply == Apply.END_OF_ROUND:
			rtv_apply = Apply.IMMEDIATE
			dropped.append("rtv_apply: end_of_round")

	if not feeds_score:
		if trigger == Trigger.SCORE_LIMIT:
			trigger = Trigger.TIME_LIMIT
			dropped.append("trigger: score_limit")
		if score_limit > 0:
			dropped.append("score_limit: %d" % score_limit)
			score_limit = 0

	return dropped


func validate() -> DotResult:
	var bad := _validate_sizes()
	if bad == null:
		bad = _validate_triggers()
	return bad if bad != null else DotResult.success(true)


## The first size or ballot-shape problem as a failure, or null.
func _validate_sizes() -> DotResult:
	if max_options < 2:
		return DotResult.fail(
			DotError.CODE_INVALID, "A ballot needs at least two options."
		)

	if nomination_slots > max_options:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"nomination_slots (%d) exceeds max_options (%d)."
				% [nomination_slots, max_options],
			"every place on the ballot would be reserved and nothing would be filled in"
		)

	if runoff_options > max_options:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"runoff_options (%d) exceeds max_options (%d)."
				% [runoff_options, max_options]
		)

	return null


## The first trigger or lead problem as a failure, or null.
func _validate_triggers() -> DotResult:
	# 0 with a rock-the-vote is "around the clock until the players ask": a real server,
	# and what a choice's own time_limit_sec: 0 already meant. Only with nothing at all
	# that could end it is it a configuration that cannot work.
	if trigger == Trigger.TIME_LIMIT and duration_sec <= 0.0 and not rtv_enabled:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"trigger is time_limit but duration_sec is 0 and rock-the-vote is off.",
			"nothing would ever start a vote; set a duration or turn rtv_enabled on"
		)

	# Any limit will do: under round_end a time or a score limit is held for the round's
	# end rather than ignored. What cannot work is no limit at all.
	if (
		trigger == Trigger.ROUND_END
		and round_limit <= 0 and duration_sec <= 0.0 and score_limit <= 0
	):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"trigger is round_end but there is no round, time or score limit.",
			"nothing would ever start a vote"
		)

	if vote_lead_sec > 0.0 and duration_sec > 0.0 and vote_lead_sec >= duration_sec:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"vote_lead_sec (%.0f) is not less than duration_sec (%.0f)."
				% [vote_lead_sec, duration_sec],
			"the ballot would open the instant the choice started"
		)

	if rtv_delay_sec > 0.0 and duration_sec > 0.0 and rtv_delay_sec >= duration_sec:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"rtv_delay_sec (%.0f) is not less than duration_sec (%.0f)."
				% [rtv_delay_sec, duration_sec],
			"rocking the vote would be refused for the whole of every map"
		)

	if not rtv_enabled and trigger == Trigger.RTV_ONLY:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"trigger is rtv_only but rtv_enabled is off.",
			"nothing could ever start a vote"
		)

	if max_runoffs > 0 and tie_break == TieBreak.RUNOFF and runoff_options < 2:
		return DotResult.fail(
			DotError.CODE_INVALID, "A runoff needs at least two options."
		)

	if trigger == Trigger.SCORE_LIMIT and score_limit <= 0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"trigger is score_limit but score_limit is 0.",
			"nothing would ever start a vote"
		)

	if score_limit > 0 and vote_lead_score >= score_limit:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"vote_lead_score (%d) is not less than score_limit (%d)."
				% [vote_lead_score, score_limit],
			"the ballot would open at the first point scored"
		)

	if vote_lead_fraction >= 1.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"vote_lead_fraction must be less than 1.",
			"the ballot would open the instant the choice started"
		)

	return null


## A short human summary. [b]Not [code]describe_lines[/code][/b], which [DotConfig]
## already defines as the full dump of every key — both are worth having, and a
## console command that showed only one of them would show the wrong one.
func summary_lines() -> PackedStringArray:
	var out := PackedStringArray()

	out.append("enabled    %s" % ("yes" if enabled else "no"))
	out.append("trigger    %s, end vote %s" % [
		enum_name("trigger"), "on" if end_vote else "off"
	])
	out.append("limit      %s%s%s" % [
		"none" if duration_sec <= 0.0 else "%ds" % int(duration_sec),
		"" if round_limit <= 0 else ", %d rounds" % round_limit,
		"" if score_limit <= 0 else ", score %d" % score_limit,
	])
	out.append("extend     %s, +%ds, %s" % [
		"offered" if include_extend else "not offered",
		int(extend_seconds),
		"unlimited" if max_extends <= 0 else "at most %d" % max_extends,
	])
	out.append("ballot     %d options, %d reserved, filled %s" % [
		max_options, nomination_slots, enum_name("fill")
	])
	out.append("counting   %s, ties by %s" % [
		enum_name("method"), enum_name("tie_break")
	])
	out.append("rtv        %s at %d%% of %d+" % [
		"on" if rtv_enabled else "off",
		int(rtv_fraction * 100.0),
		rtv_min_players,
	])
	out.append("cooldown   %s" % (
		"%d plays" % cooldown if cooldown_mode == Cooldown.PLAYS
		else "%.0f minutes" % cooldown_minutes
	))
	out.append("applies    %s after %.0fs" % [enum_name("apply"), apply_delay_sec])
	out.append("time up    %s%s" % [
		enum_name("time_up").replace("_", " "),
		"" if time_up != TimeUp.FINISH_ROUND
		else (", for at most %ds" % int(finish_round_max_sec)) if finish_round_max_sec > 0.0
		else ", however long it takes",
	])
	out.append("empty      %s; on waking, %s" % [
		enum_name("empty_choice"), "start again" if wake_restart else "resume"
	])
	out.append("ballot ui  %s, voters %s" % [
		enum_name("ballot_input"), "shown" if ballot_show_voters else "hidden"
	])

	return out
