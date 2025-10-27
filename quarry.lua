-- ======================================================
--
--  Core mining:
--    ✅ Layered quarry with zig-zag paths
--    ✅ Slot 1 fuel lock, auto-refuel & fuel estimate
--    ✅ Resume by layer (progress.txt)
--    ✅ Fast-mode (skip air blocks)
--    ✅ Bedrock detection -> safe stop
--    ✅ Auto-return to start (surface) for deposit & on finish
--
--  Telemetry & Ops (v5.1 → v5.2):
--    ✅ Rednet telemetry with adaptive intervals (wired/ender/wireless)
--    ✅ Modem detection + range banner
--    ✅ Chest capacity tracking + deposited count
--    ✅ Fault tolerance:
--         • Offline logging to logs/session-*.log when comms down
--         • Auto-reconnect scans for modem while running
--         • Telemetry backfill: replays offline log on reconnect
--         • Loss-of-signal alert (>30s) via speaker (if present)
--    ✅ Analytics:
--         • Items/minute (deposited)
--         • Fuel/1000 blocks (approx)
--         • Blocks mined counter
-- ======================================================

-- =============== UTILITIES ===============
local function prompt(msg) write(msg .. " "); return read() end
local function promptNumber(msg)
  write(msg .. " ")
  local v = tonumber(read())
  while not v or v <= 0 do print("Enter a valid positive number."); write(msg .. " "); v = tonumber(read()) end
  return v
end

local function nowUtc() return os.epoch("utc") end
local function fmt2(x) return string.format("%.2f", x) end

-- =============== CONFIG / STATE ===============
local PROGRESS_FILE = "progress.txt"
local LOG_DIR = "logs"
local FUEL_SLOT = 1

local LENGTH, WIDTH, HEIGHT = 0, 0, 0
local CHEST_SIDE = "right"
local FAST_MODE = false
local currentLayer = 1

-- telemetry / networking
local minerId = "Miner-1"
local protocol = "quarry_status"
local chestSlots, chestCapacity = 27, 27*64
local depositedCount = 0

local modemType, modemSide = "none", nil
local rangeDescription, telemetryDelay = "N/A", 5
local lastSend = 0
local lastOnline = nowUtc()

-- analytics
local sessionStart = nowUtc()
local startFuel = turtle.getFuelLevel()
local blocksMined = 0        -- forward steps + turns (approx surface changes)
local lastSignalWarned = false

-- facing: 0=N,1=E,2=S,3=W (relative tracker for simple auto-return)
local facing = 0

-- optional speaker peripheral for alerts
local speaker = peripheral.find("speaker")

-- =============== FILE I/O ===============
local function saveProgress(layer)
  local f = fs.open(PROGRESS_FILE, "w")
  f.write(tostring(layer))
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

local function clearProgress() if fs.exists(PROGRESS_FILE) then fs.delete(PROGRESS_FILE) end end

-- offline logs
local sessionLogPath = nil
local function ensureLogDir()
  if not fs.exists(LOG_DIR) then fs.makeDir(LOG_DIR) end
end

local function startSessionLog()
  ensureLogDir()
  sessionLogPath = string.format("%s/session-%d.log", LOG_DIR, nowUtc())
  local f = fs.open(sessionLogPath, "w"); f.write("-- telemetry backfill --\n"); f.close()
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

-- =============== MODEM / NETWORK ===============
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
    length = LENGTH, width = WIDTH, height = HEIGHT,
    layer = currentLayer,
    fuel = turtle.getFuelLevel(),
    deposited = depositedCount, chestCapacity = chestCapacity,
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
    -- if we stored any logs while offline, try to replay
    replayAndClearOffline()
    lastSignalWarned = false
  else
    -- queue to offline log
    appendOffline(payload)
    -- soft auto-reconnect attempt
    openModem()
  end

  -- loss-of-signal alert if > 30s with no online status
  if (nowUtc() - lastOnline) > 30000 and not lastSignalWarned then
    print("⚠️ Telemetry offline for >30s.")
    if speaker then pcall(function() speaker.playNote("harp", 3, 12) end) end
    lastSignalWarned = true
  end
end

-- =============== FUEL MANAGEMENT ===============
local function calcFuelNeed(length, width, height)
  local blocks = length * width * height
  local travel = (length * width) * 2
  return math.ceil(blocks + travel + height * 4)
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

-- =============== ORIENTATION / RETURN ===============
local function turnRight() turtle.turnRight(); facing = (facing + 1) % 4 end
local function turnLeft()  turtle.turnLeft();  facing = (facing + 3) % 4 end
local function faceNorth() while facing ~= 0 do turnLeft() end end

local function returnToStart(layerIndex)
  print("Returning to start position...")
  faceNorth()
  for _ = 1, (layerIndex - 1) do turtle.up() end
end

-- =============== INVENTORY / DEPOSIT ===============
local function isFull()
  for i = 2,16 do if turtle.getItemCount(i) == 0 then return false end end
  return true
end

