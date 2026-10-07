-- Auto Simon for Death Order Game
-- Listens to the Warden's announcements and only acts when it's really "SIMON SAYS"
-- (plus the mandatory "return to cell" orders, which have no Simon version).
-- Re-running this script replaces the previous instance. Set getgenv().AutoSimon = false to stop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VIM = game:GetService("VirtualInputManager")

local env = getgenv and getgenv() or _G
if env.AutoSimonConns then
	for _, c in ipairs(env.AutoSimonConns) do pcall(function() c:Disconnect() end) end
end
env.AutoSimonConns = {}
if env.AutoSimon == nil then env.AutoSimon = true end

-- settings survive re-running the script
local settings = env.AutoSimonSettings or {
	delay = 0.35, -- small human-ish delay before acting
	groups = { basic = true, seat = true, places = true, cell = true, colour = true },
}
env.AutoSimonSettings = settings

local LP = Players.LocalPlayer
local Simon = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Simon")
local WardenAnnounce = Simon:WaitForChild("WardenAnnounce")
local WindowClose = Simon:WaitForChild("WindowClose", 3) -- missing in the lobby

local logHook -- set by the GUI
local function log(...)
	print("[AutoSimon]", ...)
	if logHook then
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		pcall(logHook, table.concat(parts, " "))
	end
end

local function hum()
	local c = LP.Character
	return c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
end

local function keyFromAttr(attr, default)
	local v = LP:GetAttribute(attr)
	if type(v) == "string" then
		local ok, k = pcall(function() return Enum.KeyCode[v] end)
		if ok and k then return k end
	end
	return default
end

local function press(key, down)
	VIM:SendKeyEvent(down, key, false, game)
end

local function tp(pos)
	local h, root = hum()
	if not root then return end
	if h and h.Sit then h.Sit = false end
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.new(pos)
end

local function cellNum()
	return tonumber(LP:GetAttribute("AssignedCell"))
end

local function nearest(list, getPos)
	local _, root = hum()
	if not root then return end
	local best, bestDist
	for _, v in ipairs(list) do
		local p = getPos(v)
		if p then
			local d = (p - root.Position).Magnitude
			if not bestDist or d < bestDist then best, bestDist = v, d end
		end
	end
	return best
end

local function firePrompt(prompt)
	if not prompt then return false end
	local _, root = hum()
	local part = prompt.Parent
	local pos = part:IsA("BasePart") and part.Position or (part:IsA("Attachment") and part.WorldPosition)
	if root and pos and (pos - root.Position).Magnitude > prompt.MaxActivationDistance - 1 then
		local flat = (root.Position - pos) * Vector3.new(1, 0, 1)
		local dir = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(1, 0, 0)
		tp(pos + Vector3.new(0, 1, 0) + dir * 3)
		task.wait(0.15)
	end
	if fireproximityprompt then
		fireproximityprompt(prompt)
	else
		prompt:InputHoldBegin()
		task.wait(prompt.HoldDuration + 0.05)
		prompt:InputHoldEnd()
	end
	return true
end

-- cleanup actions to run when the command window closes
local cleanup = {}
local function onCleanup(fn) table.insert(cleanup, fn) end
local function runCleanup()
	for _, fn in ipairs(cleanup) do pcall(fn) end
	table.clear(cleanup)
end

local actions = {}

---------------------------------------------------------------- simple actions
actions.jump = function()
	local h = hum()
	if not h then return end
	for _ = 1, 3 do
		h:ChangeState(Enum.HumanoidStateType.Jumping)
		h.Jump = true
		task.wait(0.6)
	end
end

actions.crouch = function()
	local bus = require(ReplicatedStorage.Modules.SharedBus)
	if bus.SetCrouched then
		bus.SetCrouched(true)
		onCleanup(function() bus.SetCrouched(false) end)
	else
		local k = keyFromAttr("KeybindCrouch", Enum.KeyCode.C)
		press(k, true)
		onCleanup(function() press(k, false) end)
	end
end

actions.sit = function()
	local h, root = hum()
	if not (h and root) or h.Sit then return end
	local seats = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Seat") and not d.Occupant and not d.Disabled then table.insert(seats, d) end
	end
	local best = nearest(seats, function(s) return s.Position end)
	if not best then log("no free seat found") return end
	root.CFrame = best.CFrame + Vector3.new(0, 2.5, 0)
	task.wait(0.1)
	pcall(function() best:Sit(h) end)
	onCleanup(function()
		local hh = hum()
		if hh and hh.Sit then hh.Sit = false; hh.Jump = true end
	end)
end

actions.dance = function()
	local k = keyFromAttr("KeybindEmote", Enum.KeyCode.B)
	press(k, true)
	task.wait(0.1)
	press(k, false)
end

actions.sprint = function()
	local k = keyFromAttr("KeybindSprint", Enum.KeyCode.LeftShift)
	press(k, true)
	onCleanup(function() press(k, false) end)
end

actions.still = function()
	local h, root = hum()
	if not (h and root) then return end
	local oldWS, oldJP = h.WalkSpeed, h.JumpPower
	h.WalkSpeed = 0
	h.JumpPower = 0
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = true
	onCleanup(function()
		root.Anchored = false
		h.WalkSpeed = oldWS
		h.JumpPower = oldJP
	end)
end

actions.fight = function()
	local h = hum()
	local char = LP.Character
	if not (h and char) then return end
	local fists = char:FindFirstChild("Fists") or LP.Backpack:FindFirstChild("Fists")
	if not fists then log("no Fists tool") return end
	if fists.Parent ~= char then h:EquipTool(fists) task.wait(0.15) end
	local remote = fists:FindFirstChild("fistremote")
	for _ = 1, 4 do
		if remote then remote:FireServer("lmb") else fists:Activate() end
		task.wait(0.45)
	end
end

---------------------------------------------------------------- location actions
local function marker(name)
	local p = workspace:FindFirstChild(name)
	return p and p:IsA("BasePart") and p.Position
end

actions.floor1 = function()
	local p = marker("1stfloor") if p then tp(p + Vector3.new(0, 3, 0)) end
end

actions.floor2 = function()
	local p = marker("2ndfloor") if p then tp(p + Vector3.new(0, 3, 0)) end
end

actions.cafeteria = function()
	local p = marker("3rdfloor") if p then tp(p + Vector3.new(0, 3, 0)) end
end

actions.basement = function()
	local z = workspace:FindFirstChild("BasementZone")
	if z then tp(z.Position - Vector3.new(0, z.Size.Y / 2 - 4, 0)) end
end

actions.tables = function()
	local folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Tables")
	if not folder then return end
	local list = {}
	for _, t in ipairs(folder:GetChildren()) do
		if t:IsA("Model") or t:IsA("BasePart") then table.insert(list, t) end
	end
	local best = nearest(list, function(t) return (t:IsA("Model") and t:GetPivot() or t.CFrame).Position end)
	if not best then return end
	local cf, size
	if best:IsA("Model") then cf, size = best:GetBoundingBox() else cf, size = best.CFrame, best.Size end
	tp(cf.Position + Vector3.new(0, size.Y / 2 + 3, 0))
end

actions.climb = function()
	local h, root = hum()
	if not (h and root) then return end
	local trusses = {}
	for _, l in ipairs(workspace.Ladders:GetChildren()) do
		if not l.Name:find("Trial") then
			for _, d in ipairs(l:GetDescendants()) do
				if d:IsA("TrussPart") then table.insert(trusses, d) end
			end
		end
	end
	local truss = nearest(trusses, function(t) return t.Position end)
	if not truss then log("no ladder found") return end
	local flat = (root.Position - truss.Position) * Vector3.new(1, 0, 1)
	local dir = flat.Magnitude > 0.1 and flat.Unit or truss.CFrame.LookVector
	local bottom = truss.Position - Vector3.new(0, truss.Size.Y / 2 - 3, 0)
	local stand = bottom + dir * (math.min(truss.Size.X, truss.Size.Z) / 2 + 1.2)
	root.CFrame = CFrame.lookAt(stand, Vector3.new(bottom.X, stand.Y, bottom.Z))
	task.wait(0.1)
	press(Enum.KeyCode.W, true)
	local t0 = tick()
	while tick() - t0 < 3 do
		h:Move(-dir, false)
		task.wait()
	end
	press(Enum.KeyCode.W, false)
end

actions.stairs = function()
	local h = hum()
	local stair = workspace.Map.Structure.Architecture:FindFirstChild("Stair")
	local b = stair and stair:FindFirstChild("StairBottom")
	local t = stair and stair:FindFirstChild("StairTop")
	if not (h and b and t) then log("no stairs found") return end
	tp(b.WorldPosition + Vector3.new(0, 3, 0))
	task.wait(0.1)
	h:MoveTo(t.WorldPosition)
	h.MoveToFinished:Wait()
end

actions.line = function()
	local lines = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:upper():find("LINE") and not d.Name:upper():find("GLOW") then
			table.insert(lines, d)
		end
	end
	local best = nearest(lines, function(p) return p.Position end)
	if best then tp(best.Position + Vector3.new(0, 3, 0)) end
