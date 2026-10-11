extends RefCounted

## dot-vote's API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed (an absent file reads as 1).
# 2: DotVoteListSource.entries_fn and refresh(), DotVoteSource.before_ballot(); a passed
#    rock-the-vote opens its ballot under trigger MANUAL.
# 3: DotVoteDirector.round_in_progress_fn; finish_round holds nothing while no round is live.
# 4: DotVoteDirector.people_fn and display_name(); lines about a player name them, not
#    their id; DotVoteBallotFeed.people_fn is handed to a director that has none.
const LEVEL := 4
const OLDEST := 1
