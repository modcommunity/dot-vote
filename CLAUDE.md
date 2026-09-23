# dot-vote

Voting for what plays next. Read [../CLAUDE.md](../CLAUDE.md) first for the
family-wide rules; this file is only what is specific to this addon.

## Why it is a separate addon

dot-map already had a map vote — `DotMapVote`, `DotMapTimeLimit` — and dot-server
already had `DotVoteManager` for yes/no questions. Neither is this, and adding this to
either would have been the wrong shape twice:

- **`DotVoteManager` is a different question.** It asks "yes or no" with a quorum and
  a cooldown, and votekick is the reason it exists. A ballot with six options, a
  transferable preference and a tie-break is not a special case of it.
- **`DotMapVote` is the same question about one kind of thing.** It is a plurality
  ballot with one fixed tie-break, one fixed extend rule, and no quorum, cooldown,
  runoff, weighting or per-map limit. Generalising it in place would have made dot-map
  the home of a vote engine that dot-server's *games* also need — and a server that
  votes for its next game would then depend on dot-map to do it.

So the thing being voted for is an id, the meaning of the id is a `DotVoteSource`, and
one engine serves both. **dot-map's own vote is not deprecated**: a server happy with
a plurality ballot and a countdown needs nothing here, and `game-playground` and
`game-g2gfast` still use it.

## The one design decision

**A `DotVoteChoice` is an id, a name, and the handful of facts a ballot needs.** It is
not a game and not a map. The alternative — a ballot over `DotGameDescriptor` — fails
for the family's parse reason (a script naming a `class_name` the project does not
have takes every script referencing it down with it), and then fails again for a
better one: a server offering "Arena", "Arena (low gravity)" and "surf_beginner" on
one ballot is offering three things of two kinds, and a ballot that holds one kind
cannot.

Everything else follows from it. The sources are duck-typed. Per-choice settings —
including the time limit — live in the thing's own metadata under a `vote` key, so a
game's limit is written beside the game rather than in a second table of ids that goes
stale.

## Where a game plugs in

| To change | Where |
| --- | --- |
| Any policy at all | `DotVoteRules` — 80 settings, layered like every `DotConfig` |
| A game's own defaults, under an operator's file | `DotVoteRules.layer_over_defaults(file, DotVoteGameSource.running_game_metadata("map_vote"))` |
| What can be voted for | `DotVoteSource` subclass, or `DotVoteListSource` with a `Callable` |
| How many players there are, who is an admin, who is a spectator | `DotVoteDirector.player_count_fn` / `is_admin_fn` / `is_spectator_fn` |
| What one player's vote is worth | `DotVoteDirector.weight_fn` |
| What the players are told | `DotVoteDirector.announce_fn` |
| What they hear | `DotVoteDirector.cue` (a signal carrying a `cue_*` id) |
| A countdown on a HUD | `DotVoteDirector.countdown_started` / `countdown_tick` |
| Whether another vote is on screen | `DotVoteDirector.busy_fn` |
| The leading score, for a score limit | `DotVoteDirector.note_score` |
| Whether this addon changes anything at all | `DotVoteDirector.auto_apply`, or a source with no apply |
| Command names | `DotVoteCommands.prefix` / `names` |
| How a command context becomes a voter | `DotVoteCommands.voter_fn` |
| How what a player typed becomes a choice id | `DotVoteCommands.resolve_fn` — a game whose ids carry a prefix |

## Parity with the community map-choosers

[docs/parity.md](docs/parity.md) is every setting, command, query and event of the long-standing community map-chooser plugins — the end-of-map chooser, rock-the-vote, nominations and the sounds layer — against what covers it here. Twenty-four settings, four admin commands, twelve queries and five signals were added to close it. Read it before adding a setting: the row may already exist under another name, and the "deliberately not" rows say why.

Four things about that work are worth keeping in front of you:

