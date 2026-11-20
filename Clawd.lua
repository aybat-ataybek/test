local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local env = (getgenv and getgenv()) or _G
if env.__ClawdPetStop then pcall(env.__ClawdPetStop) end

local LANG = string.lower(tostring(env.ClawdLang or "ru")) == "en" and "en" or "ru"

local GRID_W, GRID_H = 18, 13
local SCALE = 1
local UNIT = 4
local W, H = GRID_W * UNIT, GRID_H * UNIT
local PEEK_AFTER, PEEK_HIDDEN, PEEK_OUT = 45, 3, 7
local SLEEP_AFTER = 180
local MAX_PARTICLES = 14

local BODY = Color3.fromRGB(0xD9, 0x77, 0x57)
local EYE = Color3.fromRGB(0x1A, 0x1A, 0x1A)
local BLUSH = BODY:Lerp(Color3.fromRGB(0xFF, 0x4F, 0x79), 0.5)

local PCOL = {
	heart = Color3.fromRGB(0xFF, 0x5C, 0x7A),
	zzz = Color3.fromRGB(0x8F, 0xA3, 0xBF),
	spark = Color3.fromRGB(0xFF, 0xC9, 0x4D),
}

local PATTERNS = {
	heart = { ".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..." },
	zzz = { "XXXXX", "...X.", "..X..", ".X...", "XXXXX" },
	spark = { "..X..", "..X..", "XX.XX", "..X..", "..X.." },
}

local PHRASES_RU = {
	hello = { "Привет!", "Я Clawd!", "О, это ты!" },
	idle = {
		"Чем помочь?", "Хм…", "Думаю…", "Можно я тут посижу?", "Ты молодец!",
		"Не забудь попить воды", "Пип-пип!", "Мне нравится этот чат", "*оглядывается*",
		"Пишу код… шучу", "Интересно, что там в чатах",
	},
	tap = { "Ой!", "Эй!", "Чего?", "Я тут!", "Хи!" },
	annoyed = { "Хватит тыкать!", "Щекотно же!", "Ну всё, обиделся", "Эй, полегче!" },
	pet = { "Мрр…", "Ещё!", "Приятно ♥", "Хи-хи", "Лучший день!", "♥♥♥" },
	drag = { "Ааа!", "Куда мы?", "Поставь меня!" },
	throw = { "Уиии!", "Я лечу!", "Ваааа!" },
	dizzy = { "Голова кружится…", "@_@", "Где я?" },
	wake = { "А? Что?", "Я не спал!", "*зевает*" },
	jump = { "Хоп!", "Йе!", "Ура!" },
	hang = { "Держусь!", "Помогите!", "Высоковато…", "Не отпущу!" },
	hang_fall = { "Ой-ой-ой!", "Не удержался!", "Падаю!" },
	peek = { "Ку-ку!", "Я тебя вижу", "*подглядывает*", "Ты тут?" },
	found = { "Нашёл меня!", "Эх, раскусил", "Я просто смотрел!" },
}

local PHRASES_EN = {
	hello = { "Hi!", "I'm Clawd!", "Oh, it's you!" },
	idle = {
		"How can I help?", "Hmm…", "Thinking…", "Can I sit here?", "You're doing great!",
		"Don't forget to drink water", "Beep-beep!", "I like this place", "*looks around*",
		"Writing code… just kidding", "Wonder what's going on out there",
	},
	tap = { "Oops!", "Hey!", "What?", "I'm here!", "Hehe!" },
	annoyed = { "Stop poking me!", "That tickles!", "Okay, I'm offended", "Hey, easy!" },
	pet = { "Mrr…", "More!", "Feels nice ♥", "Hehe", "Best day ever!", "♥♥♥" },
	drag = { "Aaah!", "Where are we going?", "Put me down!" },
	throw = { "Wheee!", "I'm flying!", "Waaaah!" },
	dizzy = { "I'm dizzy…", "@_@", "Where am I?" },
	wake = { "Huh? What?", "I wasn't sleeping!", "*yawns*" },
	jump = { "Hop!", "Yay!", "Hooray!" },
	hang = { "Holding on!", "Help!", "It's high up…", "Won't let go!" },
	hang_fall = { "Oh no!", "Couldn't hold on!", "Falling!" },
	peek = { "Peek-a-boo!", "I see you", "*peeking*", "You there?" },
	found = { "You found me!", "Aw, busted", "I was just looking!" },
}

