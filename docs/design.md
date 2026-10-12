# Design

Why this addon is shaped the way it is. Setting-by-setting coverage of the community map-choosers is [parity.md](parity.md); the bugs are [history.md](history.md).

## Why it is a separate addon

dot-map already had a map vote (`DotMapVote`, `DotMapTimeLimit`) and dot-server already had `DotVoteManager` for yes/no questions. Neither is this, and adding this to either would have been the wrong shape twice:

- **`DotVoteManager` is a different question.** It asks "yes or no" with a quorum and a cooldown, and votekick is the reason it exists. A ballot with six options, a transferable preference and a tie-break is not a special case of it.
- **`DotMapVote` is the same question about one kind of thing.** It is a plurality ballot with one fixed tie-break, one fixed extend rule, and no quorum, cooldown, runoff, weighting or per-map limit. Generalising it in place would have made dot-map the home of a vote engine that dot-server's *games* also need, and a server that votes for its next game would then depend on dot-map to do it.

So the thing being voted for is an id, the meaning of the id is a `DotVoteSource`, and one engine serves both. **dot-map's own vote is not deprecated**: a server happy with a plurality ballot and a countdown needs nothing here. Every game in the family with a vote is on `DotVoteDirector` now.

## The one design decision

**A `DotVoteChoice` is an id, a name, and the handful of facts a ballot needs.** It is not a game and not a map. The alternative, a ballot over `DotGameDescriptor`, fails for the family's parse reason (a script naming a `class_name` the project does not have takes every script referencing it down with it), and then fails again for a better one: a server offering "Arena", "Arena (low gravity)" and "surf_beginner" on one ballot is offering three things of two kinds, and a ballot that holds one kind cannot.

Everything else follows from it. The sources are duck-typed. Per-choice settings, including the time limit, live in the thing's own metadata under a `vote` key, so a game's limit is written beside the game rather than in a second table of ids that goes stale.

## Four rules from the parity work

- **Two "carry on"s.** After an end-of-map ballot that changes nothing the clock restarts, or the next tick expires it again. After a rock-the-vote ballot that changes nothing it RESUMES (`DotVoteClock.resume`), because a restart hands an unpopular map a fresh limit for having been voted on, which is what "don't change" used to do. `DotVoteDirector._carry_on` is the one place that decides, from the reason the ballot opened.
- **A pending change carries its own moment.** `_pending_moment` rather than `rules.apply` read at apply time, because an end-of-map winner, a rock-the-vote winner (`rtv_apply`) and an admin's `set_next` each wait for something different.
- **Presentation is not policy.** `option_ids()` is the order a player sees and a typed number indexes; `countable_ids()` is choices-first, always, and is what ties are broken in. `pseudo_options_first` moving "don't change" to the top of a menu must not make every tie go to the status quo.
- **Every new check is armed**: broken on purpose, the suite re-run, and seen to fire. That includes the settings sweep, which must fire on its own for a setting whose only reader has been removed.

## MANUAL is the schedule, not rock-the-vote

`trigger: manual` is for a game that knows better than a clock when its ballot belongs: a one-round-per-course game opens it a few seconds into the course and applies it at the round's end. What the host owns is the SCHEDULED ballot, so a limit reaching its lead or running out opens nothing. A passed rock-the-vote is not the schedule; it is the players asking now, and `_on_vote_due` opens it under MANUAL exactly as under every other trigger (an admin's `force_rtv` always did).

