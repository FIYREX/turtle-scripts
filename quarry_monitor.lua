-- ======================================================
-- Quarry Command Hub v1.3
-- FIYREX + GPT-5
-- ======================================================

local protocol = "quarry_status"
local miners = {}

local mon = peripheral.find("monitor")
local speaker = peripheral.find("speaker")
if mon then mon.setTextScale(0.5) end
local t = mon or term
local isColor = t.isColor and t.isColor()

-- ---------- Utility ----------
local function setColors(fg,bg)
  if isColor then
    if bg then t.setBackgroundColor(bg) end
    if fg then t.setTextColor(fg) end
  end
end

local function writeAt(x,y,s,fg,bg)
  if fg or bg then setColors(fg or colors.white,bg or colors.black) end
  t.setCursorPos(x,y)
  t.write(s)
end

local function clear()
  setColors(colors.white,colors.black)
  t.clear()
  t.setCursorPos(1,1)
end

local function human(n)
  if not n or n < 1000 then return tostring(n or 0) end
  if n < 1e6 then return string.format("%.1fk", n/1e3)
  elseif n < 1e9 then return string.format("%.1fM", n/1e6)
  else return string.format("%.1fB", n/1e9) end
end

local function beepNote(pitch)
  if speaker then pcall(function() speaker.playNote("harp", 3, pitch or 12) end) end
end

-- ---------- Networking ----------
local function openModem()
  for _,s in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(s)
    if t=="modem" or t=="wired_modem" or t=="ender_modem" then
      if not rednet.isOpen(s) then rednet.open(s) end
      return s,t
    end
  end
  return nil,nil
end

local side,mtype = openModem()
clear()
print("🛰️  Quarry Command Hub v1.3 ready. Listening on protocol: " .. protocol)
print("Modem: " .. (mtype or "none") .. " | Side: " .. (side or "N/A"))

-- ---------- UI ----------
local function drawMiner(y,data,w)
  local m=data.msg
  local age=os.epoch("utc")-data.ts
  local color=colors.lime
  if age>15000 then color=colors.orange end
  if age>45000 then color=colors.red end
  local chestPct=(m.deposited or 0)/math.max(1,(m.chestCapacity or 1))
  local pct=math.floor(chestPct*100)
  local label=string.format("%s | %s | Layer %d/%d | %d%% full",
    m.id or "?", m.stage or "?", m.layer or 0, m.height or 0, pct)
  writeAt(1,y,label,color)
  return y+1
end

local function drawCommands(y,minerId)
  writeAt(1,y,"Commands for " .. minerId .. ": [P]ause  [R]esume  [S]top  [B]Return  [X]Shutdown",colors.white)
  return y+2
end

local function render()
  clear()
  local w,h=t.getSize()
  writeAt(1,1,"=== Quarry Command Hub v1.3 ===",colors.white)
  writeAt(1,2,"Press letter keys to control miners | Total: "..tostring(#(function() local c=0 for _ in pairs(miners) do c=c+1 end return {c} end)()[1]),colors.gray)
  local row=4
  local ids={}
  for id,_ in pairs(miners) do table.insert(ids,id) end
  table.sort(ids)
  for _,id in ipairs(ids) do
    row=drawMiner(row,miners[id],w)
    row=drawCommands(row,id)
    if row>h-3 then break end
  end
end

-- ---------- Command send ----------
local function sendCommand(minerId,cmd)
  local payload={target=minerId,cmd=cmd}
  rednet.broadcast(payload,protocol)
  local timer=os.startTimer(10)
  local acked=false
  while true do
    local e,p1,p2,p3=os.pullEvent()
    if e=="rednet_message" then
      local sid,msg,proto=p1,p2,p3
      if proto==protocol and msg.ack and msg.miner==minerId and msg.ack==cmd then
        print(("✅ %s ACK from %s"):format(cmd,minerId))
        acked=true
        beepNote(15)
        break
      end
    elseif e=="timer" and p1==timer then
      print(("⚠️  No ACK from %s for %s command"):format(minerId,cmd))
      beepNote(5)
      break
    end
  end
end

-- ---------- Main loop ----------
local lastRender=0
render()
while true do
  local e,p1,p2,p3=os.pullEvent()
  if e=="rednet_message" then
    local sid,msg,proto=p1,p2,p3
    if proto==protocol and msg.id then
      miners[msg.id]={msg=msg,ts=os.epoch("utc")}
    end
  elseif e=="key" then
    local key=p1
    if key==keys.p then
      for id in pairs(miners) do sendCommand(id,"pause") end
    elseif key==keys.r then
      for id in pairs(miners) do sendCommand(id,"resume") end
    elseif key==keys.s then
      for id in pairs(miners) do sendCommand(id,"stop") end
    elseif key==keys.b then
      for id in pairs(miners) do sendCommand(id,"return") end
    elseif key==keys.x then
      for id in pairs(miners) do sendCommand(id,"shutdown") end
    end
  end

  if (os.clock()-lastRender)>1 then
    render()
    lastRender=os.clock()
  end
end