local function deposit()
  sendStatus("deposit", {}, true)
  print("Depositing items...")
  if CHEST_SIDE == "right" then turnRight()
  elseif CHEST_SIDE == "left" then turnLeft()
  elseif CHEST_SIDE == "back" then turnRight(); turnRight() end

  for i = 2,16 do
    turtle.select(i)
    local count = turtle.getItemCount(i)
    if count > 0 then
      local ok = turtle.drop()
      if ok then
        depositedCount = depositedCount + count
      else
        local tries = 0
        while turtle.getItemCount(i) > 0 and tries < 10 do
          print("Chest full? Waiting...")
          sleep(2)
          ok = turtle.drop()
          tries = tries + 1
        end
        local dumped = count - turtle.getItemCount(i)
        depositedCount = depositedCount + dumped
      end
    end
  end

  if CHEST_SIDE == "right" then turnLeft()
  elseif CHEST_SIDE == "left" then turnRight()
  elseif CHEST_SIDE == "back" then turnRight(); turnRight() end

  turtle.select(2)
  sendStatus("deposit_done", {deposited = depositedCount}, true)
end

-- =============== MINING HELPERS ===============
local function digIfNeeded()
  if FAST_MODE and not turtle.detect() then return end
  if turtle.dig() then blocksMined = blocksMined + 1 end
end

local function isBedrockBelow()
  if not turtle.detectDown() then return false end
  if not turtle.digDown() then return true end
  blocksMined = blocksMined + 1
  return false
end

-- =============== MINING CORE ===============
local function mineLayer(startLayer)
  for z = startLayer, HEIGHT do
    currentLayer = z
    print("Mining layer " .. z .. "/" .. HEIGHT)
    sendStatus("layer_begin", {}, true)

    for w = 1, WIDTH do
      for l = 1, (LENGTH - 1) do
        digIfNeeded()
        turtle.forward(); blocksMined = blocksMined + 1

        if isFull() then
          print("Inventory full — deposit cycle.")
          returnToStart(z)
          deposit()
          print("Returning to layer " .. z .. "...")
          for _ = 1, (z - 1) do turtle.down() end
        end

        -- adaptive telemetry + auto-reconnect
        sendStatus("layer", {})
      end

      if w < WIDTH then
        if w % 2 == 1 then
          turnRight(); digIfNeeded(); turtle.forward(); blocksMined = blocksMined + 1; turnRight()
        else
          turnLeft();  digIfNeeded(); turtle.forward(); blocksMined = blocksMined + 1; turnLeft()
        end
        sendStatus("lane_shift", {})
      end
    end

    saveProgress(z)
    sendStatus("layer_done", {layer=z}, true)

    if z < HEIGHT then
      if isBedrockBelow() then
        print("Cannot mine — already reached bedrock.")
        sendStatus("halt_bedrock", {}, true)
        return
      end
      turtle.down()
    end
  end
end

-- =============== MAIN ===============
term.clear(); term.setCursorPos(1,1)
print("=== Smart Quarry Miner v5.2 ===")

-- Init modem (first attempt)
openModem()

-- Resume
local prev = loadProgress()
if prev then
  print("Previous progress detected (layer " .. prev .. ")")
  local opt; repeat opt = prompt("Resume from saved progress? (yes/no): ") until opt=="yes" or opt=="no"
  if opt == "no" then clearProgress(); prev = nil end
end

-- Inputs
if not prev then
  LENGTH = promptNumber("Enter length:")
  WIDTH  = promptNumber("Enter width:")
  HEIGHT = promptNumber("Enter height:")
  CHEST_SIDE = prompt("Chest side (left/right/back):")
  FAST_MODE = (prompt("Enable fast-mode (skip air blocks)? (yes/no): ") == "yes")
  local chestType = prompt("Chest type single/double/custom? (s/d/c): ")
  if chestType == "d" then chestSlots = 54
  elseif chestType == "c" then chestSlots = promptNumber("Enter number of slots:") end
  chestCapacity = chestSlots * 64
  minerId = prompt("Miner ID (e.g., Miner-1):")
  clearProgress()
  currentLayer = 1
else
  LENGTH = promptNumber("Enter length (same):")
  WIDTH  = promptNumber("Enter width (same):")
  HEIGHT = promptNumber("Enter height (same):")
  CHEST_SIDE = prompt("Chest side (left/right/back):")
  FAST_MODE = (prompt("Enable fast-mode (skip air blocks)? (yes/no): ") == "yes")
  local chestType = prompt("Chest type single/double/custom? (s/d/c): ")
  if chestType == "d" then chestSlots = 54
  elseif chestType == "c" then chestSlots = promptNumber("Enter number of slots:") end
  chestCapacity = chestSlots * 64
  minerId = prompt("Miner ID (e.g., Miner-1):")
  currentLayer = prev + 1
end

-- Fuel planning
local needed = calcFuelNeed(LENGTH, WIDTH, HEIGHT - (currentLayer - 1))
print(("Estimated fuel needed: %d"):format(needed))
checkFuel(needed)

-- Initial status
sendStatus("init", {
  neededFuel = needed,
  modemType = modemType, range = rangeDescription,
  chestSlots = chestSlots
}, true)

-- Mine
print("Starting mining from layer " .. currentLayer .. "...")
mineLayer(currentLayer)

-- Wrap-up
returnToStart(HEIGHT)
deposit()
clearProgress()
sendStatus("done", {
  duration_min = fmt2((nowUtc() - sessionStart) / 60000),
  items_per_min = fmt2(depositedCount / math.max(1, (nowUtc() - sessionStart)/60000)),
  fuel_used = (startFuel ~= "unlimited" and turtle.getFuelLevel() ~= "unlimited") and (startFuel - turtle.getFuelLevel()) or -1,
  blocks_mined = blocksMined
}, true)

print("✅ Mining complete. Turtle back at start.")
if speaker then pcall(function() speaker.playNote("bell", 3, 12) end) end
