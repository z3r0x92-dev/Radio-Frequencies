require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "MeeksRadio/Config"
require "MeeksRadio/Catalog"

MeeksRadio = MeeksRadio or {}
MeeksRadio.Listener = ISPanel:derive("RadioFrequenciesListener")
MeeksRadio.Listener.instance = nil

local function button(panel,x,y,w,title,callback)
    local value=ISButton:new(x,y,w,30,title,panel,callback)
    value:initialise(); panel:addChild(value); return value
end

local function trackTitle(id)
    local track=MeeksRadio.getTrack(id)
    return track and ((track.title or track.id).." // "..(track.artist or "UNKNOWN")) or tostring(id)
end

local function stationPermission(frequency)
    local permissions=MeeksRadio.ClientPermissions or {}
    if permissions.isAdmin then return true,"administrator" end
    local value=permissions.stationPermissions and permissions.stationPermissions[frequency]
    return value and value.allowed==true or false,value and value.reason or "permission status unavailable"
end

local function fitText(text,font,maxWidth)
    text=tostring(text or ""); local tm=getTextManager()
    if tm:MeasureStringX(font,text)<=maxWidth then return text end
    while #text>0 and tm:MeasureStringX(font,text.."...")>maxWidth do text=string.sub(text,1,#text-1) end
    return text.."..."
end

function MeeksRadio.Listener:new(player,frequency)
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    local w,h=math.max(1,math.min(920,sw-20)),math.max(1,math.min(600,sh-20))
    local o=ISPanel.new(self,math.max(0,(sw-w)/2),math.max(0,(sh-h)/2),w,h)
    o.player=player; o.frequency=frequency; o.moveWithMouse=true
    o.backgroundColor={r=.03,g=.035,b=.055,a=.98}; o.borderColor={r=.88,g=.22,b=.66,a=1}
    return o
end

function MeeksRadio.Listener:createChildren()
    ISPanel.createChildren(self)
    local gap=20; local column=math.floor((self.width-60)/2); local right=40+column
    local listBottom=self.height-112
    self.history=ISScrollingListBox:new(20,78,column,listBottom-78)
    self.history:initialise(); self.history.itemheight=30; self:addChild(self.history)
    self.tracks=ISScrollingListBox:new(right,78,column,math.max(130,math.floor((listBottom-96)/2)))
    self.tracks:initialise(); self.tracks.itemheight=26; self:addChild(self.tracks)
    local requestsY=self.tracks.y+self.tracks.height+42
    self.requests=ISScrollingListBox:new(right,requestsY,column,math.max(70,listBottom-requestsY))
    self.requests:initialise(); self.requests.itemheight=26; self:addChild(self.requests)
    self.requestButton=button(self,right,self.height-94,math.floor(column*.34),"REQUEST TRACK",self.onRequest)
    local allowed=stationPermission(self.frequency)
    if allowed then
        self.approveButton=button(self,right+math.floor(column*.35),self.height-94,math.floor(column*.3),"APPROVE",self.onApprove)
        self.rejectButton=button(self,right+math.floor(column*.66),self.height-94,math.floor(column*.3),"REJECT",self.onReject)
    end
    self.closeButton=button(self,self.width-152,self.height-40,132,"CLOSE",self.close)
    self:refresh()
end

