-- ======================================================
-- Smart Quarry Miner v5.6
-- FIYREX + GPT-5
--
-- Pattern: "Snake" (Row-by-Row)
-- Starts bottom-left, mines across row, moves up 1, reverses, repeat.
-- Each ⬜ = one full vertical column.
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
local minerId = "Miner-1"
local blocksMined, depositedCount = 0, 0
local facing = 1  -- 0=N, 1=E, 2=S, 3=W

-- === Tracking ===
local posX, posZ = 0, 0

-- === Movement Helpers ===
local function turnRight() turtle.turnRight(); facing=(facing+1)%4 end
local function turnLeft()  turtle.turnLeft();  facing=(facing+3)%4 end
local function faceDirection(dir)
  while facing~=dir do turnLeft() end
end

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
  while not turtle.up() do sleep(0.1) end
end

-- === Bedrock Check ===
local function isBedrockBelow()
  if not turtle.detectDown() then return false end
  if not turtle.digDown() then return true end
  return false
end

-- === Return to Start ===
local function returnToStart()
  print("Returning to chest...")
  if posX > 0 then faceDirection(3) for _=1,posX do moveForwardSafe() end posX=0 end
  if posZ > 0 then faceDirection(0) for _=1,posZ do moveForwardSafe() end posZ=0 end
  faceDirection(1)
end

-- === Fuel & Inventory ===
local function calcFuelNeed(l,w,h)
  return (l*w*h)*2 + 100
end

local function checkFuel(required)
  local fuel=turtle.getFuelLevel()
  if fuel=="unlimited" then return end
  while fuel<required do
    print(("Fuel Low: %d/%d"):format(fuel,required))
    turtle.select(FUEL_SLOT)
    if not turtle.refuel(1) then print("Add fuel in slot 1."); sleep(3) end
    fuel=turtle.getFuelLevel()
  end
end

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
    if turtle.getItemCount(i)>0 then turtle.drop() end
  end

  if CHEST_SIDE=="right" then turtle.turnLeft()
  elseif CHEST_SIDE=="left" then turtle.turnRight()
  elseif CHEST_SIDE=="back" then turtle.turnRight(); turtle.turnRight() end

  turtle.select(2)
end

-- === Mining Logic ===
local function mineColumn(depth)
  for d=1,depth do
    if isBedrockBelow() then print("Bedrock reached."); break end
    turtle.digDown()
    moveDownSafe()
    blocksMined=blocksMined+1
    if isFull() then
      print("Inventory full, returning to deposit.")
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
print("=== Smart Quarry Miner v5.6 ===")

LENGTH=promptNumber("Enter length:")
WIDTH=promptNumber("Enter width:")
HEIGHT=promptNumber("Enter depth:")
CHEST_SIDE=prompt("Chest side (left/right/back):")
minerId=prompt("Miner ID (e.g., Miner-1):")

checkFuel(calcFuelNeed(LENGTH,WIDTH,HEIGHT))
print("Fuel check complete. Starting mining...")

-- Snake pattern mining
for row=1,WIDTH do
  print(("Row %d/%d..."):format(row,WIDTH))
  for col=1,LENGTH do
    print(("Mining column %d/%d"):format(col,LENGTH))
    mineColumn(HEIGHT)
    if col < LENGTH then moveForwardSafe() end
  end

  -- Move to next row (north) if not finished
  if row < WIDTH then
    if row % 2 == 1 then  -- currently facing east
      turnLeft()
      moveForwardSafe()
      turnLeft()
    else  -- currently facing west
      turnRight()
      moveForwardSafe()
      turnRight()
    end
  end
end

returnToStart()
deposit()
print("✅ Quarry complete. Returned to chest.")
if speaker then pcall(function() speaker.playNote("bell",3,12) end) end
