require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "MeeksRadio/Config"
require "MeeksRadio/Catalog"

MeeksRadio = MeeksRadio or {}
MeeksRadio.Console = ISPanel:derive("MeeksRadioConsole")
MeeksRadio.Console.instance = nil

-- Shared visual language with Survivor League Community.
local C = {
    bg={0.035,0.035,0.045,0.97}, panel={0.065,0.065,0.080,0.96},
    rowA={0.085,0.085,0.100,0.92}, rowB={0.055,0.055,0.068,0.92},
    accent={0.40,0.85,0.54,1.0}, silver={0.77,0.79,0.82,1.0},
    text={0.92,0.92,0.95,1.0}, muted={0.58,0.59,0.64,1.0}, line={0.20,0.20,0.24,0.85},
}

local function rgba(color)
    return {r=color[1],g=color[2],b=color[3],a=color[4]}
end

local function styleButton(button)
    button.backgroundColor={r=0,g=0,b=0,a=0.35}
    button.backgroundColorMouseOver={r=C.silver[1],g=C.silver[2],b=C.silver[3],a=0.12}
    button.borderColor={r=C.silver[1],g=C.silver[2],b=C.silver[3],a=0.8}
end

local function sortedTracks(filter)
    local result, needle = {}, string.lower(filter or "")
    for id, track in pairs(MeeksRadio.Catalog) do
        local text = string.lower((track.title or id).." "..(track.artist or ""))
        if needle=="" or string.find(text,needle,1,true) then result[#result+1]=track end
    end
    table.sort(result,function(a,b) return string.lower(a.title or a.id)<string.lower(b.title or b.id) end)
    return result
end

local function drawCorners(self,x,y,w,h,color)
    local r,g,b,a=color[1],color[2],color[3],color[4] or 1
    local n=16
    self:drawRect(x,y,n,2,a,r,g,b); self:drawRect(x,y,2,n,a,r,g,b)
    self:drawRect(x+w-n,y,n,2,a,r,g,b); self:drawRect(x+w-2,y,2,n,a,r,g,b)
    self:drawRect(x,y+h-2,n,2,a,r,g,b); self:drawRect(x,y+h-n,2,n,a,r,g,b)
    self:drawRect(x+w-n,y+h-2,n,2,a,r,g,b); self:drawRect(x+w-2,y+h-n,2,n,a,r,g,b)
end

function MeeksRadio.Console:new(player,frequency)
    local screenW,screenH=getCore():getScreenWidth(),getCore():getScreenHeight()
    local width,height=760,520
    local o=ISPanel.new(self,(screenW-width)/2,(screenH-height)/2,width,height)
    o.player=player; o.frequency=frequency or 101200; o.moveWithMouse=true
    o.backgroundColor=rgba(C.bg); o.borderColor=rgba(C.silver)
    o.frameTexture=getTexture("media/ui/MeeksRadio/dj_console_frame.png")
    return o
end


function MeeksRadio.Console:createChildren()
    ISPanel.createChildren(self)
    self.search=ISTextEntryBox:new("",26,158,438,28)
    self.search:initialise(); self.search.backgroundColor=rgba(C.panel); self.search.borderColor=rgba(C.line)
    self.search:setTooltip("Search the server-approved music catalog"); self:addChild(self.search)

    self.trackList=ISScrollingListBox:new(26,194,438,230)
    self.trackList:initialise(); self.trackList.itemheight=26
    self.trackList.backgroundColor=rgba(C.panel); self.trackList.borderColor=rgba(C.line); self:addChild(self.trackList)
    self.queueList=ISScrollingListBox:new(484,158,250,266)
    self.queueList:initialise(); self.queueList.itemheight=26
    self.queueList.backgroundColor=rgba(C.panel); self.queueList.borderColor=rgba(C.line); self:addChild(self.queueList)

    self.addButton=ISButton:new(26,444,132,32,"ADD TO QUEUE",self,self.onAdd)
    self.removeButton=ISButton:new(168,444,112,32,"REMOVE",self,self.onRemove)
    self.skipButton=ISButton:new(484,444,112,32,"SKIP TRACK",self,self.onSkip)
    self.closeButton=ISButton:new(622,444,112,32,"CLOSE",self,self.close)
    for _,button in ipairs({self.addButton,self.removeButton,self.skipButton,self.closeButton}) do
        button:initialise(); styleButton(button); self:addChild(button)
    end
    self.lastFilter=nil; self:refreshTracks(); self:refreshStation()
end

function MeeksRadio.Console:refreshTracks()
    self.trackList:clear()
    for _,track in ipairs(sortedTracks(self.search:getText())) do
        self.trackList:addItem((track.title or track.id).."  //  "..(track.artist or "UNKNOWN ARTIST"),track)
    end
end

function MeeksRadio.Console:refreshStation()
    local config=MeeksRadio.Config.stations[self.frequency]
    local state=MeeksRadio.ClientStationStates and MeeksRadio.ClientStationStates[self.frequency]
    self.stationName=config and config.name or "UNKNOWN STATION"
    self.current=state and MeeksRadio.getTrack(state.currentTrackId) or nil
    self.queueList:clear()
    for index,entry in ipairs((state and state.queue) or {}) do
        local track=MeeksRadio.getTrack(entry.id)
        self.queueList:addItem(string.format("%02d  %s",index,track and track.title or entry.id),{index=index})
    end
end

function MeeksRadio.Console:update()
    ISPanel.update(self)
    local filter=self.search:getText()
    if filter~=self.lastFilter then self.lastFilter=filter; self:refreshTracks() end
end

function MeeksRadio.Console:prerender()
    ISPanel.prerender(self)
    if self.frameTexture then self:drawTextureScaled(self.frameTexture,0,0,760,520,1,1,1,1) end
    self:drawText("MEEKS RADIO // COMMUNITY BROADCAST SYSTEM //",20,10,C.silver[1],C.silver[2],C.silver[3],1,UIFont.Small)
    self:drawText("●",20,43,C.accent[1],C.accent[2],C.accent[3],1,UIFont.Medium)
    self:drawText("BROADCAST STATUS: ONLINE",42,45,C.accent[1],C.accent[2],C.accent[3],1,UIFont.Small)
    self:drawTextRight("BUILD 42 // MULTIPLAYER",738,45,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawText(self.stationName or "MEEKS RADIO",22,83,C.text[1],C.text[2],C.text[3],1,UIFont.Large)
    self:drawTextRight(string.format("%.1f MHz",self.frequency/1000),738,90,C.silver[1],C.silver[2],C.silver[3],1,UIFont.Medium)
    local now=self.current and ((self.current.title or self.current.id).."  //  "..(self.current.artist or "")) or "OFF AIR"
    self:drawText("NOW PLAYING: "..now,26,126,C.accent[1],C.accent[2],C.accent[3],1,UIFont.Small)
    self:drawText("APPROVED TRACKS",26,141,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    self:drawText("UP NEXT",484,141,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
    drawCorners(self,20,150,450,282,C.silver); drawCorners(self,478,150,262,282,C.silver)
    self:drawText("LIVE",22,492,C.accent[1],C.accent[2],C.accent[3],1,UIFont.Small)
    self:drawTextCentre("SERVER-VALIDATED AUDIO // CREATED BY Z3R0X92",380,492,C.muted[1],C.muted[2],C.muted[3],1,UIFont.Small)
end

function MeeksRadio.Console:onAdd()
    local selected=self.trackList.items[self.trackList.selected]
    if selected then sendClientCommand(MeeksRadio.Config.module,"queue",{frequency=self.frequency,trackId=selected.item.id}) end
end

function MeeksRadio.Console:onRemove()
    local selected=self.queueList.items[self.queueList.selected]
    if selected then sendClientCommand(MeeksRadio.Config.module,"remove",{frequency=self.frequency,index=selected.item.index}) end
end

function MeeksRadio.Console:onSkip()
    sendClientCommand(MeeksRadio.Config.module,"skip",{frequency=self.frequency})
end

function MeeksRadio.Console:close()
    self:setVisible(false); self:removeFromUIManager(); MeeksRadio.Console.instance=nil
end

function MeeksRadio.Console.open(player,frequency)
    if MeeksRadio.Console.instance then MeeksRadio.Console.instance:close() end
    local ui=MeeksRadio.Console:new(player,frequency)
    ui:initialise(); ui:addToUIManager(); MeeksRadio.Console.instance=ui
end

local function deviceFrequency(item)
    if not item or not item.getDeviceData then return nil end
    local ok,device=pcall(function() return item:getDeviceData() end)
    if not ok or not device then return nil end
    local channelOk,channel=pcall(function() return device:getChannel() end)
    return channelOk and MeeksRadio.Config.normalizeFrequency(channel) or nil
end

local function onContextMenu(playerIndex,context,items)
    local permission=MeeksRadio.ClientPermissions or {}
    if not (permission.isDj or permission.isAdmin) or permission.catalogMatch==false then return end
    for _,wrapped in ipairs(items or {}) do
        local item=wrapped.items and wrapped.items[1] or wrapped
        local frequency=deviceFrequency(item)
        if frequency and MeeksRadio.Config.stations[frequency] then
            context:addOption("Open Meeks DJ Console",getSpecificPlayer(playerIndex),MeeksRadio.Console.open,frequency)
            return
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onContextMenu)
