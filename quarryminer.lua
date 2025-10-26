-- === FIYREX QUARRY MINER (Manual-Y + Smart Priority + Return Home) ===
-- Fully autonomous quarry system with tiered ore priorities and optional cobblestone fill-back.
-- Now asks for Y-level manually and returns to the starting position after completion.

-- === PROMPT HELPERS ===
local function promptNumber(msg)
  write(msg .. " ")
  local v = tonumber(read())
  while not v or v < 1 do
    print("Please enter a positive number.")
    write(msg .. " ")
    v = tonumber(read())
  end
  return v
end

local function promptYesNo(msg)
  write(msg .. " (y/n) ")
  local a = read()
  a = (a or ""):lower()
  return (a == "y" or a == "yes")
end

-- === INPUTS ===
local l = promptNumber("Quarry length:")
local w = promptNumber("Quarry width:")
local z0 = promptNumber("Enter starting Y-level (your current height):")

print("Starting Y-level set to: " .. z0)

local whitelist = promptYesNo("Use whitelist mode?")
local digWholeChunk = promptYesNo("Dig the whole chunk?")
local fin
if digWholeChunk then
  fin = z0
else
  fin = promptNumber("Layers to dig:")
end

-- === ORE PRIORITY TABLES ===
local highPriorityOres = {
  ["minecraft:iron_ore"] = true,
  ["minecraft:copper_ore"] = true,
  ["minecraft:gold_ore"] = true,
  ["minecraft:deepslate_iron_ore"] = true,
  ["minecraft:deepslate_copper_ore"] = true,
  ["minecraft:deepslate_gold_ore"] = true,
  ["minecraft:diamond_ore"] = true,
  ["minecraft:deepslate_diamond_ore"] = true,
}

local mediumPriorityOres = {
  ["minecraft:redstone_ore"] = true,
  ["minecraft:deepslate_redstone_ore"] = true,
  ["minecraft:lapis_ore"] = true,
  ["minecraft:deepslate_lapis_ore"] = true,
  ["minecraft:nether_quartz_ore"] = true,
  ["minecraft:ancient_debris"] = true,
  ["minecraft:emerald_ore"] = true,
  ["minecraft:deepslate_emerald_ore"] = true,
}

local customPriorityOres = {
  -- Add any custom ores here:
  -- ["minecraft:emerald_ore"] = true,
}

-- === STATE VARIABLES ===
local x, y, z = 0, 0, 0
local face, rev, counter = 0, 1, 0
local arr, trashtable = {0}, {}
local cobble, stone = false, false
local slot = 16
local fuelName = nil
local startX, startY, startZ, startFace = 0, 0, 0, 0

do
  local d = turtle.getItemDetail(16)
  if d and d.name then fuelName = d.name end
end

-- === CORE HELPERS ===
local function refuel()
  if turtle.getFuelLevel() >= 500 then return end
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and (not fuelName or d.name == fuelName) then
      turtle.select(i)
      while turtle.getItemCount() > 0 and turtle.getFuelLevel() < 500 do
        turtle.refuel(1)
      end
      if not fuelName then fuelName = d.name end
      if turtle.getFuelLevel() >= 500 then
        turtle.select(1)
        return
      end
    end
  end
end

local function turn(dir)
  if dir == 1 then
    turtle.turnRight(); face = (face + 1) % 4
  elseif dir == -1 then
    turtle.turnLeft(); face = face - 1
    if face < 0 then face = face + 4 end
  end
end

local function moveForward()
  refuel()
  while not turtle.forward() do turtle.dig(); sleep(0.05) end
  if face == 0 then y = y + 1
  elseif face == 1 then x = x + 1
  elseif face == 2 then y = y - 1
  elseif face == 3 then x = x - 1 end
end

-- === ITEM HANDLING ===
local function buildList()
  for i = 1, 15 do
    if turtle.getItemCount(i) > 0 then
      local d = turtle.getItemDetail(i)
      if d and d.name then
        trashtable[i] = d.name
        if d.name == "minecraft:cobblestone" then cobble = true end
        if d.name == "minecraft:stone" then stone = true end
      end
    else slot = i; break end
  end
  print("Item list captured.")
  while face ~= 2 do turn(1) end
  for i = 1, slot - 1 do turtle.select(i); turtle.drop() end
  turn(-1); turn(-1); turtle.select(1)
end

local function depositAll()
  print("Depositing items at start point...")
  for i = 1, 16 do
    turtle.select(i)
    if i ~= 16 or not turtle.refuel(0) then turtle.drop() end
  end
  turtle.select(1)
