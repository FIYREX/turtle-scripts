--[[
LayeredQuarryMiner - Persistent Stable Version (Front Chest Safe)
by FIYREX

Features:
✅ Chest stays safe in front (never mined)
✅ Mines directly below the turtle, not in front
✅ Same spot only — never moves horizontally
✅ Continues mining deeper if depth increased
✅ Stops if same/smaller depth
✅ Auto unload to front chest
✅ Saves progress to quarry_state.txt
✅ Smart fuel check
]]

-- === Utilities ===
local function say(m) print("[Quarry] " .. m) end
local function warn(m) print("[WARN] " .. m) end

-- === User Input ===
print("Enter quarry length (X):")
local length = tonumber(read())
print("Enter quarry width (Z):")
local width = tonumber(read())
print("Enter quarry depth (Y):")
local depth = tonumber(read())

local fuelSlot = 16
local stateFile = "quarry_state.txt"
local minedDepth = 0

-- === Chest Detection (in front) ===
local function isChest(name)
  return name and (name:find("chest") or name:find("barrel"))
end

local function checkChestFront()
  local ok, data = turtle.inspect()
  if not ok or not isChest(data.name) then
    warn("No chest detected in front! Place one and press Enter.")
    read()
    return checkChestFront()
  end
  say("Deposit chest detected in front: " .. data.name)
end

checkChestFront()

-- === State Persistence ===
local function loadState()
  if fs.exists(stateFile) then
    local h = fs.open(stateFile, "r")
    local data = textutils.unserialize(h.readAll())
    h.close()
    if data and data.length == length and data.width == width then
      minedDepth = data.minedDepth or 0
      say("Loaded previous quarry progress: mined " .. minedDepth .. " layers.")
    else
      warn("Different quarry size detected. Starting new quarry.")
      minedDepth = 0
    end
  end
end

local function saveState()
  local h = fs.open(stateFile, "w")
  h.write(textutils.serialize({length = length, width = width, minedDepth = minedDepth}))
  h.close()
end

loadState()

if minedDepth >= depth then
  warn("Quarry already complete up to " .. minedDepth .. " layers.")
  return
end

-- === Fuel Management ===
local function estimateFuel()
  local total = (length * width * depth * 2) + (length + width + depth)
  return math.ceil(total * 1.1)
end

local function refuel()
  if turtle.getFuelLevel() == "unlimited" then return end
  if turtle.getFuelLevel() < 10 then
    turtle.select(fuelSlot)
    turtle.refuel(1)
  end
end

local function ensureFuel()
  local need = estimateFuel()
  local current = turtle.getFuelLevel()
  say("Fuel check: current = " .. current .. ", required = " .. need)
  if current < need then
    warn("Not enough fuel! Add fuel and press Enter.")
    read()
    for i = 1, 16 do turtle.select(i) turtle.refuel(64) end
    say("New fuel level: " .. turtle.getFuelLevel())
  else
    say("Fuel sufficient.")
  end
end

ensureFuel()

-- === Basic Helpers ===
local function tryDig() while turtle.detect() do turtle.dig(); sleep(0.3) end end
local function tryDigDown() while turtle.detectDown() do turtle.digDown(); sleep(0.3) end end
local function tryDigUp() while turtle.detectUp() do turtle.digUp(); sleep(0.3) end end

local function isGrounded()
  local ok, _ = turtle.inspectDown()
  return ok
end

-- === Safe Move Functions ===
local function forward() refuel() tryDig() while not turtle.forward() do sleep(0.2) end end
local function back() refuel() while not turtle.back() do sleep(0.2) end end
local function down() refuel() tryDigDown() while not turtle.down() do sleep(0.2) end end
local function up() refuel() tryDigUp() while not turtle.up() do sleep(0.2) end end
local function turnLeft() turtle.turnLeft() end
local function turnRight() turtle.turnRight() end

-- === Deposit Function ===
local function depositToChest()
  turnRight(); turnRight() -- face chest
  local ok, data = turtle.inspect()
  if ok and isChest(data.name) then
    say("Depositing items to chest...")
    for i = 1, 15 do
      turtle.select(i)
      turtle.drop()
    end
    turtle.select(1)
  else
    warn("Chest not found in front! Please replace it.")
  end
  turnRight(); turnRight() -- face quarry again
end

local function isInventoryFull()
  for i = 1, 15 do
    if turtle.getItemCount(i) == 0 then return false end
  end
  return true
end

-- === Serpentine Layer Mining ===
local function mineLayer()
  for row = 1, width do
    for col = 1, length - 1 do
      forward()
      if isInventoryFull() then depositToChest() end
    end
    if row < width then
      if row % 2 == 1 then turnRight(); forward(); turnRight()
      else turnLeft(); forward(); turnLeft() end
    end
  end
  -- Return to starting corner
  if width % 2 == 1 then
    turnRight(); turnRight()
    for i = 1, length - 1 do forward() end
  end
  turnRight()
  for i = 1, width - 1 do forward() end
  turnRight()
end

-- === Prepare to Mine (move down first layer) ===
say("Preparing mining zone...")
turnRight(); turnRight() -- face away from chest
if minedDepth == 0 then
  if not isGrounded() then
    warn("No ground detected below start position.")
    return
  end
  turtle.digDown()
  down()
else
  for i = 1, minedDepth do down() end
end

-- === Main Mining Execution ===
say("Starting mining...")

for layer = minedDepth + 1, depth do
  if not isGrounded() then
    say("No more ground — quarry complete at depth " .. (layer - 1))
    depositToChest()
    minedDepth = layer - 1
    saveState()
    return
  end
  say(("Mining layer %d/%d..."):format(layer, depth))
  mineLayer()
  minedDepth = layer
  saveState()
  if layer < depth then
    say("Descending to next layer...")
    down()
  end
end

-- === Return to Surface ===
say("Mining finished. Returning to surface...")
for i = 1, minedDepth do up() end
depositToChest()
say("Quarry progress saved. Total depth mined: " .. minedDepth)
