--[[
LayeredQuarryMiner.lua — Fixed Version (Back Chest Edition)
]]

-- ====== UTILITIES ======
local function say(msg) print("[Quarry] " .. msg) end
local function warn(msg) print("[WARN] " .. msg) end
local function ask(msg)
  io.write(msg .. " ")
  return (read() or ""):lower()
end

local function ceil(n) return math.floor(n) == n and n or math.floor(n) + 1 end

-- ====== PROMPTS ======
local function promptPositiveInt(label)
  while true do
    io.write(label .. ": ")
    local v = tonumber(read())
    if v and v >= 1 and math.floor(v) == v then return v end
    warn("Enter a positive integer.")
  end
end

local W = promptPositiveInt("Width (X)")
local H = promptPositiveInt("Height (Y)")
local D = promptPositiveInt("Depth (Z)")
say(string.format("Configured quarry: %dx%dx%d (W x H x D)", W, H, D))

-- ====== FACING & ORIENTATION ======
local facing = 0 -- 0 = +X (east)
local function turnRight() turtle.turnRight() facing = (facing + 1) % 4 end
local function turnLeft() turtle.turnLeft() facing = (facing + 3) % 4 end
local function face(dir)
  while facing ~= dir do
    local diff = (dir - facing) % 4
    if diff == 1 then turnRight() else turnLeft() end
  end
end

-- ====== CHEST CHECK BEHIND ======
local function isChest(name)
  return name and (name:find("chest") or name:find("barrel"))
end

local function waitForBackChest()
  while true do
    turtle.turnLeft(); turtle.turnLeft()
    local ok, data = turtle.inspect()
    if ok and isChest(data.name) then
      say("Detected deposit container behind: " .. data.name)
      turtle.turnLeft(); turtle.turnLeft() -- face forward again
      face(0)
      return true
    else
      turtle.turnLeft(); turtle.turnLeft()
      warn("No chest/barrel behind. Place one and press Enter...")
      read()
    end
  end
end

waitForBackChest()
face(0)

-- ====== FRONT CLEARANCE ======
local okFront, dataFront = turtle.inspect()
if okFront then
  warn("Block detected in front of turtle. Please clear space before mining.")
  read()
end

-- ====== WHITELIST ======
local ORE_SUBSTRINGS = {"_ore", "ore_"}
local ORE_EXACT = {["minecraft:ancient_debris"] = true}

local function isWhitelistedOre(name)
  if not name then return false end
  if ORE_EXACT[name] then return true end
  for _, sub in ipairs(ORE_SUBSTRINGS) do
    if name:find(sub, 1, true) then return true end
  end
  return false
end

-- ====== MOVEMENT ======
local pos = {x=0,y=0,z=0}

local function forward()
  while not turtle.forward() do
    local ok, data = turtle.inspect()
    if ok then
      if isWhitelistedOre(data.name) then turtle.dig() else turtle.dig() end
    else os.sleep(0.1) end
  end
  if facing == 0 then pos.x = pos.x + 1
  elseif facing == 1 then pos.z = pos.z + 1
  elseif facing == 2 then pos.x = pos.x - 1
  elseif facing == 3 then pos.z = pos.z - 1 end
end

local function up()
  while not turtle.up() do local ok, data = turtle.inspectUp() if ok then turtle.digUp() end end
  pos.y = pos.y + 1
end

local function down()
  while not turtle.down() do local ok, data = turtle.inspectDown() if ok then turtle.digDown() end end
  pos.y = pos.y - 1
end

-- ====== INVENTORY & CHEST DEPOSIT ======
local function selectAny(predicate)
  for i=1,16 do local d=turtle.getItemDetail(i) if d and predicate(d) then turtle.select(i) return true end end
  return false
end

local function freeSlots()
  local n=0 for i=1,16 do if not turtle.getItemDetail(i) then n=n+1 end end return n
end

local function depositAllAtStartChest()
  say("Depositing to chest behind...")
  face(2); forward()  -- move back toward chest
  turtle.turnLeft(); turtle.turnLeft()
  for i=1,16 do
    local detail = turtle.getItemDetail(i)
    if detail then
      local keep = detail.name:find("coal") or detail.name:find("charcoal") or detail.name:find("cobblestone")
      turtle.select(i)
      if not keep then turtle.drop() end
    end
  end
  turtle.turnLeft(); turtle.turnLeft()
  forward()
  face(0)
end

-- ====== FUEL MANAGEMENT ======
local function estimateMoves(w,h,d)
  return ceil(((w*d*h) + (w*d)) * 1.15)
end

local estMoves = estimateMoves(W,H,D)
say(string.format("Fuel requirement: ~%d", estMoves))
local fuel = turtle.getFuelLevel()
if fuel ~= "unlimited" and fuel < estMoves then
  warn("Insufficient fuel! Add more and press Enter.")
  read()
  for i=1,16 do turtle.select(i) turtle.refuel(64) end
end

-- ====== MINING LOGIC ======
local function mineCell()
  local dirs = {"up", "down"}
  for _,dir in ipairs(dirs) do
    local ok,data = (dir=="up") and turtle.inspectUp() or turtle.inspectDown()
    if ok and isWhitelistedOre(data.name) then
      if dir=="up" then turtle.digUp() else turtle.digDown() end
    end
  end
end

local function serpentineLayer(width, depth)
  face(0)
  for row=1, depth do
    for col=1, width-1 do
      mineCell()
      forward()
    end
    mineCell()
    if row < depth then
      if (row % 2 == 1) then turnRight(); forward(); turnRight()
      else turnLeft(); forward(); turnLeft() end
    end
  end
  face(0)
end

-- ====== START MINING ======
say("Starting mining sequence...")
forward()  -- move into the quarry to start
for layer=1, H do
  say(string.format("Mining layer %d/%d...", layer, H))
  serpentineLayer(W, D)
  if layer < H then down() end
end

-- ====== RETURN HOME ======
say("Returning home...")
face(2)
for _=1,pos.x do forward() end
face(3)
for _=1,pos.z do forward() end
while pos.y > 0 do down() end
face(0)

depositAllAtStartChest()
say("All done. Happy mining!")