end

local function nearestCircle()
	local list = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == "InnerCylinder" and d:IsA("BasePart") then table.insert(list, d) end
	end
	return nearest(list, function(p) return p.Position end)
end

actions.circleStay = function()
	local c = nearestCircle()
	if c then tp(c.Position + Vector3.new(0, 3, 0)) end
end

actions.circleLeave = function()
	local c = nearestCircle()
	local _, root = hum()
	if not (c and root) then return end
	local r = c.Size.X / 2
	local flat = (root.Position - c.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude > r + 2 then return end -- already outside
	local dir = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(1, 0, 0)
	tp(c.Position + dir * (r + 6) + Vector3.new(0, 3, 0))
end

local function cellLightOn()
	local n = cellNum()
	local lights = workspace.Map.Lighting:FindFirstChild("CeilingLights")
	local m = n and lights and lights:FindFirstChild(string.format("CeilingLight_%02d", n))
	local pl = m and m:FindFirstChildWhichIsA("PointLight", true)
	if pl then return pl.Enabled end
	return nil
end

local function lightPrompt()
	local n = cellNum()
	if not n then return end
	for _, d in ipairs(workspace.LightSwitches:GetDescendants()) do
		if d:IsA("ProximityPrompt") and tonumber(d:GetAttribute("CellNumber")) == n then return d end
	end
end

actions.lightOn = function()
	if cellLightOn() == true then log("light already on") return end
	firePrompt(lightPrompt())
end

actions.lightOff = function()
	if cellLightOn() == false then log("light already off") return end
	firePrompt(lightPrompt())
end

actions.lightToggle = function()
	firePrompt(lightPrompt())
end

local function gatePrompt()
	local n = cellNum()
	local anchors = workspace.Map.Gates:FindFirstChild("GatePromptAnchors")
	local a = n and anchors and anchors:FindFirstChild(string.format("Anchor_Gate_%02d", n))
	return a and a:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function gate(wantWord)
	local pp = gatePrompt()
	if not pp then log("no gate prompt") return end
	local t0 = tick()
	while not pp.Enabled and tick() - t0 < 2 do task.wait(0.1) end
	if not pp.ActionText:upper():find(wantWord) then
		log("gate already done (" .. pp.ActionText .. ")")
		return
	end
	firePrompt(pp)
end

actions.gateOpen = function() gate("OPEN") end
actions.gateClose = function() gate("CLOSE") end

local function myBedPrompt()
	local n = cellNum()
	local beds = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("CellProps") and workspace.Map.CellProps:FindFirstChild("Beds")
	if not (n and beds) then return end
	for _, b in ipairs(beds:GetChildren()) do
		if tonumber(b.Name:match("Bed_(%d+)")) == n then
			return b:FindFirstChild("BedSleepPrompt", true)
		end
	end
end

actions.bed = function()
	if LP:GetAttribute("IsSleeping") == true then return end
	local pp = myBedPrompt()
	if not pp then log("no bed found for cell", tostring(cellNum())) return end
	pp.Enabled = true
	firePrompt(pp)
	onCleanup(function()
		if LP:GetAttribute("IsSleeping") == true then
			local wake = ReplicatedStorage.Remotes.Game:FindFirstChild("WakeFromBed")
			if wake then wake:FireServer() end
		end
	end)
end

actions.toCell = function()
	local n = cellNum()
	local s = n and workspace.Spawns:FindFirstChild(string.format("Spawn_%02d", n))
	if s then tp(s.Position + Vector3.new(0, 3, 0)) end
end

---------------------------------------------------------------- colour drop
local PALETTE = {
	RED = Color3.fromRGB(190, 48, 42),
	BLUE = Color3.fromRGB(40, 92, 200),
	GREEN = Color3.fromRGB(48, 150, 66),
	YELLOW = Color3.fromRGB(255, 135, 0),
}

local function colourOf(tile)
	local c, best, bestD = tile.Color, nil, math.huge
	for name, p in pairs(PALETTE) do
		local d = (c.R - p.R) ^ 2 + (c.G - p.G) ^ 2 + (c.B - p.B) ^ 2
		if d < bestD then best, bestD = name, d end
	end
	return bestD <= 0.05 and best or nil
end

local function crackedSet()
	local set = {}
	local fx = workspace:FindFirstChild("ColorDropLocalFX")
	if fx then
		for _, d in ipairs(fx:GetChildren()) do
			if d:IsA("SelectionBox") and d.Adornee then set[d.Adornee] = true end
		end
	end
	return set
end

local function colourTiles(filter)
	local arena = workspace:FindFirstChild("ColorDropArena")
	local tiles = arena and arena:FindFirstChild("Tiles")
	if not tiles then return {} end
	local cracked = crackedSet()
	local out = {}
	for _, t in ipairs(tiles:GetChildren()) do
		if t:IsA("BasePart") and t.CanCollide and t.Transparency < 0.5 and not cracked[t] and filter(colourOf(t)) then
			table.insert(out, t)
		end
	end
	return out
end

local function tileUnderMe()
	local _, root = hum()
	if not root then return end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LP.Character }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
	return hit and hit.Instance
end

local function goToTile(list)
	local t = nearest(list, function(p) return p.Position end)
	if t then tp(t.Position + Vector3.new(0, t.Size.Y / 2 + 3, 0)) return true end
end

local safeColour

local function getOnColour(colour)
	safeColour = colour
	local t0 = tick()
	repeat
		local under = tileUnderMe()
		if under and under.Parent and under.Parent.Name == "Tiles" and colourOf(under) == colour and not crackedSet()[under] then
			return -- already standing on it
		end
		if goToTile(colourTiles(function(c) return c == colour end)) then return end
		task.wait(0.15)
	until tick() - t0 > 2
	log("no", colour, "tile found")
end

local function avoidColour(colour)
	local under = tileUnderMe()
	if not (under and colourOf(under) == colour) then return end
	if safeColour and safeColour ~= colour and goToTile(colourTiles(function(c) return c == safeColour end)) then return end
	goToTile(colourTiles(function(c) return c and c ~= colour end))
end

local function colourInText(up)
	if not workspace:FindFirstChild("ColorDropArena") then return end
	for name in pairs(PALETTE) do
		if up:find("%f[%a]" .. name .. "%f[%A]") then return name end
	end
end

---------------------------------------------------------------- command matching
-- order matters: more specific phrases first
local patterns = {
	{ "DON'T MOVE", "still" },
	{ "DONT MOVE", "still" },
	{ "FREEZE", "still" },
	{ "BED", "bed" },
	{ "SLEEP", "bed" },
	{ "LEAVE CIRCLE", "circleLeave" },
	{ "LEAVE THE CIRCLE", "circleLeave" },
	{ "CIRCLE", "circleStay" },
	{ "1ST FLOOR", "floor1" },
	{ "FIRST FLOOR", "floor1" },
	{ "2ND FLOOR", "floor2" },
	{ "SECOND FLOOR", "floor2" },
	{ "CAFETERIA", "cafeteria" },
	{ "BASEMENT", "basement" },
	{ "TABLE", "tables" },
	{ "STAIR", "stairs" },
	{ "CLIMB", "climb" },
	{ "LADDER", "climb" },
	{ "CLOSE", "gateClose" }, -- "CLOSE YOUR GATE"
	{ "GATE", "gateOpen" },
	{ "LIGHTS ON", "lightOn" },
	{ "LIGHT ON", "lightOn" },
	{ "LIGHTS OFF", "lightOff" },
	{ "LIGHT OFF", "lightOff" },
	{ "LIGHT", "lightToggle" },
	{ "LINE", "line" },
	{ "FIGHT", "fight" },
	{ "PUNCH", "fight" },
	{ "SEAT", "sit" },
	{ " SIT", "sit" },
	{ "CROUCH", "crouch" },
	{ "DANCE", "dance" },
	{ "SPRINT", "sprint" },
	{ "JUMP", "jump" },
}

-- orders that must always be obeyed (no Simon version exists)
local mandatory = {
	{ "RETURN TO", "toCell" },
	{ "GO TO CELL", "toCell" },
	{ "GO TO YOUR CELL", "toCell" },
}

-- which GUI category each action belongs to
local actionGroup = {
	jump = "basic", crouch = "basic", dance = "basic", sprint = "basic", still = "basic", fight = "basic",
	sit = "seat",
	floor1 = "places", floor2 = "places", cafeteria = "places", basement = "places", tables = "places",
	stairs = "places", climb = "places", line = "places", circleStay = "places", circleLeave = "places",
	bed = "cell", gateOpen = "cell", gateClose = "cell", lightOn = "cell", lightOff = "cell", lightToggle = "cell", toCell = "cell",
}

local function run(name, text)
	local group = actionGroup[name]
	if group and not settings.groups[group] then
		log("skipped (" .. group .. " off):", text)
		return
	end
	log("doing", name, "for:", text)
	task.delay(settings.delay, function()
		local ok, err = pcall(actions[name])
		if not ok then log("error:", err) end
	end)
