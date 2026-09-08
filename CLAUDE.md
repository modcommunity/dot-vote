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
| Any policy at all | `DotVoteRules` — 55 settings, layered like every `DotConfig` |
| What can be voted for | `DotVoteSource` subclass, or `DotVoteListSource` with a `Callable` |
| How many players there are, who is an admin, who is a spectator | `DotVoteDirector.player_count_fn` / `is_admin_fn` / `is_spectator_fn` |
| What one player's vote is worth | `DotVoteDirector.weight_fn` |
| What the players are told | `DotVoteDirector.announce_fn` |
| Whether this addon changes anything at all | `DotVoteDirector.auto_apply`, or a source with no apply |
| Command names | `DotVoteCommands.prefix` / `names` |
| How a command context becomes a voter | `DotVoteCommands.voter_fn` |

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
- **Nothing draws, announces or counts down on its own.** `announce_fn` takes a
  string. What a server says, and where, is not this addon's opinion.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/vote_selftest.tscn
```

231 checks, non-zero on failure. Three sections matter more than the rest:

- **"Every setting is read by something"** runs this family's own mechanical detector
  over `DotVoteRules` — 55 settings in one resource is either this addon's best
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
