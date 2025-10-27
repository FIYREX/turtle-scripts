-- ======================================================
-- Smart Column Quarry Miner v5.3
-- FIYREX + GPT-5
--
-- Mines entire rectangular area by vertical columns.
-- (No zig-zag movement, fixed per-column mining.)
--
-- Features:
--  ✅ Length, Width, Height quarry inputs
--  ✅ Column-by-column vertical mining
--  ✅ Bedrock detection & safe stop
--  ✅ Auto-return & deposit
--  ✅ Resume from saved progress
--  ✅ Fuel estimation & auto-refuel
--  ✅ Fault-tolerant telemetry (v5.2)
-- ======================================================

-- === Utility ===
local function prompt(msg) write(msg .. " "); return read() end
local function promptNumber(msg)
  write(msg .. " ")
  local v = tonumber(read())
  while not v or v <= 0 do
    print("Enter a valid positive number.")
    write(msg .. " "); v = tonumber(read())
  end
  return v
end
local function nowUtc() return os.epoch("utc") end
local function fmt2(x) return string.format("%.2f", x) end

-- === Config ===
local PROGRESS_FILE = "progress.txt"
local LOG_DIR = "logs"
local FUEL_SLOT = 1
local LENGTH, WIDTH, HEIGHT = 0, 0, 0
local CHEST_SIDE = "right"
local FAST_MODE = false
local blocksMined = 0
local depositedCount = 0
local minerId = "Miner-1"

local modemType, modemSide = "none", nil
local rangeDescription, telemetryDelay = "N/A", 5
local lastSend = 0
local lastOnline = nowUtc()
local lastSignalWarned = false

local sessionStart = nowUtc()
local startFuel = turtle.getFuelLevel()
local speaker = peripheral.find("speaker")

-- === Progress ===
local currentX, currentZ = 1, 1
local currentDepth = 0

-- === File IO ===
local function saveProgress(x, z)
  local f = fs.open(PROGRESS_FILE, "w")
  f.write(textutils.serialize({x=x, z=z}))
  f.close()
end

