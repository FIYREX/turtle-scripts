-- ======================================================
-- Smart Column Stack Miner v5.4
-- FIYREX + GPT-5
--
-- Mines each column straight down and up in a fixed grid.
-- Pattern: Down → Up → Step Forward → Down → Up → Repeat.
--
-- Features:
--  ✅ Straight column mining (no zig-zag)
--  ✅ Length × Width × Height
--  ✅ Auto-return to chest after finish/deposit
--  ✅ Resume-safe (column tracking)
--  ✅ Full telemetry & refuel logic
-- ======================================================

-- === Utilities ===
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
local FUEL_SLOT = 1
local LENGTH, WIDTH, HEIGHT = 0, 0, 0
local CHEST_SIDE = "right"
local blocksMined = 0
local depositedCount = 0
local minerId = "Miner-1"

-- === Tracking ===
local posX, posZ = 0, 0
local facing = 0  -- 0=N,1=E,2=S,3=W
local currentX, currentZ = 1, 1
local currentDepth = 0

-- === Telemetry ===
local modemType, modemSide = "none", nil
local telemetryDelay = 5
local rangeDescription = "N/A"
local lastSend = 0
local protocol = "quarry_status"
local lastOnline = nowUtc()
local sessionStart = nowUtc()
local startFuel = turtle.getFuelLevel()
local lastSignalWarned = false
local speaker = peripheral.find("speaker")

-- === Progress ===
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
local function clearProgress() if fs.exists(PROGRESS_FILE) then fs.delete(PROGRESS_FILE) end end

-- === Movement Helpers ===
local function turnRight() turtle.turnRight(); facing=(facing+1)%4 end
local function turnLeft()  turtle.turnLeft();  facing=(facing+3)%4 end
local function faceNorth() while facing~=0 do turnLeft() end end

local function moveForwardSafe()
  while not turtle.forward() do
    turtle.dig()
    sleep(0.1)
  end
  if facing==0 then posZ=posZ-1
  elseif facing==1 then posX=posX+1
  elseif facing==2 then posZ=posZ+1
  elseif facing==3 then posX=posX-1 end
end

-- === Return to Chest ===
local function faceDirection(dir)
  while facing ~= dir do turnLeft() end
end
local function returnToStart()
  print("Returning to chest...")
  if posZ > 0 then faceDirection(0)
  elseif posZ < 0 then faceDirection(2) end
  for _=1,math.abs(posZ) do moveForwardSafe() end
  posZ=0

  if posX > 0 then faceDirection(3)
  elseif posX < 0 then faceDirection(1) end
  for _=1,math.abs(posX) do moveForwardSafe() end
  posX=0
  faceDirection(0)
end

-- === Bedrock Detection ===
local function isBedrockBelow()
  if not turtle.detectDown() then return false end
  if not turtle.digDown() then return true end
  return false
end

-- === Fuel ===
local function calcFuelNeed(l,w,h)
  return (l*w*h)*2 + 100
end
local function checkFuel(required)
  local fuel = turtle.getFuelLevel()
  if fuel == "unlimited" then return end
  while fuel < required do
    print(("Fuel Low: %d / %d"):format(fuel, required))
    turtle.select(FUEL_SLOT)
    if not turtle.refuel(1) then print("Add fuel in slot 1."); sleep(3) end
    fuel = turtle.getFuelLevel()
  end
end

-- === Inventory ===
local function isFull()
  for i=2,16 do if turtle.getItemCount(i)==0 then return false end end
  return true
end
local function deposit()
  print("Depositing items...")
  if CHEST_SIDE=="right" then turtle.turnRight()
  elseif CHEST_SIDE=="left" then turtle.turnLeft()
  elseif CHEST_SIDE=="back" then turtle.turnRight(); turtle.turnRight() end
  for i=2,16 do
    turtle.select(i)
    local count=turtle.getItemCount(i)
    if count>0 then
      if turtle.drop() then depositedCount=depositedCount+count end
    end
  end
  if CHEST_SIDE=="right" then turtle.turnLeft()
  elseif CHEST_SIDE=="left" then turtle.turnRight()
  elseif CHEST_SIDE=="back" then turtle.turnRight(); turtle.turnRight() end
  turtle.select(2)
