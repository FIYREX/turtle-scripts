--[[
LayeredQuarryMiner - Fixed Zone Edition (Front Chest)
by FIYREX

Features:
✅ Chest must be in front
✅ Mines one fixed zone only (no offset on reruns)
✅ If area below is already mined, prints "Quarry complete"
✅ Smart fuel check and refueling
✅ Auto unload to front chest
✅ Accurate coordinates, vertical descent
]]

-- === Utilities ===
local function say(m) print("[Quarry] " .. m) end
local function warn(m) print("[WARN] " .. m) end

-- === User Input ===
print("Enter length (X):")
local length = tonumber(read())
print("Enter width (Z):")
local width = tonumber(read())
print("Enter depth (Y):")
local depth = tonumber(read())

local fuelSlot = 16

-- === State ===
local x, y, z = 0, 0, 0
local dir = 0 -- 0=N, 1=E, 2=S, 3=W

-- === Chest check (front) ===
local function isChest(name)
  return name and (name:find("chest") or name:find("barrel"))
end

local function checkFrontChest()
  local ok, data = turtle.inspect()
  if not ok or not isChest(data.name) then
    warn("No chest detected in front! Place a chest and press Enter.")
    read()
  else
    say("Detected chest in front: " .. data.name)
  end
end

checkFrontChest()

-- === Fuel Logic ===
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

-- === Dig Functions ===
local function tryDig() while turtle.detect() do turtle.dig(); sleep(0.3) end end
local function tryDigDown() while turtle.detectDown() do turtle.digDown(); sleep(0.3) end end
local function tryDigUp() while turtle.detectUp() do turtle.digUp(); sleep(0.3) end end

-- === Movement ===
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

-- === Absolute Navigation ===
local function goTo(tx, ty, tz, tdir)
  while y < ty do up() end
  while y > ty do down() end

  if x < tx then face(1) while x < tx do forward() end
  elseif x > tx then face(3) while x > tx do forward() end end

  if z < tz then face(0) while z < tz do forward() end
  elseif z > tz then face(2) while z > tz do forward() end end

  face(tdir or 0)
end

-- === Inventory Handling ===
local function isInventoryFull()
  for i = 1, 15 do
    if turtle.getItemCount(i) == 0 then return false end
  end
  return true
end

local function dropItems()
  local sx, sy, sz, sdir = x, y, z, dir
  say("Inventory full — unloading to front chest...")
  face(2)
  for i = 1, 15 do
    turtle.select(i)
    turtle.drop()
  end
  turtle.select(1)
  face(sdir)
  goTo(sx, sy, sz, sdir)
end

-- === Quarry Validation ===
local function isGrounded()
  local ok, _ = turtle.inspectDown()
  return ok
end

if not isGrounded() then
  warn("No block detected under start position. Quarry already complete.")
  return
end

-- === Layer Mining ===
local function mineLayer()
  for row = 1, width do
    for col = 1, length - 1 do
      forward()
      if isInventoryFull() then dropItems() end
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

turtle.digDown()
down()

for d = 1, depth do
  if not isGrounded() then
    say("No more ground — quarry already complete.")
    goTo(0, 0, 0, 2)
    for i = 1, 15 do
      turtle.select(i)
      turtle.drop()
    end
    say("Returning to chest. Mining finished.")
    return
  end

  say(("Mining layer %d/%d..."):format(d, depth))
  mineLayer()
  if d < depth then
    say("Descending to next layer...")
    down()
  end
end

say("Returning to chest...")
goTo(0, 0, 0, 2)
for i = 1, 15 do
  turtle.select(i)
  turtle.drop()
end
turtle.select(1)
say("All done. Returned to chest. Happy mining!")
