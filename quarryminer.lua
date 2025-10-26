
-- ===== Utilities =====
local function say(msg) print("[Quarry] " .. msg) end
local function warn(msg) print("[WARN] " .. msg) end
local function ask(msg)
  io.write(msg .. " ")
  return (read() or ""):lower()
end

-- Round up helper
local function ceil(n) return math.floor(n) == n and n or math.floor(n) + 1 end

-- ===== Prompt for dimensions =====
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

-- ===== Chest detection =====
local function isChest(name)
  if not name then return false end
  return name:find("chest") or name:find("barrel")
end

local facing = 0
local function turnRight() turtle.turnRight() facing = (facing + 1) % 4 end
local function turnLeft()  turtle.turnLeft()  facing = (facing + 3) % 4 end
local function face(dir)
  while facing ~= dir do
    local diff = (dir - facing) % 4
    if diff == 1 then turnRight() else turnLeft() end
  end
end

local function waitForBackChest()
  while true do
    turtle.turnLeft()
    turtle.turnLeft()
    local ok, data = turtle.inspect()
    if ok and isChest(data.name) then
      say("Detected deposit container behind: " .. data.name)
      turtle.turnLeft()
      turtle.turnLeft()
      face(0) -- ensure facing forward toward quarry
      return true
    else
      turtle.turnLeft()
      turtle.turnLeft()
      warn("No chest/barrel behind. Place one and press Enter...")
      read()
    end
  end
end

waitForBackChest()
face(0)

-- Sanity check: Ensure front is clear
local okFront, dataFront = turtle.inspect()
if okFront and dataFront then
  warn("Block detected in front of turtle. Please clear the space before mining.")
  read()
end

-- ===== Whitelist / Blacklist =====
local ORE_SUBSTRINGS = {"_ore", "ore_"}
local ORE_EXACT = { ["minecraft:ancient_debris"] = true }

local function isWhitelistedOre(name)
  if not name then return false end
  if ORE_EXACT[name] then return true end
  for _, sub in ipairs(ORE_SUBSTRINGS) do
    if name:find(sub, 1, true) then return true end
  end
  return false
end

-- ===== Positioning & Movement =====
local pos = {x=0,y=0,z=0}

local function forward()
  while not turtle.forward() do
    local ok, data = turtle.inspect()
    if ok then
      if isWhitelistedOre(data.name) then turtle.dig() else os.sleep(0.2) turtle.dig() end
    else os.sleep(0.2) end
  end
  if facing == 0 then pos.x = pos.x + 1 elseif facing == 1 then pos.z = pos.z + 1 elseif facing == 2 then pos.x = pos.x - 1 else pos.z = pos.z - 1 end
end

local function up()
  while not turtle.up() do local ok, data = turtle.inspectUp() if ok then turtle.digUp() else os.sleep(0.2) end end
  pos.y = pos.y + 1
end

local function down()
  while not turtle.down() do local ok, data = turtle.inspectDown() if ok then turtle.digDown() else os.sleep(0.2) end end
  pos.y = pos.y - 1
end

-- ===== Inventory & Deposit =====
local function selectAny(predicate)
  for i=1,16 do local detail = turtle.getItemDetail(i) if detail and predicate(detail) then turtle.select(i) return true end end return false end
local function freeSlots() local n=0 for i=1,16 do if not turtle.getItemDetail(i) then n=n+1 end end return n end

local function depositAllAtStartChest()
  say("Depositing to start chest behind...")
  if pos.x ~= 0 then if pos.x > 0 then face(2) else face(0) end for _=1, math.abs(pos.x) do forward() end end
  if pos.z ~= 0 then if pos.z > 0 then face(3) else face(1) end for _=1, math.abs(pos.z) do forward() end end
  while pos.y > 0 do down() end while pos.y < 0 do up() end

  turtle.turnLeft() turtle.turnLeft()
  local ok, data = turtle.inspect()
  if not ok or not isChest(data.name) then warn("Deposit container missing; place it behind and press Enter.") read() end

  for i=1,16 do
    local detail = turtle.getItemDetail(i)
    if detail then
      local keep = false
      if detail.name:find("coal") or detail.name:find("charcoal") then keep = true end
      if detail.name:find("cobblestone") then keep = true end
      turtle.select(i)
      if not keep then turtle.drop() end
    end
  end
  turtle.turnLeft() turtle.turnLeft()