local PHRASES = LANG == "en" and PHRASES_EN or PHRASES_RU

local function dp(v) return v * SCALE end
local function uni(a, b) return a + math.random() * (b - a) end
local function chance(p) return math.random() < p end
local clamp = math.clamp

local gui = Instance.new("ScreenGui")
gui.Name = "ClawdPet"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2147483647
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)

do
	local ok = pcall(function()
		gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
	end)
	if not ok or not gui.Parent then
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	end
end

local pet = Instance.new("Frame")
pet.Name = "Pet"
pet.Size = UDim2.fromOffset(W, H)
pet.BackgroundTransparency = 1
pet.BorderSizePixel = 0
pet.ZIndex = 1
pet.Parent = gui

local cells, cur = {}, {}

for i = 0, GRID_W * GRID_H - 1 do
	local c = Instance.new("Frame")
	c.BorderSizePixel = 0
	c.Size = UDim2.fromOffset(UNIT, UNIT)
	c.Position = UDim2.fromOffset((i % GRID_W) * UNIT, (i // GRID_W) * UNIT)
	c.Visible = false
	c.Parent = pet
	cells[i + 1] = c
end

local hit = Instance.new("TextButton")
hit.Size = UDim2.fromScale(1, 1)
hit.BackgroundTransparency = 1
hit.Text = ""
hit.AutoButtonColor = false
hit.ZIndex = 5
hit.Parent = pet

local bubble = Instance.new("Frame")
bubble.AutomaticSize = Enum.AutomaticSize.XY
bubble.BackgroundColor3 = Color3.new(1, 1, 1)
bubble.BorderSizePixel = 0
bubble.Visible = false
bubble.ZIndex = 20
bubble.Parent = gui

local bCorner = Instance.new("UICorner")
bCorner.CornerRadius = UDim.new(0, 12)
bCorner.Parent = bubble

local bStroke = Instance.new("UIStroke")
bStroke.Color = Color3.fromRGB(205, 205, 205)
bStroke.Parent = bubble

local bPad = Instance.new("UIPadding")
bPad.PaddingLeft = UDim.new(0, 10)
bPad.PaddingRight = UDim.new(0, 10)
bPad.PaddingTop = UDim.new(0, 6)
bPad.PaddingBottom = UDim.new(0, 6)
bPad.Parent = bubble

local label = Instance.new("TextLabel")
label.AutomaticSize = Enum.AutomaticSize.XY
label.BackgroundTransparency = 1
label.TextColor3 = Color3.fromRGB(26, 26, 26)
label.Font = Enum.Font.GothamMedium
label.TextSize = 15
label.TextWrapped = true
label.ZIndex = 21
label.Parent = bubble

local bLimit = Instance.new("UISizeConstraint")
bLimit.MaxSize = Vector2.new(220, 1000)
bLimit.Parent = label

local now0 = os.clock()

local S = {
	state = "idle", x = 0, y = 0, vx = 0, vy = 0, ready = false,
	lastTick = now0, lastInteraction = now0, nextAction = now0 + 4, nextBlink = now0 + 2,
	blinkUntil = 0, look = 0, expr = nil, exprUntil = 0, squashUntil = 0, waveUntil = 0,
	hopActive = false, hopOff = 0, hopVy = 0, walkTarget = 0, walkIn = false,
	lastTap = 0, recentTaps = {}, nextHeart = 0, nextZ = 0,
	bubbleVisible = false, bubbleFade = false, bubbleUntil = 0, bubbleGen = 0, lastPhrase = nil,
	hangStart = 0, hangUntil = 0,
	peekSide = 0, peekPending = 0, peekPhase = "hide", peekPhaseUntil = 0, peekEnd = 0,
	peekMoving = false, nextPeek = now0 + PEEK_AFTER,
	minX = 0, maxX = 0, minY = 0, maxY = 0, width = 0, height = 0, frameKey = nil,
}

local touch = nil
local particles = {}

local function buildGrid(eyes, look, arms, legs, squash, blush)
	local grid = {}

	local function px(x0, y0, x1, y1, color)
		for yy = y0, y1 - 1 do
			for xx = x0, x1 - 1 do
				if xx >= 0 and xx < GRID_W and yy >= 0 and yy < GRID_H then
					grid[yy * GRID_W + xx + 1] = color
				end
			end
		end
	end

	local left, right, top, bottom = 3, 15, 3, 10

	if squash > 0 then
		left, right, top = 2, 16, 5
	elseif squash < 0 then
		left, right, top = 4, 14, 2
	end

	if legs == "tuck" then
		top += 1
		bottom += 1
	end

	local heights = ({
		stand = { 2, 2, 2, 2 },
		walk1 = { 1, 2, 1, 2 },
		walk2 = { 2, 1, 2, 1 },
		dangle = { 3, 3, 3, 3 },
		tuck = { 1, 1, 1, 1 },
	})[legs] or { 2, 2, 2, 2 }

	local cols = { left + 1, left + 3, right - 4, right - 2 }

	for i = 1, 4 do
		px(cols[i], bottom, cols[i] + 1, bottom + heights[i], BODY)
	end

	local function arm(side, style)
		if style == "up" then
			if side < 0 then
				px(left - 2, top - 1, left - 1, top + 3, BODY)
				px(left - 1, top + 2, left, top + 3, BODY)
			else
				px(right + 1, top - 1, right + 2, top + 3, BODY)
				px(right, top + 2, right + 1, top + 3, BODY)
			end
		elseif style == "tuck" then
			if side < 0 then
				px(left - 1, top + 3, left, top + 5, BODY)
			else
				px(right, top + 3, right + 1, top + 5, BODY)
			end
		else
			if side < 0 then
				px(left - 2, top + 3, left, top + 5, BODY)
			else
				px(right, top + 3, right + 2, top + 5, BODY)
			end
		end
	end

	local la, ra = arms, arms

	if arms == "wave1" then
		la, ra = "up", "normal"
	elseif arms == "wave2" then
		la, ra = "normal", "up"
	end

	arm(-1, la)
	arm(1, ra)

	px(left, top, right, bottom, BODY)

	local ey = top + 2

	for _, e in ipairs({ { -1, left + 3 + look }, { 1, right - 4 + look } }) do
		local side, cx = e[1], e[2]

		if eyes == "blink" then
			px(cx, ey + 1, cx + 1, ey + 2, EYE)
		elseif eyes == "happy" then
			px(cx - 1, ey + 1, cx, ey + 2, EYE)
			px(cx, ey, cx + 1, ey + 1, EYE)
			px(cx + 1, ey + 1, cx + 2, ey + 2, EYE)
		elseif eyes == "surprised" then
			px(cx, ey - 1, cx + 1, ey + 2, EYE)
		elseif eyes == "dizzy" then
			for _, d in ipairs({ { -1, -1 }, { 1, -1 }, { 0, 0 }, { -1, 1 }, { 1, 1 } }) do
				px(cx + d[1], ey + d[2], cx + d[1] + 1, ey + d[2] + 1, EYE)
			end
		elseif eyes == "sleep" then
			px(cx - 1, ey + 1, cx + 2, ey + 2, EYE)
		elseif eyes == "angry" then
			px(cx, ey, cx + 1, ey + 2, EYE)
			local brow = side < 0 and cx - 1 or cx + 1
			px(brow, ey - 1, brow + 1, ey, EYE)
		else
			px(cx, ey, cx + 1, ey + 2, EYE)
		end

		if blush then
			if side < 0 then
				px(cx - 2, ey + 2, cx, ey + 3, BLUSH)
			else
				px(cx + 1, ey + 2, cx + 3, ey + 3, BLUSH)
			end
		end
	end

	return grid
end

local function applyGrid(grid)
	for i = 1, GRID_W * GRID_H do
		local col = grid[i]

		if col ~= cur[i] then
			cur[i] = col
			local c = cells[i]

			if col then
				c.BackgroundColor3 = col
				c.Visible = true
			else
				c.Visible = false
			end
		end
	end
end

local function walkLegs(now)
	return (math.floor(now * 7) % 2 == 1) and "walk1" or "walk2"
end

local function compose(now)
	local eyes, look, arms, legs, squash, blush = "open", S.look, "normal", "stand", 0, false
	local st = S.state

	if st == "drag" or st == "fly" then
		eyes, arms, legs = "surprised", "up", "dangle"
	elseif st == "pet" then
		eyes, blush, look = "happy", true, 0
		squash = (math.floor(now * 3) % 2 == 1) and 1 or 0
	elseif st == "sleep" then
		eyes, arms, legs, look = "sleep", "tuck", "tuck", 0
	elseif st == "walk" then
		legs = walkLegs(now)
	elseif st == "press" then
		squash = 1
	elseif st == "hang" then
		eyes = (now - S.hangStart < 0.5) and "surprised" or "open"
		arms, legs = "up", "dangle"
		look = (math.floor(now * 1.5) % 2 == 1) and -1 or 1
	elseif st == "peek" then
		if S.peekMoving then
			legs = walkLegs(now)
		elseif S.peekPhase == "out" and math.floor(now * 3) % 2 == 1 then
			arms = S.peekSide > 0 and "wave1" or "wave2"
		end
	end

	if S.walkIn and st == "idle" then
		legs = walkLegs(now)
	end

	if (st == "idle" or st == "walk") and now < S.waveUntil then
		arms = (math.floor(now * 5) % 2 == 1) and "wave1" or "wave2"
	end

	if S.hopActive and (st == "idle" or st == "walk") then
		legs = "dangle"
		if S.hopVy < 0 then
			squash = -1
			arms = "up"
		end
	end

	if now < S.exprUntil and S.expr and st ~= "sleep" then
		eyes = S.expr
		if S.expr == "happy" then
			blush = true
		end
	end

	if now < S.squashUntil and squash == 0 then
		squash = 1
	end

	if eyes == "open" and (st == "idle" or st == "walk" or st == "peek" or st == "hang") and now < S.blinkUntil then
		eyes = "blink"
	end

	if legs == "tuck" and squash ~= 0 then
		squash = 0
	end

	return eyes, look, arms, legs, squash, blush
end

local function render(now)
	local eyes, look, arms, legs, squash, blush = compose(now)
	local key = table.concat({ eyes, look, arms, legs, squash, tostring(blush) }, "|")

	if key ~= S.frameKey then
		S.frameKey = key
		applyGrid(buildGrid(eyes, look, arms, legs, squash, blush))
	end

	pet.Position = UDim2.fromOffset(math.floor(S.x + 0.5), math.floor(S.y + S.hopOff + 0.5))

	local rot = 0

	if S.state == "fly" then
		rot = clamp(S.vx / dp(70), -25, 25)
	elseif S.state == "hang" then
		rot = math.sin((now - S.hangStart) * 3) * 6
	elseif S.expr == "dizzy" and now < S.exprUntil then
		rot = math.sin(now * 10) * 7
	elseif S.state == "drag" and touch then
		local last = touch.hist[#touch.hist]
		if now - last[1] < 0.08 then
			rot = clamp(touch.vx / dp(90), -18, 18)
		end
	end

	pet.Rotation = rot
end

local function spawnParticle(kind, now)
	if #particles >= MAX_PARTICLES then return end

	local rows, col = PATTERNS[kind], PCOL[kind]
	local s = math.max(2, math.floor(UNIT * 0.75))
	local bw, bh = #rows[1] * s, #rows * s

	local g = Instance.new("CanvasGroup")
	g.BackgroundTransparency = 1
	g.Size = UDim2.fromOffset(bw, bh)
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.ZIndex = 10
	g.Rotation = uni(-15, 15)

	local sc = Instance.new("UIScale")
	sc.Scale = 0.5
	sc.Parent = g

	for y, row in ipairs(rows) do
		for x = 1, #row do
			if row:sub(x, x) == "X" then
				local c = Instance.new("Frame")
				c.BorderSizePixel = 0
				c.BackgroundColor3 = col
				c.Size = UDim2.fromOffset(s, s)
				c.Position = UDim2.fromOffset((x - 1) * s, (y - 1) * s)
				c.Parent = g
			end
		end
	end

	local headY = S.y + S.hopOff + UNIT * 2 - bh
	local sx, sy, drift

	if kind == "zzz" then
		sx, sy, drift = S.x + W * 0.72, headY + UNIT * 2, dp(18)
	else
		sx = S.x + W / 2 - bw / 2 + uni(-W * 0.25, W * 0.25)
		sy, drift = headY, uni(-dp(16), dp(16))
	end

	g.Position = UDim2.fromOffset(sx + bw / 2, sy + bh / 2)
	g.Parent = gui

	particles[#particles + 1] = {
		g = g, sc = sc, cx = sx + bw / 2, cy = sy + bh / 2, drift = drift,
		rise = dp(uni(40, 58)), t0 = now, dur = kind == "zzz" and 1.6 or 1.1,
	}
end

local function updateParticles(now)
	for i = #particles, 1, -1 do
		local p = particles[i]
		local t = (now - p.t0) / p.dur

		if t >= 1 then
			p.g:Destroy()
			table.remove(particles, i)
		else
			p.g.Position = UDim2.fromOffset(p.cx + p.drift * t, p.cy - p.rise * t)
			p.sc.Scale = 0.5 + 0.5 * t
			p.g.GroupTransparency = t
		end
	end
end

local function setBubbleAlpha(a, dur)
	local info = TweenInfo.new(dur)
	TweenService:Create(bubble, info, { BackgroundTransparency = a }):Play()
	TweenService:Create(label, info, { TextTransparency = a }):Play()
	TweenService:Create(bStroke, info, { Transparency = a }):Play()
end

local function hideBubble()
	if not S.bubbleVisible then return end

	S.bubbleVisible, S.bubbleFade = false, false
	S.bubbleGen += 1

	local gen = S.bubbleGen
	setBubbleAlpha(1, 0.18)

	task.delay(0.2, function()
		if gen == S.bubbleGen then
			bubble.Visible = false
		end
	end)
end

local function say(category)
	local list = PHRASES[category]
	if not list then return end

	local opts = {}

	for _, p in ipairs(list) do
		if p ~= S.lastPhrase then
			opts[#opts + 1] = p
		end
	end

	if #opts == 0 then
		opts = list
	end

	local text = opts[math.random(#opts)]
	S.lastPhrase = text
	label.Text = text

	bubble.BackgroundTransparency, label.TextTransparency, bStroke.Transparency = 1, 1, 1
	bubble.Visible = true

	S.bubbleGen += 1
	S.bubbleVisible, S.bubbleFade = true, true
	S.bubbleUntil = os.clock() + 2 + #text * 0.05
end

local function updateBubble(now)
	if not S.bubbleVisible then return end
	if now >= S.bubbleUntil then
		hideBubble()
		return
	end

	local bw, bh = bubble.AbsoluteSize.X, bubble.AbsoluteSize.Y
	if bw <= 0 then return end

	local margin = dp(4)
	local bx = clamp(S.x + W / 2 - bw / 2, margin, math.max(margin, S.width - bw - margin))
	local by = S.y + S.hopOff + UNIT - bh - margin

	if by < S.minY then
		by = S.y + S.hopOff + H + margin
	end

	bubble.Position = UDim2.fromOffset(math.floor(bx), math.floor(by))

	if S.bubbleFade then
		S.bubbleFade = false
		setBubbleAlpha(0, 0.15)
	end
end

local function setExpr(e, d)
	S.expr = e
	S.exprUntil = os.clock() + d
end

local function hop(strength)
	if S.state ~= "idle" and S.state ~= "walk" then return end

	S.hopActive = true
	S.hopVy = -strength

	if S.hopOff > 0 then
		S.hopOff = 0
	end
end

local function startHang(now)
	S.state = "hang"
	S.vx, S.vy = 0, 0
	S.y = S.minY - UNIT * 2
	S.hangStart = now
	S.hangUntil = now + uni(2, 3.5)

	if chance(0.7) then
		say("hang")
	end
end

local function land(now)
	S.state = "idle"
	S.vx, S.vy = 0, 0
	S.squashUntil = now + 0.14
	S.nextAction = now + uni(2, 5)
end

local function startPeek(now, side)
	S.state = "peek"
	S.peekSide = side
	S.peekPhase = "hide"
	S.peekPhaseUntil = now + uni(3, 6)
	S.peekEnd = now + uni(30, 60)
	S.look = side
end

local function endPeek(now)
	local side = S.peekSide
	S.peekSide, S.peekMoving = 0, false
	S.nextPeek = now + uni(60, 120)
	S.state = "idle"

	if side == 0 then return end

	local inside = side < 0 and S.minX + dp(30) or S.maxX - dp(30)
	S.walkTarget = clamp(inside, S.minX, S.maxX)
	S.state = "walk"
	S.nextAction = now + uni(3, 6)
end

local function peekX(units)
	if S.peekSide > 0 then
		return S.width - units * UNIT
	end

	return units * UNIT - W
end

local function stepGround(dt, now)
	S.walkIn = false

	if S.state ~= "walk" then
		if S.x < S.minX - 0.5 or S.x > S.maxX + 0.5 then
			local step = dp(60) * dt

			if S.x < S.minX then
				S.x = math.min(S.minX, S.x + step)
				S.look = 1
			else
				S.x = math.max(S.maxX, S.x - step)
				S.look = -1
			end

			S.walkIn = true
		else
			S.x = clamp(S.x, S.minX, S.maxX)
		end
	end

	S.y = clamp(S.y, S.minY, S.maxY)

	if S.state == "walk" then
		local dir = S.walkTarget > S.x and 1 or -1
		S.look = dir
		S.x += dir * dp(42) * dt

		local reached = (dir > 0 and S.x >= S.walkTarget) or (dir < 0 and S.x <= S.walkTarget)
		local edge = (dir < 0 and S.x <= S.minX) or (dir > 0 and S.x >= S.maxX)

		if reached or edge then
			S.x = clamp(S.x, S.minX, S.maxX)
			S.state = "idle"
			S.nextAction = now + uni(2.5, 6)

			local side = S.peekPending
			S.peekPending = 0
			local e = dp(4)

			if side ~= 0 and ((side < 0 and S.x <= S.minX + e) or (side > 0 and S.x >= S.maxX - e)) then
				startPeek(now, side)
			end
		end

		return
	end

	if S.state == "sleep" then
		if now >= S.nextZ then
			S.nextZ = now + 1.6
			spawnParticle("zzz", now)
		end
		return
	end

	if now >= S.nextBlink then
		S.blinkUntil = now + 0.13
		S.nextBlink = now + (chance(0.15) and 0.35 or uni(2, 5.5))
	end

	if now - S.lastInteraction > SLEEP_AFTER and not S.hopActive and not S.walkIn then
		S.state, S.look = "sleep", 0
		S.nextZ = now + 0.6
		hideBubble()
		return
	end

	if now < S.nextAction or S.hopActive or S.walkIn then return end

	S.nextAction = now + uni(3.5, 9)
	local roll = math.random()

	if now >= S.nextPeek and now - S.lastInteraction > PEEK_AFTER and roll < 0.3 then
		local side = (S.x - S.minX < S.maxX - S.x) and -1 or 1
		S.walkTarget = side < 0 and S.minX or S.maxX
		S.peekPending = side
		S.state = "walk"
		return
	end

	if roll < 0.38 then
		local dist = uni(dp(40), dp(160)) * (chance(0.5) and 1 or -1)
		local target = clamp(S.x + dist, S.minX, S.maxX)

		if math.abs(target - S.x) > dp(12) then
			S.walkTarget = target
			S.state = "walk"
		end
	elseif roll < 0.58 then
		S.look = math.random(-1, 1)
	elseif roll < 0.72 then
		say("idle")
	elseif roll < 0.84 then
		hop(dp(360))
	else
		S.waveUntil = now + 1.6
	end
end

local function stepFly(dt, now)
	S.x += S.vx * dt
	S.y += S.vy * dt

	local f = math.exp(-2 * dt)
	S.vx *= f
	S.vy *= f

	local impact = 0

	if S.x < S.minX then
		S.x = S.minX
		impact = math.max(impact, math.abs(S.vx))
		S.vx = math.abs(S.vx) * 0.55
	elseif S.x > S.maxX then
		S.x = S.maxX
		impact = math.max(impact, math.abs(S.vx))
		S.vx = -math.abs(S.vx) * 0.55
	end

	if S.y < S.minY then
		if S.vy < -dp(250) then
			startHang(now)
			return
		end

		S.y = S.minY
		impact = math.max(impact, math.abs(S.vy))
		S.vy = math.abs(S.vy) * 0.55
	elseif S.y > S.maxY then
		S.y = S.maxY
		impact = math.max(impact, math.abs(S.vy))
		S.vy = -math.abs(S.vy) * 0.55
		S.squashUntil = now + 0.1
	end

	if impact > dp(2300) then
		setExpr("dizzy", 2.6)
		say("dizzy")
	end

	if S.state == "fly" and math.sqrt(S.vx * S.vx + S.vy * S.vy) < dp(45) then
		land(now)
	end
end

local function stepHang(now)
	S.x = clamp(S.x, S.minX, S.maxX)
	S.y = S.minY - UNIT * 2

	if now < S.hangUntil then return end

	S.state = "fly"
	S.vx, S.vy = 0, dp(700)
	setExpr("surprised", 0.8)

	if chance(0.6) then
		say("hang_fall")
	end
end

local function stepPeek(dt, now)
	local target = peekX(S.peekPhase == "out" and PEEK_OUT or PEEK_HIDDEN)
	local step = dp(50) * dt

	S.peekMoving = math.abs(target - S.x) > 0.5

	if S.peekMoving then
		if target > S.x then
			S.x = math.min(target, S.x + step)
		else
			S.x = math.max(target, S.x - step)
		end
	end

	if S.peekPhase == "hide" and S.peekMoving then
		S.look = S.peekSide
	else
		S.look = -S.peekSide
	end

	if now >= S.nextBlink then
		S.blinkUntil = now + 0.13
		S.nextBlink = now + uni(2, 5.5)
	end

	if now < S.peekPhaseUntil or S.peekMoving then return end
	if now >= S.peekEnd then
		endPeek(now)
		return
	end

	if S.peekPhase == "hide" then
		S.peekPhase = "out"
		S.peekPhaseUntil = now + uni(1.5, 2.8)

		if chance(0.5) then
			say("peek")
		end
	else
		S.peekPhase = "hide"
		S.peekPhaseUntil = now + uni(3, 7)
	end
end

local function startPet(now)
	S.state = "pet"
	S.nextHeart = now + 0.1
end

local function tap(now)
	if now - S.lastTap < 0.32 then
		S.lastTap = 0
		hop(dp(720))
		setExpr("happy", 1.3)

		for _ = 1, 3 do
			spawnParticle("spark", now)
		end

		if chance(0.4) then
			say("jump")
		end

		return
	end

	S.lastTap = now
	local fresh = {}

	for _, t in ipairs(S.recentTaps) do
		if now - t < 2.5 then
			fresh[#fresh + 1] = t
		end
	end

	fresh[#fresh + 1] = now
	S.recentTaps = fresh

	if #fresh >= 6 then
		S.recentTaps = {}
		setExpr("angry", 2.5)
		say("annoyed")
		return
	end

	S.squashUntil = now + 0.12
	setExpr("surprised", 0.45)
	hop(dp(330))

	if chance(0.35) then
		say("tap")
	end
end

local function releaseDrag(now, t, cancelled)
	local vx, vy = 0, 0
	local hist = t.hist

	if not cancelled and #hist >= 2 then
		local a, b = hist[1], hist[#hist]

		if b[1] - a[1] > 0.005 and now - b[1] < 0.08 then
			vx = (b[2] - a[2]) / (b[1] - a[1])
			vy = (b[3] - a[3]) / (b[1] - a[1])
		end
	end

	local limit = dp(6000)
	vx, vy = clamp(vx, -limit, limit), clamp(vy, -limit, limit)

	local speed = math.sqrt(vx * vx + vy * vy)

	if speed <= dp(700) and S.y <= S.minY + UNIT * 2 then
		startHang(now)
	elseif speed > dp(700) then
		S.state = "fly"
		S.vx, S.vy = vx, vy

		if speed > dp(2600) then
			say("throw")
		end
	else
		S.state = "idle"
		S.squashUntil = now + 0.12
		S.nextAction = now + uni(2, 5)
	end
end

local function pointerDown(input)
	local now = os.clock()
	local rx, ry = input.Position.X, input.Position.Y
	local wasSleep, wasPeek = S.state == "sleep", S.state == "peek"

	S.lastInteraction = now

	touch = {
		x0 = rx, y0 = ry, t0 = now, ox = rx - S.x, oy = ry - S.y,
		hist = { { now, rx, ry } }, anchor = rx, dir = 0, vx = 0, input = input,
		isMouse = input.UserInputType == Enum.UserInputType.MouseButton1,
	}

	S.hopActive, S.hopOff, S.hopVy = false, 0, 0
	S.vx, S.vy = 0, 0
	S.peekSide, S.peekPending = 0, 0
	S.state = "press"

	if wasSleep then
		setExpr("surprised", 0.9)
		say("wake")
	elseif wasPeek then
		S.nextPeek = now + uni(60, 120)
		setExpr("surprised", 0.7)
		say("found")
	end
end

local function pointerMove(input)
	local t = touch
	if not t then return end

	local now = os.clock()
	local rx, ry = input.Position.X, input.Position.Y
	local hist = t.hist

	hist[#hist + 1] = { now, rx, ry }

	while #hist > 2 and now - hist[1][1] > 0.1 do
		table.remove(hist, 1)
	end

	if S.state == "press" then
		local dx, dy = rx - t.x0, ry - t.y0

		if math.sqrt(dx * dx + dy * dy) > dp(8) then
			S.state = "drag"

			if chance(0.25) then
				say("drag")
			end
		end
	end

	if S.state == "drag" then
		S.x = clamp(rx - t.ox, -W * 0.3, S.width - W * 0.7)
		S.y = clamp(ry - t.oy, 0, S.height - H * 0.5)

		local a = hist[1]

		if now - a[1] > 0.005 then
			t.vx = (rx - a[2]) / (now - a[1])
		end
	elseif S.state == "pet" then
		local dx = rx - t.anchor

		if math.abs(dx) > dp(10) then
			local dir = dx > 0 and 1 or -1

			if t.dir ~= 0 and dir ~= t.dir then
				spawnParticle("heart", now)
			end

			t.dir = dir
			t.anchor = rx
		end
	end
end

local function pointerUp(cancelled)
	local t = touch
	if not t then return end

	touch = nil

	local now = os.clock()
	S.lastInteraction = now

	if S.state == "drag" then
		releaseDrag(now, t, cancelled)
	elseif S.state == "pet" then
		S.state = "idle"
		setExpr("happy", 2.2)
		S.nextAction = now + uni(3, 6)

		if chance(0.6) then
			say("pet")
		end
	elseif S.state == "press" then
		S.state = "idle"

		if not cancelled then
			tap(now)
		end
	end
end

local function step()
	local now = os.clock()
	local dt = clamp(now - S.lastTick, 0, 0.05)
	S.lastTick = now

	local size = gui.AbsoluteSize
	if size.X <= 0 then return end

	S.width, S.height = size.X, size.Y
	S.minX, S.maxX = 0, math.max(0, size.X - W)
	S.minY = GuiService:GetGuiInset().Y
	S.maxY = math.max(S.minY, size.Y - H)

	if not S.ready then
		S.ready = true
		S.x = S.minX + (S.maxX - S.minX) * 0.8
		S.y = S.minY + (S.maxY - S.minY) * 0.72
		hop(dp(420))
		say("hello")
	end

	local st = S.state

	if st == "press" and touch and now - touch.t0 >= 0.4 then
		startPet(now)
		st = S.state
	end

	if st == "pet" then
		if now >= S.nextHeart then
			S.nextHeart = now + 0.45
			spawnParticle("heart", now)
		end
	elseif st == "fly" then
		stepFly(dt, now)
	elseif st == "hang" then
		stepHang(now)
	elseif st == "peek" then
		stepPeek(dt, now)
	elseif st == "idle" or st == "walk" or st == "sleep" then
		stepGround(dt, now)
	end

	if S.hopActive then
		S.hopOff += S.hopVy * dt
		S.hopVy += dp(2600) * dt

		if S.hopOff >= 0 then
			S.hopOff, S.hopVy, S.hopActive = 0, 0, false
			S.squashUntil = now + 0.1
		end
	end

	render(now)
	updateParticles(now)
	updateBubble(now)
end

local conns = {}

conns[#conns + 1] = hit.InputBegan:Connect(function(input)
	local t = input.UserInputType

	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		pointerDown(input)
	end
end)

conns[#conns + 1] = UIS.InputChanged:Connect(function(input)
	if not touch then return end

	if input == touch.input or (touch.isMouse and input.UserInputType == Enum.UserInputType.MouseMovement) then
		pointerMove(input)
	end
end)

conns[#conns + 1] = UIS.InputEnded:Connect(function(input)
	if not touch then return end

	if input == touch.input or (touch.isMouse and input.UserInputType == Enum.UserInputType.MouseButton1) then
		pointerUp(false)
	end
end)

conns[#conns + 1] = RunService.Heartbeat:Connect(function()
	local ok, err = pcall(step)
	if not ok then warn("[Clawd] " .. tostring(err)) end
end)

env.__ClawdPetStop = function()
	for _, c in ipairs(conns) do
		pcall(function()
			c:Disconnect()
		end)
	end

	pcall(function()
		gui:Destroy()
	end)

	env.__ClawdPetStop = nil
end 
