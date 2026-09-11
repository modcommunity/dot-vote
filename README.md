
An asset that allows users to vote for what plays next — games, maps or modes — and every part of it is a setting.

Rock the vote, nominations, per-choice time limits, a ballot, and the change at the end of it. The shape every server in this genre has had since 2005 (`rtv`, `nominate`, `mapchooser`, `timeleft`, `extend`), rebuilt so that a community that wants it to work differently changes a number rather than forking it.

```gdscript
var votes := DotVoteDirector.new()
votes.rules = DotVoteRules.new()
votes.source = DotVoteGameSource.of(server.games)   # or a map catalogue, or your own
votes.player_count_fn = func() -> int: return players.size()
add_child(votes)

votes.begin(&"lobby")        # what is running now

# once per tick
votes.advance(delta)
```

That is the whole integration. Everything else is configuration.

## What it does

| | |
| --- | --- |
| **Rock the vote** | A fraction of the players, with a minimum player count, a delay at the start of every map, idempotent per player, and votes withdrawn when their owner disconnects. |
| **Nominations** | Per-player caps, a total cap, seconding (so "most nominated" means something), admin bypass, and reserved places on the ballot so three organised players cannot decide every map. |
| **Time limits** | In seconds, in rounds, or both — **per choice**, so a forty-minute surf map and a ten-minute bhop map are not forced under one number. Multiple warnings, extending with a cap. |
| **The ballot** | Up to N options, filled five ways, with "extend" and "none of these" as options a server can turn on or off. Opens a configurable lead time *before* the map ends, so the change happens on time. |
| **Counting** | Plurality, approval, instant runoff, or a majority runoff. Quorums, weighted ballots, and five tie-breaks — four of which a player watching can predict. |
| **Cooldowns** | In plays or in wall-clock minutes, per choice, clamped against the pool so a long cooldown on a short rotation cannot exclude everything. |
| **Applying** | Immediately, at the end of the round, or when the clock runs out — with a delay so players can read the result. |
| **Commands** | `nominate`, `rtv`, `votefor`, `timeleft`, `nextmap`, `revote`, `extend`, `endvote`, and more, on a dot-server console and in chat. Every name configurable. |

## The pieces

| | |
| --- | --- |
| `DotVoteRules` | Every policy decision, as one `DotConfig`. Layers `defaults < file < DOT_VOTE_* < --vote-*`, and enum settings are written **by name** (`method: instant_runoff`). |
| `DotVoteChoice` | One thing that can be voted for: an id, a name, and the few facts a ballot needs — player counts, its own time limit, its own cooldown, its weight. |
| `DotVoteSource` | Where the choices come from and what "play this" means. The one seam. |
| `DotVoteDirector` | The `Node` that joins them, driven by one `advance(delta)` per tick. |
| `DotVoteClock` | The limit, the warnings, the extends and the rock-the-vote. |
| `DotVoteBallot` | The open ballot and the four counting methods. |
| `DotVoteNominations` | What players have asked for, in order. |
| `DotVoteHistory` | What has been played, and what is still on cooldown. |
| `DotVoteResult` | What was decided, and **how** — including which tie-break, so the announcement can explain itself. |

## Pointing it at something

Three sources ship with it, and none of them names a class outside dot-core:

```gdscript
DotVoteGameSource.of(server.games)          # dot-server's games
DotVoteMapSource.of(catalogue, session)     # dot-map's maps
DotVoteListSource.of(my_choices)            # anything else, with a Callable
```

The two integrations are duck-typed, so this addon installs in a project that has never heard of dot-server or dot-map. Per-choice settings live in the thing's own metadata, so a game's time limit is written beside the game:

```yaml
# content/arena/game.yml
metadata:
  vote:
    time_limit_sec: 2400
    weight: 2.0
```

A source that cannot change anything is legitimate: the director runs the whole vote and emits `change_due` for the host to act on, which is what a client mirroring a server's ballot does.

## Configuring it

```yaml
trigger: time_limit
duration_sec: 1800
vote_lead_sec: 120           # the ballot opens two minutes before the end
warn_at_sec: "300,60,30"

rtv_fraction: 0.6
rtv_min_players: 2
rtv_delay_sec: 120           # no rtv in the first two minutes

max_options: 6
nomination_slots: 4
fill: least_recently_played
method: instant_runoff
tie_break: nomination_order
quorum: 0.4
on_no_quorum: keep

cooldown: 5
apply: end_of_round
apply_delay_sec: 5
```

Fifty-five settings, and the self-test fails if any one of them is read by nothing.

## Validating it

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/vote_selftest.tscn
```

231 checks. The last two sections run this addon against a real `DotGameManager` and a real `DotMapCatalogue` and change what they are running, because "the two ends have never met" is how the expensive bugs in this family start.

## Dependencies

**dot-core**, and nothing else. dot-server and dot-map are optional and are reached by duck typing.

```bash
ln -s ../../dot-core/addons/dot_core addons/dot_core

# optional, and only so the self-test can run the integrations for real
ln -s ../../dot-map/addons/dot_map addons/dot_map
ln -s ../../dot-server/addons/dot_server addons/dot_server
```
