# Parity with the long-standing community map-choosers

Servers in this genre have run the same three plugins for fifteen years: a map chooser (the end-of-map ballot), a rock-the-vote, and nominations, plus a fourth that plays sounds over the first. Every setting, command, query and event those four expose is listed below against what covers it here — so a server owner who knows the old cvar can find the new setting, and so a gap is a row that says so rather than a feature nobody noticed was missing.

The old names are kept only as a lookup key. Nothing here reads them: every setting is a `DotVoteRules` field, layered `defaults < file < DOT_VOTE_* < --vote-*`, enums by name.

Legend: **have** — it was already here; **new** — added for parity; **different** — covered, deliberately in another shape; **not** — deliberately not here, with the reason.

## The end-of-map chooser

| Old cvar / command | Here | |
| --- | --- | --- |
| `mce_endvote` | `end_vote` | **new**. The switch: off, limits still end the map and the rotation, an admin's `setnextmap` or a rock-the-vote decides what is next. `trigger: rtv_only` is the same thing, and used to open a ballot at the lead anyway — fixed. |
| `mce_starttime` | `vote_lead_sec` | have. Seconds, not minutes. |
| `mce_start_percent`, `mce_start_percent_enable` | `vote_lead_fraction` | **new**. One setting: 0 is off. Measured against the limit as extended. |
| `mce_startround` | `vote_lead_rounds` | have. |
| `mce_startfrags` | `vote_lead_score` with `score_limit` | **new**. A generic score the host reports through `DotVoteDirector.note_score` — frags, team wins, points. `trigger: score_limit` for a game whose only limit is a score. |
| `mp_winlimit` / `mp_maxrounds` / `mp_fraglimit` (read by the chooser) | `round_limit`, `score_limit`, `duration_sec` | have / **new**. The limits are the vote's own, with per-choice overrides for time and rounds. |
| `mce_extend` | `include_extend`, `max_extends` | have. Note the old `0` meant "no extends"; here `max_extends: 0` is unlimited and `include_extend: false` is none. "Extend" leaves the ballot once the extensions are used up, as the plugin's does (`mapchooser_extended.sp` checks the extend count before adding it); **new here** in the sense that dot-vote's own first version offered it and then refused it. |
| `mce_extend_timestep` | `extend_seconds` | have. Seconds, not minutes. |
| `mce_extend_roundstep` | `extend_rounds` | have. |
| `mce_extend_fragstep` | `extend_score` | **new**. `score_limit_changed` tells a host that enforces its own limit. |
| `mce_exclude` | `cooldown`, `cooldown_mode`, `cooldown_max_fraction` | have, and clamped against the pool. |
| `mce_include` | `max_options` | have. |
| `mce_novote` | `on_no_votes: keep / random / rotation` | **new**. `random` is the old default; `keep` is the default here because the commonest cause is an empty server. |
| `mce_dontchange` | `early_vote_keep` | **new**. On a rock-the-vote ballot "don't change" stands in for "extend", and resumes the clock rather than restarting it (it used to restart it — a fresh limit for an unpopular map). `include_keep` still puts it on every ballot. |
| `mce_voteduration` | `vote_duration_sec` | have. |
| `mce_runoff`, `mce_runoffpercent`, `mce_maxrunoffs` | `method: majority_runoff`, `majority_fraction`, `max_runoffs`, `runoff_options`; `tie_break: runoff` | have. `majority_fraction` now goes below a half (**new**), and anything tied at the runoff line goes through with it (**new**). |
| `mce_warningtime` | `vote_warning_sec` | **new**. A countdown before the ballot, with `countdown_started` and a per-second `countdown_tick`. |
| `mce_runoffvotewarningtime` | `runoff_warning_sec` | **new**. |
| `mce_hidetimer` | `announce_countdown_every_sec` | **new**. Off announces the start only; the tick signal fires either way. |
| `mce_warningtimerlocation` | — | **not**. Where a countdown is drawn is the host's; `countdown_tick` carries the number. |
| `mce_markcustommaps` | `unofficial_marker` and `DotVoteChoice.official` | **new**. `"*%s"` by default, `""` off, `"%s (custom)"` for the phrase. A source reads `official` from the thing's own `vote:` metadata. |
| `mce_extendposition` | `pseudo_options_first` | **new**. Presentation only: ties are still broken choices-first. |
| `mce_randomizeorder` | `shuffle_ballot` | **new**. Seeded from `fill_seed`, so a client reproduces it. |
| `mce_addnovote` | `include_abstain` | **new**. Recorded, closes the voter's part, counts toward the quorum, toward no option and no majority. |
| `mce_blockslots`, `mce_menustyle` | — | **not**. Menu rendering; dot-vote draws nothing. |
| `sm_mapvote` | `revote` → `DotVoteDirector.start_vote(reason, force)` | have, **different**: now through the countdown, and replaces a change already decided. |
| `sm_setnextmap` | `setnextmap` → `set_next(id)` | **new**. Applies at the end of the clock and counts as the end vote having finished. |
| `mce_reload_maplist` | `votereload` → `reload()` / `DotVoteSource.reload()` | **new**. Most sources read live and have nothing to reload; `DotVoteListSource` re-reads its file. |
| Retry while another vote is on screen | `busy_fn` | **new**. The due vote waits through the existing retry. |
| Change at round end / instantly / at map end | `apply: end_of_round / immediate / end_of_time`, `apply_delay_sec` | have. |

