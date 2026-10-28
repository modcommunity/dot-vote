extends "res://examples/selftest/tests_a.gd"

## Selftest sections, part b.


## Fails for any setting nothing reads.
func _test_every_setting_is_read() -> void:
	_section("Every setting is read by something")

	var sources := {}
	_read_scripts("res://addons/dot_vote", sources)

	_check(sources.size() >= 12, "%d scripts scanned" % sources.size())

	var rules := DotVoteRules.new()
	var declarations := str(sources.get("res://addons/dot_vote/core/dot_vote_rules.gd", ""))
	var unread := PackedStringArray()

	for key in rules.config_keys():
		if _reads_setting(key, sources, declarations):
			continue

		unread.append(key)

	_check(
		unread.is_empty(),
		"all %d settings are read somewhere" % rules.config_keys().size(),
		"declared and read by nothing: %s" % ", ".join(unread)
	)

	_done()
