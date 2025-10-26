-- === FIYREX QUARRY MINER ===
-- Depth-based autonomous mining turtle with Smart Ore Priority and Cobblestone Assurance System (CAS)
-- Features: Depth input, ore priority, auto-refuel, auto-deposit, cobblestone reserve & auto-fill

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

-- === STATE VARIABLES ===
local x, y, z = 0, 0, 0
local face, rev, counter = 0, 1, 0
local arr, trashtable = {0}, {}
local cobble, stone = false, false
local slot = 16
local fuelName = nil
local startFace = 0

-- === COBBLESTONE CONTROL ===
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
  ["minecraft:emerald_ore"] = true,
  ["minecraft:deepslate_emerald_ore"] = true,

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

-- === UTILITY FUNCTIONS ===
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

-- === ITEM MANAGEMENT ===
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

local function depositAll()
  print("Depositing items (keeping cobblestone reserve)...")
  cobbleCount = 0
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and d.name == "minecraft:cobblestone" then
      cobbleCount = cobbleCount + turtle.getItemCount(i)
    end
  end

  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d then
      if d.name == "minecraft:cobblestone" and cobbleCount < cobbleReserve then
        -- Keep cobblestone until reserve met
      else
        turtle.select(i)
        if i ~= 16 or not turtle.refuel(0) then turtle.drop() end
      end
    end
  end
  turtle.select(1)
  print(string.format("💾 Cobblestone held: %d / %d", cobbleCount, cobbleReserve))
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
    print("❌ No chest found in front. Please place cobblestone manually.")
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

-- === MINING LOGIC ===
local function checkfuel()
  refuel()
  local need = (x + y + z) + (l * w)
  if turtle.getFuelLevel() < need then
    print("⚠️ Low fuel. Waiting for refill...")
    repeat sleep(5); refuel() until turtle.getFuelLevel() >= need
  end
end

local function mineStep()
  if counter % 16 == 0 then checkfuel(); counter = 1 else counter = counter + 1 end
  moveForward()
  smartDig("down"); smartDig("up"); smartDig("front")
  if isFull() then
    print("📦 Inventory full. Returning to deposit...")
    depositAll()
  end
end

local function Bore()
  print("⬇️ Digging down " .. depth .. " blocks...")
  for i = 1, depth do
    while not turtle.down() do turtle.digDown(); sleep(0.05) end
    z = z + 1
  end
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

local function goHome()
  print("Returning to start point...")
  while z > 0 do turtle.up(); z = z - 1 end
  while y > 0 do if face == 2 then moveForward() else turn(1) end end
  while x > 0 do if face == 3 then moveForward() else turn(-1) end end
  while face ~= startFace do turn(1) end
  print("✅ Returned to starting position.")
  depositAll()
end

-- === MASTER ROUTINE ===
local function Mastermind()
  startFace = face
  print("🚀 Starting FIYREX Quarry Miner")
  buildList()
  refuel()

  if turtle.getFuelLevel() < 500 then
    print("Not enough fuel. Insert more and wait...")
    repeat sleep(5); refuel() until turtle.getFuelLevel() >= 500
  end

  Bore()
  for i = 0, depth - 3 do
    if i % 3 == 0 then
      turtle.digUp()
      quarry()
      if (w % 2) == 0 then rev = -rev end
      depositAll()
    end
    if i < depth - 3 then while not turtle.up() do turtle.digUp() end; z = z - 1 end
  end

  print("✅ Mining complete.")

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
