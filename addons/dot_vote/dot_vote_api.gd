extends RefCounted

## dot-vote's API level; the bumping rule is on [DotAddonApi].
## LEVEL rises for anything new a game could call; OLDEST is raised when something callable is removed or changes meaning.

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
# 9: DotVoteBallotFeed.describe() and DotVoteCommands.describe().
# 10: DotVoteListSource.follow_content(index, accepted_kinds) and DotVoteChoice.pack_title and
#     label() ("Name [Pack]"), which every ballot, menu and message prints.
# 11: DotVoteCommands names that take lists (aliases), spec_fn, chat_prefix, skipped, typed;
#     DotVoteGameSource.order; DotVoteMapSource skips maps outside the rotation. Needs dot-core
#     API level 12 (DotCommandNames).
# 12: DotVoteListSource.in_rotation_fn and rotation_order_fn: the rotation filter and order
#     apply to every choice, the maps merged by follow_content included.
# 13: DotVoteRules.apply_cfg_file and load_cfg read cfg/addons/dot_vote/<file>.yml and the
#     operator's cfg/server/addons/dot_vote/, with the flat cfg/<file>.yml as a shim.
#     Needs dot-core API level 16 (DotAddonConfig.apply_file).
const LEVEL := 14
const OLDEST := 1
