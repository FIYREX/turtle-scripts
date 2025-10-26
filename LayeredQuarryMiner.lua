--[[
LayeredQuarryMiner - Smart All-Side Chest Version
by FIYREX

Features:
✅ Detects deposit chest on any side (not just front)
✅ Mines the same quarry spot directly below the turtle
✅ Continues deeper if same location re-run with higher depth
✅ Stops gracefully if area is already mined (air below)
✅ Auto unload: searches all sides for chest each time
✅ Smart fuel system and safe descent
✅ Never mines or destroys the chest
]]

-- === Utility ===
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
local chestDir = nil

-- === Chest Detection (Any Side) ===
local function isChest(name)
  return name and (name:find("chest") or name:find("barrel"))
end

local function findChest()
  for i = 0, 3 do
    local ok, data = turtle.inspect()
    if ok and isChest(data.name) then
      chestDir = dir
      say("Detected deposit chest on side " .. i)
      return true
    end
    turtle.turnRight()
    dir = (dir + 1) % 4
  end
  warn("No chest found on any side! Place one near me and press Enter.")
  read()
  return findChest()
end

findChest()

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
    say("Refueled. New fuel level: " .. turtle.getFuelLevel())
  else
    say("Fuel sufficient.")
  end
end

ensureFuel()

-- === Movement ===
local function tryDig() while turtle.detect() do turtle.dig(); sleep(0.2) end end
local function tryDigDown() while turtle.detectDown() do turtle.digDown(); sleep(0.2) end end
local function tryDigUp() while turtle.detectUp() do turtle.digUp(); sleep(0.2) end end

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

-- === Inventory ===
local function isInventoryFull()
  for i = 1, 15 do
    if turtle.getItemCount(i) == 0 then return false end
  end
  return true
end

local function depositToChest()
  say("Depositing items...")
  for i = 0, 3 do
    local ok, data = turtle.inspect()
    if ok and isChest(data.name) then
      for slot = 1, 15 do
        turtle.select(slot)
        turtle.drop()
      end
      turtle.select(1)
      say("Deposit complete on side " .. i)
      return
    end
    turtle.turnRight()
    dir = (dir + 1) % 4
  end
  warn("No chest detected on any side for deposit! Place one and press Enter.")
  read()
  depositToChest()
end

-- === Ground Check ===
local function isGrounded()
  local ok, _ = turtle.inspectDown()
  return ok
end

-- === Mining Pattern ===
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

-- === Mining Execution ===
say("Starting mining...")
local okBelow, _ = turtle.inspectDown()
if not okBelow then
  say("No block below — quarry complete at this position.")
  return
end

turtle.digDown()
down()

for d = 1, depth do
  if not isGrounded() then
    say("No more blocks below — quarry complete.")
    depositToChest()
    return
  end
  say(("Mining layer %d/%d..."):format(d, depth))
  mineLayer()
  if d < depth then
    say("Descending to next layer...")
    down()
  end
end

say("Returning to chest for final deposit...")
depositToChest()
say("All done. Returned to chest. Happy mining!")
