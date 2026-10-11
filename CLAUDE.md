# dot-vote

Voting for what plays next: one ballot engine over ids, with rock-the-vote, nominations, runoffs, weighting, cooldowns, time, round and score limits, and the extend rules, for a server's next map or its next game.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to this addon.

**Only dot-core is a dependency.** dot-map and dot-server are optional, reached by `load()` and `call()`, and linked (`.gitignore`) only so the suite's integration sections can run against the real thing.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | anything: why it is separate from `DotMapVote` and `DotVoteManager`, choices as ids, the empty server, the three clocks, the ballot view, what is not here, the suite |
| [docs/parity.md](docs/parity.md) | adding a setting: every setting, command, query and event of the community map-choosers against what covers it here; the row may already exist under another name |
| [docs/history.md](docs/history.md) | the bugs, and how each looked |

## Layout

| Path | What |
| --- | --- |
| `addons/dot_vote/core/` | `DotVoteChoice` (an id, a name, a ballot's facts), `DotVoteResult`, `DotVoteRules` (every policy, a `DotConfig`) |
| `addons/dot_vote/runtime/` | `DotVoteDirector` (the engine), `DotVoteBallot`, `DotVoteClock`, `DotVoteNominations`, `DotVoteHistory`, `DotVoteSource` / `DotVoteListSource`, and the client views `DotVoteClockView`, `DotVoteBallotView`, `DotVoteBallotFeed` |
| `addons/dot_vote/integrations/` | `DotVoteCommands`, `DotVoteMapSource` (dot-map), `DotVoteGameSource` (dot-server's `DotGameManager`) |
| `examples/vote_selftest.tscn` | the suite; `examples/fixtures/` its data |

## Running and testing

- The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `godot --headless --path . res://examples/vote_selftest.tscn` (non-zero on failure).
- `addons/dot_map` and `addons/dot_server` must be linked; without them the two integration sections fail loudly, on purpose. [design](docs/design.md#the-suite)
- A new check is not done until it has been armed: break the code it guards and watch it fire. [design](docs/design.md#four-rules-from-the-parity-work)

## Rules that bite

- A choice is an id plus metadata, never a `DotGameDescriptor` or a map; sources are duck-typed; per-choice settings live in the thing's own metadata under `vote`. [design](docs/design.md#the-one-design-decision)
- Every `DotVoteRules` setting must be read by something; the suite's sweep checks it, and a setting read in two branches that behave the same is the same bug. [history](docs/history.md#building-it)
- Never name dot-server or dot-map classes; spell their constants out (`admin_permission = "changemap"` is `DotAdminFlags.CHANGEMAP`). [history](docs/history.md#the-parity-work)
- `DotVoteClock` latches when it fires, so a `vote_due` that cannot open is retried (`_vote_due_pending`), never dropped. [history](docs/history.md#building-it)
- `elapsed` counts on a clock with no limit; rock-the-vote timing depends on it. [history](docs/history.md#building-it)
- A no-change ballot restarts the clock after an end-of-map vote and RESUMES it after a rock-the-vote; `_carry_on` is the only place that decides. [design](docs/design.md#four-rules-from-the-parity-work)
- A pending change carries its own moment (`_pending_moment`); `_ready_to_apply` is the one gate every moment goes through, including the `finish_round` hold. [design](docs/design.md#three-clocks-and-only-one-of-them-is-a-rounds)
- `option_ids()` is display order and what a typed number indexes; `countable_ids()` (choices first) is what ties are broken in. [design](docs/design.md#four-rules-from-the-parity-work)
- `round_based` is set only by a host that reports every round end; only a time or score limit waits for the round. [design](docs/design.md#three-clocks-and-only-one-of-them-is-a-rounds)
- `trigger: manual` hands the host only the SCHEDULED ballot; a passed rock-the-vote opens its own under every trigger, and a host's leftover `clock.expired` handler finds it open (vote_due fires before expired). [design](docs/design.md#manual-is-the-schedule-not-rock-the-vote)
- API level is `addons/dot_vote/dot_vote_api.gd`; bump LEVEL for anything a game can call.
- `trigger: round_end` must behave differently from `time_limit` (a held ballot, `is_waiting_for_round_end()`); `rtv_only` and `end_vote: false` never open a ballot at the lead. [history](docs/history.md#the-parity-work)
- Hibernation pauses everything and wakes with `restart()`, which writes no second history entry. An empty server that does not sleep moves on by `empty_choice`, drawn from `empty_rng`, never `fill_seed`. [design](docs/design.md#an-empty-server-the-clock-sleeps-or-the-server-moves-on-by-itself)
- `on_no_votes` is a ballot nobody voted in; `empty_choice` is a server nobody is on. Different keys. [design](docs/design.md#an-empty-server-the-clock-sleeps-or-the-server-moves-on-by-itself)
- `DotVoteBallotFeed` is polled, compares by hash ignoring seconds, and holds `vote_closed` for exactly one poll. [design](docs/design.md#a-ballot-a-player-can-click)
- Extend comes off the ballot when the extensions are used up; nominations are refused while a ballot is open. [history](docs/history.md#the-parity-work)

## Where a game plugs in

| To change | Where |
| --- | --- |
| Any policy at all | `DotVoteRules`, layered like every `DotConfig` (`defaults < file < DOT_VOTE_* < --vote-*`) |
| A game's own defaults, under an operator's file | `DotVoteRules.layer_over_defaults(file, DotVoteGameSource.running_game_metadata("map_vote"))` |
| What can be voted for | `DotVoteSource` subclass, or `DotVoteListSource` with a `Callable` |
| A list that grows after the director is built (delivered maps) | `DotVoteListSource.entries_fn`, re-read at `begin` and before every ballot (`DotVoteSource.before_ballot`) |
| How many players there are, who is an admin, who is a spectator | `DotVoteDirector.player_count_fn` / `is_admin_fn` / `is_spectator_fn` |
| What one player's vote is worth | `DotVoteDirector.weight_fn` |
| What the players are told | `DotVoteDirector.announce_fn` |
| What they hear | `DotVoteDirector.cue` (a signal carrying a `cue_*` id) |
| A countdown on a HUD | `DotVoteDirector.countdown_started` / `countdown_tick` |
| The time left on a client's HUD | `DotVoteClockView`: `state_of(director)` on the server, sent when `is_stale`; `adopt` and `formatted_at` on the client |
| The ballot drawn on a client's screen | `DotVoteBallotView.state_of(director, people_fn)` and `DotVoteBallotFeed`; dot-ui's `DotBallotPanel` draws it |
| Whether a time limit waits for the round in progress | `DotVoteRules.time_up` / `finish_round_max_sec`, and `DotVoteDirector.round_based` |
| Whether another vote is on screen | `DotVoteDirector.busy_fn` |
| The leading score, for a score limit | `DotVoteDirector.note_score` |
| Whether this addon changes anything at all | `DotVoteDirector.auto_apply`, or a source with no apply |
| Whether the clock waits while the server sleeps | `DotVoteDirector.follow_hibernation(server)` (duck-typed on `hibernation_changed(bool)`), or `set_hibernating`; `DotVoteRules.wake_restart` |
| What an empty server's limit does when nothing sleeps | `DotVoteRules.empty_choice` (`random`, `rotation`, `wait`); `DotVoteDirector.empty_rng` |
| What a ballot nobody voted in decides | `DotVoteRules.on_no_votes` (`keep`, `random`, `rotation`) |
| Command names | `DotVoteCommands.prefix` / `names` |
| How a command context becomes a voter | `DotVoteCommands.voter_fn` |
| How what a player typed becomes a choice id | `DotVoteCommands.resolve_fn` (a game whose ids carry a prefix) |

Deliberately not here: a wire format, UI, persistence, per-choice permissions, drawing or playing anything, a dot-audio dependency. [design](docs/design.md#deliberately-not-here)