end

local lastText
table.insert(env.AutoSimonConns, WardenAnnounce.OnClientEvent:Connect(function(text, isSimon)
	if not env.AutoSimon then return end
	if type(text) ~= "string" or text == "" or text == lastText then return end
	lastText = text
	if LP:GetAttribute("IsEliminated") then return end
	local up = text:upper()

	for _, p in ipairs(mandatory) do
		if up:find(p[1], 1, true) then return run(p[2], text) end
	end

	local simon = isSimon == true and up:sub(1, 10) == "SIMON SAYS"

	local colour = colourInText(up)
	if colour then
		if not settings.groups.colour then log("skipped (colour off):", text) return end
		log(simon and "colour" or "TRAP colour (avoiding)", colour)
		task.delay(simon and settings.delay or 0.05, function()
			local ok, err = pcall(simon and getOnColour or avoidColour, colour)
			if not ok then log("error:", err) end
		end)
		return
	end

	if not simon then
		log("TRAP (ignored):", text)
		return
	end
	for _, p in ipairs(patterns) do
		if up:find(p[1], 1, true) then return run(p[2], text) end
	end
	log("no auto action for:", text)
end))

if WindowClose then
	table.insert(env.AutoSimonConns, WindowClose.OnClientEvent:Connect(function()
		lastText = nil
		runCleanup()
	end))
end

env.AutoSimonActions = actions -- for manual testing: getgenv().AutoSimonActions.tables()

---------------------------------------------------------------- mine ESP
-- The server sends the full mine layout to every client ("layout"), then "spent" per mine and "clear".
if settings.groups.mineEsp == nil then settings.groups.mineEsp = true end

local MINE_COLOUR = Color3.fromRGB(255, 40, 40)
local mineLayout, mines = nil, {} -- mines[id] = { armed, x, z }

local oldEsp = workspace:FindFirstChild("AutoSimonMineESP")
if oldEsp then oldEsp:Destroy() end
local espFolder = Instance.new("Folder")
espFolder.Name = "AutoSimonMineESP"
espFolder.Parent = workspace

local function drawMines()
	espFolder:ClearAllChildren()
	if not (settings.groups.mineEsp and mineLayout) then return end
	local y = (mineLayout.floorY or 100) + 0.15
	for id, m in pairs(mines) do
		if m.armed then
			local disc = Instance.new("Part")
			disc.Name = "Mine_" .. tostring(id)
			disc.Shape = Enum.PartType.Cylinder
			disc.Size = Vector3.new(0.1, 9, 9)
			disc.CFrame = CFrame.new(m.x, y, m.z) * CFrame.Angles(0, 0, math.pi / 2)
			disc.Material = Enum.Material.Neon
			disc.Color = MINE_COLOUR
			disc.Transparency = 0.45
			disc.Anchored, disc.CanCollide, disc.CanQuery, disc.CanTouch, disc.CastShadow = true, false, false, false, false
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.fromOffset(14, 14)
			bb.AlwaysOnTop = true
			bb.LightInfluence = 0
			bb.MaxDistance = 400
			local dot = Instance.new("Frame")
			dot.Size = UDim2.fromScale(1, 1)
			dot.BackgroundColor3 = MINE_COLOUR
			dot.BorderSizePixel = 0
			Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
			dot.Parent = bb
			bb.Parent = disc
			disc.Parent = espFolder
		end
	end
end

local function loadLayout(layout)
	mineLayout = layout
	mines = {}
	for _, m in ipairs(layout.mines or {}) do
		if type(m) == "table" and m[1] then mines[m[1]] = { armed = true, x = m[2], z = m[3] } end
	end
end

local MinefieldMines = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Game"):FindFirstChild("MinefieldMines")
if MinefieldMines then
	-- pick up a layout the game already received before this script ran
	pcall(function()
		for _, conn in ipairs(getconnections(MinefieldMines.OnClientEvent)) do
			local fn = conn.Function
			if fn then
				local layoutUv, minesUv
				for _, uv in pairs(debug.getupvalues(fn)) do
					if type(uv) == "table" then
						if type(uv.mines) == "table" then layoutUv = uv end
						local _, first = next(uv)
						if type(first) == "table" and first.armed ~= nil then minesUv = uv end
					end
				end
				if layoutUv then
					loadLayout(layoutUv)
					if minesUv then
						for id, m in pairs(minesUv) do
							if mines[id] then mines[id].armed = m.armed end
						end
					end
					log("mine ESP: picked up existing layout")
				end
			end
		end
	end)

	table.insert(env.AutoSimonConns, MinefieldMines.OnClientEvent:Connect(function(kind, data)
		if kind == "layout" and type(data) == "table" then
			loadLayout(data)
			local n = 0
			for _ in pairs(mines) do n += 1 end
			log("mine ESP: " .. n .. " mines")
			drawMines()
		elseif kind == "spent" then
			if mines[data] then mines[data].armed = false end
			drawMines()
		elseif kind == "clear" then
			mineLayout, mines = nil, {}
			drawMines()
		end
	end))
end

table.insert(env.AutoSimonConns, workspace:GetAttributeChangedSignal("MinefieldActive"):Connect(function()
	if workspace:GetAttribute("MinefieldActive") ~= true then
		mineLayout, mines = nil, {}
		drawMines()
	end
end))

drawMines()

-- for testing: getgenv().AutoSimonMineTest({ floorY = y, mines = { {1, x, z} } }) / AutoSimonMineTest(nil) to clear
env.AutoSimonMineTest = function(layout)
	if layout then loadLayout(layout) else mineLayout, mines = nil, {} end
	drawMines()
end

---------------------------------------------------------------- auto split second
-- Server sends TimeClock("begin", _, isSimon, startServerTime, buttonIdx, rate, ramp) and the client
-- answers TimeClock("press", serverTimestamp). The clock reading is dispOf(params, elapsed).
if settings.groups.splitSecond == nil then settings.groups.splitSecond = true end
settings.splitTarget = settings.splitTarget or 10
local splitAutoTarget -- target read from the round's text, overrides the manual one
local splitTargetChanged -- GUI hook

local function clockDisp(p, t)
	local rate = p.rate or 1
	local extra = (p.rate2 or rate) - rate
	local base = rate * t
	local a, b = p.rampA, p.rampB
	if extra ~= 0 and a and b and t > a then
		local span = b - a
		if t >= b then return base + extra * (span * 0.5 + (t - b)) end
		local u = (t - a) / span
		local u2 = u * u
		return base + extra * span * (u2 * u2 * (u2 - 3 * u + 2.5))
	end
	return base
end

local function solveElapsed(p, target)
	local lo, hi = 0, 120
	if clockDisp(p, hi) < target then return nil end
	for _ = 1, 60 do
		local mid = (lo + hi) / 2
		if clockDisp(p, mid) < target then lo = mid else hi = mid end
	end
	return hi
end

local function findTargetIn(text)
	if type(text) ~= "string" then return end
	local up = text:upper()
	if not (up:find("CLOCK") or up:find("STOP") or up:find("MARK") or up:find("TARGET") or up:find("AT ")) then return end
	local n = tonumber(up:match("(%d+%.%d+)") or up:match("AT (%d+)"))
	if n and n > 0 and n <= 16 then return n end
end

local function setAutoTarget(n, source)
	if n and n ~= splitAutoTarget then
		splitAutoTarget = n
		log(string.format("split second target %.2f (from %s)", n, source))
		if splitTargetChanged then pcall(splitTargetChanged) end
	end
end

local splitRound = 0
local TimeClock = ReplicatedStorage.Remotes:FindFirstChild("Game") and ReplicatedStorage.Remotes.Game:FindFirstChild("TimeClock")
if TimeClock then
	table.insert(env.AutoSimonConns, TimeClock.OnClientEvent:Connect(function(kind, a, b, c, d, e, f)
		if kind == "camera" and typeof(a) == "Instance" then
			-- look for the mark on the clock's boards
			for _, t in ipairs(a:GetDescendants()) do
				if t:IsA("TextLabel") and t.Name ~= "Digits" then
					local n = findTargetIn(t.Text)
					if n then setAutoTarget(n, "board") break end
				end
			end
		elseif kind == "sub" or kind == "notice" then
			setAutoTarget(findTargetIn(a) or findTargetIn(b), "notice")
		elseif kind == "end" then
			splitAutoTarget = nil
			if splitTargetChanged then pcall(splitTargetChanged) end
		elseif kind == "begin" then
			local t0 = os.clock()
			splitRound += 1
			local round = splitRound
			if not (env.AutoSimon and settings.groups.splitSecond) then return end
			if b ~= true then
				log("split second: Simon didn't say — not pressing")
				return
			end
			local params = { rate = type(e) == "number" and e or 1 }
			if type(f) == "table" then
				params.rate2, params.rampA, params.rampB = tonumber(f.r2), tonumber(f.a), tonumber(f.b)
			end
			local target = splitAutoTarget or settings.splitTarget
			local elapsed = solveElapsed(params, target)
			if not elapsed then log("split second: clock never reaches " .. target) return end
			local startServer = type(c) == "number" and c or nil
			log(string.format("split second: pressing at %.2f in %.3fs", target, elapsed))
			task.spawn(function()
				local RunService = game:GetService("RunService")
				while os.clock() - t0 < elapsed do
					if splitRound ~= round then return end
					local left = elapsed - (os.clock() - t0)
					if left > 0.05 then task.wait(left - 0.04) else RunService.Heartbeat:Wait() end
				end
				if splitRound ~= round or not env.AutoSimon then return end
				local stamp = startServer and (startServer + elapsed) or workspace:GetServerTimeNow()
				TimeClock:FireServer("press", stamp)
			end)
		elseif kind == "result" then
			if b ~= nil then log(string.format("split second result: %.2f (%.2f off)", tonumber(a) or 0, tonumber(b) or 0)) end
		end
	end))
