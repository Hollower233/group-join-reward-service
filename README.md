# Group Join Reward Service

A shared Wally package for a one-time reward after a player joins the Roblox group that owns the experience. The package prompts from the client, but independently verifies membership on the server before awarding anything.

## Installation

```toml
[dependencies]
GroupJoinRewardService = "hollower233/group-join-reward-service@0.1.0"
```

Run `wally install`, then require the package from your generated `Packages` folder.

## Server setup

Call `server.init` exactly once during server startup. The three callbacks connect the package to your persistence and reward systems.

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local GroupJoinRewardService = require(Packages:WaitForChild("GroupJoinRewardService"))

GroupJoinRewardService.server.init({
	hasClaimed = function(player)
		return false -- Read your saved one-time-reward flag.
	end,
	markClaimed = function(player)
		-- Persist the one-time-reward flag.
	end,
	grantReward = function(player)
		-- Grant your currency, item, or cosmetic here.
		return {
			ok = true,
			results = { rewardType = "coins", amount = 500 },
		}
	end,
})
```

`grantReward` must return `{ ok = true, results = ... }` after successfully granting the reward. Return `{ ok = false, reason = "..." }` when it cannot award the reward; the package will not mark the player as claimed.

## Client usage

```lua
if not GroupJoinRewardService.client.hasClaimed() then
	local result = GroupJoinRewardService.client.request()
	if result.ok then
		print("Reward granted", result.results)
	end
end
```

`client.request()` uses `GroupService:PromptJoinAsync(game.CreatorId)`. Therefore, publish the experience under the Roblox group whose membership should be rewarded.

## Result reasons

- `not_initialized`: The server did not call `server.init`.
- `pending`: Another claim request for this player is being processed.
- `already_claimed`: The persistence callback reports that the player already claimed the reward.
- `not_joined`: The player closed, declined, or could not complete the group prompt.
- `not_in_group`: The server could not verify group membership.
- `prompt_failed` or `request_failed`: Roblox prompt or remote communication failed.
- `error`: A callback raised an error or returned an invalid result.

## License

MIT. See [LICENSE](LICENSE).
