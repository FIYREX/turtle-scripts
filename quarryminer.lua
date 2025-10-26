-- === FIYREX QUARRY MINER v3.1 ===
-- Layered mining, chest detection, auto return, and cobblestone fill after completion.
-- Author: FIYREX ⚙️ (2025)

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

-- === USER INPUT ===
local length = promptNumber("Enter quarry length:")
local width = promptNumber("Enter quarry width:")
local depth = promptNumber("Enter quarry depth (how many layers to dig):")

print("Quarry set: " .. length .. "×" .. width .. "×" .. depth)

-- === STATE VARIABLES ===
local face = 0
local homeFace = 0
local z = 0
local cobbleReserve = math.floor(length * width * depth * 0.75)
local fuelName = nil
local cobbleCount = 0

local ores = {
  high = {
    "minecraft:iron_ore", "minecraft:copper_ore", "minecraft:gold_ore",
    "minecraft:deepslate_iron_ore", "minecraft:deepslate_copper_ore",
    "minecraft:deepslate_gold_ore", "minecraft:diamond_ore", "minecraft:deepslate_diamond_ore"
  },
  medium = {
    "minecraft:redstone_ore", "minecraft:deepslate_redstone_ore",
    "minecraft:lapis_ore", "minecraft:deepslate_lapis_ore",
    "minecraft:nether_quartz_ore", "minecraft:ancient_debris"
  }
}

-- === MOVEMENT & FUEL ===
local function turnRight() turtle.turnRight(); face = (face + 1) % 4 end
local function turnLeft() turtle.turnLeft(); face = (face - 1) % 4 if face < 0 then face = 3 end end

local function refuel()
  if turtle.getFuelLevel() >= 200 then return end
  for i=1,16 do
    if turtle.getItemCount(i) > 0 then
      local d = turtle.getItemDetail(i)
      if d and (d.name:find("coal") or d.name:find("lava_bucket")) then
        turtle.select(i)
        turtle.refuel(1)
        if turtle.getFuelLevel() > 200 then return end
      end
    end
  end
end

local function safeForward()
  refuel()
  while not turtle.forward() do turtle.dig(); sleep(0.1) end
end

local function safeDown()
  refuel()
  while not turtle.down() do turtle.digDown(); sleep(0.1) end
  z = z + 1
end

local function safeUp()
  while not turtle.up() do turtle.digUp(); sleep(0.1) end
  z = z - 1
end

-- === CHEST DEPOSIT ===
local function depositToChest()
  print("📦 Depositing items...")
  local hasChest, data = turtle.inspect()
  if hasChest and data.name:find("chest") then
    for i=1,16 do
      turtle.select(i)
      if i ~= 16 or not turtle.refuel(0) then turtle.drop() end
    end
    print("✅ Items deposited into chest.")
  else
    print("⚠️ No chest detected. Dropping items forward.")
    for i=1,16 do turtle.select(i); turtle.drop() end
  end
  turtle.select(1)
end

-- === INVENTORY UTILITIES ===
local function countCobble()
  local total = 0
  for i=1,16 do
    local d = turtle.getItemDetail(i)
    if d and d.name == "minecraft:cobblestone" then
      total = total + turtle.getItemCount(i)
    end
  end
  return total
end

local function inventoryFull()
  for i=1,15 do
    if turtle.getItemCount(i) == 0 then return false end
  end
  return true
end

-- === ORE DETECTION ===
local function isValuable(block)
  if not block then return false end
  for _,v in pairs(ores.high) do if block.name == v then return true end end
  for _,v in pairs(ores.medium) do if block.name == v then return true end end
  return false
end

local function smartDig()
  local s,d = turtle.inspect()
  if s and isValuable(d) then turtle.dig() end
  local sU,dU = turtle.inspectUp()
  if sU and isValuable(dU) then turtle.digUp() end
  local sD,dD = turtle.inspectDown()
  if sD and isValuable(dD) then turtle.digDown() end
end

-- === RETURN HOME ===
local function returnHome()
  print("🏠 Returning to base...")
  while z > 0 do safeUp() end
  while face ~= homeFace do turnRight() end
  print("✅ Arrived at base.")
  depositToChest()
end

-- === MINING CORE ===
local function mineLayer()
  for w=1,width do
    for l=1,length-1 do
      smartDig()
      safeForward()
    end
    if w < width then
      if w % 2 == 1 then turnRight(); smartDig(); safeForward(); turnRight()
      else turnLeft(); smartDig(); safeForward(); turnLeft() end
    end
  end

  -- return to start corner
  if width % 2 == 1 then
    turnRight(); turnRight()
    for i=1,length-1 do safeForward() end
    turnRight(); for i=1,width-1 do safeForward() end; turnRight()
  else
    for i=1,width-1 do safeForward() end
    turnRight(); turnRight()
  end
end

-- === FILL-BACK ===
local function fillWithCobblestone()
  print("🔧 Filling quarry with cobblestone...")
  for i=1,16 do
    local d = turtle.getItemDetail(i)
    if d and d.name == "minecraft:cobblestone" then
      turtle.select(i)
      while turtle.placeDown() do sleep(0.02) end
    end
  end
  turtle.select(1)
  print("✅ Quarry filled with cobblestone.")
end

-- === MAIN ROUTINE ===
local function Mastermind()
  homeFace = face
  print("🚀 FIYREX QUARRY MINER v3.1")
  print("Starting layered mining...")

  for layer=1,depth do
    print("⛏️ Mining layer " .. layer .. " of " .. depth)
    mineLayer()

    if inventoryFull() then
      print("📦 Inventory full! Returning to deposit...")
      returnHome()
      print("🔁 Returning to quarry...")
      for i=1,layer do safeDown() end
    end

    if layer < depth then
      print("⬇️ Moving down to next layer...")
      safeDown()
    end
  end

  print("✅ Excavation complete!")
  returnHome()

  -- === ASK FILL AFTER COMPLETION ===
  local cobbleTotal = countCobble()
  print("Cobblestone available: " .. cobbleTotal .. " / " .. cobbleReserve)
  if promptYesNo("Would you like to fill the quarry with cobblestone?") then
    if cobbleTotal >= cobbleReserve then
      fillWithCobblestone()
    else
      print("⚠️ Not enough cobblestone for full fill. Skipping.")
    end
  else
    print("Skipped filling process.")
  end

  print("🏁 Operation complete. Turtle parked at base.")
end

Mastermind()
