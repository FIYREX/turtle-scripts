--[[ 
LayeredQuarryMiner - Safe Working Core (Back Chest)
by FIYREX

Features:
- Detect chest behind before start
- Move forward into quarry (dig if blocked)
- Mine width x height x depth (layered)
- Basic ore whitelist logic (no crashes)
- Safe nil checks
- Automatically continues if front is clear
]]

-- === Utilities ===
local function say(m) print("[Quarry] " .. m) end
local function warn(m) print("[WARN] " .. m) end
local function ask(m)
  io.write(m .. " ")
  return (read() or ""):lower()
end

-- === Prompt ===
local function promptInt(label)
  while true do
    io.write(label .. ": ")
    local v = tonumber(read())
    if v and v >= 1 then return math.floor(v) end
    warn("Enter positive integer")
  end
end

local W = promptInt("Width (X)")
local H = promptInt("Height (Y)")
local D = promptInt("Depth (Z)")
say(("Configured quarry: %dx%dx%d"):format(W,H,D))

-- === Facing system ===
local facing = 0 -- 0=east,+X
local function turnRight() turtle.turnRight() facing=(facing+1)%4 end
local function turnLeft() turtle.turnLeft() facing=(facing+3)%4 end
local function face(dir)
  while facing~=dir do
    local diff=(dir-facing)%4
    if diff==1 then turnRight() else turnLeft() end
  end
end

-- === Chest check behind ===
local function isChest(name)
  return name and (name:find("chest") or name:find("barrel"))
end

local function waitForBackChest()
  while true do
    turtle.turnLeft(); turtle.turnLeft()
    local ok,data = turtle.inspect()
    turtle.turnLeft(); turtle.turnLeft()
    if ok and isChest(data.name) then
      say("Detected deposit container behind: "..data.name)
      face(0)
      return true
    else
      warn("No chest behind. Place one and press Enter.")
      read()
    end
  end
end

waitForBackChest()

-- === Ore whitelist ===
local ORE_SUBS = {"_ore","ore_"}
local ORE_EXACT = {["minecraft:ancient_debris"]=true}

local function isOre(name)
  if not name then return false end
  if ORE_EXACT[name] then return true end
  for _,s in ipairs(ORE_SUBS) do if name:find(s) then return true end end
  return false
end

-- === Movement tracking ===
local pos={x=0,y=0,z=0}

local function safeInspect(fn)
  local ok,data = fn()
  if ok and data and data.name then return true,data.name end
  return false,nil
end

local function forward()
  while not turtle.forward() do
    local ok,name = safeInspect(turtle.inspect)
    if ok then turtle.dig() else os.sleep(0.1) end
  end
  if facing==0 then pos.x=pos.x+1
  elseif facing==1 then pos.z=pos.z+1
  elseif facing==2 then pos.x=pos.x-1
  else pos.z=pos.z-1 end
end

local function up()
  while not turtle.up() do local ok,name=safeInspect(turtle.inspectUp) if ok then turtle.digUp() end end
  pos.y=pos.y+1
end
local function down()
  while not turtle.down() do local ok,name=safeInspect(turtle.inspectDown) if ok then turtle.digDown() end end
  pos.y=pos.y-1
end

-- === Mine cell ===
local function mineCell()
  -- mine up/down if ore
  local dirs={turtle.inspectUp,turtle.inspectDown}
  for i,fn in ipairs(dirs) do
    local ok,name=safeInspect(fn)
    if ok and isOre(name) then
      if i==1 then turtle.digUp() else turtle.digDown() end
    end
  end
end

-- === Serpentine mining ===
local function serpentineLayer(w,d)
  face(0)
  for row=1,d do
    for col=1,w-1 do
      mineCell()
      forward()
    end
    mineCell()
    if row<d then
      if row%2==1 then turnRight(); forward(); turnRight()
      else turnLeft(); forward(); turnLeft() end
    end
  end
  face(0)
end

-- === Start mining ===
say("Starting mining sequence...")

-- If block in front, dig it once, then continue
local okFront, dataFront = turtle.inspect()
if okFront then
  say("Front blocked by: " .. (dataFront.name or "unknown block") .. " — digging...")
  turtle.dig()
end

-- Move into quarry
if not turtle.forward() then
  local okNext, dataNext = turtle.inspect()
  if okNext then turtle.dig() end
  turtle.forward()
end

-- Begin mining layers
for layer=1,H do
  say(("Mining layer %d/%d..."):format(layer,H))
  serpentineLayer(W,D)
  if layer<H then
    say("Descending to next layer...")
    down()
  end
end

-- === Return to start ===
say("Returning home...")
face(2)
for _=1,pos.x do forward() end
face(3)
for _=1,pos.z do forward() end
while pos.y>0 do down() end
face(0)
say("All done. Happy mining!")
