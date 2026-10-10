local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")

local ENV = getgenv()

ENV.FakeName = ENV.FakeName or ".gg/ROMU"
ENV.FakeDisplay = ENV.FakeDisplay or ".gg/ROMU"
ENV.Badge = ENV.Badge or "roblox-plus"

local CONFIG = {
    IconFont = "rbxasset://LuaPackages/Packages/_Index/BuilderIcons/BuilderIcons/BuilderIcons.json",
    Blue = "#0066FF",
    Separator = " "
}

local BADGES = {
    ["roblox-plus"] = "roblox-plus",
    ["premium"] = "premium",
    ["verified-mono"] = "verified-mono"
}

local LocalPlayer = Players.LocalPlayer
local RealName = LocalPlayer.Name
local RealDisplay = LocalPlayer.DisplayName

local function escapeRichText(text)
    return text:gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub('"', "&quot;")
        :gsub("'", "&apos;")
end

local function badgeText(name)
    local badge = BADGES[ENV.Badge] or BADGES["roblox-plus"]

    return escapeRichText(name)
        .. CONFIG.Separator
        .. '<font color="' .. CONFIG.Blue
        .. '" family="' .. CONFIG.IconFont
        .. '"><b>' .. escapeRichText(badge)
        .. '</b></font>'
end

local TargetName = ENV.FakeName

local function replaceNames(text)
    if not text or text == "" then
        return text
    end

    if text:find(ENV.FakeDisplay, 1, true) then
        return text
    end

    if text == RealDisplay then
        return badgeText(ENV.FakeDisplay)
    end

    if text == RealName then
        return TargetName
    end

    local result = text

    if RealDisplay ~= "" then
        local escapedDisplay = RealDisplay:gsub(
            "([^%w])",
            "%%%1"
        )

        result = result:gsub(escapedDisplay, function()
            return badgeText(ENV.FakeDisplay)
        end)
    end

    if result == text and RealName ~= "" then
        local escapedName = RealName:gsub(
            "([^%w])",
            "%%%1"
        )

        result = result:gsub(escapedName, function()
            return TargetName
        end)
    end

    return result
end

local function monitorText(obj)
    if not (
        obj:IsA("TextLabel")
        or obj:IsA("TextButton")
        or obj:IsA("TextBox")
    ) then
        return
    end

    if obj:GetAttribute("ROMUMonitor") then
        return
    end

    obj:SetAttribute("ROMUMonitor", true)

    local updating = false

    local function update()
        if updating or not obj.Parent then
            return
        end

        local original = obj.Text

        if original == "" then
            return
        end

        local updated = replaceNames(original)

        if updated ~= original then
            updating = true

            if updated:find("<font", 1, true) then
                obj.RichText = true
            end

            obj.Text = updated
            updating = false
        end
    end

    update()
    obj:GetPropertyChangedSignal("Text"):Connect(update)
end

local function scanGui(root)
    for _, obj in ipairs(root:GetDescendants()) do
        monitorText(obj)
    end

    root.DescendantAdded:Connect(monitorText)
end

scanGui(LocalPlayer:WaitForChild("PlayerGui"))

pcall(function()
    scanGui(game:GetService("CoreGui"))
end)

local function monitorBillboard(billboard)
    if billboard:GetAttribute("ROMUBillboardMonitor") then
        return
    end

    billboard:SetAttribute("ROMUBillboardMonitor", true)

    for _, obj in ipairs(billboard:GetDescendants()) do
        monitorText(obj)
    end

    billboard.DescendantAdded:Connect(monitorText)
end

for _, obj in ipairs(Workspace:GetDescendants()) do
    if obj:IsA("BillboardGui") then
        monitorBillboard(obj)
    end
end

Workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("BillboardGui") then
        task.defer(function()
            if obj.Parent then
                monitorBillboard(obj)
            end
        end)
    end
end)

local function monitorCharacter(character)
    local humanoid = character:WaitForChild("Humanoid", 10)

    if not humanoid then
        return
    end

    for _, obj in ipairs(character:GetDescendants()) do
        if obj:IsA("BillboardGui") then
            monitorBillboard(obj)
        else
            monitorText(obj)
        end
    end

    character.DescendantAdded:Connect(function(obj)
        if obj:IsA("BillboardGui") then
            monitorBillboard(obj)
        else
            monitorText(obj)
        end
    end)
end

if LocalPlayer.Character then
    task.spawn(monitorCharacter, LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(monitorCharacter)

pcall(function()
    TextChatService.OnIncomingMessage = function(message)
        if not message.TextSource
            or message.TextSource.UserId ~= LocalPlayer.UserId then
            return
        end

        local properties = Instance.new("TextChatMessageProperties")
        properties.PrefixText = badgeText(ENV.FakeDisplay)

        return properties
    end
end)