end

-- === SMART DIGGING ===
local function smartDig(where)
  local suc, dat
  if where == "up" then suc, dat = turtle.inspectUp()
  elseif where == "down" then suc, dat = turtle.inspectDown()
  else suc, dat = turtle.inspect() end

  if suc and dat and dat.name then
    if highPriorityOres[dat.name] or mediumPriorityOres[dat.name] or customPriorityOres[dat.name] then
      print("⛏️ Mining valuable ore: " .. dat.name)
      if where == "up" then while turtle.digUp() do sleep(0.05) end
      elseif where == "down" then while turtle.digDown() do sleep(0.05) end
      else while turtle.dig() do sleep(0.05) end end
    end
  end
end

local function isFull()
  for i = 1, 15 do if turtle.getItemCount(i) == 0 then return false end end
  return true
end

local function trashRemoval()
  for i = 1, 15 do
    if not arr[i + 1] then
      local dispose = whitelist
      local d = turtle.getItemDetail(i)
      if d then
        for j = 1, slot - 1 do
          if whitelist then if d.name == trashtable[j] then dispose = false end
          else if d.name == trashtable[j] then dispose = true end end
        end
        local tags = (d and d.tags) or {}
        if cobble and tags["forge:cobblestone"] then dispose = not whitelist end
        if stone and tags["forge:stone"] then dispose = not whitelist end
        if dispose then turtle.select(i); turtle.drop() end
      end
      if turtle.getItemCount(i) > 0 then arr[i + 1] = 1; arr[1] = (arr[1] or 0) + 1 end
    end
  end
  turtle.select(1)
end

local function checkfuel()
  refuel()
  local need = (x + y + z) + (l * w)
  if turtle.getFuelLevel() < need then goHome("fuel") end
end

local function mineStep()
  if counter % 16 == 0 then checkfuel(); counter = 1 else counter = counter + 1 end
  moveForward()
  smartDig("down"); smartDig("up"); smartDig("front")
  if isFull() then trashRemoval(); if (arr[1] or 0) >= 14 then goHome("full") end end
end

-- === MOVEMENT ===
local function Bore()
  while z < z0 - 3 do while not turtle.down() do turtle.digDown() end; z = z + 1 end
end

local function moveY()
  if y == 0 then
    while y < l - 1 do mineStep() end
  else
    while y > 0 do mineStep() end
  end
end

local function quarry()
  refuel()
  for i = 0, w - 1 do
    moveY()
    if i < w - 1 then
      if (i % 2) == 0 then turn(rev) else turn(-rev) end
      mineStep()
    end
  end
end

-- === FILL BACK ===
local function fillWithCobblestone()
  print("🔧 Filling quarry with cobblestone...")
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and d.name == "minecraft:cobblestone" then
      turtle.select(i)
      while turtle.placeDown() do sleep(0.02) end
    end
  end
  turtle.select(1)
  print("✅ Quarry filled with cobblestone.")
end

-- === GO HOME ===
local function goHome()
  print("Returning to start point...")
  -- Go up to surface
  while z > 0 do turtle.up(); z = z - 1 end
  -- Face forward and move to origin
  while y > 0 do if face == 2 then moveForward() else turn(1) end end
  while x > 0 do if face == 3 then moveForward() else turn(-1) end end
  -- Restore starting direction
  while face ~= startFace do turn(1) end
  print("✅ Returned to starting position.")
  depositAll()
end

-- === MASTER ROUTINE ===
local function Mastermind()
  startFace = face
  print("Starting mining at Y=" .. z0)
  buildList()
  refuel()
  if turtle.getFuelLevel() < 500 then
    print("Not enough fuel. Insert more and wait...")
    repeat sleep(5); refuel() until turtle.getFuelLevel() >= 500
  end

  Bore()
  for i = 0, fin - 3 do
    if i % 3 == 0 then
      turtle.digUp()
      quarry()
      if (w % 2) == 0 then rev = -rev end
      trashRemoval()
    end
    if i < fin - 3 then while not turtle.up() do turtle.digUp() end; z = z - 1 end
  end
  trashRemoval()
  print("✅ Mining complete.")

  if promptYesNo("Would you like to fill the quarry with cobblestone?") then
    fillWithCobblestone()
  else
    print("Skipped filling process.")
  end

  goHome()
  print("🏁 All tasks complete. Turtle ready for next operation.")
end

Mastermind()
