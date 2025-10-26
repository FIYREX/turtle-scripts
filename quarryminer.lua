-- === FIYREX QUARRY MINER v2.5 ===
-- Depth-based autonomous mining turtle with Layered Quarry Logic,
-- Smart Chest Detection, and Cobblestone Assurance System (CAS)
-- Created by FIYREX ⚙️

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
local depth = promptNumber("Quarry depth (how many blocks down to dig):")

print("Mining will go " .. depth .. " blocks deep from current position.")

local whitelist = promptYesNo("Use whitelist mode?")
local digWholeChunk = promptYesNo("Dig the whole chunk?")

-- === VARIABLES ===
local x, y, z = 0, 0, 0
local face, rev, counter = 0, 1, 0
local arr, trashtable = {0}, {}
local cobble, stone = false, false
local slot = 16
local fuelName = nil
local startFace = 0
local homeX, homeY, homeZ, homeFace = 0, 0, 0, 0

-- Cobblestone Reserve Logic
local cobbleCount = 0
local cobbleReserve = math.floor(l * w * depth * 0.75)
print("Cobblestone reserve target for fill: " .. cobbleReserve .. " blocks.")

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
}

local customPriorityOres = {
  -- Add any custom ores here
  -- ["minecraft:emerald_ore"] = true,
}

-- === INITIALIZATION ===
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
end

-- === SMART CHEST DEPOSIT ===
local function depositAll()
  print("📦 Depositing items...")
  local hasChest, data = turtle.inspect()
  local chestFound = hasChest and data.name:find("chest")

  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d then
      if d.name == "minecraft:cobblestone" and cobbleCount < cobbleReserve then
        -- Keep cobblestone until reserve met
      else
        turtle.select(i)
        if chestFound then turtle.drop() else turtle.drop() end
      end
    end
  end
  turtle.select(1)
  print(chestFound and "✅ Deposited into chest." or "⚠️ No chest found, items dropped forward.")
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

-- === COBBLE REFILL SYSTEM ===
local function cobbleCheckAndRefill(cobbleNeeded)
  print("🔍 Checking cobblestone inventory for fill...")
  local cobbleCount = 0
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and d.name == "minecraft:cobblestone" then
      cobbleCount = cobbleCount + turtle.getItemCount(i)
    end
  end

  if cobbleCount >= cobbleNeeded then
    print("✅ Enough cobblestone available: " .. cobbleCount)
    return true
  end

  local missing = cobbleNeeded - cobbleCount
  print("⚠️ Not enough cobblestone. Need " .. missing .. " more blocks.")

  local hasChest, chestData = turtle.inspect()
  if hasChest and chestData.name:find("chest") then
    print("📦 Chest detected in front. Attempting to pull cobblestone...")
    while missing > 0 do
      if turtle.suck() then
        cobbleCount = 0
        for i = 1, 16 do
          local d = turtle.getItemDetail(i)
          if d and d.name == "minecraft:cobblestone" then
            cobbleCount = cobbleCount + turtle.getItemCount(i)
          end
        end
        missing = cobbleNeeded - cobbleCount
        if missing <= 0 then
          print("✅ Cobblestone refill complete!")
          return true
        end
      else
        print("⏳ Waiting for cobblestone in chest... still need " .. missing)
        sleep(5)
      end
    end
  else
    print("❌ No chest found. Please supply cobblestone manually.")
    repeat
      sleep(5)
      local current = 0
      for i = 1, 16 do
        local d = turtle.getItemDetail(i)
        if d and d.name == "minecraft:cobblestone" then
          current = current + turtle.getItemCount(i)
        end
      end
      missing = cobbleNeeded - current
    until missing <= 0
  end
  return true
end

-- === MINING CORE ===
local function checkfuel()
  refuel()
  local need = (x + y + z) + (l * w)
  if turtle.getFuelLevel() < need then
    print("⚠️ Low fuel. Waiting for refill...")
    repeat sleep(5); refuel() until turtle.getFuelLevel() >= need
  end
end

local function mineStep()
  checkfuel()
  moveForward()
  smartDig("down"); smartDig("up"); smartDig("front")
end

local function moveY()
  if y == 0 then
    while y < l - 1 do mineStep(); y = y + 1 end
  else
    while y > 0 do mineStep(); y = y - 1 end
  end
end

local function quarry()
  refuel()
  for i = 0, w - 1 do
    moveY()
    if i < w - 1 then
      if (i % 2) == 0 then turn(1) else turn(-1) end
      mineStep()
    end
  end
end

-- === RETURN TO BASE ===
local function goHome()
  print("🔙 Returning to base...")

  while z > 0 do
    if not turtle.up() then turtle.digUp(); sleep(0.05) end
    z = z - 1
  end

  while y > 0 do if face ~= 2 then while face ~= 2 do turn(1) end end; moveForward(); y = y - 1 end
  while x > 0 do if face ~= 3 then while face ~= 3 do turn(1) end end; moveForward(); x = x - 1 end
  while face ~= homeFace do turn(1) end

  print("✅ Turtle returned to base.")

  local hasChest, data = turtle.inspect()
  if hasChest and data.name:find("chest") then
    print("📦 Chest detected! Depositing directly...")
    for i = 1, 16 do
      turtle.select(i)
      if i ~= 16 or not turtle.refuel(0) then turtle.drop() end
    end
    print("✅ Deposit complete.")
  else
    print("⚠️ No chest detected. Dropping items forward.")
    for i = 1, 16 do turtle.select(i); turtle.drop() end
  end

  turtle.select(1)
  print("🏁 Turtle parked at base and ready.")
end

-- === FILL-BACK ===
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

-- === MAIN EXECUTION ===
local function Mastermind()
  startFace = face
  homeX, homeY, homeZ, homeFace = x, y, z, face
  print("🚀 Starting FIYREX Quarry Miner (Layered Mode)")
  buildList()
  refuel()

  -- === LAYERED QUARRY LOGIC ===
  for currentDepth = 1, depth do
    print("⛏️ Mining layer " .. currentDepth .. " of " .. depth)
    quarry()
    depositAll()

    if currentDepth < depth then
      print("⬇️ Descending to next layer...")
      if not turtle.down() then
        while not turtle.down() do turtle.digDown(); sleep(0.05) end
      end
      z = z + 1
    end
  end

  print("✅ Excavation complete.")
  if promptYesNo("Would you like to fill the quarry with cobblestone?") then
    local cobbleNeeded = math.floor(l * w * depth * 0.75)
    print("🧮 Estimated cobblestone needed: " .. cobbleNeeded)
    if cobbleCheckAndRefill(cobbleNeeded) then
      fillWithCobblestone()
    else
      print("❌ Could not verify cobblestone supply. Skipping fill.")
    end
  else
    print("Skipped filling process.")
  end

  goHome()
  print("🏁 All tasks complete. Turtle ready for next operation.")
end

Mastermind()
