require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "MeeksRadio/Config"
require "MeeksRadio/Catalog"
require "MeeksRadio/Theme"

MeeksRadio = MeeksRadio or {}
MeeksRadio.Listener = ISPanel:derive("RadioFrequenciesListener")
MeeksRadio.Listener.instance = nil

local C = MeeksRadio.getInterfaceTheme()
local function rgba(c) return {r=c[1],g=c[2],b=c[3],a=c[4]} end

local function button(panel,x,y,w,title,callback)
    local value=ISButton:new(x,y,w,30,title,panel,callback)
    value:initialise()
    value.backgroundColor=rgba(C.button)
    value.backgroundColorMouseOver=rgba(C.buttonHover)
    value.borderColor=rgba(C.line)
    value.textColor=rgba(C.buttonText)
    panel:addChild(value); return value
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
    o.backgroundColor=rgba(C.bg); o.borderColor=rgba(C.line)
    return o
end

function MeeksRadio.Listener:createChildren()
    ISPanel.createChildren(self)
    local gap=20; local column=math.floor((self.width-60)/2); local right=40+column
    local listBottom=self.height-112
    self.history=ISScrollingListBox:new(20,122,column,listBottom-122)
    self.history:initialise(); self.history.itemheight=30; self:addChild(self.history)
    self.tracks=ISScrollingListBox:new(right,122,column,math.max(130,math.floor((listBottom-140)/2)))
    self.tracks:initialise(); self.tracks.itemheight=26; self:addChild(self.tracks)
    local requestsY=self.tracks.y+self.tracks.height+42
    self.requests=ISScrollingListBox:new(right,requestsY,column,math.max(70,listBottom-requestsY))
    self.requests:initialise(); self.requests.itemheight=26; self:addChild(self.requests)
    self.requestButton=button(self,right,self.height-94,math.floor(column*.30),"REQUEST",self.onRequest)
    self.favoriteButton=button(self,right+math.floor(column*.31),self.height-94,math.floor(column*.22),"FAVORITE",self.onFavorite)
    local allowed=stationPermission(self.frequency)
    if allowed then
        self.approveButton=button(self,right+math.floor(column*.54),self.height-94,math.floor(column*.21),"APPROVE",self.onApprove)
        self.rejectButton=button(self,right+math.floor(column*.76),self.height-94,math.floor(column*.23),"REJECT",self.onReject)
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
    local data=self.player and self.player:getModData() or {}
    local favorites=data.MeeksRadioFavorites or {}
    for _,track in ipairs(sorted) do
        self.tracks:addItem((favorites[track.id] and "* " or "  ")..trackTitle(track.id),track)
    end
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
    self:drawRect(4,4,self.width-8,30,1,C.accent[1],C.accent[2],C.accent[3])
    self:drawText("RADIO FREQUENCIES - LISTENER // "..C.name,12,10,C.titleText[1],C.titleText[2],C.titleText[3],1,UIFont.Small)
    self:drawRect(12,40,self.width-24,58,1,C.panel[1],C.panel[2],C.panel[3])
    self:drawText((station.name or "UNKNOWN").." // "..string.format("%.1f MHz",self.frequency/1000),20,48,C.text[1],C.text[2],C.text[3],1,UIFont.Medium)
    local playbackStatus=MeeksRadio.ClientPlaybackStatus or {}
    local waiting=playbackStatus.waitingForNext==true and playbackStatus.frequency==self.frequency and playbackStatus.trackId==(self.state and self.state.currentTrackId)
    if waiting then
        self:drawTextCentre("TUNED IN - CURRENT BROADCAST ALREADY IN PROGRESS",self.width/2,68,C.live[1],C.live[2],C.live[3],1,UIFont.Small)
        self:drawTextCentre("AUDIO BEGINS WITH NEXT TRACK",self.width/2,84,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    end
    self:drawText("BROADCAST HISTORY",20,102,C.label[1],C.label[2],C.label[3],1,UIFont.Small)
    self:drawText("APPROVED TRACKS",self.tracks.x,102,C.label[1],C.label[2],C.label[3],1,UIFont.Small)
    self:drawText("PLAYER REQUESTS",self.requests.x,self.requests.y-20,C.label[1],C.label[2],C.label[3],1,UIFont.Small)
    local receiver=MeeksRadio.activeRadioReceiver and MeeksRadio.activeRadioReceiver(self.player,false) or nil
    local allowed,reason=stationPermission(self.frequency)
    local reception=receiver and receiver.label or "NO ACTIVE RECEIVER"
    self:drawText(fitText("RECEPTION: "..reception.." // ACCESS: "..(allowed and "DJ" or "LISTENER").." ("..reason..")",UIFont.Small,self.width-190),20,self.height-36,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    local selected=self.history.items[self.history.selected]
    if selected and selected.item then
        self:drawText(fitText("DETAIL: "..tostring(selected.item.text or ""),UIFont.Small,self.history.width),20,self.height-58,C.text[1],C.text[2],C.text[3],1,UIFont.Small)
    end
    local state=self.state or {}
    if state.currentTrackId and state.endsAt then
        local now=getTimestamp and getTimestamp() or os.time()
        local remaining=math.max(0,math.floor(tonumber(state.endsAt)-now))
        self:drawTextRight("NOW PLAYING: "..trackTitle(state.currentTrackId).." // "..string.format("%02d:%02d",math.floor(remaining/60),remaining%60).." REMAINING",self.width-20,38,C.live[1],C.live[2],C.live[3],1,UIFont.Small)
    end
end

function MeeksRadio.Listener:onRequest()
    local selected=self.tracks.items[self.tracks.selected]
    local active=MeeksRadio.activeRadioFrequency and MeeksRadio.activeRadioFrequency(self.player,true) or nil
    if selected then sendClientCommand(MeeksRadio.Config.module,"requestTrack",{frequency=self.frequency,receiverFrequency=active,trackId=selected.item.id}) end
end
function MeeksRadio.Listener:onFavorite()
    local selected=self.tracks.items[self.tracks.selected]
    if not selected or not self.player then return end
    local data=self.player:getModData()
    data.MeeksRadioFavorites=data.MeeksRadioFavorites or {}
    local id=selected.item.id
    if data.MeeksRadioFavorites[id] then data.MeeksRadioFavorites[id]=nil
    else
        local count=0; for _ in pairs(data.MeeksRadioFavorites) do count=count+1 end
        if count<math.max(1,tonumber(MeeksRadio.Config.maxFavorites) or 100) then data.MeeksRadioFavorites[id]=true end
    end
    self:refresh()
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
    local configured=string.upper(tostring(MeeksRadio.Config.openKey or "F7"))
    if key == 65 or key == 296 then
        local player=getPlayer(); local frequency=(MeeksRadio.activeRadioFrequency and MeeksRadio.activeRadioFrequency(player,true)) or 102800
        if frequency then
            local allowed=stationPermission(frequency)
            if allowed and MeeksRadio.Console then MeeksRadio.Console.open(player,frequency)
            else MeeksRadio.Listener.open(player,frequency) end
        end
    end
end
Events.OnFillInventoryObjectContextMenu.Add(contextMenu)
if Events.OnKeyPressed then Events.OnKeyPressed.Add(onKeyPressed) end
