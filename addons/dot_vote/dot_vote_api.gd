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
# 5: the map menu's server half: DotVoteMapMenu (`mapmenu`, `sv_map_menu_flag`, change_fn,
#    rows_fn, notice_fn), DotVoteCommands.map_menu and with_map_menu.
# 6: DotVoteMapMenu.unavailable_text(); a source's optional unavailable_reason(id) says why
#    the menu refuses an id it does not offer now.
# 7: the map menu fails closed and counts humans: sv_map_menu_flag empty is staff and
#    `anyone` is everybody; sv_map_menu_alone (the only human may change directly) and
#    sv_map_menu_vote_min (humans before a menu choice rocks the vote); DotVoteMapMenu
#    humans_fn, humans(), is_staff(), is_alone(), alone_allowed(), min_voters(); the
#    listen host's own (local) session may change; an offer carries `alone`.
# 8: votebans: DotVoteBans (start(starter, target, reason), vote, advance, the voteban,
#    voteban_yes and voteban_no commands) and DotVoteBanRules (the sv_voteban* cvars).
const LEVEL := 8
const OLDEST := 1
