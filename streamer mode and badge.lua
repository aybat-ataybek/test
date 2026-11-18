local Players = game:GetService("Players")
local TextChat = game:GetService("TextChatService")

local env = getgenv()
local lp = Players.LocalPlayer
local realName, realDisplay = lp.Name, lp.DisplayName

env.FakeName = env.FakeName or ".test"
env.FakeDisplay = env.FakeDisplay or ".test"
env.Badge = env.Badge or "roblox-plus"
env.NameColor = env.NameColor or "#FFFFFF"
env.DisplayColor = env.DisplayColor or "#FFFFFF"
env.BadgeColor = env.BadgeColor or "#0066FF"

local ICONS = "rbxasset://LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons/BuilderIcons.json"
local BADGES = { ["roblox-plus"] = true, ["premium"] = true, ["verified-mono"] = true }

local function hex(c, default)
    return tostring(c):match("^#%x%x%x%x%x%x$") and c or default
end

local function esc(s)
    return (tostring(s):gsub("[&<>\"']", {
        ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;",
        ['"'] = "&quot;", ["'"] = "&apos;",
    }))
end

local function colored(text, color)
    return ('<font color="%s">%s</font>'):format(color, esc(text))
end

local function badged(text)
    local badge = BADGES[env.Badge] and env.Badge or "roblox-plus"
    return colored(text, hex(env.DisplayColor, "#FFFFFF")) .. " "
        .. ('<font color="%s" family="%s"><b>%s</b></font>'):format(hex(env.BadgeColor, "#0066FF"), ICONS, badge)
end

local function pat(s)
    return (s:gsub("%W", "%%%0"))
end

local function swap(text)
    if text:find(env.FakeDisplay, 1, true) or text:find(env.FakeName, 1, true) then
        return text
    end
    if text == realDisplay then return badged(env.FakeDisplay) end
    if text == realName then return colored(env.FakeName, hex(env.NameColor, "#FFFFFF")) end

    local out = text:gsub(pat(realDisplay), function() return badged(env.FakeDisplay) end)
    if out == text then
        out = text:gsub(pat(realName), function() return colored(env.FakeName, hex(env.NameColor, "#FFFFFF")) end)
    end
    return out
end

local function hook(obj)
    if not (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then return end
    if obj:GetAttribute("ROMUMonitor") then return end
    obj:SetAttribute("ROMUMonitor", true)

    local busy = false
    local function update()
        if busy or obj.Text == "" then return end
        local new = swap(obj.Text)
        if new ~= obj.Text then
            busy = true
            obj.RichText = true
            obj.Text = new
            busy = false
        end
    end

    update()
    obj:GetPropertyChangedSignal("Text"):Connect(update)
end

local function watch(root)
    for _, v in root:GetDescendants() do hook(v) end
    root.DescendantAdded:Connect(hook)
end

watch(lp:WaitForChild("PlayerGui"))
watch(workspace) -- nametags, billboards, characters
pcall(watch, game:GetService("CoreGui"))

pcall(function()
    TextChat.OnIncomingMessage = function(msg)
        if msg.TextSource and msg.TextSource.UserId == lp.UserId then
            local p = Instance.new("TextChatMessageProperties")
            p.PrefixText = badged(env.FakeDisplay)
            return p
        end
    end
end)