end

table.insert(env.AutoSimonConns, WardenAnnounce.OnClientEvent:Connect(function(text)
	if workspace:GetAttribute("TimeClockActive") == true then setAutoTarget(findTargetIn(text), "Warden") end
end))

---------------------------------------------------------------- auto seeker
-- Hide & seek: the seeker has HuntSeeker / HideSeekSeeker, the hunt runs while workspace.SeekHuntActive.
-- There is no tag remote — catches are server-side proximity, so we sit on each hider until they're eliminated.
if settings.groups.seeker == nil then settings.groups.seeker = true end

local RunService = game:GetService("RunService")
local seekerRunning = false

local function isSeeker(p)
	return p:GetAttribute("HuntSeeker") == true or p:GetAttribute("HideSeekSeeker") == true
end

local function blackedOut()
	local g = LP:FindFirstChildOfClass("PlayerGui")
	local b = g and g:FindFirstChild("SeekerBlackout")
	return b and b.Enabled
end

local function huntTargets(skip)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP and not isSeeker(p) and (skip[p] or 0) < tick()
			and p:GetAttribute("IsEliminated") ~= true and p:GetAttribute("GhostMode") ~= true and p:GetAttribute("SpectatorJoiner") ~= true then
			local ch = p.Character
			local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
			local h = ch and ch:FindFirstChildOfClass("Humanoid")
			if hrp and h and h.Health > 0 then table.insert(list, { p = p, hrp = hrp }) end
		end
	end
	return list
end

local function huntActive()
	return env.AutoSimon and settings.groups.seeker and isSeeker(LP)
		and workspace:GetAttribute("SeekHuntActive") == true and LP:GetAttribute("IsEliminated") ~= true
end

local function checkSeeker()
	if seekerRunning or not huntActive() then return end
	seekerRunning = true
	task.spawn(function()
		log("seeker: you're the seeker — hunting")
		local skip, caught = {}, 0
		while huntActive() do
			if blackedOut() then
				task.wait(0.2)
			else
				local t = nearest(huntTargets(skip), function(x) return x.hrp.Position end)
				local _, root = hum()
				if not (t and root) then
					task.wait(0.4)
				else
					local t0 = tick()
					while tick() - t0 < 1.2 and huntActive() and t.hrp.Parent and t.p:GetAttribute("IsEliminated") ~= true do
						root.CFrame = t.hrp.CFrame * CFrame.new(0, 0, 1.5)
						root.AssemblyLinearVelocity = Vector3.zero
						RunService.Heartbeat:Wait()
					end
					if t.p:GetAttribute("IsEliminated") == true then
						caught += 1
						log("seeker: caught " .. t.p.Name)
					else
						skip[t.p] = tick() + 4 -- couldn't catch them; try others first
					end
				end
			end
		end
		log("seeker: hunt over — caught " .. caught)
		seekerRunning = false
	end)
end

for _, attr in ipairs({ "HuntSeeker", "HideSeekSeeker", "IsEliminated" }) do
	table.insert(env.AutoSimonConns, LP:GetAttributeChangedSignal(attr):Connect(checkSeeker))
end
table.insert(env.AutoSimonConns, workspace:GetAttributeChangedSignal("SeekHuntActive"):Connect(checkSeeker))
task.spawn(checkSeeker)

---------------------------------------------------------------- infinite stamina
-- The sprint controller keeps stamina in a local that SharedBus.GetStamina reads (upvalue 1).
if settings.groups.infStamina == nil then settings.groups.infStamina = true end

table.insert(env.AutoSimonConns, RunService.Heartbeat:Connect(function()
	if not settings.groups.infStamina then return end
	local ok, bus = pcall(require, ReplicatedStorage.Modules.SharedBus)
	local get = ok and bus and bus.GetStamina
	if get and get() < 100 then pcall(debug.setupvalue, get, 1, 100) end
end))

---------------------------------------------------------------- trap guard
-- While a bait order (no "SIMON SAYS") is up, block the matching input so a reflex can't kill you.
if settings.groups.trapGuard == nil then settings.groups.trapGuard = true end

local CAS = game:GetService("ContextActionService")
local guardOn, guardToken = false, nil
local guardStates = {}
local guardPrompts = {} -- [prompt] = Enabled before the guard

local function endGuard()
	if not guardOn then return end
	guardOn, guardToken = false, nil
	pcall(function() CAS:UnbindAction("AutoSimonTrapGuard") end)
	local h = hum()
	for state in pairs(guardStates) do
		if h then pcall(function() h:SetStateEnabled(state, true) end) end
	end
	table.clear(guardStates)
	for pp, was in pairs(guardPrompts) do
		pcall(function() pp.Enabled = was end)
	end
	table.clear(guardPrompts)
end

local function guardKeys(name)
	if name == "jump" then return { Enum.KeyCode.Space, Enum.KeyCode.ButtonA } end
	if name == "crouch" then
		return { keyFromAttr("KeybindCrouch", Enum.KeyCode.C), Enum.KeyCode.LeftControl, keyFromAttr("PadCrouch", Enum.KeyCode.ButtonB) }
	end
	return {}
end

local GUARD_STATES = {
	jump = { Enum.HumanoidStateType.Jumping },
	sit = { Enum.HumanoidStateType.Seated },
}

local function startGuard(name, text)
	endGuard()
	if not (GUARD_STATES[name] or name == "crouch" or name == "bed") then return end
	guardOn = true
	if name == "bed" then
		local beds = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("CellProps") and workspace.Map.CellProps:FindFirstChild("Beds")
		for _, d in ipairs(beds and beds:GetDescendants() or {}) do
			if d:IsA("ProximityPrompt") and d.Name == "BedSleepPrompt" then
				guardPrompts[d] = d.Enabled
				d.Enabled = false
			end
		end
	end
	local h = hum()
	for _, s in ipairs(GUARD_STATES[name] or {}) do
		if h and not (s == Enum.HumanoidStateType.Seated and h.Sit) then
			h:SetStateEnabled(s, false)
			guardStates[s] = true
		end
	end
	local keys = guardKeys(name)
	if #keys > 0 then
		CAS:BindActionAtPriority("AutoSimonTrapGuard", function() return Enum.ContextActionResult.Sink end, false, 3000, table.unpack(keys))
	end
	log("trap guard: blocking " .. name .. " (" .. text .. ")")
	local token = {}
	guardToken = token
	task.delay(10, function() if guardToken == token then endGuard() end end) -- safety net
end

table.insert(env.AutoSimonConns, WardenAnnounce.OnClientEvent:Connect(function(text, isSimon)
	if type(text) ~= "string" or text == "" then return end
	local up = text:upper()
	if isSimon == true and up:sub(1, 10) == "SIMON SAYS" then endGuard() return end
	if not (env.AutoSimon and settings.groups.trapGuard) or LP:GetAttribute("IsEliminated") then return end
	for _, p in ipairs(patterns) do
		if up:find(p[1], 1, true) then
			startGuard(p[2], text)
			return
		end
	end
end))
if WindowClose then table.insert(env.AutoSimonConns, WindowClose.OnClientEvent:Connect(endGuard)) end

---------------------------------------------------------------- player ESP
-- Highlights every living player; seekers/necromancers/duelists in red, armed players in orange.
if settings.groups.playerEsp == nil then settings.groups.playerEsp = true end

local ESP_DANGER = Color3.fromRGB(255, 60, 70)
local ESP_ARMED = Color3.fromRGB(255, 160, 50)
local ESP_NORMAL = Color3.fromRGB(150, 125, 255)
local WEAPON_WORDS = { "knife", "gun", "bat", "taser", "bomb", "revolver", "pistol", "rifle", "shotgun", "axe", "machete", "crowbar", "sword" }

local espRoot = (gethui and gethui()) or game:GetService("CoreGui")
local oldPlayerEsp = espRoot:FindFirstChild("AutoSimonPlayerESP")
if oldPlayerEsp then oldPlayerEsp:Destroy() end
local playerEspFolder = Instance.new("Folder")
playerEspFolder.Name = "AutoSimonPlayerESP"
playerEspFolder.Parent = espRoot

local espObjects = {} -- [player] = { hl, bb, name, info }

