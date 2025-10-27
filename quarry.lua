-- ======================================================
-- Smart Column Stack Miner v5.5
-- FIYREX + GPT-5
--
-- Mines a perfect rectangular quarry in vertical columns.
-- Pattern: Down → Up → Move 1 → Down → Up → repeat.
-- Fully aligned grid with consistent east-west and south movement.
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

-- === Config ===
local PROGRESS_FILE = "progress.txt"
local FUEL_SLOT = 1
local LENGTH, WIDTH, HEIGHT = 0, 0, 0
local CHEST_SIDE = "right"
local blocksMined, depositedCount = 0, 0
local minerId = "Miner-1"
local posX, posZ, facing = 0, 0, 0
local currentX, currentZ, currentDepth = 1, 1, 0
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
local function faceDirection(dir) while facing~=dir do turnLeft() end end

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

local function moveDownSafe()
  while not turtle.down() do
    turtle.digDown()
    sleep(0.1)
  end
end

local function moveUpSafe()
  while not turtle.up() do
    sleep(0.1)
  end
end

-- === Return to Start ===
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

-- === Bedrock Check ===
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

-- === Column Mining ===
local function mineColumn(depth)
  for d=1,depth do
    currentDepth=d
    if isBedrockBelow() then
      print("Bedrock reached.")
      for _=1,d-1 do moveUpSafe() end
      return
    end
    turtle.digDown()
    moveDownSafe()
    blocksMined=blocksMined+1
    if isFull() then
      for _=1,d do moveUpSafe() end
      returnToStart()
      deposit()
      for _=1,d do moveDownSafe() end
    end
  end
  for _=1,depth do moveUpSafe() end
end

-- === Main ===
term.clear(); term.setCursorPos(1,1)
print("=== Smart Column Stack Miner v5.5 ===")

LENGTH=tonumber(prompt("Enter length:"))
WIDTH=tonumber(prompt("Enter width:"))
HEIGHT=tonumber(prompt("Enter depth:"))
CHEST_SIDE=prompt("Chest side (left/right/back):")
minerId=prompt("Miner ID (e.g., Miner-1):")

local prev=loadProgress()
if prev then
  print(("Resume from X:%d Z:%d? (yes/no): "):format(prev.x,prev.z))
  local opt=read()
  if opt=="no" then clearProgress(); prev=nil end
end

local needed=calcFuelNeed(LENGTH,WIDTH,HEIGHT)
checkFuel(needed)
print(("Fuel OK. Needed: %d"):format(needed))

-- === Grid Mining (Perfect Alignment) ===
for z=(prev and prev.z or 1),WIDTH do
  -- Always start each row facing east
  faceDirection(1)
  for x=(prev and prev.x or 1),LENGTH do
    currentX, currentZ = x, z
    print(("Mining column X:%d Z:%d"):format(x, z))
    mineColumn(HEIGHT)
    saveProgress(x, z)
    if x < LENGTH then moveForwardSafe() end
  end

  -- End of row: move one south for next line
  if z < WIDTH then
    faceDirection(2)
    moveForwardSafe()
  end
end

returnToStart()
deposit()
clearProgress()
print("✅ Quarry complete. Returned to chest.")
if speaker then pcall(function() speaker.playNote("bell",3,12) end) end
