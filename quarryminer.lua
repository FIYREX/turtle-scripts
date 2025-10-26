-- ===== Utilities =====
local function say(msg) print("[Quarry] " .. msg) end
local function warn(msg) print("[WARN] " .. msg) end
local function ask(msg)
io.write(msg .. " ")
return (read() or ""):lower()
end


-- Round up helper
local function ceil(n) return math.floor(n) == n and n or math.floor(n) + 1 end


-- ===== Prompt for dimensions =====
local function promptPositiveInt(label)
while true do
io.write(label .. ": ")
local v = tonumber(read())
if v and v >= 1 and math.floor(v) == v then return v end
warn("Enter a positive integer.")
end
end


local W = promptPositiveInt("Width (X)")
local H = promptPositiveInt("Height (Y)")
local D = promptPositiveInt("Depth (Z)")


say(string.format("Configured quarry: %dx%dx%d (W x H x D)", W, H, D))


-- ===== Chest detection =====
local function isChest(name)
if not name then return false end
return name:find("chest") or name:find("barrel")
end


local function waitForFrontChest()
while true do
local ok, data = turtle.inspect()
if ok and isChest(data.name) then
say("Detected deposit container in front: " .. data.name)
return true
else
warn("No chest/barrel in front. Place one and press Enter...")
read()
end
end
end


waitForFrontChest()


-- ===== Whitelist / Blacklist =====
local ORE_SUBSTRINGS = {
"_ore", -- most vanilla/mod ores (iron_ore, deepslate_iron_ore, etc.)
"ore_", -- some mods prefix
}
local ORE_EXACT = {
["minecraft:ancient_debris"] = true,
}
say("All done. Happy mining!")