end

-- ===== Fuel Planning =====
local function estimateMoves(w,h,d)
  local layerMoves = math.max(0, w*d - 1)
  local laneTurnsMoves = math.max(0, d - 1)
  local vertical = math.max(0, h - 1)
  local traverse = h * (layerMoves + laneTurnsMoves)
  local returnHome = math.max(0,w-1) + math.max(0,h-1) + math.max(0,d-1)
  local total = traverse + vertical + returnHome
  return ceil(total * 1.15)
end

local function ensureFuelFor(moves)
  local fuel = turtle.getFuelLevel()
  if fuel == "unlimited" then return true end
  if fuel < moves then
    warn(string.format("Fuel low: have %d, need ~%d.", fuel, moves))
    warn("Add fuel and press Enter to refuel.")
    read()
    for i=1,16 do turtle.select(i) turtle.refuel(64) end
  end
end

local totalVolume = W*H*D
local estMoves = estimateMoves(W,H,D)
say(string.format("Estimated moves: ~%d (fuel units)", estMoves))
ensureFuelFor(estMoves)

-- ===== Mining Logic =====
local function tryMine(dir)
  local ok, data
  if dir == "front" then ok, data = turtle.inspect() elseif dir == "up" then ok, data = turtle.inspectUp() else ok, data = turtle.inspectDown() end
  if ok and data and isWhitelistedOre(data.name) then
    if dir == "front" then turtle.dig() elseif dir == "up" then turtle.digUp() else turtle.digDown() end
  end
end

local function mineCell()
  tryMine("up"); tryMine("down"); turnLeft(); tryMine("front"); turnRight(); turnRight(); tryMine("front"); turnLeft()
end

local function needUnload() return freeSlots() <= 1 end

local function serpentineLayer(width, depth)
  face(0)
  for row=1, depth do
    for col=1, width-1 do
      mineCell() forward()
      if needUnload() then depositAllAtStartChest() face(0) end
    end
    mineCell()
    if row < depth then
      if (row % 2 == 1) then turnRight(); mineCell(); forward(); turnRight()
      else turnLeft(); mineCell(); forward(); turnLeft() end
    end
  end
  face(0)
end

for layer=1, H do
  say(string.format("Mining layer %d/%d...", layer, H))
  serpentineLayer(W, D)
  if layer < H then down() end
end

-- Return home
say("Returning home...")
face(2); for _=1,pos.x do forward() end
face(3); for _=1,pos.z do forward() end
while pos.y > 0 do down() end
face(0)

-- Unload final
depositAllAtStartChest()

-- ===== Backfill =====
local function countCobblestone()
  local c=0 for i=1,16 do local d=turtle.getItemDetail(i) if d and d.name:find("cobblestone") then c=c+d.count end end return c end
local fillNeeded = totalVolume
say(string.format("Backfill requires ~%d cobblestone.", fillNeeded))

local resp=ask("Fill quarry with cobblestone? (y/n)")
if resp=="y" or resp=="yes" then
  local have=countCobblestone()
  if have<fillNeeded then warn(string.format("Not enough cobble: have %d need %d", have, fillNeeded)) else
    say("Filling quarry...")
    for i=1,H do
      for z=1,D do
        for x=1,W do
          if not selectAny(function(d)return d.name:find("cobblestone") end) then warn("Out of cobble!") return end
          local ok,_=turtle.inspectDown() if not ok then turtle.placeDown() end
          if x<W then forward() end
        end
        if z<D then if (z%2==1) then turnRight() forward() turnRight() else turnLeft() forward() turnLeft() end end
      end
      if i<H then up() end
    end
  end
end

say("All done. Happy mining!")