The games written before this opened the rocked ballot themselves from `clock.expired`, guarded by `director.is_voting()`. That handler cannot double a ballot against this code: the clock emits `vote_due` before `expired`, so the director has already opened the ballot (the guard returns) or started its countdown (the game's `start_vote` is refused with "A vote is about to start"), and when it could not open at all the game's attempt is refused for the same reason and the director's `_vote_due_pending` retries once. The suite runs that handler verbatim against the director.

**A list read at the ballot, not copied at setup.** `DotVoteSource.choices()` was always meant to be fresh, but a `DotVoteListSource` is a copy, and every game whose catalogue grew after boot (delivered maps) had to remember to refresh it, or a server built with one map never opened a ballot. `entries_fn` is the host's list as a function; `before_ballot()` (a no-op on the base) re-reads it, and the director calls that from `begin`, `start_vote` (before `has_alternatives`) and `open_vote`. Re-reading in `choices()` itself was the alternative and is worse: `find` calls `choices()` from views and polls, and every call would rebuild every choice.

## An empty server: the clock sleeps, or the server moves on by itself

Two halves, one per setting of dot-server's `sv_hibernate_when_empty`:

- **Hibernating (the default).** A director following the server (`follow_hibernation`, which dot-game's `DotGameModule` does for every director under a game module) counts nothing while it sleeps: not the clock, a ballot, a countdown or the cooldown. Waking calls `restart()`: the choice's own limit, every extend, no rock-the-vote, no ballot, no decided change, and **no second history entry** (calling `begin` again would write one and shorten every cooldown). `wake_restart: false` resumes instead.
- **Not hibernating.** The clock runs, the vote due at the lead cannot open for want of a voter (`min_players_to_vote` is 1) and is retried, so somebody arriving before the limit still gets it; and at the limit, with `player_count()` at 0, `empty_choice` decides: `random` (default) draws from the ballot's own pool, judged for one player, never the running choice even under `include_current`; `rotation` takes the next in order; `wait` is the old behaviour. The change is immediate, with no `apply_delay_sec` and no `finish_round` hold, because nobody is reading a result or playing a round. A one-choice server restarts its clock rather than sitting expired. The draw uses `empty_rng` (entropy-seeded), not `fill_seed`, because a deterministic draw would send every freshly booted server in a fleet to the same map.

**`on_no_votes` is the other "nobody" and is not this.** A ballot that opened with people present and closed with no votes stays (`keep`, the default: the clock restarts, which players see as an extension), or draws one of the ballot's real options, never Extend (`random`), or takes the rotation (`rotation`). Both are ordinary `DotVoteRules` keys, so every game sets them the same way as every other rule: its vote JSON, `DOT_VOTE_ON_NO_VOTES` / `DOT_VOTE_EMPTY_CHOICE`, `--vote-on-no-votes=random`, or its game metadata.

## Three clocks, and only one of them is a round's

A map's time limit, a round's time limit and a round limit are three settings, and the round-based shooters have always kept them apart: `duration_sec` is the map's clock (or the game's, for a server's game vote), `round_limit` is how many rounds it gets, and how long ONE round lasts is the game's own rule (dot-match's `time_limit_sec`), which this addon never sees. Any of them can be set at once and whichever arrives first ends the choice.

**0 is around the clock.** `duration_sec: 0` with rock-the-vote on validates: refusing it as "nothing would ever start a vote" was true of the rules and not of the server, because a rock-the-vote still does. A choice's own `time_limit_sec: 0` means the same for one map under a server with a limit.

**When the time is up, `time_up` decides what happens to the round in progress.** `change_now` (the default) or `finish_round`: the change waits for the host's next `note_round_end`, for at most `finish_round_max_sec`. Four things about it:

- **Only on a host that says it has rounds.** `DotVoteDirector.round_based` is the host's to set, and only a host that reports every round end may set it. Without it there is no round to finish, and a deathmatch would otherwise sit out the five-minute cap waiting for a `note_round_end` that never comes.
- **Only while a round is live.** `round_based` says the game has rounds, not that one is being played. A round-based game in warmup or waiting for players has nothing to finish, and once held the change for the whole cap (for ever at `finish_round_max_sec: 0`). The host answers `DotVoteDirector.round_in_progress_fn`; it is asked every tick, so a match reset to warmup mid-hold releases the change without a `note_round_end`. Unset reads as always live.
- **Only a time or score limit waits.** A rock-the-vote and an admin's command are somebody asking for now, and a round limit is only ever reached AT a round's end.
- **The hold is in `_ready_to_apply`, which is the one place every moment goes through**: a winner decided early and waiting for the clock, a ballot still open when the clock ran out, and the rotation a limit falls back on when nobody was asked.

**The defaults:** `duration_sec` is 2700 (forty-five minutes; thirty was a deathmatch's number) and `vote_lead_sec` is 150, which fits a countdown, a thirty-second ballot, a runoff and the result with time left, so a decided change waits for the clock rather than the clock for the vote.

## A ballot a player can click

`DotVoteBallotView` is the ballot as a screen draws it, and `DotVoteBallotFeed` sends it. Still no wire format and still no UI here (the dictionary rides whatever the host has: dot-server-deploy and every game put it in a dot-server notice's `data`, and dot-ui's `DotBallotPanel` draws it), but what a client needs to draw a ballot is decided here, once, rather than by every host:

- **Options in `option_ids()` order**, the order a typed number indexes, so option `i` is `!<command> i+1` on every screen and in every console. Not `countable_ids()`.
- **Who voted for what, by option index**, so every voter's avatar can sit on their choice and move when they change it. `ballot_show_voters: false` sends the counts and no names, for a secret ballot.
- **How to choose is a rule** (`ballot_input`: numbers, pointer, both), not a client setting, because what the ballot says to press has to be true on every screen at once.
- **The feed is polled, not signalled**, because `forget_voter` withdraws a ballot without emitting anything and a signal-driven feed kept a departed player's avatar on the board. It compares by hash ignoring the seconds, so an unchanged ballot sends nothing; and it holds the `vote_closed` result for one poll, because by the next the director has forgotten what won.

## Deliberately not here

- **No wire format.** It belongs in the game's netcode bridge: dot-net's message registry is where a message type is declared, and naming it here would make this addon require dot-net. `DotVoteDirector` emits everything a bridge needs (`vote_opened`, `vote_cast`, `tally_updated`, `vote_closed`) and takes votes by voter id, which is what a bridge hands it.
- **No UI.** dot-ui's `DotBallotPanel` draws a `DotVoteBallotView`; it takes the dictionary and names nothing here.
- **No persistence.** `DotVoteHistory` serialises to a dictionary and the host decides where it goes. A server that wants its cooldowns to survive a restart writes it out; a store interface for one dictionary would be ceremony.
- **No per-choice permissions.** dot-map has `nominate_permission` on a map def and this deliberately does not copy it: whether a player may nominate something is a question about the player, and the host answers it before calling `nominate`.
- **Nothing draws or plays on its own.** `announce_fn` takes a string and `cue` carries an id. The countdown is counted here and drawn by the host.
- **No dependency on dot-audio.** The `cue_*` settings are ids and the signal hands them over; a sound set is a different set of ids in the rules file.

## The suite

Three sections matter more than the rest:

- **"Every setting is read by something"** runs the family's mechanical detector over `DotVoteRules`. That many settings in one resource is either this addon's best feature or a pile of the family's most repeated bug, and the check is the difference. It matches `rules.<key>` across the addon and bare identifiers inside the rules themselves, rather than any occurrence: `DotVoteChoice` has an `enabled` too, and a crude grep would report `DotVoteRules.enabled` as read by a file that has never heard of it.
- **The two integration sections** run a real `DotServer` and a real `DotMapSession` and change what they are running. They are written entirely through `load()` and `set()`/`call()`, so the suite parses with neither addon linked and, more to the point, exercises exactly the reflection the sources use. If the duck typing is wrong, this is the only place it can show. Without the links those sections **fail loudly** rather than being skipped, because "0 failures" from a suite that ran nothing is how a family ships two ends that never met.

## The map menu

Every game has a map menu on M (dot-menu's `DotMenuMaps`), and on a server its other half is here, because every game already has a director over a source that lists its maps and applies one. `DotVoteCommands.bind` installs `DotVoteMapMenu`, so no game wires it.

- `mapmenu` answers with a `map_menu` notice: `{maps, allowed, flag, vote, where}`. `mapmenu <id>` changes the map for a player holding `sv_map_menu_flag` (default `generic`, which every staff group from moderator up holds, so "moderator or above" without an opinion here about what a moderator is), and for anybody else nominates the map and rocks the vote (or casts a vote for it when a ballot is open). The result goes back as a notice and a reply line.
- **The command is open and the gate is inside**, not the console's `permission`: a player without the flag still gets the list and the vote. The flag is read on every request, so `sv_map_menu_flag changemap` at the console applies to the next press; empty lets anybody change the map.
- **"Now", not "next round".** Most round-based games' source applies by setting the next round's map, which is right for a ballot and wrong for an admin pressing M. A game sets `map_menu.change_fn` to its immediate change; without one the source's apply is used.
- **A long list goes out in parts** (`chunks_of`, `PART_BYTES` each, `part`/`parts` on every one): dot-server drops a notice over 8 KB whole, and a timer server's few hundred maps are well over it.
- A change while a ballot is open is refused: the ballot decides, and `endvote` closes it first.