- **Two "carry on"s.** After an end-of-map ballot that changes nothing the clock restarts, or the next tick expires it again. After a rock-the-vote ballot that changes nothing it RESUMES (`DotVoteClock.resume`), because a restart hands an unpopular map a fresh limit for having been voted on — which is what "don't change" used to do. `DotVoteDirector._carry_on` is the one place that decides, from the reason the ballot opened.
- **A pending change carries its own moment.** `_pending_moment` rather than `rules.apply` read at apply time, because an end-of-map winner, a rock-the-vote winner (`rtv_apply`) and an admin's `set_next` each wait for something different.
- **Presentation is not policy.** `option_ids()` is the order a player sees and a typed number indexes; `countable_ids()` is choices-first, always, and is what ties are broken in. `pseudo_options_first` moving "don't change" to the top of a menu must not make every tie go to the status quo.
- **Every new check was armed.** The runoff-line tie, the clock resuming, the rtv interval and the end-vote switch were each broken on purpose and the suite re-run; each fired, and so did the settings sweep, on its own, for the setting whose only reader had been removed.

## Bugs found by building it

All five parsed cleanly. Three are the family's own recurring shapes.

- **A choice with no time limit never counted its elapsed time.** `DotVoteClock.running`
  meant "has a limit" rather than "has started", so `advance()` returned before
  `elapsed += delta` on a choice configured with no clock — which is exactly the
  server whose only way to change anything is a vote. `rtv_delay_sec` is measured
  against `elapsed`, so **rocking the vote was refused for ever on precisely the
  deployment that depends on it**, with nothing erroring. Found by asserting on
  `elapsed` rather than on the symptom, which is the only reason it was visible: every
  other observable on that clock is correct.

- **`extend_needs_majority` decided nothing in either position.** With it on, a tie
  between "extend" and a map went to the map, because extend is erased from the tie.
  With it off, the ordinary tie-break ran — and every pseudo-option sorts last in
  ballot order, so `BALLOT_ORDER` handed the tie to the map as well. Two documented
  policies, one behaviour. *A setting that reads differently and behaves identically
  is this family's most repeated bug wearing a disguise*: the usual detector — a name
  that occurs once — does not fire, because the name occurs twice and one of the
  branches is a no-op.

- **`Fill.MOST_NOMINATED` could never do anything.** A second player nominating what
  somebody had already nominated was refused, so every nomination count was exactly 1
  and a ballot "filled by most nominated" had nothing to sort by. SourceMod refuses
  the duplicate too, and there it is consistent because it has no such fill mode.
  Seconding is now allowed and configurable (`nomination_seconding`), and a player
  still cannot second themselves.

- **A vote that could not open was the last one that would ever be offered.** The
  clock fires once and latches — it has to, or an expired limit opens a ballot on
  every tick — so a `vote_due` arriving while the vote cooldown was still running, or
  while there were too few players, was dropped with one warning. The most ordinary
  sequence there is reaches it: a vote fails for want of a quorum, somebody rocks the
  vote thirty seconds later, and **the server never changes anything again.**
  `_vote_due_pending` retries until it can.

- **`await` on a coroutine reached through `Object.call` works, and it had to be
  checked rather than assumed.** `DotVoteGameSource.apply` is
  `await manager.call("change_game", …)` — a coroutine, called by name, through a
  variable statically typed as `Object`, from a director whose `source` is statically
  typed as the *base* class whose `apply` is not a coroutine. Three places for GDScript
  to decide it is not awaiting anything. The self-test drives a real `DotGameManager`
  through it for that reason.

Found by the parity work, 2026-09-23:

