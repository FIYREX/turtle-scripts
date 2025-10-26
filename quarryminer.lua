-- === FIYREX QUARRY MINER (Auto-Y version) ===
-- Automatically determines starting Y instead of prompting user

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

-- ⚙️ Auto-detect current Y if GPS available, else assume 64
local z0 = 64
if gps then
  local x0, y0, zt = gps.locate(3)
  if y0 then
    z0 = y0
  else
    print("⚠️ GPS not found — using default Y: 64")
  end
else
  print("⚠️ GPS API not available — using default Y: 64")
end
print("Starting Y-level detected as: " .. z0)

local whitelist = promptYesNo("Use whitelist mode?")
local digWholeChunk = promptYesNo("Dig the whole chunk?")

local fin
if digWholeChunk then
  fin = z0
else
  fin = promptNumber("Layers to dig:")
end

-- === STATE VARIABLES ===
local x, y, z = 0, 0, 0
local face, rev, counter = 0, 1, 0
local arr, trashtable = {0}, {}
local cobble, stone = false, false
local slot = 16
local fuelName = nil
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
    turtle.turnLeft(); face = (face - 1) % 4
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
  for i=1,15 do
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
  for i=1,slot-1 do turtle.select(i); turtle.drop() end
  turn(-1); turn(-1); turtle.select(1)
end

local function depositAll()
  print("Depositing items...")
  turtle.turnRight(); turtle.turnRight()
  for i=1,16 do
    turtle.select(i)
    if i ~= 16 or not turtle.refuel(0) then turtle.drop() end
  end
  turtle.turnLeft(); turtle.turnLeft(); turtle.select(1)
end

-- === LOGIC UTILITIES ===
local function compare(where)
  local suc, dat
  if where == "up" then suc, dat = turtle.inspectUp()
  elseif where == "front" then suc, dat = turtle.inspect()
  elseif where == "down" then suc, dat = turtle.inspectDown()
  elseif where == "in" then dat = turtle.getItemDetail(); suc = dat ~= nil end

  local tf = not whitelist
  if whitelist then tf = false end

  if suc and dat and dat.name then
    for i=1,slot-1 do
      if trashtable[i] == dat.name then return tf end
    end
    local tags = dat.tags or {}
    if (cobble and tags["forge:cobblestone"]) or (stone and tags["forge:stone"]) then
      return tf
    end
  end
  return not tf
end

local function digUp() if not compare("up") then while turtle.digUp() do sleep(0.02) end end end
local function digDown() if not compare("down") then while turtle.digDown() do sleep(0.02) end end end

local function inventoryFull()
  for i=1,15 do if turtle.getItemCount(i)==0 then return false end end
  return true
end

local function trashRemoval()
  for i=1,15 do
    if not arr[i+1] then
      local dispose = whitelist
      local d = turtle.getItemDetail(i)
      if d then
        for j=1,slot-1 do
          if whitelist then if d.name==trashtable[j] then dispose=false end
          else if d.name==trashtable[j] then dispose=true end end
        end
        local tags = (d and d.tags) or {}
        if cobble and tags["forge:cobblestone"] then dispose = not whitelist end
        if stone and tags["forge:stone"] then dispose = not whitelist end
        if dispose then turtle.select(i); turtle.drop() end
      end
      if turtle.getItemCount(i)>0 then arr[i+1]=1; arr[1]=(arr[1] or 0)+1 end
    end
  end
  turtle.select(1)
end

local function isFull()
  for i=0,14 do if turtle.getItemCount(15-i)==0 then return false end end
  return true
end

-- === MOVEMENT CONTROL ===
local function goHome(state)
  local xp, yp, zp, facep = x, y, z, face
  while y>0 do if face==2 then moveForward() else turn(1) end end
  while x>0 do if face==3 then moveForward() else turn(-1) end end
  if state=="full" or state=="fuel" then trashRemoval() end
  while z>0 do turtle.up(); z=z-1 end
  while face~=2 do turn(-1) end
  if state=="fuel" then
    print("Waiting for fuel… put fuel anywhere."); repeat sleep(5); refuel() until turtle.getFuelLevel()>=500
    state="full"
  end
  if state=="full" then depositAll(); arr={0}; state="mine" end
  if state=="comp" then depositAll(); while face~=0 do turn(1) end; error("✅ Quarry complete!") end
  if state=="mine" then
    while z<zp do while not turtle.down() do turtle.digDown() end; z=z+1 end
    while x<xp do if face~=1 then turn(1) end; moveForward() end
    while y<yp do if face~=0 then turn(-1) end; moveForward() end
    while face~=facep do turn(1) end
  end
end

local function checkfuel()
  refuel()
  local need=(x+y+z)+(l*w)
  if turtle.getFuelLevel()<need then goHome("fuel") end
end

local function mineStep()
  if counter%16==0 then checkfuel(); counter=1 else counter=counter+1 end
  moveForward(); digDown(); digUp()
  if isFull() then trashRemoval(); if (arr[1] or 0)>=14 then goHome("full") end end
end

local function Bore()
  while z<z0-3 do while not turtle.down() do turtle.digDown() end; z=z+1 end
end

local function moveY()
  if y==0 then
    while y<l-1 do if face==0 then mineStep() else if face==1 or face==2 then turn(-1) else turn(1) end end end
  else
    while y>0 do if face==2 then mineStep() else if face==1 or face==0 then turn(1) else turn(-1) end end end
  end
end

local function quarry()
  refuel()
  for i=0,w-1 do
    moveY()
    if i<w-1 then if (i%2)==0 then turn(rev) else turn(-rev) end; mineStep() end
  end
end

-- === MASTER ROUTINE ===
local function Mastermind()
  buildList()
  refuel()
  if turtle.getFuelLevel()<500 then
    print("Not enough fuel. Insert more and wait...")
    repeat sleep(5); refuel() until turtle.getFuelLevel()>=500
  end
  Bore()
  for i=0,fin-3 do
    if i%3==0 then turtle.digUp(); quarry(); if (w%2)==0 then rev=-rev end; trashRemoval() end
    if i<fin-3 then while not turtle.up() do turtle.digUp() end; z=z-1 end
  end
  trashRemoval(); print("✅ Job complete."); goHome("comp")
end

Mastermind()