local function weaponOf(ch)
	for _, t in ipairs(ch:GetChildren()) do
		if t:IsA("Tool") and t.Name ~= "Fists" and t.Name ~= "Push" then
			if t:GetAttribute("MeleeDamage") ~= nil then return t.Name end
			local n = t.Name:lower()
			for _, w in ipairs(WEAPON_WORDS) do
				if n:find(w, 1, true) then return t.Name end
			end
		end
	end
	if ch:FindFirstChild("HolsterGun") then return "Gun" end
	if ch:FindFirstChild("HolsterKnife") then return "Knife" end
end

local function roleOf(p, ch)
	if isSeeker(p) then return "SEEKER" end
	if ch:GetAttribute("IsNecromancer") or p:GetAttribute("IsNecromancer") then return "NECROMANCER" end
	if p:GetAttribute("Duelist") == true then return "DUELIST" end
end

local function dropEsp(p)
	local o = espObjects[p]
	if o then
		pcall(function() o.hl:Destroy() o.bb:Destroy() end)
		espObjects[p] = nil
	end
end

local function makeEsp(p)
	local hl = Instance.new("Highlight")
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.FillTransparency = 0.78
	hl.OutlineTransparency = 0.1
	hl.Parent = playerEspFolder
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(200, 34)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = playerEspFolder
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 16)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 13
	name.TextStrokeTransparency = 0.4
	name.Parent = bb
	local info = Instance.new("TextLabel")
	info.BackgroundTransparency = 1
	info.Position = UDim2.fromOffset(0, 16)
	info.Size = UDim2.new(1, 0, 0, 14)
	info.Font = Enum.Font.GothamMedium
	info.TextSize = 11
	info.TextStrokeTransparency = 0.4
	info.Parent = bb
	local o = { hl = hl, bb = bb, name = name, info = info }
	espObjects[p] = o
	return o
end

local function updatePlayerEsp()
	local _, myRoot = hum()
	for p, _ in pairs(espObjects) do
		if not p.Parent then dropEsp(p) end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		local h = ch and ch:FindFirstChildOfClass("Humanoid")
		local show = settings.groups.playerEsp and p ~= LP and root and h and h.Health > 0
			and p:GetAttribute("IsEliminated") ~= true and p:GetAttribute("GhostMode") ~= true
		if not show then
			dropEsp(p)
		else
			local o = espObjects[p] or makeEsp(p)
			local role, weapon = roleOf(p, ch), weaponOf(ch)
			local colour = role and ESP_DANGER or (weapon and ESP_ARMED) or ESP_NORMAL
			o.hl.Adornee = ch
			o.hl.FillColor = colour
			o.hl.OutlineColor = colour
			o.bb.Adornee = ch:FindFirstChild("Head") or root
			o.name.Text = p.DisplayName
			o.name.TextColor3 = colour
			local dist = myRoot and math.floor((root.Position - myRoot.Position).Magnitude) or 0
			local tags = { dist .. " studs" }
			if role then table.insert(tags, role) end
			if weapon then table.insert(tags, weapon:upper()) end
			o.info.Text = table.concat(tags, "  •  ")
			o.info.TextColor3 = role and ESP_DANGER or Color3.fromRGB(220, 220, 230)
		end
	end
end

do
	local acc = 0
	table.insert(env.AutoSimonConns, RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then return end
		acc = 0
		pcall(updatePlayerEsp)
	end))
	table.insert(env.AutoSimonConns, Players.PlayerRemoving:Connect(dropEsp))
end

---------------------------------------------------------------- two doors tracker
-- The client is never told which door is safe. Instead we watch other players: note which door they
-- walk up to, then which room (safe / trial) they land in, and mark the doors from that evidence.
if settings.groups.doorTracker == nil then settings.groups.doorTracker = true end
if settings.groups.doorAutoPick == nil then settings.groups.doorAutoPick = false end

local doorEvidence, doorLast, doorLanded = {}, {}, {}
local doorMarks = {}
local doorPicked = false
local doorVerdictChanged -- GUI hook

local function resetDoors()
	doorEvidence = { Door1 = { safe = 0, trial = 0 }, Door2 = { safe = 0, trial = 0 } }
	table.clear(doorLast)
	table.clear(doorLanded)
	doorPicked = false
	for _, m in pairs(doorMarks) do pcall(function() m.hl:Destroy() m.bb:Destroy() end) end
	table.clear(doorMarks)
	if doorVerdictChanged then pcall(doorVerdictChanged) end
end
resetDoors()

local function roomBoxes()
	local lights = workspace:FindFirstChild("TwoDoors") and workspace.TwoDoors:FindFirstChild("RoomLights")
	if not lights then return end
	local boxes = {}
	for _, kind in ipairs({ "Safe", "Trial" }) do
		local mn, mx
		for _, l in ipairs(lights:GetChildren()) do
			if l.Name:find("RoomLight" .. kind) then
				local p = l:IsA("Model") and l:GetPivot().Position or (l:IsA("BasePart") and l.Position)
				if p then
					mn = mn and Vector3.new(math.min(mn.X, p.X), math.min(mn.Y, p.Y), math.min(mn.Z, p.Z)) or p
					mx = mx and Vector3.new(math.max(mx.X, p.X), math.max(mx.Y, p.Y), math.max(mx.Z, p.Z)) or p
				end
			end
		end
		if mn then boxes[kind] = { min = mn - Vector3.new(16, 40, 18), max = mx + Vector3.new(16, 6, 18) } end
	end
	return boxes
end

local function inBox(p, b)
	return b and p.X >= b.min.X and p.X <= b.max.X and p.Y >= b.min.Y and p.Y <= b.max.Y and p.Z >= b.min.Z and p.Z <= b.max.Z
end

-- "SAFE" / "TRIAL" / "MIXED" / nil, plus whether it was inferred from the other door
local function doorVerdict(name)
	local e = doorEvidence[name]
	local other = doorEvidence[name == "Door1" and "Door2" or "Door1"]
	if e.safe > 0 and e.trial > 0 then return "MIXED" end
	if e.safe > 0 then return "SAFE" end
	if e.trial > 0 then return "TRIAL" end
	if other.safe > 0 and other.trial == 0 then return "TRIAL", true end
	if other.trial > 0 and other.safe == 0 then return "SAFE", true end
end

local function safeDoor()
	for _, n in ipairs({ "Door1", "Door2" }) do
		if doorVerdict(n) == "SAFE" then return n end
	end
end

local function pickSafeDoor()
	local n = safeDoor()
	local door = n and workspace:FindFirstChild("TwoDoors") and workspace.TwoDoors:FindFirstChild(n)
	local pp = door and door:FindFirstChild("ChoosePrompt", true)
	if not pp then log("two doors: no safe door known yet") return end
	doorPicked = true
	log("two doors: picking " .. n)
	firePrompt(pp)
end

local function drawDoorMarks()
	local td = workspace:FindFirstChild("TwoDoors")
	for _, n in ipairs({ "Door1", "Door2" }) do
		local door = td and td:FindFirstChild(n)
		local verdict, inferred = doorVerdict(n)
		local m = doorMarks[n]
		if not (door and verdict and settings.groups.doorTracker) then
			if m then pcall(function() m.hl:Destroy() m.bb:Destroy() end) doorMarks[n] = nil end
			local gameHl = door and door:FindFirstChild("DoorHighlight")
			if gameHl then gameHl.Enabled = true end
		else
			if not m then
				m = { hl = Instance.new("Highlight"), bb = Instance.new("BillboardGui") }
				m.hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				m.hl.FillTransparency = 0.55
				m.hl.Parent = playerEspFolder
				m.bb.Size = UDim2.fromOffset(160, 36)
				m.bb.StudsOffset = Vector3.new(0, 5, 0)
				m.bb.AlwaysOnTop = true
				m.bb.LightInfluence = 0
				m.label = Instance.new("TextLabel")
				m.label.BackgroundTransparency = 1
				m.label.Size = UDim2.fromScale(1, 1)
				m.label.Font = Enum.Font.GothamBlack
				m.label.TextSize = 20
				m.label.TextStrokeTransparency = 0.3
				m.label.Parent = m.bb
				m.bb.Parent = playerEspFolder
				doorMarks[n] = m
			end
			local colour = verdict == "SAFE" and Color3.fromRGB(70, 220, 120)
				or verdict == "TRIAL" and Color3.fromRGB(255, 60, 70) or Color3.fromRGB(240, 200, 60)
			local e = doorEvidence[n]
			m.hl.Adornee = door
			m.hl.FillColor, m.hl.OutlineColor = colour, colour
			m.bb.Adornee = door.PrimaryPart or door:FindFirstChildWhichIsA("BasePart", true)
			m.label.TextColor3 = colour
			m.label.Text = verdict .. (inferred and " (inferred)" or string.format("  %d/%d", e.safe, e.trial))
			local gameHl = door:FindFirstChild("DoorHighlight")
			if gameHl then gameHl.Enabled = false end
		end
	end
end

