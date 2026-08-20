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
    value.font=UIFont.Small
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

local function wrapText(text,font,maxWidth,maxLines)
    local tm=getTextManager(); local lines={}; local current=""; local overflow=false
    for word in string.gmatch(tostring(text or ""),"%S+") do
        local candidate=current=="" and word or (current.." "..word)
        if tm:MeasureStringX(font,candidate)<=maxWidth then
            current=candidate
        else
            if current~="" then lines[#lines+1]=current end
            current=word
            if #lines>=maxLines then overflow=true; break end
        end
    end
    if current~="" and #lines<maxLines then lines[#lines+1]=current end
    if #lines==0 then lines[1]="" end
    if overflow then lines[#lines]=fitText(lines[#lines].."...",font,maxWidth) end
    return lines
end

local function listFontHeight(font)
    local height=20
    pcall(function() height=getTextManager():getFontHeight(font) end)
    return tonumber(height) or 20
end

local function themedListItem(list,y,item,alt)
    local selected=list.selected==item.index
    local fill=selected and {0.095,0.095,0.112,0.98} or (alt and {0.048,0.048,0.058,0.94} or {0.032,0.032,0.040,0.94})
    list:drawRect(0,y,list:getWidth(),list.itemheight,fill[4],fill[1],fill[2],fill[3])
    if selected then list:drawRect(0,y,3,list.itemheight,1,C.accent[1],C.accent[2],C.accent[3]) end
    local lines=wrapText(item.text or "",list.font,list:getWidth()-20,list.wrapLines or 1)
    local lineHeight=listFontHeight(list.font)
    local textY=y+math.max(2,math.floor((list.itemheight-(#lines*lineHeight))/2))
    for index,line in ipairs(lines) do
        list:drawText(fitText(line,list.font,list:getWidth()-20),10,textY+((index-1)*lineHeight),C.text[1],C.text[2],C.text[3],1,list.font)
    end
    return y+list.itemheight
end

local function styleList(list)
    list.backgroundColor=rgba(C.panel)
    list.borderColor=rgba(C.line)
    list.doDrawItem=themedListItem
end

function MeeksRadio.Listener:new(player,frequency)
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    local w,h=math.max(1,math.min(1180,sw-30)),math.max(1,math.min(680,sh-30))
    local o=ISPanel.new(self,math.max(0,(sw-w)/2),math.max(0,(sh-h)/2),w,h)
    o.player=player; o.frequency=frequency; o.moveWithMouse=true
    o.backgroundColor=rgba(C.bg); o.borderColor=rgba(C.line)
    return o
end

function MeeksRadio.Listener:createChildren()
    ISPanel.createChildren(self)
    local margin,gap=24,16
    local leftW=math.floor((self.width-(margin*2)-gap)*0.56)
    local right=margin+leftW+gap
    local rightW=self.width-margin-right
    local listTop,listBottom=206,self.height-154
    self.history=ISScrollingListBox:new(margin,listTop,leftW,listBottom-listTop)
    self.history:initialise(); self.history.font=UIFont.Small; self.history.itemheight=math.max(54,listFontHeight(UIFont.Small)*2+10); self.history.wrapLines=2; styleList(self.history); self:addChild(self.history)
    local rightSpace=listBottom-listTop
    self.tracks=ISScrollingListBox:new(right,listTop,rightW,math.max(92,math.floor((rightSpace-44)/2)))
    self.tracks:initialise(); self.tracks.font=UIFont.Small; self.tracks.itemheight=24; styleList(self.tracks); self:addChild(self.tracks)
    local requestsY=self.tracks.y+self.tracks.height+36
    self.requests=ISScrollingListBox:new(right,requestsY,rightW,math.max(70,listBottom-requestsY))
    self.requests:initialise(); self.requests.font=UIFont.Small; self.requests.itemheight=24; styleList(self.requests); self:addChild(self.requests)
    local actionY=self.height-140
    local actionGap=8
    local actionW=math.floor((rightW-(actionGap*3))/4)
    self.requestButton=button(self,right,actionY,actionW,"REQUEST",self.onRequest)
    self.favoriteButton=button(self,right+actionW+actionGap,actionY,actionW,"FAVORITE",self.onFavorite)
    local allowed=stationPermission(self.frequency)
    if allowed then
        self.operationsButton=button(self,margin,actionY,180,"OPERATIONS",self.onOperations)
        self.approveButton=button(self,right+(actionW+actionGap)*2,actionY,actionW,"APPROVE",self.onApprove)
        self.rejectButton=button(self,right+(actionW+actionGap)*3,actionY,actionW,"REJECT",self.onReject)
    end
    self.topCloseButton=button(self,self.width-52,16,28,"X",self.close)
    self.closeButton=button(self,self.width-166,self.height-48,142,"CLOSE",self.close)
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
    self:drawRect(0,0,self.width,68,1,C.panel[1],C.panel[2],C.panel[3])
    self:drawRect(0,67,self.width,1,1,C.line[1],C.line[2],C.line[3])
    self:drawText("RADIO FREQUENCIES // COMMAND CENTER",22,20,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawText("STATUS: ONLINE",22,44,C.live[1],C.live[2],C.live[3],1,UIFont.Small)
    self:drawText("LISTENER ACCESS",174,44,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawTextRight("BUILD 42",self.width-64,20,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawText("RADIO FREQUENCIES",22,84,C.text[1],C.text[2],C.text[3],1,UIFont.Large)
    self:drawText("LISTENER",24,116,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawTextRight(station.name or "UNKNOWN",self.width-24,80,C.text[1],C.text[2],C.text[3],1,UIFont.Medium)
    self:drawTextRight(string.format("%.1f MHz",self.frequency/1000),self.width-24,108,C.accent[1],C.accent[2],C.accent[3],1,UIFont.Medium)
    local state=self.state or {}
    local current=state.currentTrackId and MeeksRadio.getTrack(state.currentTrackId) or nil
    local nowPlaying=(current and ((current.title or current.id).." // "..(current.artist or "UNKNOWN ARTIST"))) or "OFF AIR // WAITING FOR BROADCAST"
    self:drawTextCentre(fitText(nowPlaying,UIFont.Small,420),self.width/2,90,C.text[1],C.text[2],C.text[3],1,UIFont.Small)
    local playbackStatus=MeeksRadio.ClientPlaybackStatus or {}
    local waiting=playbackStatus.waitingForNext==true and playbackStatus.frequency==self.frequency and playbackStatus.trackId==(self.state and self.state.currentTrackId)
    if waiting then
        self:drawTextCentre("TUNED IN // AUDIO BEGINS WITH NEXT TRACK",self.width/2,140,C.live[1],C.live[2],C.live[3],1,UIFont.Small)
    elseif state.currentTrackId and state.endsAt then
        local now=getTimestamp and getTimestamp() or os.time()
        local remaining=math.max(0,math.floor(tonumber(state.endsAt)-now))
        self:drawTextCentre(string.format("%02d:%02d REMAINING // SERVER SYNCHRONIZED",math.floor(remaining/60),remaining%60),self.width/2,140,C.live[1],C.live[2],C.live[3],1,UIFont.Small)
    end
    self:drawRectBorder(22,158,self.history.width+4,self.history.height+50,0.9,C.line[1],C.line[2],C.line[3])
    self:drawRectBorder(self.tracks.x-2,158,self.tracks.width+4,self.history.height+50,0.9,C.line[1],C.line[2],C.line[3])
    self:drawText("BROADCAST HISTORY",24,174,C.label[1],C.label[2],C.label[3],1,UIFont.Small)
    self:drawText("APPROVED TRACKS",self.tracks.x,174,C.label[1],C.label[2],C.label[3],1,UIFont.Small)
    self:drawText("PLAYER REQUESTS",self.requests.x,self.requests.y-24,C.label[1],C.label[2],C.label[3],1,UIFont.Small)
    local receiver=MeeksRadio.activeRadioReceiver and MeeksRadio.activeRadioReceiver(self.player,false) or nil
    local allowed,reason=stationPermission(self.frequency)
    local reception=receiver and receiver.label or "NO ACTIVE RECEIVER"
    self:drawText(fitText("RECEPTION: "..reception.." // ACCESS: "..(allowed and "DJ" or "LISTENER").." ("..reason..")",UIFont.Small,self.width-220),24,self.height-40,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    local selected=self.history.items[self.history.selected]
    if selected and selected.item then
        local detailLines=wrapText("DETAIL: "..tostring(selected.item.text or ""),UIFont.Small,self.width-190,2)
        local detailLineHeight=listFontHeight(UIFont.Small)
        for index,line in ipairs(detailLines) do
            self:drawText(fitText(line,UIFont.Small,self.width-220),24,self.height-92+((index-1)*detailLineHeight),C.text[1],C.text[2],C.text[3],1,UIFont.Small)
        end
    end
    self:drawText("ONLINE",24,self.height-26,C.live[1],C.live[2],C.live[3],1,UIFont.Small)
end

function MeeksRadio.Listener:onRequest()
    local selected=self.tracks.items[self.tracks.selected]
    -- The selected Listener station is authoritative for a request. Audio
    -- playback still requires a powered receiver tuned to this frequency.
    if selected then sendClientCommand(MeeksRadio.Config.module,"requestTrack",{frequency=self.frequency,receiverFrequency=self.frequency,trackId=selected.item.id}) end
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
function MeeksRadio.Listener:onOperations()
    local player,frequency=self.player,self.frequency
    self:close()
    if MeeksRadio.Console then MeeksRadio.Console.open(player,frequency) end
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