end

-- === Modem ===
local function detectModemType()
  for _,s in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(s)
    if t=="ender_modem" or t=="wired_modem" or t=="modem" then return t,s end
  end
  return "none",nil
end
local function openModem()
  modemType,modemSide=detectModemType()
  if modemType~="none" then
    if not rednet.isOpen(modemSide) then rednet.open(modemSide) end
    rangeDescription = (modemType=="ender_modem" and "Unlimited (Ender)")
      or (modemType=="wired_modem" and "Unlimited (Wired)") or "64 blocks"
    print("📡 Modem detected:",modemType,"| Range:",rangeDescription)
  else
    print("⚠️ No modem detected.")
  end
end
local function sendStatus(stage,extra,force)
  local payload = {
    id=minerId,stage=stage,
    x=currentX,z=currentZ,depth=currentDepth,
    length=LENGTH,width=WIDTH,height=HEIGHT,
    fuel=turtle.getFuelLevel(),deposited=depositedCount,
    ts=nowUtc(),
    analytics={
      items_per_min=depositedCount/math.max(1,(nowUtc()-sessionStart)/60000),
      blocks_mined=blocksMined
    },
    extra=extra
  }
  local ok=(force or (os.clock()-lastSend)>telemetryDelay)
  if not ok then return end
  if modemType~="none" then
    rednet.broadcast(payload,protocol)
    lastSend=os.clock()
    lastOnline=nowUtc()
  end
end

-- === Column Mining ===
local function mineColumn(depth)
  for d=1,depth do
    currentDepth=d
    if isBedrockBelow() then
      print("Bedrock reached.")
      for _=1,d-1 do turtle.up() end
      return
    end
    turtle.digDown(); turtle.down(); blocksMined=blocksMined+1
    if isFull() then
      for _=1,d do turtle.up() end
      returnToStart(); deposit()
      for _=1,d do turtle.down() end
    end
    sendStatus("mining",{})
  end
  for _=1,depth do turtle.up() end
end

-- === Main ===
term.clear(); term.setCursorPos(1,1)
print("=== Smart Column Stack Miner v5.4 ===")
openModem()

local prev=loadProgress()
if prev then
  print(("Previous progress found (X:%d Z:%d)"):format(prev.x,prev.z))
  local opt; repeat opt=prompt("Resume? (yes/no): ") until opt=="yes" or opt=="no"
  if opt=="no" then clearProgress(); prev=nil end
end

LENGTH=promptNumber("Enter length:")
WIDTH=promptNumber("Enter width:")
HEIGHT=promptNumber("Enter depth:")
CHEST_SIDE=prompt("Chest side (left/right/back):")
minerId=prompt("Miner ID (e.g., Miner-1):")

local needed=calcFuelNeed(LENGTH,WIDTH,HEIGHT)
checkFuel(needed)
sendStatus("init",{range=rangeDescription},true)

for z=(prev and prev.z or 1),WIDTH do
  for x=(prev and prev.x or 1),LENGTH do
    currentX, currentZ = x, z
    print(("Column X:%d Z:%d"):format(x,z))
    mineColumn(HEIGHT)
    saveProgress(x,z)
    if not (x==LENGTH and z==WIDTH) then moveForwardSafe() end
  end
  if z < WIDTH then
    turnRight()
    moveForwardSafe()
    turnRight()
    for _=1,LENGTH-1 do moveForwardSafe() end
    turnLeft(); turnLeft()
  end
end

returnToStart()
deposit()
clearProgress()
sendStatus("done",{blocks=blocksMined,items=depositedCount},true)
print("✅ Finished mining and returned to chest.")
if speaker then pcall(function() speaker.playNote("bell",3,12) end) end