## Rock the vote

| Old cvar / command | Here | |
| --- | --- | --- |
| `sm_rtv_needed` | `rtv_fraction` | have. |
| `sm_rtv_minplayers` | `rtv_min_players` | have. |
| `sm_rtv_initialdelay` | `rtv_delay_sec` | have. |
| `sm_rtv_interval` | `rtv_interval_sec` | **new**. After a rock-the-vote ballot that changed nothing. |
| `sm_rtv_changetime` | `rtv_apply` | **new**. Separate from `apply`; the clock resumes under a winner that waits. |
| `sm_rtv_postvoteaction` | `rtv_after_decided: change_now / deny` | **new**. It used to be refused whatever the setting would have said. |
| `sm_rtv`, `say rtv` | `rtv` (console and chat) | have. `unrtv` too. |
| `sm_forcertv` | `forcertv` → `force_rtv()` | **new**. With a decision pending, brings it forward. |
| Votes withdrawn on disconnect | `rtv_forgets_leavers` | have. |
| — | `rtv_admin_instant`, `rtv_outcome` | beyond: one admin passes it; or change/end without a ballot. |

## Nominations

| Old cvar / command | Here | |
| --- | --- | --- |
| `sm_nominate_excludecurrent` | `nominate_current_allowed` | have (inverted). |
| `sm_nominate_excludeold` | `nominate_on_cooldown_allowed` | have (inverted). |
| `sm_nominate <map>`, `say nominate` | `nominate` (console and chat) | have. With no argument it now lists only what could be nominated (`nominatable_ids()`), **new**. |
| `sm_nominate_addmap` | `nominate_addmap` → `force_nominate(id)` | **new**. Takes no reserved player place. |
| Nominating during or after the vote | refused: `nomination_state()` | **new**. It used to be accepted and then silently cleared. |
| One per player, replaced | `nominations_per_player: 1` | have. |
| List full (capped at the ballot size) | `nominations_max`, `nomination_slots` | have, **different**: the list and the ballot places are two numbers. |
| Duplicates refused | `nomination_seconding: false` | have, **different**: seconding is on by default, because `fill: most_nominated` needs it. |
| Nominations dropped on disconnect | `nominations_forget_leavers` | **different**: the plugin always drops a leaver's nomination, with no setting (`OnClientDisconnect` in `mapchooser_extended.sp`). Here it is a setting, off by default, because a nomination is a request of the server rather than of the person. Turn it on for the plugin's behaviour. |

## Sounds

| Old cvar / command | Here | |
| --- | --- | --- |
| Vote start / vote end / warning / runoff warning sounds | `cue_vote_start`, `cue_vote_end`, `cue_warning`, `cue_runoff_warning` → `signal cue(id)` | **new**. Ids, not files; empty is silent and every one ships empty. The host plays them through dot-audio. dot-vote names no audio class. |
| Counter sounds, per second | `cue_countdown` (`%d` template) and `cue_countdown_at` | **new**. |
| `mce_sounds_enablesounds`, `mce_sounds_enablewarningcountersounds` | empty cue ids | **different**: nothing to switch off when nothing is configured. |
| `mce_sounds_soundset` | a different set of ids in the rules file | **different**. |
| `mce_sounds_downloadallsounds`, `mce_sounds_reload`, `mce_sounds_list_soundsets` | — | **not**. Delivery and listing are dot-audio's and dot-cloud's. |

