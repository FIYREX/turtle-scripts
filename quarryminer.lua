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


local function waitForBackChest()
while true do
turtle.turnLeft()
turtle.turnLeft()
local ok, data = turtle.inspect()
turtle.turnLeft()
turtle.turnLeft()
if ok and isChest(data.name) then
say("Detected deposit container behind: " .. data.name)
return true
else
warn("No chest/barrel behind. Place one and press Enter...")
read()
end
end
end


waitForBackChest()


-- ===== Whitelist / Blacklist =====
local ORE_SUBSTRINGS = {
"_ore",
"ore_",
}
local ORE_EXACT = {
["minecraft:ancient_debris"] = true,
}
say("All done. Happy mining!")