local function trackDoors()
	if workspace:GetAttribute("TwoDoorsActive") ~= true or not settings.groups.doorTracker then return end
	local td = workspace:FindFirstChild("TwoDoors")
	local boxes = roomBoxes()
	if not (td and boxes) then return end
	local doors = {}
	for _, n in ipairs({ "Door1", "Door2" }) do
		local d = td:FindFirstChild(n)
		if d then doors[n] = d:GetPivot().Position end
	end
	local changed = false
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if root and not doorLanded[p] then
			local pos = root.Position
			local best, bestD
			for n, dp in pairs(doors) do
				local d = (pos - dp).Magnitude
				if d < 12 and (not bestD or d < bestD) then best, bestD = n, d end
			end
			if best then doorLast[p] = { door = best, t = tick() } end
			local room = inBox(pos, boxes.Safe) and "safe" or (inBox(pos, boxes.Trial) and "trial")
			local last = doorLast[p]
			if room and last and tick() - last.t < 10 then
				doorLanded[p] = true
				doorEvidence[last.door][room] += 1
				changed = true
				log(string.format("two doors: %s took %s -> %s room", p.DisplayName, last.door, room))
			end
		end
	end
	if changed then
		drawDoorMarks()
		if doorVerdictChanged then pcall(doorVerdictChanged) end
		if settings.groups.doorAutoPick and env.AutoSimon and not doorPicked and not doorLanded[LP] and safeDoor() then
			task.spawn(pickSafeDoor)
		end
	end
end

do
	local acc = 0
	table.insert(env.AutoSimonConns, RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then return end
		acc = 0
		pcall(trackDoors)
	end))
	for _, attr in ipairs({ "TwoDoorsActive", "TwoDoorsRoundActive" }) do
		table.insert(env.AutoSimonConns, workspace:GetAttributeChangedSignal(attr):Connect(function()
			resetDoors()
			drawDoorMarks()
		end))
	end
end

---------------------------------------------------------------- instant proximity prompts
if settings.groups.instantPrompts == nil then settings.groups.instantPrompts = true end

-- original hold times, kept across re-runs so "off" can always restore them
env.AutoSimonPromptHold = env.AutoSimonPromptHold or setmetatable({}, { __mode = "k" })
local promptHold = env.AutoSimonPromptHold
local promptWatch = {}

local function applyPrompt(pp)
	if not settings.groups.instantPrompts then return end
	if pp.HoldDuration > 0 then
		promptHold[pp] = promptHold[pp] or pp.HoldDuration
		pp.HoldDuration = 0
	end
	if not promptWatch[pp] then
		-- the game may reset HoldDuration later; force it back to 0
		promptWatch[pp] = pp:GetPropertyChangedSignal("HoldDuration"):Connect(function()
			if settings.groups.instantPrompts and pp.HoldDuration > 0 then
				promptHold[pp] = pp.HoldDuration
				pp.HoldDuration = 0
			end
		end)
		table.insert(env.AutoSimonConns, promptWatch[pp])
	end
end

local function setInstantPrompts(on)
	if on then
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") then applyPrompt(d) end
		end
		log("instant prompts on")
	else
		for pp, hold in pairs(promptHold) do
			if pp.Parent then pp.HoldDuration = hold end
		end
		table.clear(promptHold)
		log("instant prompts off")
	end
end

table.insert(env.AutoSimonConns, workspace.DescendantAdded:Connect(function(d)
	if d:IsA("ProximityPrompt") then applyPrompt(d) end
end))
if settings.groups.instantPrompts then setInstantPrompts(true) end

---------------------------------------------------------------- GUI
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local guiParent = (gethui and gethui()) or game:GetService("CoreGui")
local old = guiParent:FindFirstChild("AutoSimonGui")
if old then old:Destroy() end

local C = {
	window = Color3.fromRGB(13, 12, 19),
	sidebar = Color3.fromRGB(17, 16, 25),
	card = Color3.fromRGB(19, 18, 28),
	cardOpen = Color3.fromRGB(23, 21, 34),
	header = Color3.fromRGB(30, 28, 46),
	field = Color3.fromRGB(26, 25, 37),
	stroke = Color3.fromRGB(37, 34, 54),
	text = Color3.fromRGB(232, 230, 242),
	sub = Color3.fromRGB(122, 118, 142),
	dim = Color3.fromRGB(78, 75, 96),
	accent = Color3.fromRGB(124, 96, 255),
	accentDim = Color3.fromRGB(44, 37, 82),
	off = Color3.fromRGB(46, 43, 62),
	green = Color3.fromRGB(70, 210, 120),
	yellow = Color3.fromRGB(230, 196, 70),
	red = Color3.fromRGB(232, 82, 92),
}
local F = { reg = Enum.Font.Gotham, med = Enum.Font.GothamMedium, bold = Enum.Font.GothamBold }

local function new(class, props, children)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	for _, c in ipairs(children or {}) do c.Parent = o end
	return o
end
local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r or 6) }) end
local function stroke(col) return new("UIStroke", { Color = col or C.stroke, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
local function pad(l, r, t, b)
	return new("UIPadding", { PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0), PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0) })
end
local function text(props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.Font = props.Font or F.reg
	props.TextColor3 = props.TextColor3 or C.text
	return new("TextLabel", props)
end
local function conn(c) table.insert(env.AutoSimonConns, c) return c end

local W, H, SIDE = 680, 440, 190

local gui = new("ScreenGui", { Name = "AutoSimonGui", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999, IgnoreGuiInset = true })
pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
gui.Parent = guiParent

local win = new("Frame", {
	Name = "Window", Size = UDim2.fromOffset(W, H), Position = UDim2.new(0.5, -W / 2, 0.5, -H / 2),
	BackgroundColor3 = C.window, BorderSizePixel = 0, ClipsDescendants = true, Parent = gui,
}, { corner(12), stroke() })

---------------------------------------------------------------- sidebar
local sidebar = new("Frame", { Size = UDim2.new(0, SIDE, 1, 0), BackgroundColor3 = C.sidebar, BorderSizePixel = 0, Parent = win }, { corner(12) })
new("Frame", { Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0, 12, 1, 0), BackgroundColor3 = C.sidebar, BorderSizePixel = 0, Parent = sidebar })
new("Frame", { Position = UDim2.new(0, SIDE, 0, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = C.stroke, BorderSizePixel = 0, Parent = win })

local brand = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58), Parent = sidebar })
new("TextLabel", {
	Text = "S", Font = F.bold, TextSize = 16, TextColor3 = C.accent, BackgroundColor3 = C.accentDim,
	Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(32, 32), Parent = brand,
}, { corner(9), stroke(Color3.fromRGB(70, 58, 130)) })
text({ Text = "Auto Simon", Font = F.bold, TextSize = 15, Position = UDim2.fromOffset(58, 16), Size = UDim2.new(1, -66, 0, 18), Parent = brand })
text({ Text = "Death Order Game", TextSize = 11, TextColor3 = C.sub, Position = UDim2.fromOffset(58, 34), Size = UDim2.new(1, -66, 0, 14), Parent = brand })

local searchField = new("Frame", { BackgroundColor3 = C.field, BorderSizePixel = 0, Position = UDim2.fromOffset(12, 66), Size = UDim2.new(1, -24, 0, 30), Parent = sidebar }, { corner(8), stroke() })
text({ Text = "⌕", TextSize = 15, TextColor3 = C.sub, Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(14, 30), Parent = searchField })
local searchBox = new("TextBox", {
	Text = "", PlaceholderText = "Search features...", PlaceholderColor3 = C.dim, ClearTextOnFocus = false,
	Font = F.reg, TextSize = 12, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -36, 1, 0), Parent = searchField,
})

local footer = new("Frame", { BackgroundColor3 = C.field, BorderSizePixel = 0, Position = UDim2.new(0, 12, 1, -58), Size = UDim2.new(1, -24, 0, 46), Parent = sidebar }, { corner(8), stroke() })
local statusDot = new("Frame", { BorderSizePixel = 0, Position = UDim2.fromOffset(12, 19), Size = UDim2.fromOffset(8, 8), Parent = footer }, { corner(4) })
text({ Text = LP.DisplayName, Font = F.bold, TextSize = 13, Position = UDim2.fromOffset(28, 8), Size = UDim2.new(1, -34, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, Parent = footer })
local statusText = text({ RichText = true, TextSize = 10, TextColor3 = C.sub, Position = UDim2.fromOffset(28, 25), Size = UDim2.new(1, -34, 0, 13), Parent = footer })
local function refreshStatus()
	statusDot.BackgroundColor3 = env.AutoSimon and C.green or C.red
	statusText.Text = env.AutoSimon and 'Status: <font color="#7C60FF">Active</font>' or 'Status: <font color="#E8525C">Paused</font>'
end
refreshStatus()

---------------------------------------------------------------- content area
local content = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(SIDE + 1, 0), Size = UDim2.new(1, -(SIDE + 1), 1, 0), Parent = win })
local pageTitle = text({ Font = F.bold, TextSize = 22, Position = UDim2.fromOffset(22, 16), Size = UDim2.new(1, -80, 0, 26), Parent = content })
local pageSub = text({ TextSize = 11, TextColor3 = C.sub, Position = UDim2.fromOffset(22, 44), Size = UDim2.new(1, -80, 0, 14), Parent = content })
local minBtn = new("TextButton", {
	Text = "–", Font = F.bold, TextSize = 16, TextColor3 = C.sub, BackgroundColor3 = C.field, AutoButtonColor = false,
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 18), Size = UDim2.fromOffset(28, 28), Parent = content,
}, { corner(7), stroke() })