local function loadProgress()
  if fs.exists(PROGRESS_FILE) then
    local f = fs.open(PROGRESS_FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()
    return data
  end
  return nil
end

local function clearProgress()
  if fs.exists(PROGRESS_FILE) then fs.delete(PROGRESS_FILE) end
end

-- === Modem ===
local function detectModemType()
  for _, s in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(s)
    if t == "ender_modem" or t == "wired_modem" or t == "modem" then
      return t, s
    end
  end
  return "none", nil
end

local function openModem()
  modemType, modemSide = detectModemType()
  if modemType ~= "none" then
    if not rednet.isOpen(modemSide) then rednet.open(modemSide) end
    if modemType == "ender_modem" then
      rangeDescription, telemetryDelay = "Unlimited (Ender Network)", 3
    elseif modemType == "wired_modem" then
      rangeDescription, telemetryDelay = "Unlimited (Wired Cable)", 3
    else
      rangeDescription, telemetryDelay = "Approx. 64 blocks radius", 10
    end
    print(("📡 Modem: %s | Side: %s | Range: %s | Telemetry: %.1fs")
      :format(modemType, tostring(modemSide), rangeDescription, telemetryDelay))
    return true
  else
    print("⚠️ No modem detected — telemetry offline.")
    return false
  end
end

local function sendStatus(stage, extra, force)
  local payload = {
    id = minerId, stage = stage,
    x = currentX, z = currentZ, depth = currentDepth,
    length = LENGTH, width = WIDTH, height = HEIGHT,
    fuel = turtle.getFuelLevel(),
    deposited = depositedCount,
    ts = nowUtc(),
    analytics = {
      items_per_min = (depositedCount / math.max(1, (nowUtc() - sessionStart)/60000)),
      fuel_per_k = (startFuel ~= "unlimited" and turtle.getFuelLevel() ~= "unlimited")
        and (math.max(0,(startFuel - turtle.getFuelLevel())) / math.max(1, blocksMined/1000))
        or -1,
      blocks_mined = blocksMined
    },
    extra = extra
  }

  local intervalOk = force or ((os.clock() - lastSend) > telemetryDelay)
  if not intervalOk then return end

  if modemType ~= "none" and modemSide and rednet.isOpen(modemSide) then
    rednet.broadcast(payload, "quarry_status")
    lastSend = os.clock()
    lastOnline = nowUtc()
    lastSignalWarned = false
  else
    openModem()
  end

  if (nowUtc() - lastOnline) > 30000 and not lastSignalWarned then
    print("⚠️ Telemetry offline for >30s.")
    if speaker then pcall(function() speaker.playNote("harp", 3, 12) end) end
    lastSignalWarned = true
  end
end

-- === Fuel ===
local function calcFuelNeed(l, w, h)
  return (l*w*h)*2 + 100
end

local function checkFuel(required)
  local fuel = turtle.getFuelLevel()
  if fuel == "unlimited" then return end
  while fuel < required do
    print(("Fuel Low: %d / %d"):format(fuel, required))
    turtle.select(FUEL_SLOT)
    if not turtle.refuel(1) then
      print("Add fuel to slot 1.")
      sleep(3)
    end
    fuel = turtle.getFuelLevel()
    sendStatus("refuel", {needed = required}, true)
  end
end

-- === Inventory ===
local function isFull()
  for i=2,16 do if turtle.getItemCount(i)==0 then return false end end
  return true
end

local function deposit()
  sendStatus("deposit", {}, true)
  print("Depositing...")
  if CHEST_SIDE=="right" then turtle.turnRight()
  elseif CHEST_SIDE=="left" then turtle.turnLeft()
  elseif CHEST_SIDE=="back" then turtle.turnRight(); turtle.turnRight() end
  for i=2,16 do
    turtle.select(i)
    if turtle.getItemCount(i)>0 then
      local count=turtle.getItemCount(i)
      if turtle.drop() then depositedCount=depositedCount+count end
    end
  end
  if CHEST_SIDE=="right" then turtle.turnLeft()
  elseif CHEST_SIDE=="left" then turtle.turnRight()
  elseif CHEST_SIDE=="back" then turtle.turnRight(); turtle.turnRight() end
  turtle.select(2)
  sendStatus("deposit_done",{deposited=depositedCount},true)
end

-- === Bedrock Detection ===
local function isBedrockBelow()
  if not turtle.detectDown() then return false end
  if not turtle.digDown() then return true end
  return false
end

-- === Movement ===
local function moveForwardSafe()
  while not turtle.forward() do
    turtle.dig()
    sleep(0.1)
  end
end

local function moveNextColumn(x, z)
  -- Move one step in the X direction
  if x < LENGTH then
    moveForwardSafe()
  else
    -- Move to next row (Z)
    turtle.turnRight()
    moveForwardSafe()
    turtle.turnRight()
    for _=1,LENGTH-1 do moveForwardSafe() end
    turtle.turnLeft(); turtle.turnLeft()
  end
end

-- === Column Mining ===
local function mineColumn(depth)
  for d=1,depth do
    currentDepth=d
    if isBedrockBelow() then
      print("Bedrock reached.")
      sendStatus("halt_bedrock", {}, true)
      for _=1,d-1 do turtle.up() end
      return
    end
    turtle.digDown()
    turtle.down()
    blocksMined=blocksMined+1
    if isFull() then
      print("Inventory full, returning to deposit.")
      for _=1,d do turtle.up() end
      deposit()
      for _=1,d do turtle.down() end
    end
    sendStatus("layer", {})
  end
  -- Return up
  for _=1,depth do turtle.up() end
end

-- === Main ===
term.clear(); term.setCursorPos(1,1)
print("=== Smart Column Quarry Miner v5.3 ===")
openModem()

local prev = loadProgress()
if prev then
  print(("Previous progress found (X:%d Z:%d)"):format(prev.x, prev.z))
  local opt; repeat opt=prompt("Resume from last progress? (yes/no): ") until opt=="yes" or opt=="no"
  if opt=="no" then clearProgress(); prev=nil end
end

LENGTH = promptNumber("Enter length:")
WIDTH = promptNumber("Enter width:")
HEIGHT = promptNumber("Enter depth (height):")
CHEST_SIDE = prompt("Chest side (left/right/back):")
minerId = prompt("Miner ID (e.g., Miner-1):")

local needed = calcFuelNeed(LENGTH, WIDTH, HEIGHT)
checkFuel(needed)
sendStatus("init",{range=rangeDescription},true)

print("Starting mining grid " .. LENGTH .. "x" .. WIDTH .. " depth " .. HEIGHT)
for z=(prev and prev.z or 1),WIDTH do
  for x=(prev and prev.x or 1),LENGTH do
    currentX, currentZ = x, z
    print(("Mining column X:%d Z:%d"):format(x,z))
    sendStatus("column_start", {x=x, z=z}, true)
    mineColumn(HEIGHT)
    saveProgress(x,z)
    if not (x==LENGTH and z==WIDTH) then moveNextColumn(x,z) end
  end
end

deposit()
clearProgress()
sendStatus("done",{blocks_mined=blocksMined,items=depositedCount},true)
print("✅ Quarry complete.")
if speaker then pcall(function() speaker.playNote("bell",3,12) end) end
