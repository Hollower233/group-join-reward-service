-- GroupJoinRewardService: prompt the experience's owner group, verify membership on the server, and grant one reward.
-- The reward and persistence details are supplied by server.init, so this package stays game-agnostic.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")

local Net = require(script.Parent:WaitForChild("Net"))

local requestFunction = Net:RemoteFunction("GroupJoinRewardRequest")
local claimedFunction = Net:RemoteFunction("GroupJoinRewardHasClaimed")

export type RequestResult = {
	ok: boolean,
	reason: string?,
	results: any?,
}

type InitOptions = {
	hasClaimed: (player: Player) -> boolean,
	markClaimed: (player: Player) -> (),
	grantReward: (player: Player) -> RequestResult,
}

local options: InitOptions? = nil
local pendingPlayers: { [Player]: boolean } = {}

local function serverHandleRequest(player: Player): RequestResult
	if not options then
		return { ok = false, reason = "not_initialized" }
	end
	if pendingPlayers[player] then
		return { ok = false, reason = "pending" }
	end
	if options.hasClaimed(player) then
		return { ok = false, reason = "already_claimed" }
	end

	pendingPlayers[player] = true

	local verifyOk, isInGroup = pcall(function()
		return player:IsInGroupAsync(game.CreatorId)
	end)
	if not verifyOk or not isInGroup then
		pendingPlayers[player] = nil
		return { ok = false, reason = "not_in_group" }
	end

	if options.hasClaimed(player) then
		pendingPlayers[player] = nil
		return { ok = false, reason = "already_claimed" }
	end

	local grantOk, result = pcall(options.grantReward, player)
	if not grantOk then
		warn(`[GroupJoinRewardService] Reward callback failed: {result}`)
		pendingPlayers[player] = nil
		return { ok = false, reason = "error" }
	end
	if typeof(result) ~= "table" or result.ok ~= true then
		local reason = if typeof(result) == "table" then result.reason else nil
		warn(`[GroupJoinRewardService] Reward was not granted: {reason}`)
		pendingPlayers[player] = nil
		return { ok = false, reason = reason or "error" }
	end

	options.markClaimed(player)
	pendingPlayers[player] = nil
	return { ok = true, results = result.results }
end

if RunService:IsServer() then
	requestFunction.OnServerInvoke = function(player: Player)
		local ok, result = pcall(serverHandleRequest, player)
		if not ok then
			warn(`[GroupJoinRewardService] Request failed: {result}`)
			pendingPlayers[player] = nil
			return { ok = false, reason = "error" }
		end
		return result
	end

	claimedFunction.OnServerInvoke = function(player: Player)
		if not options then
			return false
		end
		local ok, claimed = pcall(options.hasClaimed, player)
		return ok and claimed == true
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		pendingPlayers[player] = nil
	end)
end

local function initServer(config: InitOptions)
	options = config
end

local function clientRequest(): RequestResult
	local promptOk, status = pcall(function()
		return GroupService:PromptJoinAsync(game.CreatorId)
	end)
	if not promptOk then
		warn(`[GroupJoinRewardService] Group prompt failed: {status}`)
		return { ok = false, reason = "prompt_failed" }
	end
	if status ~= Enum.GroupMembershipStatus.Joined and status ~= Enum.GroupMembershipStatus.AlreadyMember then
		return { ok = false, reason = "not_joined" }
	end

	local requestOk, result = pcall(function()
		return requestFunction:InvokeServer()
	end)
	if not requestOk then
		warn(`[GroupJoinRewardService] Claim request failed: {result}`)
		return { ok = false, reason = "request_failed" }
	end
	return result
end

local function clientHasClaimed(): boolean
	local ok, claimed = pcall(function()
		return claimedFunction:InvokeServer()
	end)
	if not ok then
		warn(`[GroupJoinRewardService] Claim-status request failed: {claimed}`)
		return false
	end
	return claimed == true
end

return {
	server = {
		init = initServer,
	},
	client = {
		request = clientRequest,
		hasClaimed = clientHasClaimed,
	},
}