- **`trigger: rtv_only` opened a ballot at the lead anyway.** The clock fires `vote_due` for a time limit whatever the trigger, and only MANUAL was checked; `_on_expired`'s rotation branch for RTV_ONLY was unreachable on any server with a clock. The fix is `end_vote_enabled()`, which is also what the new `end_vote` switch turns off.
- **Every admin vote command was root-only.** `DotVoteCommands.admin_permission` was `"changelevel"` — a command's name, not a flag anybody holds — and `DotAdminFlags.granted` matches exactly. It is `"changemap"` now, which is `DotAdminFlags.CHANGEMAP`, spelled out because this file cannot name dot-server's classes.
- **"Extend" stayed on the ballot after the extensions were used up**, and winning with it produced "This cannot be extended again" and a restarted clock. `DotVoteBallot.extend_available` is set from the clock when a ballot opens.
- **A nomination made while a ballot was open was accepted and then thrown away** by the change that ballot caused. `nomination_state()` refuses it and says why.
- **`trigger: time_limit` and `trigger: round_end` behaved identically at runtime** — both limits fired whichever the trigger — and differed only in what `validate()` demanded: the shape of a setting that reads differently and decides nothing. Fixed in a second pass the same day: under `round_end` a time or score limit reaching its lead no longer opens a ballot over a fight in progress; the director holds it (`is_waiting_for_round_end()`) and the host's next `note_round_end` opens it. A round limit opens at the round end it is due on, as before, and a rock-the-vote never waits. `validate()` now asks only that round_end has some limit. The suite's section runs the same clock under both triggers and fails unless they differ; it was armed by removing the hold, and four checks fired.

And one process hazard, which is already in the family CLAUDE.md and was hit anyway:
`==` binds tighter than `as`, so `a == [x] as Array[StringName]` parses as
`(a == [x]) as Array[StringName]` and fails to compile — **and a scene whose script
fails to parse hangs rather than failing.** Run `--check-only` before running a scene.

## Things deliberately not here

- **No wire format.** A client showing a live ballot needs one, and it belongs in the
  game's netcode bridge rather than here: dot-net's message registry is where a
  message type is declared, and naming it here would make this addon require dot-net.
  `DotVoteDirector` emits everything a bridge needs (`vote_opened`, `vote_cast`,
  `tally_updated`, `vote_closed`) and takes votes by voter id, which is what a bridge
  hands it.
- **No UI.** dot-ui's `DotScreen` is the place, and the same dependency argument
  applies.
- **No persistence.** `DotVoteHistory` serialises to a dictionary and the host decides
  where it goes. A server that wants its cooldowns to survive a restart writes it out;
  most do not, and a store interface for one dictionary would be ceremony.
- **No per-choice permissions.** dot-map has `nominate_permission` on a map def and
  this deliberately does not copy it: whether a player may nominate something is a
  question about the player, and the host answers it before calling `nominate`.
- **Nothing draws or plays on its own.** `announce_fn` takes a string and `cue` carries an
  id. What a server says and plays, and where, is not this addon's opinion — the
  countdown is counted here and drawn by the host.
- **No dependency on dot-audio.** The `cue_*` settings are ids and the signal hands them
  over; a sound set is a different set of ids in the rules file.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/vote_selftest.tscn
```

358 checks, non-zero on failure. Three sections matter more than the rest:

- **"Every setting is read by something"** runs this family's own mechanical detector
  over `DotVoteRules` — 80 settings in one resource is either this addon's best
  feature or twenty-six instances of the family's most repeated bug, and the check is
  the difference. It matches `rules.<key>` across the addon and bare identifiers
  inside the rules themselves, rather than any occurrence: `DotVoteChoice` has an
  `enabled` too, and a crude grep would report `DotVoteRules.enabled` as read by a
  file that has never heard of it.
- **The two integration sections** run a real `DotServer` and a real `DotMapSession`
  and change what they are running. They are also written entirely through `load()`
  and `set()`/`call()`, so the suite runs with neither addon linked — and, more to the
  point, so it exercises exactly the reflection the sources use. If the duck typing is
  wrong, this is the only place it can show.

`addons/dot_map` and `addons/dot_server` are gitignored symlinks. Without them those
two sections **fail loudly** rather than being skipped, because "0 failures" from a
suite that ran nothing is how a family ships two ends that never met.
