--[[
LayeredQuarryMiner - Persistent Quarry Version
by FIYREX

Features:
✅ Chest must be in front
✅ Mines one fixed zone only (X×Z area)
✅ Saves progress (depth mined) to quarry_state.txt
✅ Continues deeper if user sets a greater depth
✅ Stops if quarry already complete
✅ Straight down vertical mining
✅ Auto unload when full
✅ Smart fuel check
]]

-- === Utilities ===
local function say(m) print("[Quarry] " .. m) end
local function warn(m) print("[WARN] " .. m) end

-- === User Input ===
print("Enter length (X):")
local length = tonumber(read())
print("Enter width (Z):")
local width = tonumber(read())
print("Enter total depth (Y):")
local depth = tonumber(read())

local fuelSlot = 16
local dir = 0 -- 0=N,1=E,2=S,3=W
local x, y, z = 0, 0, 0
local chestDir = 0
local chestPos = {x=0, y=0, z=0}
local stateFile = "quarry_state.txt"
local minedDepth = 0

-- === Chest Detection ===
local function isChest(name)
  return name and (name:find("chest") or name:find("barrel"))
end

local function detectChestAround()
  for i = 0, 3 do
    local ok, data = turtle.inspect()
    if ok and isChest(data.name) then
      chestDir = dir
      chestPos = {x=x, y=y, z=z}
      say("Deposit chest detected in front: " .. data.name)
      return true
    end
    turtle.turnRight()
    dir = (dir + 1) % 4
  end
  return false
end

if not detectChestAround() then
  warn("No chest detected nearby! Place one and press Enter.")
  read()
  detectChestAround()
end

-- === State Management ===
local function loadState()
  if fs.exists(stateFile) then
    local h = fs.open(stateFile, "r")
    local data = textutils.unserialize(h.readAll())
    h.close()
    if data and data.length == length and data.width == width then
      minedDepth = data.minedDepth or 0
      say("Loaded saved quarry progress: mined " .. minedDepth .. " layers.")
    else
      warn("Previous quarry dimensions differ. Starting new quarry.")
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

-- === Fuel ===
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

-- === Movement ===
local function tryDig() while turtle.detect() do turtle.dig(); sleep(0.3) end end
local function tryDigDown() while turtle.detectDown() do turtle.digDown(); sleep(0.3) end end
local function tryDigUp() while turtle.detectUp() do turtle.digUp(); sleep(0.3) end end

local function forward()
  refuel()
  tryDig()
  while not turtle.forward() do sleep(0.2) end
  if dir == 0 then z = z + 1
  elseif dir == 1 then x = x + 1
  elseif dir == 2 then z = z - 1
  elseif dir == 3 then x = x - 1 end
end

local function back()
  refuel()
  while not turtle.back() do sleep(0.2) end
  if dir == 0 then z = z - 1
  elseif dir == 1 then x = x - 1
  elseif dir == 2 then z = z + 1
  elseif dir == 3 then x = x + 1 end
end

local function down()
  refuel()
  tryDigDown()
  while not turtle.down() do sleep(0.2) end
  y = y - 1
end

local function up()
  refuel()
  tryDigUp()
  while not turtle.up() do sleep(0.2) end
  y = y + 1
end

local function turnLeft()
  turtle.turnLeft()
  dir = (dir - 1) % 4
  if dir < 0 then dir = dir + 4 end
end

local function turnRight()
  turtle.turnRight()
  dir = (dir + 1) % 4
end

local function face(target)
  while dir ~= target do turnRight() end
end

-- === Navigation ===
local function goTo(tx, ty, tz, tdir)
  while y < ty do up() end
  while y > ty do down() end

  if x < tx then face(1) while x < tx do forward() end
  elseif x > tx then face(3) while x > tx do forward() end end

  if z < tz then face(0) while z < tz do forward() end
  elseif z > tz then face(2) while z > tz do forward() end end

  face(tdir or 0)
end

-- === Inventory ===
local function isInventoryFull()
  for i = 1, 15 do
    if turtle.getItemCount(i) == 0 then return false end
  end
  return true
end

local function depositToChest()
  say("Depositing to chest...")
  goTo(chestPos.x, chestPos.y, chestPos.z, chestDir)
  face(chestDir)
  local ok, data = turtle.inspect()
  if ok and isChest(data.name) then
    for i = 1, 15 do
      turtle.select(i)
      turtle.drop()
    end
    turtle.select(1)
    say("Deposited successfully.")
  else
    warn("Chest missing! Place it again and press Enter.")
    read()
    depositToChest()
  end
end

-- === Ground Check ===
local function isGrounded()
  local ok, _ = turtle.inspectDown()
  return ok
end

-- === Layer Mining ===
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
  if width % 2 == 1 then face(2) for i = 1, length - 1 do forward() end end
  face(3) for i = 1, width - 1 do forward() end
  face(0)
end

-- === Continue from previous depth ===
if minedDepth > 0 then
  say("Descending to previous quarry depth (" .. minedDepth .. ")...")
  for i = 1, minedDepth do down() end
end

-- === Start Mining ===
say("Starting mining...")

for d = minedDepth + 1, depth do
  if not isGrounded() then
    say("No more ground — quarry already complete.")
    depositToChest()
    say("Returning to chest. Mining finished.")
    return
  end

  say(("Mining layer %d/%d..."):format(d, depth))
  mineLayer()
  minedDepth = minedDepth + 1
  saveState()

  if d < depth then
    say("Descending to next layer...")
    down()
  end
end

say("Returning to deposit chest...")
depositToChest()
say("All done. Returned to chest. Quarry saved at depth " .. minedDepth .. ".")
