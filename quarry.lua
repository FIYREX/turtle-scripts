-- ======================================================
-- Smart Shaft Miner v5.2 (Fixed Position)
-- FIYREX + GPT-5
--
-- Mines a single vertical shaft (1x1) downward with all
-- Smart Quarry features: telemetry, analytics, refuel,
-- auto-return, auto-deposit, resume, and bedrock safety.
-- ======================================================

-- === Utilities ===
local function prompt(msg) write(msg .. " "); return read() end
local function promptNumber(msg)
  write(msg .. " ")
  local v = tonumber(read())
  while not v or v <= 0 do
    print("Enter a valid positive number.")
    write(msg .. " ")
    v = tonumber(read())
  end
  return v
end

local function nowUtc() return os.epoch("utc") end
local function fmt2(x) return string.format("%.2f", x) end

-- === Configuration ===
local PROGRESS_FILE = "progress.txt"
local LOG_DIR = "logs"
local FUEL_SLOT = 1
local DEPTH = 0
local CHEST_SIDE = "right"
local FAST_MODE = false
local currentDepth = 1
local blocksMined = 0
local depositedCount = 0

-- Networking
local minerId = "Miner-1"
local protocol = "quarry_status"
local modemType, modemSide = "none", nil
local rangeDescription, telemetryDelay = "N/A", 5
local lastSend = 0
local lastOnline = nowUtc()

-- Analytics
local sessionStart = nowUtc()
local startFuel = turtle.getFuelLevel()
local lastSignalWarned = false
local speaker = peripheral.find("speaker")

-- === File IO ===
local function saveProgress(depth)
  local f = fs.open(PROGRESS_FILE, "w")
  f.write(tostring(depth))
  f.close()
end

local function loadProgress()
  if fs.exists(PROGRESS_FILE) then
    local f = fs.open(PROGRESS_FILE, "r")
    local data = tonumber(f.readAll())
    f.close()
    return data
  end
  return nil
end

local function clearProgress()
  if fs.exists(PROGRESS_FILE) then fs.delete(PROGRESS_FILE) end
end

-- Offline log storage
local sessionLogPath = nil
local function ensureLogDir()
  if not fs.exists(LOG_DIR) then fs.makeDir(LOG_DIR) end
end

local function startSessionLog()
  ensureLogDir()
  sessionLogPath = string.format("%s/session-%d.log", LOG_DIR, nowUtc())
  local f = fs.open(sessionLogPath, "w")
  f.write("-- telemetry backfill --\n")
  f.close()
end

local function appendOffline(payload)
  if not sessionLogPath then startSessionLog() end
  local f = fs.open(sessionLogPath, "a")
  f.write(textutils.serialize(payload) .. "\n")
  f.close()
end

local function replayAndClearOffline()
  if not sessionLogPath or not fs.exists(sessionLogPath) then return end
  local f = fs.open(sessionLogPath, "r")
  local lines = {}
  while true do
    local line = f.readLine()
    if not line then break end
    if line:sub(1,2) ~= "--" then table.insert(lines, line) end
  end
  f.close()
  for _, ln in ipairs(lines) do
    local ok, payload = pcall(textutils.unserialize, ln)
    if ok and payload then rednet.broadcast(payload, protocol) end
  end
  fs.delete(sessionLogPath)
  sessionLogPath = nil
end

-- === Modem / Telemetry ===
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
    print("⚠️ No modem detected — telemetry offline. Will retry periodically.")
    return false
  end
end

local function sendStatus(stage, extra, force)
  local payload = {
    id = minerId, stage = stage,
    depth = currentDepth, targetDepth = DEPTH,
    fuel = turtle.getFuelLevel(),
    deposited = depositedCount,
    fast = FAST_MODE,
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
    rednet.broadcast(payload, protocol)
    lastSend = os.clock()
    lastOnline = nowUtc()
    replayAndClearOffline()
    lastSignalWarned = false
  else
    appendOffline(payload)
    openModem()
  end

  if (nowUtc() - lastOnline) > 30000 and not lastSignalWarned then
    print("⚠️ Telemetry offline for >30s.")
    if speaker then pcall(function() speaker.playNote("harp", 3, 12) end) end
    lastSignalWarned = true
  end
end

-- === Fuel ===
local function calcFuelNeed(depth)
  return depth * 2 + 100
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

-- === Deposit ===
local function isFull()
  for i=2,16 do if turtle.getItemCount(i)==0 then return false end end
  return true
end

local function deposit()
  sendStatus("deposit", {}, true)
  print("Depositing items...")
  if CHEST_SIDE=="right" then turtle.turnRight()
  elseif CHEST_SIDE=="left" then turtle.turnLeft()
  elseif CHEST_SIDE=="back" then turtle.turnRight(); turtle.turnRight() end
  for i=2,16 do
    turtle.select(i)
    if turtle.getItemCount(i)>0 then
      local count=turtle.getItemCount(i)
      if turtle.drop() then
        depositedCount=depositedCount+count
      end
    end
  end
  if CHEST_SIDE=="right" then turtle.turnLeft()
  elseif CHEST_SIDE=="left" then turtle.turnRight()
  elseif CHEST_SIDE=="back" then turtle.turnRight(); turtle.turnRight() end
  turtle.select(2)
  sendStatus("deposit_done", {deposited=depositedCount}, true)
end

-- === Bedrock Detection ===
local function isBedrockBelow()
  if not turtle.detectDown() then return false end
  if not turtle.digDown() then return true end
  return false
end

-- === Mining Routine ===
local function mineShaft(startDepth)
  for d=startDepth, DEPTH do
    currentDepth = d
    sendStatus("layer_begin", {}, true)
    if isBedrockBelow() then
      print("Bedrock reached — stopping.")
      sendStatus("halt_bedrock", {}, true)
      return
    end

    turtle.digDown()
    turtle.down()
    blocksMined = blocksMined + 1

    if isFull() then
      print("Inventory full — returning to deposit.")
      for _=1,d do turtle.up() end
      deposit()
      for _=1,d do turtle.down() end
    end

    sendStatus("layer", {})
    saveProgress(d)
  end
end

-- === Main ===
term.clear(); term.setCursorPos(1,1)
print("=== Smart Shaft Miner v5.2 ===")
openModem()

local prev = loadProgress()
if prev then
  print("Previous progress found (depth " .. prev .. ")")
  local opt
  repeat opt = prompt("Resume from last depth? (yes/no): ") until opt=="yes" or opt=="no"
  if opt=="no" then clearProgress(); prev=nil end
end

DEPTH = promptNumber("Enter target depth:")
CHEST_SIDE = prompt("Chest side (left/right/back):")
FAST_MODE = (prompt("Enable fast-mode (skip air)? (yes/no):")=="yes")
minerId = prompt("Miner ID (e.g., Shaft-1):")

local needed = calcFuelNeed(DEPTH)
checkFuel(needed)
sendStatus("init",{targetDepth=DEPTH,range=rangeDescription},true)

local start = prev and (prev+1) or 1
print("Starting mining from depth " .. start .. "...")
mineShaft(start)

print("Returning to surface...")
for _=1,currentDepth do turtle.up() end
deposit()
clearProgress()

sendStatus("done",{
  depth=DEPTH,
  blocks_mined=blocksMined,
  items_per_min=fmt2(depositedCount / math.max(1, (nowUtc()-sessionStart)/60000))
},true)

print("✅ Shaft complete. Returned to surface.")
if speaker then pcall(function() speaker.playNote("bell", 3, 12) end) end
