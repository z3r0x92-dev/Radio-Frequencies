require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "MeeksRadio/Config"
require "MeeksRadio/Catalog"
require "MeeksRadio/Theme"

MeeksRadio = MeeksRadio or {}
MeeksRadio.Console = ISPanel:derive("MeeksRadioConsole")
MeeksRadio.Console.instance = nil

local C = MeeksRadio.getInterfaceTheme()

local function rgba(c) return {r=c[1],g=c[2],b=c[3],a=c[4]} end

local function fitText(text,font,maxWidth)
    text=tostring(text or "")
    local tm=getTextManager()
    if tm:MeasureStringX(font,text)<=maxWidth then return text end
    while #text>0 and tm:MeasureStringX(font,text.."...")>maxWidth do text=string.sub(text,1,#text-1) end
    return text.."..."
end

local function clock(seconds)
    seconds=math.max(0,math.floor(tonumber(seconds) or 0))
    return string.format("%02d:%02d",math.floor(seconds/60),seconds%60)
end

local function sortedTracks(filter)
    local result,needle={},string.lower(filter or "")
    for id,track in pairs(MeeksRadio.Catalog) do
        local text=string.lower((track.title or id).." "..(track.artist or ""))
        if needle=="" or string.find(text,needle,1,true) then result[#result+1]=track end
    end
    table.sort(result,function(a,b) return string.lower(a.title or a.id)<string.lower(b.title or b.id) end)
    return result
end

local function addButton(self,x,y,w,label,callback,primary)
    local b=ISButton:new(x,y,w,self.buttonHeight or 30,label,self,callback)
    b:initialise()
    b.backgroundColor=rgba(primary and C.buttonPrimary or C.button)
    b.backgroundColorMouseOver=rgba(C.buttonHover)
    b.borderColor=rgba(C.line)
    b.textColor=rgba(C.buttonText)
    self:addChild(b); return b
end

function MeeksRadio.Console:new(player,frequency)
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    local w,h=math.max(1,math.min(1020,sw-80)),math.max(1,math.min(760,sh-80))
    local o=ISPanel.new(self,math.max(0,(sw-w)/2),math.max(0,(sh-h)/2),w,h)
    o.player=player; o.frequency=frequency or 102800; o.moveWithMouse=true
    o.backgroundColor=rgba(C.bg); o.borderColor={r=.08,g=.08,b=.08,a=1}
    return o
end

function MeeksRadio.Console:createChildren()
    ISPanel.createChildren(self)
    self.isAdmin=MeeksRadio.ClientPermissions and MeeksRadio.ClientPermissions.isAdmin==true
    local fontHeight=getTextManager():getFontHeight(UIFont.Small)
    self.buttonHeight=math.max(30,fontHeight+8)
    self.rowHeight=math.max(28,fontHeight+6)
    local leftX=22; local rightX=math.floor(self.width*.62); local leftW=rightX-leftX-16; local rightW=self.width-rightX-22
    local labelY=252
    local searchY=labelY+fontHeight+6
    local fieldHeight=math.max(28,fontHeight+8)
    local listY=searchY+fieldHeight+6
    local actionY=self.isAdmin and self.height-(self.buttonHeight*4+86) or self.height-(self.buttonHeight+54)
    local listHeight=math.max(100,actionY-listY-14)
    self.layout={labelY=labelY,searchY=searchY,listY=listY,actionY=actionY}
    self.search=ISTextEntryBox:new("",leftX,searchY,leftW,fieldHeight)
    self.search:initialise(); self.search.backgroundColor=rgba(C.panel); self.search.borderColor=rgba(C.line)
    self.search:setTooltip("Search the server-approved music catalog"); self:addChild(self.search)
    self.trackList=ISScrollingListBox:new(leftX,listY,leftW,listHeight)
    self.trackList:initialise(); self.trackList.itemheight=self.rowHeight; self.trackList.backgroundColor=rgba(C.panel); self:addChild(self.trackList)
    self.queueList=ISScrollingListBox:new(rightX,searchY,rightW,actionY-searchY-14)
    self.queueList:initialise(); self.queueList.itemheight=self.rowHeight; self.queueList.backgroundColor=rgba(C.panel); self:addChild(self.queueList)
    self.addButton=addButton(self,leftX,actionY,160,"ADD TO QUEUE",self.onAdd,true)
    self.removeButton=addButton(self,leftX+170,actionY,120,"REMOVE",self.onRemove,false)
    self.closeButton=addButton(self,self.width-154,actionY,132,"CLOSE",self.close,false)
    if self.isAdmin then
        local secondY=actionY+self.buttonHeight+8
        self.skipButton=addButton(self,leftX+300,actionY,100,"SKIP",self.onSkip,false)
        self.stopButton=addButton(self,leftX+410,actionY,100,"STOP",self.onStop,false)
        self.lockButton=addButton(self,rightX,actionY,math.max(100,rightW-154),"LOCK",self.onLock,false)
        self.emergencyButton=addButton(self,rightX,secondY,rightW,"EMERGENCY: SELECTED TRACK",self.onEmergency,true)
        self.djInput=ISTextEntryBox:new("",leftX,secondY,220,self.buttonHeight)
        self.djInput:initialise(); self.djInput.backgroundColor=rgba(C.panel); self.djInput.borderColor=rgba(C.line)
        self.djInput:setTooltip("Exact username for a DJ assignment"); self:addChild(self.djInput)
        self.djGrantButton=addButton(self,leftX+230,secondY,110,"GRANT DJ",self.onGrantDj,false)
        self.djRevokeButton=addButton(self,leftX+350,secondY,110,"REVOKE",self.onRevokeDj,false)
        self.broadcastKinds={"announcement","emergency","lore","event","community"}
        self.broadcastKindIndex=1
        self.layout.broadcastLabelY=secondY+self.buttonHeight+8
        self.layout.broadcastInputY=self.layout.broadcastLabelY+fontHeight+4
        self.layout.broadcastButtonsY=self.layout.broadcastInputY+fieldHeight+6
        self.broadcastInput=ISTextEntryBox:new("",22,self.layout.broadcastInputY,self.width-44,fieldHeight)
        self.broadcastInput:initialise(); self.broadcastInput.backgroundColor=rgba(C.panel); self.broadcastInput.borderColor=rgba(C.line)
        self.broadcastInput:setTooltip("Text shown only to players listening on this frequency"); self:addChild(self.broadcastInput)
        self.broadcastKindButton=addButton(self,22,self.layout.broadcastButtonsY,math.floor((self.width-66)/3),"TYPE: ANNOUNCEMENT",self.onBroadcastKind,false)
        self.broadcastSendButton=addButton(self,32+math.floor((self.width-66)/3),self.layout.broadcastButtonsY,math.floor((self.width-66)/3),"SEND BROADCAST",self.onBroadcast,true)
        self.templateIndex=0
        self.templateButton=addButton(self,42+math.floor((self.width-66)*2/3),self.layout.broadcastButtonsY,math.floor((self.width-66)/3),"LOAD NEXT TEMPLATE",self.onTemplate,false)
    end
    self.lastFilter=nil; self:refreshTracks(); self:refreshStation()
end

function MeeksRadio.Console:refreshTracks()
    self.trackList:clear()
    for _,track in ipairs(sortedTracks(self.search:getText())) do
        self.trackList:addItem(fitText((track.title or track.id).."  //  "..(track.artist or "UNKNOWN"),UIFont.Small,410),track)
    end
end

function MeeksRadio.Console:refreshStation()
    local config=MeeksRadio.Config.stations[self.frequency]
    local state=MeeksRadio.ClientStationStates and MeeksRadio.ClientStationStates[self.frequency]
    self.state=state; self.stationName=config and config.name or "UNKNOWN STATION"
    self.current=state and MeeksRadio.getTrack(state.currentTrackId) or nil
    self.queueList:clear()
    for index,entry in ipairs((state and state.queue) or {}) do
        local track=MeeksRadio.getTrack(entry.id)
        self.queueList:addItem(fitText(string.format("%02d  %s",index,track and track.title or entry.id),UIFont.Small,244),{index=index})
    end
    if self.lockButton then self.lockButton:setTitle(state and state.locked and "UNLOCK" or "LOCK") end
end

function MeeksRadio.Console:update()
    ISPanel.update(self)
    local filter=self.search:getText()
    if filter~=self.lastFilter then self.lastFilter=filter; self:refreshTracks() end
    local state=MeeksRadio.ClientStationStates and MeeksRadio.ClientStationStates[self.frequency]
    if state and (not self.state or state.revision~=self.state.revision) then self:refreshStation() end
    local permissions=MeeksRadio.ClientPermissions or {}
    local stationPermission=permissions.stationPermissions and permissions.stationPermissions[self.frequency]
    self.permissionAllowed=permissions.isAdmin==true or (stationPermission and stationPermission.allowed==true)
    self.permissionReason=permissions.isAdmin and "administrator" or (stationPermission and stationPermission.reason or "permission status unavailable")
end

function MeeksRadio.Console:prerender()
    ISPanel.prerender(self)
    local center=self.width/2
    -- Windows 95 shell surrounding a black 1990s hi-fi receiver display.
    self:drawRect(4,4,self.width-8,30,1,C.accent[1],C.accent[2],C.accent[3])
    self:drawText("RADIO FREQUENCIES // "..C.name,12,10,C.titleText[1],C.titleText[2],C.titleText[3],1,UIFont.Small)
    local permission=MeeksRadio.ClientPermissions or {}
    local status="ONLINE"
    local statusColor=C.live
    if permission.helloAcknowledged==false then status="CONNECTING..."; statusColor=C.muted
    elseif permission.protocolMatch==false then status="PROTOCOL MISMATCH"; statusColor=C.bright
    elseif permission.catalogMatch==false then status="CATALOG MISMATCH"; statusColor=C.bright end
    self:drawTextCentre("[ "..status.." ]",center,10,statusColor[1],statusColor[2],statusColor[3],1,UIFont.Small)
    self:drawTextRight(self.isAdmin and "ADMIN" or (self.permissionAllowed and "DJ" or "LISTENER"),self.width-12,10,C.titleText[1],C.titleText[2],C.titleText[3],1,UIFont.Small)
    self:drawRect(12,42,self.width-24,202,1,.02,.03,.025)
    self:drawRect(12,42,self.width-24,2,1,1,1,1)
    self:drawRect(12,42,2,202,1,1,1,1)
    self:drawRect(12,self.height-2,self.width-12,2,1,.16,.16,.16)
    self:drawTextCentre(fitText(self.stationName or "RADIO FREQUENCIES",UIFont.Small,self.width-80),center,51,C.text[1],C.text[2],C.text[3],1,UIFont.Small)
    self:drawTextCentre(string.format("%.1f MHz",self.frequency/1000),center,73,C.accent[1],C.accent[2],C.accent[3],1,UIFont.Large)
    local title=self.current and (self.current.title or self.current.id) or "OFF AIR"
    local artist=self.current and (self.current.artist or "UNKNOWN ARTIST") or "WAITING FOR BROADCAST"
    self:drawTextCentre(fitText(title,UIFont.Medium,self.width-100),center,112,C.text[1],C.text[2],C.text[3],1,UIFont.Medium)
    self:drawTextCentre(fitText(artist,UIFont.Small,self.width-100),center,139,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    local state=self.state or {}; local duration=self.current and tonumber(self.current.duration) or 0
    local now=getTimestamp and getTimestamp() or os.time()
    local elapsed=state.startedAt and math.min(duration,math.max(0,now-state.startedAt)) or 0
    local progress=duration>0 and elapsed/duration or 0
    local playbackStatus=MeeksRadio.ClientPlaybackStatus or {}
    local waiting=playbackStatus.waitingForNext==true and playbackStatus.frequency==self.frequency and playbackStatus.trackId==state.currentTrackId
    if waiting then
        self:drawTextCentre("TUNED IN - CURRENT BROADCAST ALREADY IN PROGRESS",center,160,C.bright[1],C.bright[2],C.bright[3],1,UIFont.Small)
        self:drawTextCentre("AUDIO BEGINS WITH NEXT TRACK",center,182,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    else
        local heights={8,18,28,14,22,34,16,26,11,21,30,13,24,17,27,9}
        for i,height in ipairs(heights) do self:drawRect(center-132+(i-1)*17,174-height/2,5,height,.82,C.accent[1],C.accent[2],C.accent[3]) end
    end
    local progressWidth=math.max(20,self.width-140)
    self:drawRect(70,204,progressWidth,4,1,C.line[1],C.line[2],C.line[3]); self:drawRect(70,204,progressWidth*progress,4,1,C.accent[1],C.accent[2],C.accent[3])
    self:drawText(clock(elapsed),70,216,C.text[1],C.text[2],C.text[3],1,UIFont.Small)
    self:drawTextCentre("SERVER SYNCHRONIZED",center,216,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawTextRight(clock(duration),self.width-70,216,C.text[1],C.text[2],C.text[3],1,UIFont.Small)
    self:drawText("APPROVED TRACKS",22,self.layout.labelY,C.label[1],C.label[2],C.label[3],1,UIFont.Small)
    self:drawText("UP NEXT",math.floor(self.width*.62),self.layout.labelY,C.label[1],C.label[2],C.label[3],1,UIFont.Small)
    local bulletin=state.activeBulletin
    if bulletin then
        self:drawText(fitText("["..string.upper(tostring(bulletin.kind or "announcement")).."] "..tostring(bulletin.text or ""),UIFont.Small,self.width-44),22,self.layout.broadcastLabelY or (self.layout.actionY+self.buttonHeight+8),C.bright[1],C.bright[2],C.bright[3],1,UIFont.Small)
    elseif self.isAdmin then
        self:drawText("BROADCAST MESSAGE",22,self.layout.broadcastLabelY,C.label[1],C.label[2],C.label[3],1,UIFont.Small)
    end
    self:drawRect(22,self.height-27,10,10,1,C.live[1],C.live[2],C.live[3])
    self:drawText("LIVE",40,self.height-32,C.label[1],C.label[2],C.label[3],1,UIFont.Small)
    local receiver=MeeksRadio.activeRadioReceiver and MeeksRadio.activeRadioReceiver(self.player,false) or nil
    self:drawTextCentre(fitText((receiver and receiver.label or "NO ACTIVE RECEIVER").." // "..tostring(self.permissionReason or "checking permission"),UIFont.Small,self.width-100),center,self.height-32,C.label[1],C.label[2],C.label[3],1,UIFont.Small)
end

function MeeksRadio.Console:onAdd()
    local selected=self.trackList.items[self.trackList.selected]
    if selected then sendClientCommand(MeeksRadio.Config.module,"queue",{frequency=self.frequency,trackId=selected.item.id}) end
end
function MeeksRadio.Console:onRemove()
    local selected=self.queueList.items[self.queueList.selected]
    if selected then sendClientCommand(MeeksRadio.Config.module,"remove",{frequency=self.frequency,index=selected.item.index}) end
end
function MeeksRadio.Console:onSkip() if self.isAdmin then sendClientCommand(MeeksRadio.Config.module,"skip",{frequency=self.frequency}) end end
function MeeksRadio.Console:onStop() if self.isAdmin then sendClientCommand(MeeksRadio.Config.module,"stop",{frequency=self.frequency}) end end
function MeeksRadio.Console:onLock()
    if self.isAdmin then sendClientCommand(MeeksRadio.Config.module,"lock",{frequency=self.frequency,locked=not (self.state and self.state.locked)}) end
end
function MeeksRadio.Console:onEmergency()
    local selected=self.trackList.items[self.trackList.selected]
    if self.isAdmin and selected then
        sendClientCommand(MeeksRadio.Config.module,"emergency",{frequency=self.frequency,trackId=selected.item.id})
    end
end
function MeeksRadio.Console:onGrantDj()
    local name=self.djInput and self.djInput:getText() or ""
    if self.isAdmin and string.match(name,"%S") then sendClientCommand(MeeksRadio.Config.module,"grant",{username=name}) end
end
function MeeksRadio.Console:onRevokeDj()
    local name=self.djInput and self.djInput:getText() or ""
    if self.isAdmin and string.match(name,"%S") then sendClientCommand(MeeksRadio.Config.module,"revoke",{username=name}) end
end
function MeeksRadio.Console:onBroadcastKind()
    if not self.isAdmin then return end
    self.broadcastKindIndex=(self.broadcastKindIndex % #self.broadcastKinds)+1
    self.broadcastKindButton:setTitle("TYPE: "..string.upper(self.broadcastKinds[self.broadcastKindIndex]))
end
function MeeksRadio.Console:onBroadcast()
    if not self.isAdmin or not self.broadcastInput then return end
    local text=self.broadcastInput:getText() or ""
    if string.match(text,"%S") then
        sendClientCommand(MeeksRadio.Config.module,"broadcast",{
            frequency=self.frequency,
            kind=self.broadcastKinds[self.broadcastKindIndex],
            text=text,
        })
        self.broadcastInput:setText("")
    end
end
function MeeksRadio.Console:onTemplate()
    local templates=MeeksRadio.Config.broadcastTemplates or {}
    if not self.isAdmin or #templates==0 then return end
    self.templateIndex=(self.templateIndex % #templates)+1
    local template=templates[self.templateIndex]
    self.broadcastInput:setText(tostring(template.text or ""))
    for index,kind in ipairs(self.broadcastKinds) do
        if kind==template.kind then self.broadcastKindIndex=index break end
    end
    self.broadcastKindButton:setTitle("TYPE: "..string.upper(self.broadcastKinds[self.broadcastKindIndex]))
    self.templateButton:setTitle("TEMPLATE: "..string.upper(tostring(template.id or self.templateIndex)))
end
function MeeksRadio.Console:close() self:setVisible(false); self:removeFromUIManager(); MeeksRadio.Console.instance=nil end
function MeeksRadio.Console.open(player,frequency)
    if MeeksRadio.Console.instance then MeeksRadio.Console.instance:close() end
    local ui=MeeksRadio.Console:new(player,frequency); ui:initialise(); ui:addToUIManager(); MeeksRadio.Console.instance=ui
end

local function deviceFrequency(item)
    if not item or not item.getDeviceData then return nil end
    local ok,device=pcall(function() return item:getDeviceData() end); if not ok or not device then return nil end
    local onOk,turnedOn=pcall(function() return device:getIsTurnedOn() end)
    local channelOk,channel=pcall(function() return device:getChannel() end)
    return onOk and turnedOn and channelOk and MeeksRadio.Config.normalizeFrequency(channel) or nil
end
local function onContextMenu(playerIndex,context,items)
    local permission=MeeksRadio.ClientPermissions or {}
    for _,wrapped in ipairs(items or {}) do
        local item=wrapped.items and wrapped.items[1] or wrapped; local frequency=deviceFrequency(item)
        if frequency and MeeksRadio.Config.stations[frequency] then
            if permission.helloAcknowledged==false then
                local option=context:addOption("Radio Frequencies: checking compatibility")
                option.notAvailable=true
                return
            end
            if permission.protocolMatch==false or permission.catalogMatch==false then
                local reason=permission.protocolMatch==false and "protocol mismatch" or "catalog mismatch"
                local option=context:addOption("Radio Frequencies: "..reason.." (update required)")
                option.notAvailable=true
                return
            end
            local stationPermission=permission.stationPermissions and permission.stationPermissions[frequency]
            if not permission.isAdmin and not (stationPermission and stationPermission.allowed==true) then return end
            context:addOption("Open Radio Operations Console",getSpecificPlayer(playerIndex),MeeksRadio.Console.open,frequency); return
        end
    end
end
Events.OnFillInventoryObjectContextMenu.Add(onContextMenu)