local scroll = new("ScrollingFrame", {
	BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(14, 72), Size = UDim2.new(1, -24, 1, -84),
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3,
	ScrollBarImageColor3 = C.accent, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = content,
}, { new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }), pad(2, 10, 2, 10) })

---------------------------------------------------------------- widgets
local cards = {}
local cardOrder = 0

local function groupToggle(key, after)
	return function() return settings.groups[key] end, function(v)
		settings.groups[key] = v
		if after then after(v) end
	end
end
local TAG_COLOURS = { C.green, C.yellow, C.red }

local function switch(parent, get, set)
	local track = new("TextButton", {
		Text = "", AutoButtonColor = false, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0, 28), Size = UDim2.fromOffset(36, 18), ZIndex = 3, Parent = parent,
	}, { corner(9) })
	local knob = new("Frame", { BorderSizePixel = 0, Size = UDim2.fromOffset(12, 12), ZIndex = 4, Parent = track }, { corner(6) })
	local function render(animate)
		local on = get()
		local goalT = { BackgroundColor3 = on and C.accent or C.off }
		local goalK = { Position = on and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3), BackgroundColor3 = on and Color3.new(1, 1, 1) or C.sub }
		if animate then
			TweenService:Create(track, TweenInfo.new(0.15), goalT):Play()
			TweenService:Create(knob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), goalK):Play()
		else
			for k, v in pairs(goalT) do track[k] = v end
			for k, v in pairs(goalK) do knob[k] = v end
		end
	end
	track.MouseButton1Click:Connect(function()
		set(not get())
		render(true)
	end)
	render(false)
	return render
end

-- o = { page, title, desc, tag, level (1-3), get, set, open }
local function card(o)
	cardOrder += 1
	if o.group then o.get, o.set = groupToggle(o.group, o.after) end
	local hasTag = o.tag ~= nil
	local frame = new("Frame", {
		BackgroundColor3 = C.card, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = cardOrder, Parent = scroll,
	}, { corner(9), stroke(), new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }) })
	local header = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, hasTag and 64 or 56), LayoutOrder = 1, Parent = frame })
	local chevron = text({ Text = "›", Font = F.bold, TextSize = 20, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(16, 18), Visible = false, Parent = header })
	text({ Text = o.title, Font = F.bold, TextSize = 14, Position = UDim2.fromOffset(36, 11), Size = UDim2.new(1, -110, 0, 18), Parent = header })
	text({ Text = o.desc or "", TextSize = 11, TextColor3 = C.sub, Position = UDim2.fromOffset(36, 29), Size = UDim2.new(1, -110, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd, Parent = header })
	if hasTag then
		local col = TAG_COLOURS[o.level or 1]
		for i = 0, 2 do
			new("Frame", { BorderSizePixel = 0, BackgroundColor3 = i < (o.level or 1) and col or C.off, Position = UDim2.fromOffset(36 + i * 9, 50), Size = UDim2.fromOffset(7, 3), Parent = header }, { corner(1) })
		end
		text({ Text = o.tag, Font = F.med, TextSize = 9, TextColor3 = col, Position = UDim2.fromOffset(66, 45), Size = UDim2.fromOffset(100, 12), Parent = header })
	end
	if o.get then switch(header, o.get, o.set) end

	local body = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, LayoutOrder = 2, Parent = frame }, {
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }), pad(16, 16, 0, 10),
	})
	new("Frame", { BackgroundColor3 = C.stroke, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1), LayoutOrder = 0, Parent = body })
	new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 6), LayoutOrder = 1, Parent = body })

	local c = { frame = frame, body = body, page = o.page, key = (o.title .. " " .. (o.desc or "")):lower(), rows = 0 }
	local open = false
	function c.setOpen(v)
		open = v and c.rows > 0
		body.Visible = open
		frame.BackgroundColor3 = open and C.cardOpen or C.card
		TweenService:Create(chevron, TweenInfo.new(0.15), { Rotation = open and 90 or 0 }):Play()
	end
	function c.row(label)
		c.rows += 1
		chevron.Visible = true
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = c.rows + 1, Parent = body })
		text({ Text = label, TextSize = 12, Size = UDim2.new(0.38, 0, 1, 0), Parent = row })
		return row
	end
	header.MouseButton1Click:Connect(function() c.setOpen(not open) end)
	table.insert(cards, c)
	if o.open then task.defer(c.setOpen, true) end
	return c
end

local function valueBox(parent, width)
	return new("TextLabel", {
		Font = F.med, TextSize = 11, TextColor3 = C.text, BackgroundColor3 = C.field, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(width or 62, 20), Parent = parent,
	}, { corner(5), stroke() })
end

local function slider(c, label, min, max, step, get, set, fmt)
	local row = c.row(label)
	local track = new("Frame", {
		BackgroundColor3 = C.off, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.38, 0, 0.5, 0), Size = UDim2.new(0.62, -80, 0, 4), Parent = row,
	}, { corner(2) })
	local fill = new("Frame", { BackgroundColor3 = C.accent, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track }, { corner(2) })
	local knob = new("Frame", {
		BackgroundColor3 = C.accent, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(12, 12), Parent = track,
	}, { corner(6), new("UIStroke", { Color = Color3.fromRGB(190, 175, 255), Thickness = 1.5 }) })
	local box = valueBox(row)
	local function render()
		local a = math.clamp((get() - min) / (max - min), 0, 1)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		box.Text = fmt(get())
	end
	local dragging = false
	local function update(x)
		local a = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local v = math.clamp(math.round((min + a * (max - min)) / step) * step, min, max)
		set(v)
		render()
	end
	local hit = new("TextButton", { Text = "", BackgroundTransparency = 1, Position = UDim2.new(0, -6, 0.5, -10), Size = UDim2.new(1, 12, 0, 20), Parent = track })
	hit.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			update(i.Position.X)
		end
	end)
	conn(UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then update(i.Position.X) end
	end))
	conn(UIS.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end))
	render()
	return render
end

local function pill(c, label, getText)
	local row = c.row(label)
	local p = new("TextLabel", {
		Font = F.med, TextSize = 11, TextColor3 = C.text, BackgroundColor3 = C.field, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X, Parent = row,
	}, { corner(5), stroke(), pad(9, 9) })
	local function render() p.Text = getText() end
	render()
	return render
end

local function button(c, label, btnText, colour, onClick)
	local row = c.row(label)
	local b = new("TextButton", {
		Text = btnText, Font = F.bold, TextSize = 11, TextColor3 = colour, BackgroundColor3 = C.field, AutoButtonColor = true,
		BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X, Parent = row,
	}, { corner(5), stroke(), pad(12, 12) })
	b.MouseButton1Click:Connect(onClick)
end

---------------------------------------------------------------- pages & cards
local PAGES = {
	{ key = "commands", icon = "◆", title = "Commands", sub = "Auto-play the Warden's orders" },
	{ key = "visuals", icon = "◉", title = "Visuals", sub = "See what others can't" },
	{ key = "misc", icon = "✦", title = "Misc", sub = "Quality of life" },
	{ key = "log", icon = "≡", title = "Log", sub = "What the script just did" },
	{ key = "settings", icon = "⚙", title = "Settings", sub = "Interface & script" },
}

-- Commands
local master = card({
	page = "commands", title = "Auto Simon", desc = "Master switch — reacts only when Simon really says", tag = "Core", level = 1,
	get = function() return env.AutoSimon end,
	set = function(v) env.AutoSimon = v refreshStatus() log(v and "enabled" or "disabled") end,
})
slider(master, "Reaction Delay", 0, 2000, 10,
	function() return settings.delay * 1000 end,
	function(v) settings.delay = v / 1000 end,
	function(v) return string.format("%d ms", v) end)

card({ page = "commands", title = "Basic Actions", desc = "Jump, crouch, dance, sprint, don't move, fight", tag = "Legit", level = 1, group = "basic" })
card({ page = "commands", title = "Find a Seat", desc = "Teleports onto the nearest free seat", tag = "Teleport", level = 2, group = "seat" })
card({ page = "commands", title = "Locations", desc = "Floors, cafeteria, basement, tables, ladder, stairs, circle, line", tag = "Teleport", level = 2, group = "places" })
card({ page = "commands", title = "Cell Orders", desc = "Bed, gate, light and return to cell", tag = "Teleport", level = 2, group = "cell" })
card({ page = "commands", title = "Colour Drop", desc = "Gets on the called colour, steps off trap colours", tag = "Teleport", level = 2, group = "colour" })

