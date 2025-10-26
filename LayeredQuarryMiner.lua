--[[ 
LayeredQuarryMiner - Professional Stable Version
by FIYREX

Features:
- Detect chest behind before start
- Smart fuel estimation and refueling
- Mines layer-by-layer (straight vertical descent)
- Starts forward automatically (digs if blocked)
- Returns exactly to starting chest position
]]

-- === Utilities ===
local function say(m) print("[Quarry] " .. m) end
local function warn(m) print("[WARN] " .. m) end

-- === Prompt ===
local function promptInt(label)
  while true do
    io.write(label .. ": ")
    local v = tonumber(read())
    if v and v >= 1 then return math.floor(v) end
    warn("Enter positive integer")
  end
end

local W = promptInt("Width (X)")
local H = promptInt("Height (Y)")
local D = promptInt("Depth (Z)")
say(("Configured quarry: %dx%dx%d"):format(W,H,D))

-- === Facing System ===
local facing = 0 -- 0 = east (+X)
local function turnRight() turtle.turnRight() facing = (facing + 1) % 4 end
local function turnLeft() turtle.turnLeft() facing = (facing + 3) % 4 end
local function face(dir)
  while facing ~= dir do
    local diff = (dir - facing) % 4
    if diff == 1 then turnRight() else turnLeft() end
  end
end

-- === Chest Detection Behind ===
local function isChest(name)
  return name and (name:find("chest") or name:find("barrel"))
end

local function waitForBackChest()
  while true do
    turtle.turnLeft(); turtle.turnLeft()
    local ok, data = turtle.inspect()
    turtle.turnLeft(); turtle.turnLeft()
    if ok and isChest(data.name) then
      say("Detected deposit container behind: " .. data.name)
      return true
    else
      warn("No chest behind. Place one and press Enter.")
      read()
    end
  end
end

waitForBackChest()
facing = 0
face(0)

-- === Ore Whitelist ===
local ORE_SUBS = {"_ore", "ore_"}
local ORE_EXACT = {["minecraft:ancient_debris"] = true}
local function isOre(name)
  if not name then return false end
  if ORE_EXACT[name] then return true end
  for _, s in ipairs(ORE_SUBS) do
    if name:find(s) then return true end
  end
  return false
end

-- === Movement Tracking ===
local pos = {x = 0, y = 0, z = 0}

local function safeInspect(fn)
  local ok, data = fn()
  if ok and data and data.name then return true, data.name end
  return false, nil
end

local function forward()
  local attempts = 0
  while not turtle.forward() and attempts < 5 do
    local ok, name = safeInspect(turtle.inspect)
    if ok then
      turtle.dig()
    else
      os.sleep(0.2)
    end
    attempts = attempts + 1
  end
  if facing == 0 then pos.x = pos.x + 1
  elseif facing == 1 then pos.z = pos.z + 1
  elseif facing == 2 then pos.x = pos.x - 1
  else pos.z = pos.z - 1 end
end

local function up()
  while not turtle.up() do
    local ok, name = safeInspect(turtle.inspectUp)
    if ok then turtle.digUp() end
  end
  pos.y = pos.y + 1
end

local function down()
  while not turtle.down() do
    local ok, name = safeInspect(turtle.inspectDown)
    if ok then turtle.digDown() end
  end
  pos.y = pos.y - 1
end

-- === Fuel Management ===
local function estimateFuel(w, h, d)
  local moves = (w * d * h * 2) + (w + d + h)
  return math.ceil(moves * 1.15)
end

local function ensureFuel(required)
  local fuel = turtle.getFuelLevel()
  if fuel == "unlimited" then
    say("Fuel not required (creative turtle).")
    return true
  end
  say("Current fuel: " .. fuel .. " | Required: " .. required)
  if fuel < required then
    warn("Not enough fuel! Insert fuel and press Enter to refuel.")
    read()
    for i = 1, 16 do turtle.select(i) turtle.refuel(64) end
    fuel = turtle.getFuelLevel()
    say("Refueled. New fuel level: " .. fuel)
    if fuel < required then
      warn("Still not enough fuel. The turtle may not return home safely.")
    end
  else
    say("Fuel sufficient to complete quarry.")
  end
end

local estimatedFuel = estimateFuel(W, H, D)
ensureFuel(estimatedFuel)

-- === Mine Cell ===
local function mineCell()
  local dirs = {turtle.inspectUp, turtle.inspectDown}
  for i, fn in ipairs(dirs) do
    local ok, name = safeInspect(fn)
    if ok and isOre(name) then
      if i == 1 then turtle.digUp() else turtle.digDown() end
    end
  end
end

-- === Serpentine Layer Mining ===
local function serpentineLayer(w, d)
  face(0)
  for row = 1, d do
    for col = 1, w - 1 do
      mineCell()
      forward()
    end
    mineCell()
    if row < d then
      if row % 2 == 1 then turnRight(); forward(); turnRight()
      else turnLeft(); forward(); turnLeft() end
    end
  end
  -- Return to west edge (start corner)
  if d % 2 == 1 then face(2) for _ = 1, w - 1 do forward() end end
  face(3)
  for _ = 1, d - 1 do forward() end
  face(0)
end

-- === Start Mining ===
say("Starting mining sequence...")

local okFront, dataFront = turtle.inspect()
if okFront then
  say("Front blocked by: " .. (dataFront.name or "block") .. " — digging...")
  turtle.dig()
end

turtle.forward()
pos.x = pos.x + 1

for layer = 1, H do
  say(("Mining layer %d/%d..."):format(layer, H))
  serpentineLayer(W, D)
  if layer < H then
    say("Descending straight down to next layer...")
    down()
  end
end

-- === Return Home ===
say("Returning to chest position...")
-- Go straight up to surface (same vertical path)
while pos.y < 0 do up() end
while pos.y > 0 do up() end
-- Return to x/z = 0
face(2)
for _ = 1, pos.x do forward() end
face(3)
for _ = 1, pos.z do forward() end
face(2)
turtle.forward() -- move into chest position
face(0)
say("All done. Returned to chest. Happy mining!")
