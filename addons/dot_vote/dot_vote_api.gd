extends RefCounted

## dot-vote's API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed (an absent file reads as 1).
# 2: DotVoteListSource.entries_fn and refresh(), DotVoteSource.before_ballot(); a passed
#    rock-the-vote opens its ballot under trigger MANUAL.
const LEVEL := 2
const OLDEST := 1
