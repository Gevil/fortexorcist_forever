# Shared quest reward currency projection into the original panel

Retail/Forever C_QuestInfoSystem.GetQuestRewardCurrencies reads existing
currency_rewards through the same serializer as C_QuestLog. Source:
`src/c_api/quest_reward_currencies.rs`. [Architecture](../wiki/systems/lua-api.md#original-reward-currency-rows)
and [execution receipt](../baselines/quest-lifecycle.md) own implementation/proof.

## What it must do

- [x] A supplied1166/5 record reaches actual original reward currency rows; name/count
  and currencyInfo, not just function callability, are observable.
- [x] Original CurrencyContainerUtil displays the exact modeled `Timewarped Badge`
  label/count5 while currencyInfo retains the explicitly supplied name and amount.
- [x] Both quest namespaces expose the same supplied record, without another store;
  nullable selected context works and absent context permits no result.
- [x] The original rewards frame remains hidden without supplied rewards.

Cached QuestInfoSystemDocumentation.lua:58-72 declares AllowedWhenUntainted,
nullable questID and MayReturnNothing; QuestLogDocumentation.lua:493-506 requires ID.
Authenticate/unwrap the original argument before validation. Authored nil-context
policy uses selected_quest_log_id; an absent/unrepresentable context returns nothing.
An explicit representable ID retains the existing list projection's empty miss.
Existing represented fields/optional base amount are unchanged; quality/bonus/context
metadata absent from the record are not invented. Native context/schema parity is separate.

## How it works

- [Reward projection](../wiki/systems/lua-api.md#original-reward-currency-rows)
- [QL-2](quest-readiness-dialog.md)

## Implementation inventory

- `src/c_api/quest_reward_currencies.rs`: cross-profile wrapper and shared serializer.
- `src/c_api/mod.rs`, `globals/register.rs`: Retail/Forever registration.
- `globals/quest_surface/handlers.rs`: C_QuestLog delegates to that same projection.

## Tests asserting this spec

`tests/quest_reward_currency_panel.rs` calls original QuestInfo_ShowRewards with
explicit existing reward-frame context. Original Mainline/QuestInfo.lua:608,963-975
reads the namespace and builds currency rows. FrameXMLUtil/CurrencyContainer.lua:3-9
owns the modeled container display override.

Historical empty control passed while supplied row was absent (actual RED). After
publication the row appeared; the first oracle incorrectly expected its raw name.
Corrected tests require the exact modeled container label and preserved raw metadata,
plus both namespaces and nullable/no-context behavior. Saved GREEN/latest-base status
are distinct in the execution receipt.

## Known gaps (current cycle)

- [ ] Close the latest-base quest/startup/B5 gate in the execution receipt.

## Out of scope

New reward stores, acquisition/grants, reward-spell modeling, complete native reward
metadata, automatic panel scheduling, pixels and all-profile acceptance.