## Natives and forwards

| Old | Here | |
| --- | --- | --- |
| `NominateMap(map, force, owner)` | `nominate(voter, id)` / `force_nominate(id, by)` | have / **new**. |
| `RemoveNominationByMap` | `remove_nomination(id)` | **new**. |
| `RemoveNominationByOwner` | `remove_nominations_by(voter)` | **new**. |
| `InitiateMapChooserVote(when, list)` | `start_vote(reason, force)`, `open_vote(reason, only)` | have; the hand-picked list is **new**. |
| `CanMapChooserStartVote` | `can_start_vote()` | **new**. |
| `HasEndOfMapVoteFinished` | `has_end_vote_finished()` | **new**. |
| `EndOfMapVoteEnabled` | `end_vote_enabled()` | **new**. |
| `GetExcludeMapList` | `excluded_ids()` | **new**. |
| `GetNominatedMapList` | `nominated_ids()`, `nominated_list()` | **new**. |
| `IsMapOfficial` | `is_official(id)` | **new**. |
| `CanNominate` | `nomination_state()` → `YES / DISABLED / FULL / VOTE_IN_PROGRESS / VOTE_COMPLETE`, `can_nominate()` | **new**. |
| `IsWarningTimer` | `is_counting_down()`, `countdown_remaining()` | **new**. The plugin defines this native and never registers it (it is not in its `CreateNative` list or its include file), so no other plugin could ever call it; the row is here for the name. |
| `OnMapVoteStarted` | `vote_opened` | have. |
| `OnMapVoteEnd` | `vote_closed` | have. |
| `OnMapVoteWarningStart`, `OnMapVoteRunnoffWarningStart` | `countdown_started(seconds, runoff)` | **new**. |
| `OnMapVoteWarningTick` | `countdown_tick(seconds_left, runoff)` | **new**. |
| `OnNominationRemoved` | `nomination_removed(voter, id, reason)` | **new**. Every removal path, with the reason. |

## Not a setting at all

| Old | Why not |
| --- | --- |
| Translations | `announce_fn` takes a string; dot-locale is where localisation lives, and naming it here would make this addon require it. |
| Menus, hint boxes, blocked slots | dot-vote draws nothing — `vote_opened`, `countdown_tick` and `tally_updated` carry what a HUD needs. |
| Bonus-round-time warning | Engine-specific round timing. A host that has one calls `note_round_end` when it ends. |
| Win-limit clinch detection | The game knows when a match is clinched and reports it as a score or a round. |

## Checked against the source, 2026-09-26

The table was read row by row against the plugins' `.sp` files. Three rows were corrected above (the Extend note, nominations on disconnect, `IsWarningTimer`). What the plugins have that the table did not list, all minor:

| In the plugin | Here |
| --- | --- |
| `mce_forcertv`, an alias of `sm_forcertv` | `forcertv` is the one name; aliases are a console's business. |
| `OnMapVoteStart`, a deprecated forward | `vote_opened`, which the non-deprecated forward already maps to. |
| `sm_mapvote_reload_sounds`, `sm_mapvote_list_soundsets` (deprecated) | **not**: dot-vote plays nothing; cue ids are the host's catalogue. |
| The version cvars | **not**: an addon's version is its `plugin.cfg`. |
| A tie for first always goes to a runoff, whatever the runoff percentage | Stated here because the table did not say it outright: see the runoff rows above for what `runoff_*` does on a tie. |

**What reaches a running ballot, per layer.** `vote_selftest`'s "every config layer reaches a running ballot" sets `end_vote`, `include_extend` and `extend_seconds` through the game's metadata overlay, the JSON file, `DOT_VOTE_*` and `--vote-*`, each in a child process (`examples/layer_probe.gd`, because the command line is the process's own), and asserts the ballot: none opened, no Extend on it, the clock moved by the layered number. dot-server-deploy's own layers (`cfg/vote.yml`, `DOT_GAME_VOTE_*`, `--game-vote-*`) feed the game vote there and are not covered by this.