function MeeksRadio.Listener:refresh()
    local state=MeeksRadio.ClientStationStates and MeeksRadio.ClientStationStates[self.frequency] or {}
    self.state=state; self.revision=state.revision
    self.history:clear()
    for _,entry in ipairs(state.bulletins or {}) do
        local label="["..string.upper(tostring(entry.kind or "announcement")).."] "..tostring(entry.text or "")
        self.history:addItem(label,entry)
    end
    self.tracks:clear()
    local sorted={}
    for _,track in pairs(MeeksRadio.Catalog or {}) do sorted[#sorted+1]=track end
    table.sort(sorted,function(a,b) return string.lower(a.title or a.id)<string.lower(b.title or b.id) end)
    for _,track in ipairs(sorted) do self.tracks:addItem(trackTitle(track.id),track) end
    self.requests:clear()
    for index,entry in ipairs(state.requests or {}) do
        self.requests:addItem(trackTitle(entry.trackId).." // "..tostring(entry.requestedBy),{index=index,entry=entry})
    end
end

function MeeksRadio.Listener:update()
    ISPanel.update(self)
    local state=MeeksRadio.ClientStationStates and MeeksRadio.ClientStationStates[self.frequency]
    if state and state.revision~=self.revision then self:refresh() end
end

function MeeksRadio.Listener:prerender()
    ISPanel.prerender(self)
    local station=MeeksRadio.Config.stations[self.frequency] or {}
    self:drawText("RADIO FREQUENCIES // LISTENER TERMINAL",20,14,.65,.61,.69,1,UIFont.Small)
    self:drawText((station.name or "UNKNOWN").." // "..string.format("%.1f MHz",self.frequency/1000),20,38,.97,.16,.75,1,UIFont.Medium)
    self:drawText("BROADCAST HISTORY",20,58,.65,.61,.69,1,UIFont.Small)
    self:drawText("APPROVED TRACKS",self.tracks.x,58,.65,.61,.69,1,UIFont.Small)
    self:drawText("PLAYER REQUESTS",self.requests.x,self.requests.y-20,.65,.61,.69,1,UIFont.Small)
    local receiver=MeeksRadio.activeRadioReceiver and MeeksRadio.activeRadioReceiver(self.player,false) or nil
    local allowed,reason=stationPermission(self.frequency)
    local reception=receiver and receiver.label or "NO ACTIVE RECEIVER"
    self:drawText(fitText("RECEPTION: "..reception.." // ACCESS: "..(allowed and "DJ" or "LISTENER").." ("..reason..")",UIFont.Small,self.width-190),20,self.height-36,.65,.61,.69,1,UIFont.Small)
    local selected=self.history.items[self.history.selected]
    if selected and selected.item then
        self:drawText(fitText("DETAIL: "..tostring(selected.item.text or ""),UIFont.Small,self.history.width),20,self.height-58,.94,.94,.97,1,UIFont.Small)
    end
end

function MeeksRadio.Listener:onRequest()
    local selected=self.tracks.items[self.tracks.selected]
    local active=MeeksRadio.activeRadioFrequency and MeeksRadio.activeRadioFrequency(self.player,true) or nil
    if selected then sendClientCommand(MeeksRadio.Config.module,"requestTrack",{frequency=self.frequency,receiverFrequency=active,trackId=selected.item.id}) end
end
function MeeksRadio.Listener:onApprove()
    local selected=self.requests.items[self.requests.selected]
    if selected then sendClientCommand(MeeksRadio.Config.module,"approveRequest",{frequency=self.frequency,index=selected.item.index}) end
end
function MeeksRadio.Listener:onReject()
    local selected=self.requests.items[self.requests.selected]
    if selected then sendClientCommand(MeeksRadio.Config.module,"rejectRequest",{frequency=self.frequency,index=selected.item.index}) end
end
function MeeksRadio.Listener:close()
    self:setVisible(false); self:removeFromUIManager(); MeeksRadio.Listener.instance=nil
end
function MeeksRadio.Listener.open(player,frequency)
    if not frequency then return end
    if MeeksRadio.Listener.instance then MeeksRadio.Listener.instance:close() end
    local ui=MeeksRadio.Listener:new(player,frequency); ui:initialise(); ui:addToUIManager(); MeeksRadio.Listener.instance=ui
end

local function inventoryDeviceFrequency(item)
    if not item or not item.getDeviceData then return nil end
    local ok,device=pcall(function() return item:getDeviceData() end)
    if not ok or not device then return nil end
    local onOk,turnedOn=pcall(function() return device:getIsTurnedOn() end)
    local channelOk,channel=pcall(function() return device:getChannel() end)
    return onOk and turnedOn and channelOk and MeeksRadio.Config.normalizeFrequency(channel) or nil
end
local function contextMenu(playerIndex,context,items)
    for _,wrapped in ipairs(items or {}) do
        local item=wrapped.items and wrapped.items[1] or wrapped
        local frequency=inventoryDeviceFrequency(item)
        if frequency and MeeksRadio.Config.stations[frequency] then
            context:addOption("Open Radio History & Requests",getSpecificPlayer(playerIndex),MeeksRadio.Listener.open,frequency)
            return
        end
    end
end
local function onKeyPressed(key)
    if Keyboard and key==Keyboard.KEY_F7 and MeeksRadio.activeRadioFrequency then
        local player=getPlayer(); local frequency=MeeksRadio.activeRadioFrequency(player,true)
        if frequency then
            local allowed=stationPermission(frequency)
            if allowed and MeeksRadio.Console then MeeksRadio.Console.open(player,frequency)
            else MeeksRadio.Listener.open(player,frequency) end
        end
    end
end
Events.OnFillInventoryObjectContextMenu.Add(contextMenu)
if Events.OnKeyPressed then Events.OnKeyPressed.Add(onKeyPressed) end