local split = card({ page = "commands", title = "Split Second", desc = "Stops the clock on the mark — Simon rounds only", tag = "Remote", level = 2, group = "splitSecond" })
local renderTarget = slider(split, "Clock Target", 0.25, 16, 0.25,
	function() return settings.splitTarget end,
	function(v) settings.splitTarget = v end,
	function(v) return string.format("%.2f", v) end)
local renderDetected = pill(split, "Detected Mark", function()
	return splitAutoTarget and string.format("%.2f", splitAutoTarget) or "None"
end)
splitTargetChanged = function()
	renderTarget()
	renderDetected()
end

card({ page = "commands", title = "Auto Seeker", desc = "When you're the seeker, teleports onto every hider to catch them", tag = "Teleport", level = 3, group = "seeker",
	after = function(v) if v then checkSeeker() end end })

card({ page = "commands", title = "Trap Guard", desc = "Blocks jump, crouch & sitting while a fake order is up", tag = "Legit", level = 1, group = "trapGuard",
	after = function(v) if not v then endGuard() end end })

local doors = card({ page = "commands", title = "Door Tracker", desc = "Marks the safe door by watching where other players land", tag = "Client", level = 1, group = "doorTracker",
	after = function() drawDoorMarks() end })
local renderDoorStatus = pill(doors, "Safe Door", function()
	local n = safeDoor()
	if n then return n == "Door1" and "Door 1" or "Door 2" end
	if doorVerdict("Door1") == "MIXED" or doorVerdict("Door2") == "MIXED" then return "Random per player" end
	return workspace:GetAttribute("TwoDoorsActive") == true and "Watching..." or "No round"
end)
local renderDoorEvidence = pill(doors, "Evidence", function()
	local a, b = doorEvidence.Door1, doorEvidence.Door2
	return string.format("D1 %d safe / %d trial   D2 %d safe / %d trial", a.safe, a.trial, b.safe, b.trial)
end)
button(doors, "Pick Now", "Pick Safe Door", C.green, function() task.spawn(pickSafeDoor) end)
doorVerdictChanged = function()
	renderDoorStatus()
	renderDoorEvidence()
end
card({ page = "commands", title = "Auto Pick Door", desc = "Chooses the safe door as soon as the tracker knows it", tag = "Teleport", level = 2, group = "doorAutoPick" })

-- Visuals
card({ page = "visuals", title = "Player ESP", desc = "Everyone through walls — seekers red, armed players orange", tag = "Client", level = 1, group = "playerEsp",
	after = function() pcall(updatePlayerEsp) end })
card({ page = "visuals", title = "Mine ESP", desc = "Shows every armed mine in No Man's Land", tag = "Client", level = 1, group = "mineEsp", after = drawMines })

-- Misc
card({ page = "misc", title = "Infinite Stamina", desc = "Sprint bar never drains", tag = "Client", level = 1, group = "infStamina" })
card({ page = "misc", title = "Instant Prompts", desc = "No holding — every prompt fires instantly", tag = "Client", level = 1, group = "instantPrompts", after = setInstantPrompts })

-- Log
local logCard = card({ page = "log", title = "Activity", desc = "Last commands and what Auto Simon did", open = true })
local logRow = logCard.row("")
logRow.AutomaticSize = Enum.AutomaticSize.Y
logRow.Size = UDim2.new(1, 0, 0, 0)
logRow:ClearAllChildren()
new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = logRow })
local logLines, logN = {}, 0
logHook = function(msg)
	logN += 1
	local colour = C.text
	if msg:find("TRAP") or msg:find("skipped") or msg:find("not pressing") then colour = C.sub end
	if msg:find("error") or msg:find("no auto action") or msg:find("never reaches") then colour = C.red end
	if msg:find("^doing") or msg:find("^colour") or msg:find("pressing at") then colour = C.accent end
	local line = text({
		RichText = true, TextSize = 11, Font = Enum.Font.Code, TextColor3 = colour, TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = -logN, Parent = logRow,
	})
	line.Text = '<font color="#4E4B60">' .. os.date("%H:%M:%S") .. "</font>  " .. msg:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	table.insert(logLines, line)
	while #logLines > 18 do table.remove(logLines, 1):Destroy() end
end

-- Settings
local iface = card({ page = "settings", title = "Interface", desc = "Window and keybinds", open = true })
pill(iface, "Toggle UI", function() return "RightShift" end)
pill(iface, "Executor", function() return identifyexecutor and tostring((identifyexecutor())) or "Unknown" end)
button(iface, "Unload Script", "Unload", C.red, function()
	env.AutoSimon = false
	pcall(setInstantPrompts, false)
	local esp = workspace:FindFirstChild("AutoSimonMineESP")
	if esp then esp:Destroy() end
	pcall(endGuard)
	pcall(function() playerEspFolder:Destroy() end)
	for _, c in ipairs(env.AutoSimonConns) do pcall(function() c:Disconnect() end) end
	env.AutoSimonConns = {}
	gui:Destroy()
	print("[AutoSimon] unloaded")
end)

---------------------------------------------------------------- navigation & search
local currentPage, searchText = "commands", ""
local navButtons = {}

local function applyFilter()
	local meta
	for _, p in ipairs(PAGES) do if p.key == currentPage then meta = p end end
	if searchText ~= "" then
		pageTitle.Text = "Search"
		pageSub.Text = 'Results for "' .. searchText .. '"'
	else
		pageTitle.Text = meta.title
		pageSub.Text = meta.sub
	end
	for _, c in ipairs(cards) do
		if searchText ~= "" then
			c.frame.Visible = c.page ~= "log" and c.key:find(searchText, 1, true) ~= nil
		else
			c.frame.Visible = c.page == currentPage
		end
	end
	for key, n in pairs(navButtons) do
		local sel = searchText == "" and key == currentPage
		n.b.BackgroundTransparency = sel and 0 or 1
		n.bar.Visible = sel
		n.ic.BackgroundColor3 = sel and C.accentDim or C.field
		n.ic.TextColor3 = sel and C.accent or C.sub
		n.t.TextColor3 = sel and C.text or C.sub
	end
	scroll.CanvasPosition = Vector2.zero
end

for i, p in ipairs(PAGES) do
	local b = new("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundColor3 = C.header, BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 108 + (i - 1) * 50), Size = UDim2.new(1, -20, 0, 46), Parent = sidebar,
	}, { corner(8) })
	local bar = new("Frame", { BackgroundColor3 = C.accent, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 12), Size = UDim2.fromOffset(3, 22), Visible = false, Parent = b }, { corner(2) })
	local ic = new("TextLabel", { Text = p.icon, Font = F.bold, TextSize = 13, BackgroundColor3 = C.field, TextColor3 = C.sub, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 9), Size = UDim2.fromOffset(28, 28), Parent = b }, { corner(7) })
	local t = text({ Text = p.title, Font = F.bold, TextSize = 13, TextColor3 = C.sub, Position = UDim2.fromOffset(48, 8), Size = UDim2.new(1, -52, 0, 16), Parent = b })
	text({ Text = p.sub, TextSize = 10, TextColor3 = C.dim, Position = UDim2.fromOffset(48, 25), Size = UDim2.new(1, -52, 0, 12), TextTruncate = Enum.TextTruncate.AtEnd, Parent = b })
	navButtons[p.key] = { b = b, bar = bar, ic = ic, t = t }
	b.MouseButton1Click:Connect(function()
		currentPage = p.key
		if searchBox.Text ~= "" then searchBox.Text = "" else applyFilter() end
	end)
end

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	searchText = searchBox.Text:lower():gsub("^%s+", ""):gsub("%s+$", "")
	applyFilter()
end)
applyFilter()

---------------------------------------------------------------- window behaviour
-- minimise to a small pill
local restore = new("TextButton", {
	Text = "  Auto Simon", Font = F.bold, TextSize = 12, TextColor3 = C.text, BackgroundColor3 = C.sidebar, AutoButtonColor = false,
	TextXAlignment = Enum.TextXAlignment.Left, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.fromOffset(120, 30), Visible = false, Parent = gui,
}, { corner(15), stroke(), pad(16, 8) })
new("Frame", { BackgroundColor3 = C.accent, BorderSizePixel = 0, Position = UDim2.new(0, -8, 0.5, -3), Size = UDim2.fromOffset(6, 6), Parent = restore }, { corner(3) })
minBtn.MouseButton1Click:Connect(function() win.Visible = false restore.Visible = true end)
restore.MouseButton1Click:Connect(function() win.Visible = true restore.Visible = false end)

-- drag from the brand block or the page header
do
	local dragging, startPos, startInput
	local function hook(handle)
		handle.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging, startPos, startInput = true, win.Position, input.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then dragging = false end
				end)
			end
		end)
	end
	hook(brand)
	hook(new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -60, 0, 66), Parent = content }))
	conn(UIS.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - startInput
			win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
end

conn(UIS.InputBegan:Connect(function(input, gp)
	if not gp and input.KeyCode == Enum.KeyCode.RightShift then gui.Enabled = not gui.Enabled end
end))

log("loaded")
