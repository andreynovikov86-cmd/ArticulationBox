-- @description ArticulationBox
-- @version 1.0.10
-- @author Andrey Novikov
-- @provides
--   [main=main,midi_editor] .
--   [main=midi_editor] Articulation_Quick_Menu.lua
--   [main=midi_editor] Articulation_Menu_Popup.lua
--   [nomain] Articulation_Editor.lua
--   [nomain] THIRD_PARTY_NOTICES.txt
--   [nomain] INSTALL_RU.txt
--   [nomain] USER_GUIDE.md
--   [nomain] USER_GUIDE_RU.md
--   [nomain] LICENSE.md
-- @about
--   Compact articulation field for REAPER MIDI Editor.
--   Requires js_ReaScriptAPI and ReaImGui, installed separately through ReaPack.
--   Supports per-track banks, keyswitches, MIDI channels and controllers.
--   Personal banks are stored outside this package and are not distributed.
--   Licensed under MIT; see LICENSE.md and THIRD_PARTY_NOTICES.txt.
-- @changelog
--   Keep note links active while Add / Edit articulation is open.
--   Pause automatic writes during native Quantize Events preview.
--   Use one MIDI buffer write and indexed matching for long items.
--   Handle selection changes without regenerating keyswitches.
--   Skip MIDI scans on unrelated project changes during playback.
--   Display literal ampersands in articulation menus.
--   Add explicit Ending type; only ending records appear in its submenu.
--   Add independent Ending keyswitches with Note end timing and Clear ending.
--   Create and select a named bank before editing articulations from Empty bank.
--   Widen bank name fields for creation and renaming.
--   Clear the Name input buffer after Save & Next and when learning an unmapped key.
--   Exclude standalone Controller presets from keyswitch name learning.
--   Keep the source name when creating an articulation variant.
--   Add independent group names to keyswitch velocity submenus.
--   Move Default articulation below Banks; disable it for Empty bank.
--   Restore defaults after manual keyswitch regions and show named velocity groups.
--   Start Controller with None; do not add Pitch Bend when changing types.

-- ArticulationBox by Andrey Novikov.
-- License: MIT. See LICENSE.md and THIRD_PARTY_NOTICES.txt.
-- Articulation Manager v5 UI (v4 MIDI format). One assignment per musical note; owned keyswitches.
-- Built-in gfx/MIDI API and js_ReaScriptAPI for the embedded field.
local R=reaper
local function validPointer(value,kind,project)
 if not value then return false end
 if R.ValidatePtr2 then return R.ValidatePtr2(project or 0,value,kind) end
 if R.ValidatePtr then return R.ValidatePtr(value,kind) end
 return true
end
local function isMidiTake(take,project)
 return validPointer(take,'MediaItem_Take*',project) and R.TakeIsMIDI(take)
end
local SECTION='ArticulationManager_v4'
local ART='ABART4'
local KS='ABKS4'
local status='Select notes and choose an articulation.'
local banks,bankIndex={},1
local function enc(s) return (s:gsub('%%','%%25'):gsub('\t','%%09'):gsub('\n','%%0A'):gsub('\r','%%0D')) end
local function dec(s) return (s:gsub('%%(%x%x)',function(h) return string.char(tonumber(h,16)) end)) end
local function hex(s) return (s:gsub('.',function(c) return string.format('%02X',c:byte()) end)) end
local function unhex(s)
 if #s%2~=0 or s:find('[^%x]') then return nil end
 return (s:gsub('%x%x',function(h) return string.char(tonumber(h,16)) end))
end
local function split(s,separator)
 local f={} for v in (s..separator):gmatch('(.-)'..separator) do f[#f+1]=v end return f
end
local function number(v,min,max,integer)
 local n=tonumber(v)
 if not n or n~=n or n<min or n>max or (integer and n%1~=0) then return nil end
 return n
end
local controllers={prefix='ABCTRL1',eventPrefix='ABCC1:'}
function controllers.editorTake()
 local context=controllers.editorContext
 if not context or (context.project and R.EnumProjects(-1,'')~=context.project) then return nil end
 return isMidiTake(context.take,context.project) and context.take or nil
end
function controllers.enabled(a) return a and (a.ctrl=='cc' or a.ctrl=='pitch') end
function controllers.valid(a)
 if not a.ctrl or a.ctrl=='none' then return true end
 local low,high=a.ctrl=='pitch' and -8192 or 0,a.ctrl=='pitch' and 8191 or 127
 return controllers.enabled(a) and (a.ctrl~='cc' or number(a.ctrlCC,0,127,true))
  and number(a.ctrlValue,low,high,true) and number(a.ctrlChannel,0,16,true)
  and (a.ctrlTiming=='full' or a.ctrlTiming=='start' or a.ctrlTiming=='end')
  and number(a.ctrlLead,0.01,10000,false) and number(a.ctrlTail,0.01,10000,false)
  and number(a.ctrlReset,low,high,true)
end
function controllers.fields(a)
 return {hex(a.name or ''),a.ctrl,a.ctrlCC or 1,a.ctrlValue,a.ctrlChannel,a.ctrlTiming,a.ctrlLead,a.ctrlTail,a.ctrlReset}
end
function controllers.config(a)
 if not controllers.enabled(a) then return '' end
 local fields=controllers.fields(a) table.remove(fields,1) return table.concat(fields,'|')
end
function controllers.encode(a) return hex(table.concat(controllers.fields(a),'|')) end
function controllers.decode(data)
 local raw=unhex(data) if not raw then return nil end
 local f=split(raw,'|') if #f~=9 then return nil end
 local name=unhex(f[1]) if not name then return nil end
 local a={mode='controller',name=name,ctrl=f[2],ctrlCC=tonumber(f[3]),ctrlValue=tonumber(f[4]),ctrlChannel=tonumber(f[5]),ctrlTiming=f[6],ctrlLead=tonumber(f[7]),ctrlTail=tonumber(f[8]),ctrlReset=tonumber(f[9])}
 return controllers.enabled(a) and controllers.valid(a) and a or nil
end
function controllers.attach(a,data)
 local c=controllers.decode(data) if not c then return false end
 for k,v in pairs(c) do if k~='name' and k~='mode' then a[k]=v end end
 return true
end
function controllers.copy(a)
 return controllers.decode(controllers.encode(a))
end
function controllers.lane(a,n)
 return table.concat({a.ctrl,a.ctrl=='cc' and a.ctrlCC or -1,a.ctrlChannel==0 and n.ch or a.ctrlChannel-1},':')
end
function controllers.restoreShift(n)
 if n.controllerShift and n.controllerShift>0 then
  n.olds=n.olds or n.s n.olde=n.olde or n.e
  n.s=n.s-n.controllerShift n.controllerShift=nil n.changed=true
 end
end
function controllers.set(n,c)
 controllers.restoreShift(n)
 local result={} local lane=c and controllers.lane(c,n)
 for _,old in ipairs(n.controllers or {}) do if lane and controllers.lane(old,n)~=lane then result[#result+1]=old end end
 if c then result[#result+1]=controllers.copy(c) end
 n.controllers=#result>0 and result or nil n.changed=true
end
function controllers.pack(list,shift)
 if not list or #list==0 then return '' end
 local parts={tostring(shift or 0)}
 for _,c in ipairs(list) do parts[#parts+1]=controllers.encode(c) end
 return hex(table.concat(parts,';'))
end
function controllers.unpack(data)
 local raw=unhex(data) if not raw then return nil end
 local f=split(raw,';') local shift=number(f[1],0,1e12,false) if not shift or #f<2 then return nil end
 local result={}
 for i=2,#f do local c=controllers.decode(f[i]) if not c then return nil end result[#result+1]=c end
 return result,shift
end
local function valid(a)
 return a.name and a.name~='' and (a.mode=='ch' or a.mode=='ks' or a.mode=='both')
  and number(a.channel,1,16,true) and number(a.pitch,0,127,true)
  and number(a.velocity,1,127,true) and number(a.lead,-10000,10000,false) and math.abs(a.lead)>=0.01
  and number(a.length,0.01,10000,false) and number(a.kschannel,0,16,true) and controllers.valid(a)
end
local function defaults(name,mode,ch)
 return {name=name,mode=mode,channel=ch,pitch=24,velocity=100,lead=1,length=1,kschannel=0}
end
local articulationGroups={}
function articulationGroups.key(a)
 if not a or (a.mode~='ks' and a.mode~='both') then return nil end
 return table.concat({a.mode,a.mode=='both' and a.channel or 0,a.kschannel,a.pitch},':')..(a.trigger=='end' and ':end' or '')
end
function articulationGroups.multiple(b,a)
 local id=articulationGroups.key(a) if not id then return false end
 local velocity
 for _,other in ipairs(b.arts) do if articulationGroups.key(other)==id then
  if velocity and velocity~=other.velocity then return true end
  velocity=other.velocity
 end end
 return false
end
local function parse(data)
 if data:sub(1,5)=='ABP1:' then data=unhex(data:sub(6)) if not data then return nil end end
 local result,b={},nil
 for line in data:gmatch('[^\r\n]+') do
  local f=split(line,'\t')
  if f[1]=='B' and f[2] and f[2]~='' then b={name=dec(f[2]),arts={},controllers={},default=tonumber(f[3]),ksLengthMode=f[4]=='follow' and 'follow' or 'short',overlap=tonumber(f[5])} result[#result+1]=b
  elseif b and f[1]=='G' and #f==3 and f[2]~='' and f[3]~='' then
   b.groupNames=b.groupNames or {};b.groupNames[dec(f[2])]=dec(f[3])
  elseif b and f[1]=='T' and #f==2 then
   local c=controllers.decode(f[2]) if not c or c.name=='' then return nil end
   b.controllers[#b.controllers+1]=c
  elseif b and (f[1]=='A' or f[1]=='C' or f[1]=='D') then
   local a
   if f[1]=='C' then a=defaults(dec(f[2] or ''),'ch',tonumber(f[3]))
   else a={name=dec(f[2] or ''),mode=f[3],channel=tonumber(f[4]),pitch=tonumber(f[5]),velocity=tonumber(f[6]),lead=tonumber(f[7]),length=tonumber(f[8]),kschannel=tonumber(f[9]) or (f[1]=='A' and tonumber(f[4]) or nil)} end
   for i=10,#f do
    if f[i]=='ending' then a.trigger='end'
    elseif f[i]:sub(1,5)=='ctrl:' then if not controllers.attach(a,f[i]:sub(6)) then return nil end
    else return nil end
   end
   if not valid(a) then return nil end b.arts[#b.arts+1]=a
  else return nil end
 end
 for _,bank in ipairs(result) do
  if bank.overlap and not number(bank.overlap,0,10000,false) then return nil end
  if bank.default and (not number(bank.default,1,#bank.arts,true) or bank.arts[bank.default].mode=='ch' or bank.arts[bank.default].trigger=='end') then return nil end
 end
 return #result>0 and result or nil
end
local function serialize(collection)
 local lines={}
 for _,b in ipairs(collection or banks) do
  lines[#lines+1]='B\t'..enc(b.name)..((b.default or b.ksLengthMode or b.overlap) and table.concat({'',b.default or '',b.ksLengthMode or 'short',b.overlap or 0},'\t') or '')
  for _,a in ipairs(b.arts) do
   local line=table.concat({'D',enc(a.name),a.mode,a.channel,a.pitch,a.velocity,a.lead,a.length,a.kschannel},'\t')
   if controllers.enabled(a) then line=line..'\tctrl:'..controllers.encode(a) end
   if a.trigger=='end' then line=line..'\tending' end
   lines[#lines+1]=line
  end
  for _,c in ipairs(b.controllers or {}) do lines[#lines+1]='T\t'..controllers.encode(c) end
  local ids={} for id in pairs(b.groupNames or {}) do ids[#ids+1]=id end table.sort(ids)
  for _,id in ipairs(ids) do lines[#lines+1]='G\t'..enc(id)..'\t'..enc(b.groupNames[id]) end
 end
 return table.concat(lines,'\n')
end
local presetPath=R.GetResourcePath and (R.GetResourcePath()..'/Scripts/ArticulationBox/Banks.txt') or nil
local function readPresetFile(path)
 local file=path and io.open(path,'r') if not file then return nil end
 local data=file:read('*a') file:close() return parse(data)
end
local savedPresets=R.GetExtState(SECTION,'banks')
local presets=(savedPresets=='ABP1:' and {} or parse(savedPresets)) or readPresetFile(presetPath) or readPresetFile(presetPath and presetPath..'.bak') or parse(R.GetExtState('ArticulationBanks_Channels_v3','banks')) or parse(R.GetExtState('ArticulationBanks_v1','banks')) or {}
local function persistPresets()
 local data=serialize(presets)
 R.SetExtState(SECTION,'banks','ABP1:'..hex(data),true)
 if presetPath then
  if R.RecursiveCreateDirectory then R.RecursiveCreateDirectory(presetPath:match('^(.*)/'),0) end
  local previous=io.open(presetPath,'r')
  if previous then
   local old=previous:read('*a') previous:close()
   if old~=data and parse(old) then local backup=io.open(presetPath..'.bak','w') if backup then backup:write(old) backup:close() end end
  end
  local file=io.open(presetPath..'.tmp','w')
  if file then file:write(data) file:close() os.rename(presetPath..'.tmp',presetPath) end
 end
end
local legacyIndex=math.min(#presets,math.max(1,tonumber(R.GetExtState(SECTION,'bank')) or 1))
-- Migrate the formerly bank-local playback preferences once into common settings.
if R.GetExtState(SECTION,'commonPlaybackSettings')~='1' then
 local old=presets[legacyIndex] or {}
 if R.GetExtState(SECTION,'ksLengthMode')=='' then R.SetExtState(SECTION,'ksLengthMode',old.ksLengthMode or 'short',true) end
 if R.GetExtState(SECTION,'ksOverlap')=='' then R.SetExtState(SECTION,'ksOverlap',tostring(old.overlap or 0),true) end
 R.SetExtState(SECTION,'commonPlaybackSettings','1',true)
end
R.SetExtState(SECTION,'ksLengthMode','follow',true)
if #presets>0 then persistPresets() end
local trackBankKey,trackIndexKey='P_EXT:ABART_BANKS','P_EXT:ABART_BANK_INDEX'
local bankTrack,loadedBankData,loadedBankIndex,bankReady=nil,nil,nil,false
local function newTrackBanks()
 local result={{name='Empty bank',arts={}}}
 for _,b in ipairs(parse(serialize(presets)) or {}) do
  if b.name~='Empty bank' then result[#result+1]=b end
 end
 return result
end
local function mergePresets()
 local names={} for _,b in ipairs(banks) do names[b.name]=true end
 for _,b in ipairs(parse(serialize(presets)) or {}) do
  if not names[b.name] and b.name~='Empty bank' then banks[#banks+1]=b names[b.name]=true end
 end
end
local function loadTrackBanks()
 -- Compatibility for environments without REAPER's native track API.
 if not R.GetMediaItem_Track or not R.GetSetMediaTrackInfo_String then
  if not bankReady then banks=parse(serialize(presets)) or newTrackBanks() bankIndex=1 bankReady=true end
  return
 end
 local editor=R.MIDIEditor_GetActive() local take=editor and R.MIDIEditor_GetTake(editor)
 take=take or controllers.editorTake()
 local track=take and isMidiTake(take) and R.GetMediaItem_Track(R.GetMediaItemTake_Item(take)) or nil
 local data,index='',''
 if track then
  local ok,value=R.GetSetMediaTrackInfo_String(track,trackBankKey,'',false) if ok then data=value end
  ok,value=R.GetSetMediaTrackInfo_String(track,trackIndexKey,'',false) if ok then index=value end
 end
 if bankReady and track==bankTrack and data==loadedBankData and index==loadedBankIndex then return end
 banks=parse(data) or newTrackBanks()
 mergePresets()
 bankIndex=number(index,1,#banks,true) or 1
 bankTrack=track loadedBankData=data loadedBankIndex=index bankReady=true
end
local function save(updatePresets)
 local data=serialize()
 if bankTrack then
  local stored='ABP1:'..hex(data)
  assert(R.GetSetMediaTrackInfo_String(bankTrack,trackBankKey,stored,true),'Could not save track banks')
  assert(R.GetSetMediaTrackInfo_String(bankTrack,trackIndexKey,tostring(bankIndex),true),'Could not save track bank choice')
  loadedBankData=stored loadedBankIndex=tostring(bankIndex)
  if R.MarkProjectDirty then R.MarkProjectDirty(0) end
 end
 -- Saved presets are reusable templates; every track gets an independent copy.
 local b=bankIndex and (parse(data) or {})[bankIndex]
 if updatePresets~=false and b and b.name~='Empty bank' then
  local found=false
  for i,existing in ipairs(presets) do if existing.name==b.name then presets[i]=b found=true break end end
  if not found then presets[#presets+1]=b end
 end
 persistPresets()
end
local function bank() loadTrackBanks() return banks[bankIndex] end
loadTrackBanks()
local function payload(a)
 local values={a.mode,a.base,a.channel,a.pitch,a.velocity,a.lead,a.length,a.kschannel,hex(a.bank),hex(a.name)}
 if (a.shift and a.shift>0) or a.implicit then values[#values+1]=a.shift or 0 end
 if a.implicit then values[#values+1]='default' end
 if controllers.enabled(a) then values[#values+1]='ctrl:'..controllers.encode(a) end
 return hex(table.concat(values,'|'))
end
local function assignment(s)
 local raw=unhex(s) if not raw then return nil end
 local f=split(raw,'|')
 local a={mode=f[1],base=tonumber(f[2]),channel=tonumber(f[3]),pitch=tonumber(f[4]),velocity=tonumber(f[5]),lead=tonumber(f[6]),length=tonumber(f[7]),kschannel=tonumber(f[8]),bank=unhex(f[9] or ''),name=unhex(f[10] or '')}
 if f[#f] and f[#f]:sub(1,5)=='ctrl:' then
  if not controllers.attach(a,table.remove(f):sub(6)) then return nil end
 end
 if #f>=11 then a.shift=number(f[11],0,1e12,false) if not a.shift then return nil end end
 if #f==12 then if f[12]~='default' then return nil end a.implicit=true end
 if (#f~=10 and #f~=11 and #f~=12) or not valid(a) or not number(a.base,0,15,true) or not a.bank then return nil end
 return a
end
-- REAPER supports one hidden 'user' value on NOTE notation. Preserve any
-- existing plugin's user value and append our namespaced suffix inside it.
local function userValue(tail)
 local first,last=tail:find('%suser%s+')
 if not first then return nil end
 local begin=last+1 local q=tail:sub(begin,begin)
 if q=='"' or q=="'" or q=='`' then
  local finish=tail:find(q,begin+1,true) if not finish then error('Unclosed user field in MIDI notation.') end
  return tail:sub(begin+1,finish-1),first,finish
 end
 local finish=(tail:find('%s',begin) or (#tail+1))-1
 return tail:sub(begin,finish),first,finish
end
local function quoted(value)
 if not value:find('%s') and not value:find('"',1,true) and not value:find("'",1,true) and not value:find('`',1,true) then return value end
 for _,q in ipairs({'"',"'",'`'}) do if not value:find(q,1,true) then return q..value..q end end
 error('Cannot safely write a user field containing all three quote types.')
end
local function setUser(tail,value)
 local _,first,last=userValue(tail)
 local field=value and value~='' and (' user '..quoted(value)) or ''
 if first then return tail:sub(1,first-1)..field..tail:sub(last+1) end
 return tail..field
end
local function extractUserMarker(tail,prefix)
 local user=userValue(tail) if not user then return nil,tail end
 local first,last,marker=user:find('^'..prefix..':(%x+)')
 if first and (last==#user or user:sub(last+1,last+1)=='~') then
  return marker,setUser(tail,user:sub(last+1):gsub('^~',''))
 end
 first,last,marker=user:find('~'..prefix..':(%x+)')
 if first and (last==#user or user:sub(last+1,last+1)=='~') then
  return marker,setUser(tail,user:sub(1,first-1)..user:sub(last+1))
 end
 return nil,tail
end
local function extractMarker(tail) return extractUserMarker(tail,ART) end
local function appendUserMarker(tail,prefix,data)
 local user=userValue(tail)
 return setUser(tail,(user and user~='' and (user..'~') or '')..prefix..':'..data)
end
local function appendMarker(tail,data) return appendUserMarker(tail,ART,data) end
local function key(s,ch,p) return string.format('%.6f:%d:%d',s,ch,p) end
local function round(v) return math.floor(v+0.5) end
-- Existing positive lead values mean Before; negative values encode After.
-- Keep the bank/notation format compatible with all existing positive timings.
local function afterSwitchStart(take,start,lead)
 local time=R.MIDI_GetProjTimeFromPPQPos(take,start)
 return math.max(math.floor(start)+1,round(R.MIDI_GetPPQPosFromProjTime(take,time-lead/1000)))
end
local function switchFits(take,a,start,switchStart)
 if a.lead<0 then return math.abs(switchStart-afterSwitchStart(take,start,a.lead))<0.5 end
 local time=R.MIDI_GetProjTimeFromPPQPos(take,start)
 local earliest=math.floor(R.MIDI_GetPPQPosFromProjTime(take,time-a.lead/1000))-1
 return switchStart>=earliest and switchStart<start
end
local function activeTake()
 local editor=R.MIDIEditor_GetActive() local take=editor and R.MIDIEditor_GetTake(editor)
 take=take or controllers.editorTake()
 if not take or not isMidiTake(take) then status='Open the MIDI editor.' return end
 return take,editor
end
local function keyswitchRows()
 local rows={}
 for _,a in ipairs(bank().arts) do if a.mode~='ch' then
  local first,last=0,15
  if a.kschannel~=0 then first=a.kschannel-1 last=first
  elseif a.mode=='both' then first=a.channel-1 last=first end
  for ch=first,last do rows[ch..':'..a.pitch]=true end
 end end
 return rows
end
function controllers.forNote(n)
 local list,lanes={},{}
 local a=n.effective or n.a
 if controllers.enabled(a) then list[1]=a lanes[controllers.lane(a,n)]=1 end
 if controllers.enabled(n.ending) then
  local lane=controllers.lane(n.ending,n);local index=lanes[lane]
  if index then list[index]=n.ending else list[#list+1]=n.ending lanes[lane]=#list end
 end
 for _,c in ipairs(n.controllers or {}) do
  local lane=controllers.lane(c,n) local index=lanes[lane]
  if index then list[index]=c else list[#list+1]=c lanes[lane]=#list end
 end
 return list
end
function controllers.needsLead(n)
 for _,c in ipairs(controllers.forNote(n)) do if c.ctrlTiming~='end' then return true end end
 return false
end
function controllers.eventKey(pos,status,ch,d1,d2)
 return string.format('%.6f:%d:%d:%d:%d',pos,status,ch,d1,d2)
end
function controllers.read(take,scene)
 scene.ccs={} scene.controlTexts={}
 if not R.MIDI_GetCC then return end
 local ok,_,count,texts=R.MIDI_CountEvts(take) if not ok then error('Could not read controllers.') end
 local available={}
 for i=0,count-1 do
  local yes,sel,mute,pos,msg,ch,d1,d2=R.MIDI_GetCC(take,i)
  if yes then
   local c={idx=i,sel=sel,mute=mute,s=pos,status=msg,ch=ch,d1=d1,d2=d2}
   c.key=controllers.eventKey(pos,msg,ch,d1,d2)
   scene.ccs[#scene.ccs+1]=c available[c.key]=available[c.key] or {} table.insert(available[c.key],c)
  end
 end
 for i=0,texts-1 do
  local yes,_,_,pos,typ,msg=R.MIDI_GetTextSysexEvt(take,i)
  if yes and typ==15 then
   local status,ch,d1,d2=msg:match('^ABCC1:(%d+):(%d+):(%d+):(%d+)$')
   if status then
    status,ch,d1,d2=tonumber(status),tonumber(ch),tonumber(d1),tonumber(d2)
    if (status==176 or status==224) and ch<=15 and d1<=127 and d2<=127 then
     scene.controlTexts[#scene.controlTexts+1]=i
     local matches=available[controllers.eventKey(pos,status,ch,d1,d2)] or {}
     for _,c in ipairs(matches) do if not c.owned then c.owned=true break end end
    end
   end
  end
 end
end
function controllers.plan(take,scene)
 local item=R.GetMediaItemTake_Item(take)
 local left=math.ceil(R.MIDI_GetPPQPosFromProjTime(take,R.GetMediaItemInfo_Value(item,'D_POSITION')))
 local lanes={}
 for _,n in ipairs(scene.notes) do if not n.generated and not n.keyswitchRow and not n.mute then
  for _,c in ipairs(controllers.forNote(n)) do
   local anchor=c.ctrlTiming=='end' and n.e or n.s
   local time=R.MIDI_GetProjTimeFromPPQPos(take,anchor)
   local desired=round(R.MIDI_GetPPQPosFromProjTime(take,time-c.ctrlLead/1000))
   local start
   if c.ctrlTiming=='end' then start=math.max(math.ceil(n.s),math.min(math.floor(n.e)-1,desired))
   else start=math.max(left,math.min(math.floor(n.s)-1,desired)) end
   if start>=anchor then error('Not enough room for the controller before the note boundary.') end
   local release=c.ctrlTiming=='start' and n.s or n.e
   local ending=math.max(math.floor(release)+1,round(R.MIDI_GetPPQPosFromProjTime(take,R.MIDI_GetProjTimeFromPPQPos(take,release)+c.ctrlTail/1000)))
   local lane=controllers.lane(c,n)
   lanes[lane]=lanes[lane] or {}
   lanes[lane][#lanes[lane]+1]={s=start,e=ending,c=c,ch=c.ctrlChannel==0 and n.ch or c.ctrlChannel-1}
  end
 end end
 local events,seen={},{}
 local function emit(segment,pos,value)
  local c=segment.c local status,d1,d2=176,c.ctrlCC,value
  if c.ctrl=='pitch' then local unsigned=value+8192 status=224 d1=unsigned&127 d2=unsigned>>7 end
  local id=controllers.eventKey(pos,status,segment.ch,d1,d2)
  local location=string.format('%.6f:%d:%d:%d',pos,status,segment.ch,c.ctrl=='cc' and c.ctrlCC or -1)
  if seen[location] then
   if seen[location]~=id then error('Different controller values share one channel and time. Use separate MIDI channels.') end
   return
  end
  seen[location]=id
  for _,existing in ipairs(scene.ccs or {}) do if not existing.owned and existing.s==pos and existing.status==status and existing.ch==segment.ch and (status==224 or existing.d1==d1) then
   if existing.d1==d1 and existing.d2==d2 and not existing.mute then return end
   error('A manual controller event already occupies this position. Move it or use another MIDI channel.')
  end end
  events[#events+1]={s=pos,status=status,ch=segment.ch,d1=d1,d2=d2,key=id}
 end
 for _,segments in pairs(lanes) do
  table.sort(segments,function(a,b) return a.s<b.s end)
  local merged={}
  for _,segment in ipairs(segments) do
   local prior=merged[#merged]
   if prior and prior.s==segment.s then
    if prior.c.ctrlValue~=segment.c.ctrlValue or prior.c.ctrlReset~=segment.c.ctrlReset then error('Different controllers share one channel and note boundary.') end
    prior.e=math.max(prior.e,segment.e)
   else merged[#merged+1]=segment end
  end
  for i,segment in ipairs(merged) do
   emit(segment,segment.s,segment.c.ctrlValue)
   local following=merged[i+1]
   if not following or following.s>segment.e then emit(segment,segment.e,segment.c.ctrlReset) end
  end
 end
 table.sort(events,function(a,b) if a.s~=b.s then return a.s<b.s end return a.key<b.key end)
 scene.controlRight=nil
 for _,event in ipairs(events) do scene.controlRight=math.max(scene.controlRight or 0,event.s+1) end
 return events
end
function controllers.match(scene,events)
 local actual,expected={},{}
 for _,c in ipairs(scene.ccs or {}) do if c.owned then actual[#actual+1]=c.key..':'..tostring(c.mute) end end
 for _,c in ipairs(events or {}) do expected[#expected+1]=c.key..':false' end
 table.sort(actual) table.sort(expected) return table.concat(actual,'\n')==table.concat(expected,'\n')
end
local function read(take)
 local ok,count,_,textCount=R.MIDI_CountEvts(take) if not ok then error('Could not read MIDI.') end
 local scene={take=take,notes={},texts={},bykey={},groups={},generated={}}
 for i=0,count-1 do
  local yes,sel,mute,s,e,ch,p,v=R.MIDI_GetNote(take,i)
  if yes then
   local n={idx=i,sel=sel,mute=mute,s=s,e=e,ch=ch,p=p,v=v,key=key(s,ch,p),extras=''}
   scene.notes[#scene.notes+1]=n
   scene.bykey[n.key]=scene.bykey[n.key] or {} table.insert(scene.bykey[n.key],n)
  end
 end
 for i=0,textCount-1 do
  local yes,sel,mute,pos,typ,msg=R.MIDI_GetTextSysexEvt(take,i)
  if yes and typ==15 then
   local ch,p,tail=msg:match('^NOTE (%d+) (%d+)(.*)$')
   if ch then
    local t={idx=i,sel=sel,mute=mute,pos=pos,ch=tonumber(ch),p=tonumber(p),tail=tail,msg=msg}
    t.key=key(pos,t.ch,t.p) scene.texts[#scene.texts+1]=t
    local marker,extras=extractMarker(tail)
    local controlMarker controlMarker,extras=extractUserMarker(extras,controllers.prefix)
    local endingMarker endingMarker,extras=extractUserMarker(extras,'ABEND1')
    t.ownedKS=userValue(tail)==KS..':1'
    t.manualKS=userValue(tail)==KS..':manual'
    t.managed=marker~=nil or controlMarker~=nil or endingMarker~=nil or t.ownedKS
    local matches=scene.bykey[t.key] or {}
    if t.managed and #matches>1 then error('Overlapping duplicate notes on one channel: separate them before assigning an articulation.') end
    if #matches==1 then
     local n=matches[1]
     if t.ownedKS then n.generated=true scene.generated[n.idx]=true
     else
      n.manualKS=t.manualKS or n.manualKS
      n.extras=n.extras..extras
      if marker then
       if n.a then error('This note has two assignment markers. Undo the last change.') end
       n.a=assignment(marker) if not n.a then error('Invalid articulation marker.') end
      end
      if endingMarker then
       n.ending=assignment(endingMarker) if not n.ending then error('Invalid ending marker.') end
      end
      if controlMarker then
       if n.controllers then error('This note has two controller assignment markers.') end
       n.controllers,n.controllerShift=controllers.unpack(controlMarker)
       if not n.controllers then error('Invalid controller assignment marker.') end
      end
     end
    end
   end
  end
 end
 local rows=keyswitchRows()
 scene.switches={}
 for _,n in ipairs(scene.notes) do if n.generated then
  local id=n.ch..':'..n.p..':'..n.v
  scene.switches[id]=scene.switches[id] or {} table.insert(scene.switches[id],n)
 end end
 for _,list in pairs(scene.switches) do table.sort(list,function(a,b) return a.s<b.s end) end
 for _,n in ipairs(scene.notes) do n.keyswitchRow=not n.generated and (n.manualKS or rows[n.ch..':'..n.p]) or false end
 -- Untagged notes on mapped rows are manual switches. Their last note-on wins
 -- until an explicit automatic assignment is encountered on that channel.
 local controls,explicit={},{}
 local currentBank=bank()
 local hasDefault=currentBank.default and currentBank.arts[currentBank.default] and currentBank.arts[currentBank.default].mode~='ch'
 for _,n in ipairs(scene.notes) do
  if n.keyswitchRow and not n.mute then
   local a,fallback,velocities,names=nil,nil,{},{nameList={},seen={}}
   for _,mapped in ipairs(currentBank.arts) do
    local ch=mapped.kschannel==0 and (mapped.mode=='both' and mapped.channel-1 or n.ch) or mapped.kschannel-1
    if mapped.mode~='ch' and mapped.pitch==n.p and ch==n.ch then
     fallback=fallback or mapped velocities[mapped.velocity]=true
     if not names.seen[mapped.name] then names.seen[mapped.name]=true names.nameList[#names.nameList+1]=mapped.name end
     if mapped.velocity==n.v then a={bank=currentBank.name} for k,v in pairs(mapped) do a[k]=v end break end
    end
   end
   if not a and fallback then
    local variants=0 for _ in pairs(velocities) do variants=variants+1 end
    a={bank=currentBank.name} for k,v in pairs(fallback) do a[k]=v end
    if variants>1 then
     a.name=((currentBank.groupNames or {})[articulationGroups.key(fallback)] or table.concat(names.nameList,' / '))..' [Vel '..n.v..']'
    end
   end
   if a then a.velocity=n.v end
   a=a or {bank=currentBank.name,name='KS '..n.p,mode='ks',channel=n.ch+1,pitch=n.p,velocity=n.v,lead=1,length=1,kschannel=n.ch+1}
   controls[n.ch]=controls[n.ch] or {} controls[n.ch][#controls[n.ch]+1]={s=n.s,e=n.e,a=a}
  elseif not n.generated and n.a and not n.a.implicit and n.a.mode~='ch' and not n.mute then
   local ch=n.a.kschannel==0 and n.ch or n.a.kschannel-1
   explicit[ch]=explicit[ch] or {} explicit[ch][#explicit[ch]+1]=n.a.lead<0 and afterSwitchStart(take,n.s,n.a.lead) or n.s
  end
 end
 for _,list in pairs(controls) do table.sort(list,function(a,b) return a.s<b.s end) end
 for _,list in pairs(explicit) do table.sort(list) end
 local function lastBefore(list,pos,strict,events)
  local lo,hi=1,#list local found
  while lo<=hi do local mid=(lo+hi)//2 local value=events and list[mid].s or list[mid]
   if value<pos or (not strict and value==pos) then found=list[mid] lo=mid+1 else hi=mid-1 end
  end
  return found
 end
 for _,n in ipairs(scene.notes) do if not n.generated and not n.keyswitchRow then
  local ch=n.a and n.a.mode~='ch' and n.a.kschannel~=0 and n.a.kschannel-1 or n.ch
  local latest=lastBefore(controls[ch] or {},n.s,false,true)
  local reset=lastBefore(explicit[ch] or {},n.s,true,false)
  -- With a default, a manual switch covers its drawn region, rather than
  -- suppressing defaults for every later note on that MIDI channel.
  if latest and hasDefault and n.s>=latest.e then latest=nil end
  if hasDefault then
   for _,ev in ipairs(controls[ch] or {}) do
    if ev.a.lead<0 and ev.s>n.s and ev.s<n.e and switchFits(take,ev.a,n.s,ev.s) and (not latest or ev.s>latest.s) then latest=ev end
   end
  end
  if latest and (not reset or latest.s>reset) then
   n.manualSignal=latest.a
   if not n.a or n.a.implicit then n.manualArt=latest.a end
  end
 end end
 controllers.read(take,scene)
 return scene
end
local function config(a)
 local result=table.concat({a.mode,a.channel,a.pitch,a.velocity,a.lead,a.length,a.kschannel},':')
 local control=controllers.config(a) return control~='' and (result..':ctrl:'..control) or result
end
-- Per-track ownership preserves prior names independently for every channel.
local rowNameTrack,rowNameSignature=nil,nil
local rowNameKey='P_EXT:ABART_ROW_NAMES'
local function rowNamesUpdate(destinationTrack,destinationBank)
 if not R.GetMediaItem_Track or not R.SetTrackMIDINoteNameEx or not R.GetTrackMIDINoteNameEx or not R.GetSetMediaTrackInfo_String then return end
 local track=destinationTrack
 if not track then
  local editor=R.MIDIEditor_GetActive() local take=editor and R.MIDIEditor_GetTake(editor)
  if not take or not isMidiTake(take) then return end
  track=R.GetMediaItem_Track(R.GetMediaItemTake_Item(take))
  loadTrackBanks()
 end
 local current=destinationBank or bank()
 local enabled=R.GetExtState(SECTION,'nameKeyswitchRows')~='0'
 local signature=tostring(enabled)..':'..serialize({current})
 if track==rowNameTrack and signature==rowNameSignature then return end
 local _,stored=R.GetSetMediaTrackInfo_String(track,rowNameKey,'',false)
 local owned={}
 for line in (stored or ''):gmatch('[^\r\n]+') do
  local f=split(line,'\t') local pitch=number(f[1],0,127,true) local channel=number(f[2],0,15,true)
  if pitch and channel and f[3] and f[4] then owned[pitch..':'..channel]={pitch=pitch,channel=channel,previous=dec(f[3]),applied=dec(f[4])} end
 end
 local wanted={}
 if enabled then for _,a in ipairs(current.arts) do if a.mode~='ch' then
  local first,last=0,15
  if a.kschannel~=0 then first=a.kschannel-1 last=first
  elseif a.mode=='both' then first=a.channel-1 last=first end
  for ch=first,last do
   local id=a.pitch..':'..ch
   if not wanted[id] then wanted[id]={pitch=a.pitch,channel=ch,names={},seen={}} end
   local row=wanted[id] if not row.seen[a.name] then row.names[#row.names+1]=a.name row.seen[a.name]=true end
  end
 end end end
 local changed=false
 for id,record in pairs(owned) do if not wanted[id] then
  local current=R.GetTrackMIDINoteNameEx(0,track,record.pitch,record.channel) or ''
  if current==record.applied then R.SetTrackMIDINoteNameEx(0,track,record.pitch,record.channel,record.previous) changed=true end
  owned[id]=nil
 end end
 for id,row in pairs(wanted) do
  local desired=table.concat(row.names,' / ')
  local current=R.GetTrackMIDINoteNameEx(0,track,row.pitch,row.channel) or ''
  local record=owned[id]
  if not record then record={pitch=row.pitch,channel=row.channel,previous=current} owned[id]=record
  elseif current~=record.applied then record.previous=current end
  record.applied=desired
  if current~=desired then R.SetTrackMIDINoteNameEx(0,track,row.pitch,row.channel,desired) changed=true end
 end
 local lines={} for _,record in pairs(owned) do
  lines[#lines+1]=table.concat({record.pitch,record.channel,enc(record.previous),enc(record.applied)},'\t')
 end table.sort(lines)
 local serialized=table.concat(lines,'\n')
 if serialized~=(stored or '') then R.GetSetMediaTrackInfo_String(track,rowNameKey,serialized,true) changed=true end
 if changed then
  if R.MarkProjectDirty then R.MarkProjectDirty(0) end
  if R.UpdateArrange then R.UpdateArrange() end
 end
 rowNameTrack=track rowNameSignature=signature
end
local function toggleRowNames()
 local enabled=R.GetExtState(SECTION,'nameKeyswitchRows')~='0'
 R.SetExtState(SECTION,'nameKeyswitchRows',enabled and '0' or '1',true)
 rowNameSignature=nil rowNamesUpdate()
end

local function defaultArt()
 local b=bank() local a=b.default and b.arts[b.default]
 return a and a.mode~='ch' and a.trigger~='end' and a or nil
end
-- Every unassigned musical note uses the default, including members of a
-- partially assigned chord. Keep this virtual so changing the bank's default
-- does not turn implicit choices into permanent per-note overrides.
local function prepareDefaults(take,scene)
 local default=defaultArt()
 local ordered={}
 for _,n in ipairs(scene.notes) do
  n.effective=not n.keyswitchRow and (n.manualArt or n.a or (not n.generated and default or nil)) or nil
  n.skipDefaultSwitch=nil
  if not n.generated and not n.keyswitchRow and not n.mute then ordered[#ordered+1]=n end
 end
 if not default then return end
 local item=R.GetMediaItemTake_Item(take)
 local left=math.ceil(R.MIDI_GetPPQPosFromProjTime(take,R.GetMediaItemInfo_Value(item,'D_POSITION')))
 local defaultChoice=config(default)
 table.sort(ordered,function(a,b) if a.ch~=b.ch then return a.ch<b.ch end if a.s~=b.s then return a.s<b.s end return a.idx<b.idx end)
 local overridden={} local i=1
 while i<=#ordered do
  local first=ordered[i] local j=i
  while j<=#ordered and ordered[j].ch==first.ch and ordered[j].s==first.s do j=j+1 end
  local changes,restores=false,false
  for k=i,j-1 do local a=ordered[k].a
   if a and a.mode~='ch' then
    if config(a)==defaultChoice then restores=true else changes=true end
   end
  end
  for k=i,j-1 do local n=ordered[k]
   if not n.a then
    -- Defaults take part in conflict detection even when a redundant restore
    -- pulse can be skipped. Staggering then rebuilds these groups at new starts.
    n.skipDefaultSwitch=not changes and not overridden[n.ch] and
     (overridden[n.ch]~=nil or math.floor(n.s)<=left)
    restores=true
   end
  end
  if changes then overridden[first.ch]=true elseif restores then overridden[first.ch]=false end
  i=j
 end
end

-- Optional workaround: move only the newly assigned selected chord group.
-- Ends stay fixed: delayed notes get shorter, never extending into the next note.
-- Existing/unselected voices stay fixed. A failed plan never writes the move.
local function staggerConflicts(take,scene,includeExisting)
 if R.GetExtState(SECTION,'autoStagger')~='1' then return 0 end
 local delay=number(R.GetExtState(SECTION,'staggerMs'),0.1,50,false) or 2
 local groups,order,choices={},{},{}
 for _,n in ipairs(scene.notes) do if not n.generated and not n.mute and n.effective and n.effective.lead>=0 then
  local id=key(n.s,n.ch,0) local choice=config(n.effective)
  local existing=choices[id]
  if not existing then choices[id]={first=choice}
  elseif existing.first~=choice then existing.mixed=true end
 end end
 for _,n in ipairs(scene.notes) do
  if not n.generated and not n.mute and ((n.sel and n.changed) or includeExisting) and n.a and n.a.mode~='ch' and n.a.lead>=0 then
   local id=key(n.s,n.ch,0)..':'..config(n.a)
   if not groups[id] then groups[id]={s=n.s,ch=n.ch,choice=config(n.a),notes={},members={}} order[#order+1]=groups[id] end
   local g=groups[id] g.notes[#g.notes+1]=n g.members[n]=true
  end
 end
 local default=defaultArt() local defaultChoice=default and config(default)
 table.sort(order,function(a,b)
  if a.s~=b.s then return a.s<b.s end
  if a.ch~=b.ch then return a.ch<b.ch end
  if (a.choice==defaultChoice)~=(b.choice==defaultChoice) then return b.choice==defaultChoice end
  return a.choice<b.choice
 end)
 local moved=0
 for _,g in ipairs(order) do
  local at=choices[key(g.s,g.ch,0)]
  local conflict=at and (at.mixed or at.first~=g.choice)
  if conflict then
   local time=R.MIDI_GetProjTimeFromPPQPos(take,g.s)
   local candidate=math.max(math.floor(g.s)+2,round(R.MIDI_GetPPQPosFromProjTime(take,time+delay/1000)))
   -- Leave one keyswitch tick between note starts, including nearby notes
   -- that would otherwise become the preceding onset after this move.
   for attempt=1,#scene.notes+1 do
    local nextCandidate=candidate
    for _,n in ipairs(scene.notes) do
     if not g.members[n] and not n.generated and not n.mute and n.ch==g.ch then
      if n.s<=candidate and candidate-math.floor(n.s)<2 then nextCandidate=math.max(nextCandidate,math.floor(n.s)+2)
      elseif n.effective and n.effective.mode~='ch' and n.s>candidate and math.floor(n.s)-candidate<2 then nextCandidate=math.max(nextCandidate,math.floor(n.s)+2) end
     end
    end
    if nextCandidate==candidate then break end
    candidate=nextCandidate
   end
   if R.MIDI_GetProjTimeFromPPQPos(take,candidate)-time>0.050001 then error('Auto-stagger would exceed 50 ms. Use separate channels or move the notes manually.') end
   local offset=candidate-g.s
   for _,n in ipairs(g.notes) do
    if n.e-candidate<1 then error('A selected note is too short for auto-stagger. Reduce the spacing or use separate channels. No notes were changed.') end
   end
   for _,n in ipairs(g.notes) do
    n.olds=n.olds or n.s n.olde=n.olde or n.e n.s=n.s+offset n.a.shift=(n.a.shift or 0)+offset n.changed=true moved=moved+1
   end
  end
 end
 return moved
end

local function keyswitchLengthSettings(a)
 return 'follow',number(R.GetExtState(SECTION,'ksOverlap'),0,10000,false) or 0
end
-- Give an explicitly assigned onset at the item boundary a preceding MIDI tick.
-- Store the offset just like staggering; preserve the original musical end.
local function ensureBoundaryRoom(take,scene)
 local item=R.GetMediaItemTake_Item(take)
 local left=math.ceil(R.MIDI_GetPPQPosFromProjTime(take,R.GetMediaItemInfo_Value(item,'D_POSITION')))
 local groups,order,starts,near,unassignedLeft={},{},{},{},{}
 for _,n in ipairs(scene.notes) do if not n.generated and not n.mute then
  if not n.a and math.floor(n.s)==left then unassignedLeft[n.ch]=true end
  if not n.keyswitchRow then starts[n.ch]=starts[n.ch] or {} table.insert(starts[n.ch],n.s) end
 end end
 for ch,list in pairs(starts) do
  table.sort(list) near[ch]={} local previous
  for _,pos in ipairs(list) do
   if previous~=pos then near[ch][pos]=previous and math.floor(pos)-math.floor(previous)<2 or false previous=pos end
  end
 end
 for _,n in ipairs(scene.notes) do
  local keyswitch=n.a and n.a.mode~='ch' and n.a.lead>=0
  local controller=controllers.needsLead(n)
  local signal=keyswitch or controller
  local channel=keyswitch and (n.a.kschannel==0 and n.ch or n.a.kschannel-1) or n.ch
  local needsRoom=math.floor(n.s)<=left
  if not needsRoom and signal and math.floor(n.s)==left+1 then
   needsRoom=unassignedLeft[channel] or false
  end
  local closeStart=false
  if R.GetExtState(SECTION,'autoStagger')=='1' and signal then
   closeStart=near[channel] and near[channel][n.s] or false
   -- An explicit KS channel can differ from the musical channel.
   if channel~=n.ch then
    local list=starts[channel] or {} local lo,hi=1,#list local previous
    while lo<=hi do local mid=(lo+hi)//2 if list[mid]<n.s then previous=list[mid] lo=mid+1 else hi=mid-1 end end
    closeStart=previous and math.floor(n.s)-math.floor(previous)<2 or false
   end
  end
  if not n.generated and not n.keyswitchRow and not n.mute and signal and (needsRoom or closeStart) then
   local choice=(n.a and config(n.a) or '')
   if n.controllers and #n.controllers>0 then choice=choice..':ctrl:'..controllers.pack(n.controllers,n.controllerShift) end
   local id=key(n.s,n.ch,0)..':'..choice
   if not groups[id] then
    groups[id]={s=n.s,close=closeStart,notes={},members={},choice=choice,ch=channel}
    order[#order+1]=groups[id]
   end
   local g=groups[id] g.notes[#g.notes+1]=n g.members[n]=true
  end
 end
 local moved=0
 local default=defaultArt() local defaultChoice=default and config(default)
 table.sort(order,function(a,b)
  if (a.choice==defaultChoice)~=(b.choice==defaultChoice) then return a.choice==defaultChoice end
  return a.notes[1].idx<b.notes[1].idx
 end)
 for _,g in ipairs(order) do
  local candidate=math.max(left+1,math.ceil(g.s))
  if g.close then
   local time=R.MIDI_GetProjTimeFromPPQPos(take,g.s)
   local delay=number(R.GetExtState(SECTION,'staggerMs'),0.1,50,false) or 2
   candidate=math.max(candidate,round(R.MIDI_GetPPQPosFromProjTime(take,time+delay/1000)))
  end
  for attempt=1,#scene.notes+1 do
   local nextCandidate=candidate
   for _,other in ipairs(scene.notes) do
    if not g.members[other] and not other.generated and not other.mute and other.ch==g.ch then
     local same=other.s==candidate and other.effective and config(other.effective)==g.choice
     if not same then
      if other.s<=candidate and candidate-math.floor(other.s)<2 then nextCandidate=math.max(nextCandidate,math.floor(other.s)+2)
      elseif other.effective and other.effective.mode~='ch' and other.s>candidate and math.floor(other.s)-candidate<2 then
       nextCandidate=math.max(nextCandidate,config(other.effective)==g.choice and other.s or math.floor(other.s)+2)
      end
     end
    end
   end
   if nextCandidate==candidate then break end candidate=nextCandidate
  end
  if g.close and R.MIDI_GetProjTimeFromPPQPos(take,candidate)-R.MIDI_GetProjTimeFromPPQPos(take,g.s)>0.050001 then error('Auto-stagger would exceed 50 ms. No notes were changed.') end
  for _,n in ipairs(g.notes) do
   if n.e-candidate<1 then error('This note is too short to leave room for a keyswitch at the item start. No notes were changed.') end
  end
  for _,n in ipairs(g.notes) do
   local offset=candidate-n.s
   n.olds=n.olds or n.s n.olde=n.olde or n.e
   n.s=candidate
   if n.a then n.a.shift=(n.a.shift or 0)+offset else n.controllerShift=(n.controllerShift or 0)+offset end
   n.changed=true moved=moved+1
  end
 end
 return moved
end
function articulationGroups.endingPosition(take,n)
 local a=n.ending local finish=math.floor(n.e)
 local start=math.max(math.floor(n.s)+1,math.min(finish-1,round(R.MIDI_GetPPQPosFromProjTime(take,R.MIDI_GetProjTimeFromPPQPos(take,n.e)-math.abs(a.lead)/1000))))
 if start>=finish then error('This note is too short for a keyswitch ending.') end
 return start,finish,a.kschannel==0 and n.ch or a.kschannel-1
end
local function plan(take,scene)
 prepareDefaults(take,scene)
 local events,seen={},{}
 local item=R.GetMediaItemTake_Item(take)
 local left=R.MIDI_GetPPQPosFromProjTime(take,R.GetMediaItemInfo_Value(item,'D_POSITION'))
 -- Gather preceding note starts per receiving channel, including unassigned
 -- musical notes. A new switch must never run before the preceding note starts.
 local starts={}
 local function addStart(ch,pos)
  starts[ch]=starts[ch] or {} starts[ch][#starts[ch]+1]=pos
 end
 for _,n in ipairs(scene.notes) do if not n.generated and not n.keyswitchRow and not n.mute then
  addStart(n.ch,n.s)
  if n.effective and n.effective.mode~='ch' and n.effective.kschannel~=0 and n.effective.kschannel-1~=n.ch then addStart(n.effective.kschannel-1,n.s) end
 end end
 for _,positions in pairs(starts) do table.sort(positions) end
 local function precedingStart(ch,pos)
  local positions=starts[ch] or {} local lo,hi=1,#positions local previous=nil
  while lo<=hi do
   local mid=math.floor((lo+hi)/2)
   if positions[mid]<pos then previous=positions[mid] lo=mid+1 else hi=mid-1 end
  end
  return previous
 end
 local music={}
 for _,n in ipairs(scene.notes) do if not n.generated then
  if n.olds and n.s<left then error('Restoring auto-stagger would move a note before the MIDI item. Extend the item start or adjust the note manually.') end
  local k=key(n.s,n.ch,n.p)
  if music[k] and (n.a or music[k].a) then error('Two musical notes share their start, pitch and channel. Assignment is ambiguous.') end music[k]=n
  if n.effective and not n.mute then
   local a=n.effective
   -- Reject different managed articulations at the same onset on one instrument.
   local conflict=key(n.s,n.ch,0)
   local choice=config(a)
   if a.mode=='ch' or a.lead>=0 then
    if seen[conflict] and seen[conflict]~=choice then error('Different articulations start together on one channel. Use separate channels.') end
    seen[conflict]=choice
   end
   if a.mode~='ch' and not n.skipDefaultSwitch and not n.manualArt and not (a.lead>=0 and n.manualSignal and n.manualSignal.pitch==a.pitch and n.manualSignal.velocity==a.velocity and (a.kschannel==0 or a.kschannel==n.manualSignal.kschannel)) then
    local time=R.MIDI_GetProjTimeFromPPQPos(take,n.s)
    local ch=a.kschannel==0 and n.ch or a.kschannel-1
    local onset=math.floor(n.s)
    local previous=precedingStart(ch,n.s)
    local earliest=math.max(math.ceil(left),previous and (math.floor(previous)+1) or math.ceil(left))
    local desired=round(R.MIDI_GetPPQPosFromProjTime(take,time-a.lead/1000))
    local s
    if a.lead<0 then s=afterSwitchStart(take,n.s,a.lead)
    else
     s=math.max(earliest,math.min(onset-1,desired))
     if s>=onset then error('Not enough space for a keyswitch before this note. Enable Auto-stagger conflicting notes, move the note later, or use a separate channel.',0) end
    end
    local switchTime=R.MIDI_GetProjTimeFromPPQPos(take,s)
    local mode,overlap=keyswitchLengthSettings(a)
    local e
    if mode=='follow' then e=math.max(onset+1,s+1,math.floor(n.e))
    elseif overlap>0 then
     e=math.max(onset+1,round(R.MIDI_GetPPQPosFromProjTime(take,time+overlap/1000)))
    else e=math.min(onset,math.max(s+1,round(R.MIDI_GetPPQPosFromProjTime(take,switchTime+a.length/1000)))) end
    local right=R.MIDI_GetPPQPosFromProjTime(take,R.GetMediaItemInfo_Value(item,'D_POSITION')+R.GetMediaItemInfo_Value(item,'D_LENGTH'))
    e=math.min(e,math.floor(right))
    if e<=s then error('No space in the MIDI item for this keyswitch.') end
    local id=key(s,ch,0)
    local signal=table.concat({a.pitch,a.velocity},':')
    if events[id] and events[id].signal~=signal then error('Conflicting keyswitches on the same channel and position.') end
    if events[id] then e=math.max(e,events[id].e) end
    events[id]={s=s,e=e,ch=ch,p=a.pitch,v=a.velocity,signal=signal}
   end
  end
 end end
 for _,n in ipairs(scene.notes) do if n.ending and not n.generated and not n.keyswitchRow and not n.mute then
  local a=n.ending
  local start,finish,ch=articulationGroups.endingPosition(take,n)
  local id=key(start,ch,0) local signal=a.pitch..':'..a.velocity
  if events[id] and events[id].signal~=signal then error('Conflicting keyswitch endings on one channel.') end
  events[id]={s=start,e=finish,ch=ch,p=a.pitch,v=a.velocity,signal=signal}
 end end
 -- Never overwrite a real musical note, even if it happens to be on a keyswitch pitch.
 local occupancy={}
 for _,n in ipairs(scene.notes) do if not n.generated then
  local id=tostring(n.ch)..':'..n.p occupancy[id]=occupancy[id] or {} table.insert(occupancy[id],n)
 end end
 local ordered={}
 for _,ev in pairs(events) do ordered[#ordered+1]=ev end
 -- Manual and automatic switches share one timeline per receiving channel.
 -- A later note-on ends the earlier switch; never extend or delete a manual note.
 table.sort(ordered,function(a,b) if a.ch~=b.ch then return a.ch<b.ch end if a.s~=b.s then return a.s<b.s end return a.p<b.p end)
 local timeline={}
 for _,ev in ipairs(ordered) do timeline[#timeline+1]={s=ev.s,e=ev.e,ch=ev.ch,event=ev} end
 for _,n in ipairs(scene.notes) do if n.keyswitchRow and not n.mute then
  timeline[#timeline+1]={s=n.s,e=n.e,ch=n.ch,note=n}
 end end
 table.sort(timeline,function(a,b) if a.ch~=b.ch then return a.ch<b.ch end return a.s<b.s end)
 scene.manualEnds={}
 local nextStart,previousStart,previousChannel
 for i=#timeline,1,-1 do
  local entry=timeline[i]
  if entry.ch~=previousChannel then nextStart=nil previousStart=nil
  elseif entry.s~=previousStart then nextStart=previousStart end
  if nextStart and entry.e>nextStart then
   if entry.event then entry.event.e=nextStart
   else scene.manualEnds[entry.note.idx]=nextStart end
  end
  previousStart=entry.s previousChannel=entry.ch
 end
 for _,ev in ipairs(ordered) do
  for _,n in ipairs(occupancy[tostring(ev.ch)..':'..ev.p] or {}) do
   local ending=scene.manualEnds[n.idx] or n.e
   if ev.s<ending and n.s<ev.e then error('A keyswitch overlaps a musical note of the same pitch and channel.') end
  end
 end
 scene.plannedControls=controllers.plan(take,scene)
 return ordered
end
function controllers.writeRaw(take,scene,events,raw)
 if not raw then return false end
 local input={} local offset,pos=1,0
 local valid=pcall(function()
  while offset<=#raw do
   local delta,flags,msg;delta,flags,msg,offset=string.unpack('<i4Bs4',raw,offset)
   pos=pos+delta input[#input+1]={s=pos,flags=flags,msg=msg,order=#input+1,rank=1}
  end
 end)
 if not valid then return false end -- Compatibility with old hosts/test adapters.
 local starts,ends,removeTexts,removeCC={},{},{},{}
 local function add(map,id,n) map[id]=map[id] or {} map[id][#map[id]+1]=n end
 local function textKey(s,msg) return string.format('%.6f',s)..'\0'..msg end
 for _,n in ipairs(scene.notes) do
  local ch=n.oldch or n.ch
  add(starts,key(n.olds or n.s,ch,n.p),n)
  add(ends,key(n.olde or n.e,ch,n.p),n)
 end
 for _,t in ipairs(scene.texts) do
  local n=(scene.bykey[t.key] or {})[1]
  if t.managed or (n and not n.generated and (n.a or n.changed)) then
   add(removeTexts,textKey(t.pos,t.msg),true)
  end
 end
 for _,idx in ipairs(scene.controlTexts or {}) do
  local yes,_,_,s,_,msg=R.MIDI_GetTextSysexEvt(take,idx)
  if yes then add(removeTexts,textKey(s,msg),true) end
 end
 for _,c in ipairs(scene.ccs or {}) do if c.owned then add(removeCC,c.key,true) end end
 local function consume(map,id)
  local list=map[id] if not list or #list==0 then return nil end
  return table.remove(list)
 end
 local output={} local terminal,removedCurveOwner
 for i,ev in ipairs(input) do
  local msg=ev.msg local keep=true
  local status=#msg>0 and msg:byte(1)&0xF0
  if #msg==3 and (status==0x90 or status==0x80) then
   local on=status==0x90 and msg:byte(3)>0
   local n=consume(on and starts or ends,key(ev.s,msg:byte(1)&15,msg:byte(2)))
   -- Imported MIDI may contain unmatched note-ons/offs which the native note
   -- API does not enumerate. Preserve those foreign bytes unchanged.
   keep=not n or not n.generated
   if n and keep then
    ev.s=round(on and n.s or n.e)
    ev.msg=string.char(status|n.ch,n.p,msg:byte(3))
   end
  elseif #msg==3 and (status==0xB0 or status==0xE0) then
   keep=not consume(removeCC,controllers.eventKey(ev.s,status,msg:byte(1)&15,msg:byte(2),msg:byte(3)))
  elseif msg:sub(1,2)==string.char(0xFF,15) then
   keep=not consume(removeTexts,textKey(ev.s,msg:sub(3)))
   if removedCurveOwner and msg:sub(3,7)=='CCBZ ' then keep=false end
  end
  removedCurveOwner=(status==0xB0 or status==0xE0) and not keep
  if keep then
   output[#output+1]=ev
   if i==#input and (#msg==0 or (#msg==3 and status==0xB0 and msg:byte(2)==123 and msg:byte(3)==0)) then terminal=ev end
  end
 end
 for _,map in ipairs({starts,ends}) do for _,list in pairs(map) do assert(#list==0,'A native MIDI note has no matching raw event.') end end
 local function append(s,msg,rank,flags)
  output[#output+1]={s=round(s),flags=flags or 0,msg=msg,rank=rank or 2,order=#input+#output+1}
 end
 for _,ev in ipairs(events) do
  append(ev.s,string.char(0x90|ev.ch,ev.p,ev.v),2)
  append(ev.e,string.char(0x80|ev.ch,ev.p,0),0)
  append(ev.s,string.char(0xFF,15)..'NOTE '..ev.ch..' '..ev.p..' user '..KS..':1',3)
 end
 for _,n in ipairs(scene.notes) do if not n.generated and (n.a or n.ending or n.changed or (n.controllers and #n.controllers>0)) then
  local tail=n.extras
  if n.a then tail=appendMarker(tail,payload(n.a)) end
  if n.ending then tail=appendUserMarker(tail,'ABEND1',payload(n.ending)) end
  local control=controllers.pack(n.controllers,n.controllerShift)
  if control~='' then tail=appendUserMarker(tail,controllers.prefix,control) end
  if tail:find('%S') then append(n.s,string.char(0xFF,15)..'NOTE '..n.ch..' '..n.p..tail,3,n.mute and 2 or 0) end
 end end
 for _,c in ipairs(scene.plannedControls or {}) do
  append(c.s,string.char(c.status|c.ch,c.d1,c.d2),2)
  append(c.s,string.char(0xFF,15)..controllers.eventPrefix..table.concat({c.status,c.ch,c.d1,c.d2},':'),3)
 end
 if terminal then
  for _,ev in ipairs(output) do terminal.s=math.max(terminal.s,ev.s) end terminal.rank=4
 end
 table.sort(output,function(a,b) if a.s~=b.s then return a.s<b.s end if a.rank~=b.rank then return a.rank<b.rank end return a.order<b.order end)
 local packed={} pos=0
 for _,ev in ipairs(output) do packed[#packed+1]=string.pack('<i4Bs4',ev.s-pos,ev.flags,ev.msg) pos=ev.s end
 assert(R.MIDI_SetAllEvts(take,table.concat(packed)),'Could not write the MIDI event buffer.')
 return true
end
local function write(take,scene,events,raw)
 -- One native buffer write avoids thousands of per-event deletes/inserts,
 -- whose cost grows sharply in long items. Keep all foreign event bytes.
 if controllers.writeRaw(take,scene,events,raw) then return end
 -- Keep note/text indexes stable through the ENTIRE edit, including deletes.
 R.MIDI_DisableSort(take)
 -- Rebuild note-notation records only for notes with our assignment or changed channel.
 local textsToDelete={}
 for _,t in ipairs(scene.texts) do
  local matches=scene.bykey[t.key] or {} local n=matches[1]
  if t.managed or (n and not n.generated and (n.a or n.changed)) then textsToDelete[#textsToDelete+1]=t.idx end
 end
 for _,idx in ipairs(scene.controlTexts or {}) do textsToDelete[#textsToDelete+1]=idx end
 table.sort(textsToDelete,function(a,b) return a>b end)
 for _,idx in ipairs(textsToDelete) do if not R.MIDI_DeleteTextSysexEvt(take,idx) then error('MIDI_DeleteTextSysexEvt failed') end end
 -- MIDI_SetNote can relocate native NOTE records even with sorting disabled.
 -- Remove records we will rebuild BEFORE moving their notes, while the saved
 -- text indexes are valid. Text deletion leaves the note indexes unchanged.
 for _,n in ipairs(scene.notes) do if not n.generated and ((n.oldch and n.ch~=n.oldch) or n.olds) then
  if not R.MIDI_SetNote(take,n.idx,nil,nil,n.olds and n.s or nil,n.olde and n.e or nil,n.ch,nil,nil,true) then error('MIDI_SetNote failed') end
 end end
 local generated={} for idx in pairs(scene.generated) do generated[#generated+1]=idx end
 table.sort(generated,function(a,b) return a>b end)
 for _,idx in ipairs(generated) do if not R.MIDI_DeleteNote(take,idx) then error('MIDI_DeleteNote failed') end end
 for _,ev in ipairs(events) do
  if not R.MIDI_InsertNote(take,false,false,ev.s,ev.e,ev.ch,ev.p,ev.v,true) then error('MIDI_InsertNote failed') end
 end
 -- Finish all note edits before attaching NOTE records to their final onsets.
 R.MIDI_Sort(take)
 for _,n in ipairs(scene.notes) do if not n.generated and (n.a or n.ending or n.changed or (n.controllers and #n.controllers>0)) then
  local tail=n.extras
  if n.a then tail=appendMarker(tail,payload(n.a)) end
  if n.ending then tail=appendUserMarker(tail,'ABEND1',payload(n.ending)) end
  local control=controllers.pack(n.controllers,n.controllerShift)
  if control~='' then tail=appendUserMarker(tail,controllers.prefix,control) end
  if tail:find('%S') then
   if not R.MIDI_InsertTextSysexEvt(take,false,n.mute,n.s,15,'NOTE '..n.ch..' '..n.p..tail) then error('MIDI_InsertTextSysexEvt failed') end
  end
 end end
 for _,ev in ipairs(events) do
  if not R.MIDI_InsertTextSysexEvt(take,false,false,ev.s,15,'NOTE '..ev.ch..' '..ev.p..' user '..KS..':1') then error('Keyswitch marker failed') end
 end
 local remove={}
 for _,c in ipairs(scene.ccs or {}) do if c.owned then remove[#remove+1]=c.idx end end
 table.sort(remove,function(a,b) return a>b end)
 R.MIDI_DisableSort(take)
 for _,idx in ipairs(remove) do assert(R.MIDI_DeleteCC(take,idx),'Could not replace the owned controller event.') end
 for _,c in ipairs(scene.plannedControls or {}) do
  assert(R.MIDI_InsertCC(take,false,false,c.s,c.status,c.ch,c.d1,c.d2),'Could not insert the controller event.')
  assert(R.MIDI_InsertTextSysexEvt(take,false,false,c.s,15,controllers.eventPrefix..table.concat({c.status,c.ch,c.d1,c.d2},':')),'Could not attach controller ownership.')
 end
 if R.MIDI_SetCCShape and #(scene.plannedControls or {})>0 then
  R.MIDI_Sort(take)
  local written={} controllers.read(take,written)
  for _,c in ipairs(written.ccs) do if c.owned then assert(R.MIDI_SetCCShape(take,c.idx,0,0,true),'Could not set the controller hold shape.') end end
 end
end
-- Verify the complete planned musical-note multiset after native sorting.
-- If an API unexpectedly reindexes, deletes or changes a voice, roll back all MIDI.
local function musicalSignature(n)
 return string.format('%.6f:%.6f:%d:%d:%d:%d:%d',n.s,n.e,n.ch,n.p,n.v,n.sel and 1 or 0,n.mute and 1 or 0)
end
local function verifyWrittenNotes(take,scene,events)
 local function signature(n) return musicalSignature(n)..':'..(n.a and payload(n.a) or '')..':'..controllers.pack(n.controllers,n.controllerShift)..':end:'..(n.ending and payload(n.ending) or '') end
 local expected={} local expectedCount=0
 for _,n in ipairs(scene.notes) do if not n.generated then
  local id=signature(n) expected[id]=(expected[id] or 0)+1 expectedCount=expectedCount+1
 end end
 local actual=read(take) local count,generatedCount=0,0
 for _,n in ipairs(actual.notes) do
  if n.generated then generatedCount=generatedCount+1
  else
   count=count+1 local id=signature(n)
   if not expected[id] or expected[id]==0 then error('Musical-note integrity check failed. The MIDI edit has been reverted.') end
   expected[id]=expected[id]-1
  end
 end
 if count~=expectedCount or generatedCount~=#events then error('MIDI note count changed unexpectedly. The MIDI edit has been reverted.') end
 for _,remaining in pairs(expected) do if remaining~=0 then error('A musical note is missing. The MIDI edit has been reverted.') end end
 if not controllers.match(actual,scene.plannedControls) then error('Controller integrity check failed. The MIDI edit has been reverted.') end
 return actual
end
local legacyPatterns={}
local function rememberLegacy(data)
 local parsed=parse(data) if not parsed then return end
 for _,b in ipairs(parsed) do for _,a in ipairs(b.arts) do
  if a.mode~='ch' then legacyPatterns[#legacyPatterns+1]=a end
 end end
end
rememberLegacy(R.GetExtState('ArticulationBanks_v1','banks'))
rememberLegacy(R.GetExtState('ArticulationBanks_SingleInstrument_v2','banks'))
rememberLegacy(R.GetExtState('ArticulationBanks_Channels_v3','legacy'))
rememberLegacy(R.GetExtState(SECTION,'legacy'))
if #legacyPatterns==0 then
 local a=defaults('Arco','ks',1) a.pitch=24 a.lead=10 a.length=20 legacyPatterns[#legacyPatterns+1]=a
 local b=defaults('Staccato','ks',1) b.pitch=25 b.lead=10 b.length=20 legacyPatterns[#legacyPatterns+1]=b
end
local function legacyCandidates(take,scene,selectedOnly)
 local patterns={}
 for _,a in ipairs(legacyPatterns) do patterns[#patterns+1]=a end
 for _,a in ipairs(bank().arts) do if a.mode~='ch' then patterns[#patterns+1]=a end end
 local candidates={}
 for _,n in ipairs(scene.notes) do if not n.generated and not n.a and not n.mute then
  local start=R.MIDI_GetProjTimeFromPPQPos(take,n.s)
  local duration=(R.MIDI_GetProjTimeFromPPQPos(take,n.e)-start)*1000
  for _,a in ipairs(patterns) do if n.p==a.pitch and n.v==a.velocity and math.abs(duration-a.length)<0.1 then
   for _,musical in ipairs(scene.notes) do
    if not musical.generated and musical.idx~=n.idx and musical.p~=a.pitch and (not selectedOnly or musical.sel) then
     local onset=R.MIDI_GetProjTimeFromPPQPos(take,musical.s)
     if math.abs((onset-start)*1000-a.lead)<0.1 then candidates[n.idx]=true break end
    end
   end
  end end
 end end
 return candidates
end
local function findOwnedSwitch(take,scene,n)
 local a=n.a if not a or a.mode=='ch' or n.mute then return end
 local channel=a.kschannel==0 and n.ch or a.kschannel-1
 local list=scene.switches[channel..':'..a.pitch..':'..a.velocity] or {}
 local pos=a.lead<0 and afterSwitchStart(take,n.s,a.lead)+0.5 or n.s-0.000001
 local lo,hi=1,#list local found
 while lo<=hi do local mid=(lo+hi)//2
  if list[mid].s<=pos then found=list[mid] lo=mid+1 else hi=mid-1 end
 end
 return found and switchFits(take,a,n.s,found.s) and found.key or nil
end
local function hasAnyOwnedSwitch(scene,n)
 local a=n.a local channel=a.kschannel==0 and n.ch or a.kschannel-1
 if a.lead>=0 and n.manualSignal and n.manualSignal.pitch==a.pitch and n.manualSignal.velocity==a.velocity then return true end
 if a.lead>=0 then return #(scene.switches[channel..':'..a.pitch..':'..a.velocity] or {})>0 end
 return findOwnedSwitch(scene.take,scene,n)~=nil
end
local function restoreStaggerStart(n)
 local shift=n.a and n.a.shift
 if shift and shift>0 then
  n.olds=n.olds or n.s n.olde=n.olde or n.e
  n.s=n.s-shift n.changed=true n.a.shift=nil
  return shift
 end
 return 0
end
local function detachAssignment(n)
 restoreStaggerStart(n)
 n.oldch=n.oldch or n.ch n.changed=true n.ch=n.a.base n.a=nil
end
local function needsDefaultAssignments(scene)
 local default=defaultArt()
 local bankName=bank().name
 for _,n in ipairs(scene.notes) do if not n.generated then
  if n.keyswitchRow and n.a and n.a.implicit then return true end
  if not n.keyswitchRow then
  if n.manualArt then if n.a and n.a.implicit then return true end
  elseif default and (not n.a or (n.a.implicit and (n.a.bank~=bankName or config(n.a)~=config(default)))) then return true end
  if not n.manualArt and not default and n.a and n.a.implicit then return true end
  end
 end end
 return false
end
local function assignDefaults(scene)
 local default=defaultArt()
 local bankName=bank().name
 for _,n in ipairs(scene.notes) do
  if n.keyswitchRow and n.a and n.a.implicit then detachAssignment(n) end
  if not n.generated and not n.keyswitchRow and (not n.a or n.a.implicit) then
  if n.manualArt then if n.a then n.a=nil n.changed=true end
  elseif not default then if n.a then detachAssignment(n) end
  elseif not n.a or n.a.bank~=bankName or config(n.a)~=config(default) then
   local base=n.a and n.a.base or n.ch
   restoreStaggerStart(n)
   n.oldch=n.oldch or n.ch n.changed=true
   n.a={base=base,bank=bankName,implicit=true}
   for k,v in pairs(default) do n.a[k]=v end
   n.ch=default.mode=='ks' and base or default.channel-1
  end
 end end
end

local editGeneration=0
local movementSnapshot,musicalGeometry=nil,nil
local switchesMatch
local keyswitchGuard=nil
local deletionSnapshot=nil
-- Background maintenance belongs to the user's native MIDI edit, rather than
-- creating another undo point. REAPER stores that edit before the deferred
-- maintenance runs, so Redo can restore the unmaintained MIDI. Keep bounded,
-- exact before/after patches for that history entry and replay them silently.
-- Full raw-MIDI equality prevents a patch from replacing subsequent user edits.
local automaticHistory={patches={},bytes=0}
function automaticHistory.key()
 if not R.Undo_CanUndo2 or not R.GetSetMediaItemTakeInfo_String then return nil end
 bank()
 local project=R.EnumProjects and R.EnumProjects(-1,'') or 0
 local index=R.Undo_GetCurEntry and R.Undo_GetCurEntry(project)
 local desc=R.Undo_CanUndo2(project) or ''
 local stamp=index and R.Undo_GetEntryTime and R.Undo_GetEntryTime(project,index) or ''
 local settings=table.concat({serialize(),R.GetExtState(SECTION,'autoStagger'),R.GetExtState(SECTION,'staggerMs'),R.GetExtState(SECTION,'ksOverlap')},'\n')
 return project,tostring(index or '')..'\n'..desc..'\n'..stamp..'\n'..settings
end
function automaticHistory.remember(take,before,pitchBefore,lengthBefore)
 local project,historyKey=automaticHistory.key() if not project then return end
 local ok,guid=R.GetSetMediaItemTakeInfo_String(take,'GUID','',false)
 if not ok or guid=='' then return end
 local got,after=R.MIDI_GetAllEvts(take,'') if not got then return end
 local pitchAfter=R.GetMediaItemTakeInfo_Value(take,'D_PITCH')
 local lengthAfter=R.GetMediaItemInfo_Value(R.GetMediaItemTake_Item(take),'D_LENGTH')
 lengthBefore=lengthBefore or lengthAfter
 pitchBefore=pitchBefore or pitchAfter
 if before==after and pitchBefore==pitchAfter and lengthBefore==lengthAfter then return end
 local patches=automaticHistory.patches local last=patches[#patches]
 if last and last.project==project and last.key==historyKey and last.guid==guid and last.after==before and last.pitchAfter==pitchBefore and last.lengthAfter==lengthBefore then
  automaticHistory.bytes=automaticHistory.bytes-#last.after+#after
  last.after=after last.pitchAfter=pitchAfter last.lengthAfter=lengthAfter last.take=take
 else
  patches[#patches+1]={project=project,key=historyKey,guid=guid,take=take,before=before,after=after,pitchBefore=pitchBefore,pitchAfter=pitchAfter,lengthBefore=lengthBefore,lengthAfter=lengthAfter}
  automaticHistory.bytes=automaticHistory.bytes+#before+#after
 end
 while #patches>128 or automaticHistory.bytes>32*1024*1024 do
  local old=table.remove(patches,1) automaticHistory.bytes=automaticHistory.bytes-#old.before-#old.after
 end
end
function automaticHistory.restore()
 if #automaticHistory.patches==0 then return end
 local project=R.EnumProjects and R.EnumProjects(-1,'') or 0
 local changes=R.GetProjectStateChangeCount and R.GetProjectStateChangeCount(project)
 if changes and automaticHistory.project==project and automaticHistory.changes==changes then return end
 local project,historyKey=automaticHistory.key() if not project then return end
 local changes=R.GetProjectStateChangeCount and R.GetProjectStateChangeCount(project)
 if changes and automaticHistory.project==project and automaticHistory.historyKey==historyKey and automaticHistory.changes==changes then return end
 local restored=false
 for _,patch in ipairs(automaticHistory.patches) do if patch.project==project and patch.key==historyKey then
  local take=patch.take
  if not isMidiTake(take,project) then
   take=nil
   for i=0,R.CountMediaItems(project)-1 do
    local item=R.GetMediaItem(project,i)
    for j=0,R.CountTakes(item)-1 do
     local candidate=R.GetTake(item,j)
     if isMidiTake(candidate,project) then
      local ok,guid=R.GetSetMediaItemTakeInfo_String(candidate,'GUID','',false)
      if ok and guid==patch.guid then take=candidate break end
     end
    end
    if take then break end
   end
  end
  if take then
   local ok,guid=R.GetSetMediaItemTakeInfo_String(take,'GUID','',false)
   local got,raw=R.MIDI_GetAllEvts(take,'')
   local item=R.GetMediaItemTake_Item(take)
   if ok and guid==patch.guid and got and raw==patch.before and R.GetMediaItemTakeInfo_Value(take,'D_PITCH')==patch.pitchBefore and R.GetMediaItemInfo_Value(item,'D_LENGTH')==patch.lengthBefore then
    if R.MIDI_SetAllEvts(take,patch.after) and R.SetMediaItemTakeInfo_Value(take,'D_PITCH',patch.pitchAfter) then
     if patch.lengthAfter~=patch.lengthBefore then R.SetMediaItemInfo_Value(item,'D_LENGTH',patch.lengthAfter) end
     R.UpdateItemInProject(R.GetMediaItemTake_Item(take))
     patch.take=take restored=true
    else R.MIDI_SetAllEvts(take,raw) end
   end
  end
 end end
 if restored then keyswitchGuard=nil deletionSnapshot=nil movementSnapshot=nil end
 automaticHistory.project=project automaticHistory.historyKey=historyKey
 automaticHistory.changes=R.GetProjectStateChangeCount and R.GetProjectStateChangeCount(project)
end
local function rawKeyNotes(take)
 local ok,count=R.MIDI_CountEvts(take) if not ok then return nil end
 local state={take=take,count=count,notes={},counts={}}
 for i=0,count-1 do
  local yes,sel,mute,s,e,ch,p,v=R.MIDI_GetNote(take,i)
  if yes then
   local n={idx=i,sel=sel,mute=mute,s=s,e=e,ch=ch,p=p,v=v}
   n.id=string.format('%.6f:%.6f:%d:%d:%d:%d',s,e,ch,p,v,mute and 1 or 0)
   state.notes[#state.notes+1]=n
   state.counts[n.id]=(state.counts[n.id] or 0)+1
  end
 end
 return state
end
local function captureKeyswitchGuard(take,readyScene,readyRaw)
 local ok,raw=true,readyRaw
 if not raw then ok,raw=R.MIDI_GetAllEvts(take,'') end
 if not ok then return nil end
 local scene=readyScene or read(take) local state={take=take,raw=raw,scene=scene,counts={}}
 for _,n in ipairs(scene.notes) do
  local id=string.format('%.6f:%.6f:%d:%d:%d:%d',n.s,n.e,n.ch,n.p,n.v,n.mute and 1 or 0)
  state.counts[id]=(state.counts[id] or 0)+1
 end
 return state
end
local function watchKeyswitchRows(readyScene,readyRaw)
 local take=activeTake() if not take then keyswitchGuard=nil return end
 if R.JS_Mouse_GetState and R.JS_Mouse_GetState(1)&1~=0 then return end
 local ok,current=pcall(captureKeyswitchGuard,take,readyScene,readyRaw) if not ok or not current then return end
 local previous=keyswitchGuard
 keyswitchGuard=current
 if not previous or previous.take~=take then return end
 local function musicSignature(scene)
  local result={}
  for _,n in ipairs(scene.notes) do if not n.generated and not n.keyswitchRow then
   result[#result+1]=string.format('%.6f:%.6f:%d:%d:%d:%s',n.s,n.e,n.ch,n.p,n.v,(n.a and payload(n.a) or '')..':ctrl:'..controllers.pack(n.controllers,n.controllerShift)..':end:'..(n.ending and payload(n.ending) or ''))
  end end
  table.sort(result) return table.concat(result,'\n')
 end
 -- Coherent musical moves, transposes, undo and writes by another action keep
 -- automatic ownership. A switch edited independently becomes a manual note.
 if musicSignature(previous.scene)~=musicSignature(current.scene) then return end
 local old,new,oldCount,newCount={},{},0,0
 for _,n in ipairs(previous.scene.notes) do if n.generated then old[n.key]=n oldCount=oldCount+1 end end
 for _,n in ipairs(current.scene.notes) do if n.generated then new[n.key]=n newCount=newCount+1 end end
 if oldCount~=newCount then return end
 local changed,removed={},{}
 for id,n in pairs(new) do
  local before=old[id]
  if not before or before.s~=n.s or before.e~=n.e or before.ch~=n.ch or before.p~=n.p or before.v~=n.v or before.mute~=n.mute then changed[id]=true end
 end
 if not next(changed) then return end
 local planned,events=pcall(plan,take,current.scene)
 if planned and switchesMatch and switchesMatch(current.scene,events) then return end
 for id,n in pairs(old) do
  local after=new[id]
  if not after or changed[id] then removed[id]=true end
 end
 local ownerKeys,endingOwnerKeys={},{}
 for _,n in ipairs(previous.scene.notes) do if n.a and n.a.mode~='ch' then
  local owner=findOwnedSwitch(take,previous.scene,n)
  if owner and removed[owner] then ownerKeys[n.key]=true end
 end end
 for _,n in ipairs(previous.scene.notes) do if n.ending then
  local ok,start,finish,ch=pcall(articulationGroups.endingPosition,take,n)
  if ok and removed[key(start,ch,n.ending.pitch)] then endingOwnerKeys[n.key]=true end
 end end
 local success,err=xpcall(function()
  R.MIDI_DisableSort(take)
  -- Only our notation changes; all MIDI notes keep the user's exact edits.
  local edits={}
  for _,t in ipairs(current.scene.texts) do
   local tail
   if t.ownedKS and changed[t.key] then tail=setUser(t.tail,KS..':manual')
   elseif ownerKeys[t.key] or endingOwnerKeys[t.key] then
    tail=t.tail
    if ownerKeys[t.key] then local marker,extras=extractMarker(tail) if marker then tail=extras end end
    if endingOwnerKeys[t.key] then local marker,extras=extractUserMarker(tail,'ABEND1') if marker then tail=extras end end
   end
   if tail then edits[#edits+1]={t=t,tail=tail} end
  end
  table.sort(edits,function(a,b) return a.t.idx>b.t.idx end)
  for _,edit in ipairs(edits) do
   local t=edit.t
   assert(R.MIDI_DeleteTextSysexEvt(take,t.idx),'Could not detach automatic notation')
   if edit.tail:find('%S') then assert(R.MIDI_InsertTextSysexEvt(take,t.sel,t.mute,t.pos,15,'NOTE '..t.ch..' '..t.p..edit.tail),'Could not save manual keyswitch notation') end
  end
  R.MIDI_Sort(take)
  local after=rawKeyNotes(take)
  for id,count in pairs(current.counts) do assert(after.counts[id]==count,'A MIDI note changed while enabling manual editing') end
  for id,count in pairs(after.counts) do assert(current.counts[id]==count,'A MIDI note changed while enabling manual editing') end
 end,debug.traceback)
 if not success then R.MIDI_SetAllEvts(take,current.raw) R.MIDI_Sort(take) status='Manual edit metadata could not be updated.'
 else automaticHistory.remember(take,current.raw) deletionSnapshot=nil status='Manual keyswitch edit preserved.' end
 R.UpdateItemInProject(R.GetMediaItemTake_Item(take))
 keyswitchGuard=captureKeyswitchGuard(take)
end
local function execute(a,clear,sync,timing,removedKeys,background,controlAction,endingAction,removedEndings)
 local take=activeTake() if not take then return false end
 local ok,scene=pcall(read,take) if not ok then status=tostring(scene) return false end
 local removedMissing=0
 for _,n in ipairs(scene.notes) do if n.ending and removedEndings and removedEndings[n.key]==payload(n.ending) then n.ending=nil n.changed=true end end
 for _,n in ipairs(scene.notes) do
  if not n.generated and n.a and n.a.mode~='ch' and not n.mute then
   local explicitRemoval=removedKeys and removedKeys[n.key]==payload(n.a)
   local observed=deletionSnapshot and deletionSnapshot.take==take and deletionSnapshot.notes[n.key]
   local rebuilding=observed and observed.rebuild and observed.data==payload(n.a)
   local orphan=not sync and not rebuilding and not hasAnyOwnedSwitch(scene,n)
   if explicitRemoval or orphan then detachAssignment(n) removedMissing=removedMissing+1 end
  end
 end
 if timing then
  for _,n in ipairs(scene.notes) do
   if not n.generated and n.a and n.a.mode~='ch' and n.a.bank==timing.bank then
    n.a.lead=n.a.lead<0 and -timing.lead or timing.lead n.a.length=timing.length n.changed=true
   end
  end
 end
 local selected=0
 for _,n in ipairs(scene.notes) do if n.sel and not n.generated and not n.keyswitchRow then
  selected=selected+1
  local base=n.a and n.a.base or n.ch
  if endingAction then
   n.changed=true n.ending=nil
   if endingAction.value then
    n.ending={base=base,bank=bank().name}
    for k,v in pairs(endingAction.value) do n.ending[k]=v end
    n.ending.mode='ks' n.ending.lead=math.abs(n.ending.lead)
   end
  end
  if controlAction then
   if n.a and n.a.mode=='ch' then restoreStaggerStart(n) end
   controllers.set(n,controlAction.value)
  end
  if not sync then
   controllers.restoreShift(n)
   n.restoredShift=restoreStaggerStart(n)
   n.oldch=n.oldch or n.ch n.changed=true
   if clear then n.ch=base n.a=nil
   else
    n.a={base=base,bank=bank().name}
    n.manualArt=nil
    for k,v in pairs(a) do n.a[k]=v end
    n.ch=a.mode=='ks' and base or a.channel-1
    if controllers.enabled(a) and n.controllers then
     local keep={}
     for _,c in ipairs(n.controllers) do if controllers.lane(c,n)~=controllers.lane(a,n) then keep[#keep+1]=c end end
     n.controllers=#keep>0 and keep or nil
    end
   end
  end
 end end
 assignDefaults(scene)
 if controlAction and not controlAction.value then
  for _,n in ipairs(scene.notes) do if n.sel and not n.generated and not n.keyswitchRow and controllers.enabled(n.a) then
   n.a.ctrl='none' n.a.implicit=nil n.changed=true
  end
  if n.sel and not n.generated and not n.keyswitchRow and controllers.enabled(n.ending) then n.ending.ctrl='none' n.changed=true end
  end
 end
 prepareDefaults(take,scene)
 local room,moved=pcall(ensureBoundaryRoom,take,scene) if not room then status=tostring(moved) return false end
 -- If auto-stagger was disabled after an earlier edit, keep its old offset
 -- while a conflict still exists. Common articulations always restore alignment.
 prepareDefaults(take,scene)
 if not sync and not clear and R.GetExtState(SECTION,'autoStagger')~='1' then
  for _,n in ipairs(scene.notes) do if n.sel and n.restoredShift and n.restoredShift>0 and n.a and n.a.lead>=0 then
   for _,other in ipairs(scene.notes) do
    if other~=n and not other.generated and not other.mute and other.effective and other.effective.lead>=0 and other.ch==n.ch and other.s==n.s and config(other.effective)~=config(n.a) then
     n.s=n.s+n.restoredShift n.a.shift=n.restoredShift break
    end
   end
  end end
 end
 if (not sync or controlAction or endingAction) and selected==0 then status='No musical notes selected.' return false end
 local shifted=moved
 if not clear or defaultArt() then
  local fit,result=pcall(function() prepareDefaults(take,scene) return staggerConflicts(take,scene,sync or clear) end)
  if not fit then status=tostring(result) return false end
  shifted=shifted+result
 end
 local yes,events=pcall(plan,take,scene) if not yes then status=tostring(events) return false end
 for _,n in ipairs(scene.notes) do
  local ending=scene.manualEnds and scene.manualEnds[n.idx]
  if ending then n.olds=n.olds or n.s n.olde=n.olde or n.e n.e=ending n.changed=true end
 end
 local got,backup=R.MIDI_GetAllEvts(take,'') if not got then status='Could not back up MIDI.' return false end
 local item=R.GetMediaItemTake_Item(take)
 local lengthBefore=R.GetMediaItemInfo_Value(item,'D_LENGTH')
 if not background then R.Undo_BeginBlock() end
 local verifiedScene
 local success,err=xpcall(function()
  if scene.controlRight then
   local needed=R.MIDI_GetProjTimeFromPPQPos(take,scene.controlRight)-R.GetMediaItemInfo_Value(item,'D_POSITION')
   if needed>lengthBefore then assert(R.SetMediaItemInfo_Value(item,'D_LENGTH',needed),'Could not leave room for controller release.') end
  end
  write(take,scene,events,backup) R.MIDI_Sort(take) verifiedScene=verifyWrittenNotes(take,scene,events)
 end,debug.traceback)
 if not success then R.MIDI_SetAllEvts(take,backup) if R.GetMediaItemInfo_Value(item,'D_LENGTH')~=lengthBefore then R.SetMediaItemInfo_Value(item,'D_LENGTH',lengthBefore) end end
 R.MIDI_Sort(take) R.UpdateItemInProject(R.GetMediaItemTake_Item(take))
 if not background then
  R.Undo_EndBlock(endingAction and (endingAction.value and ('Apply ending: '..endingAction.value.name) or 'Clear ending') or controlAction and (controlAction.value and ('Apply controller: '..controlAction.value.name) or 'Clear controllers') or removedKeys and 'Clear deleted keyswitch assignments' or timing and 'Change keyswitch timing' or sync and 'Refresh keyswitches' or clear and 'Clear articulation' or 'Replace articulation: '..a.name,-1)
 elseif success then automaticHistory.remember(take,backup,nil,lengthBefore) end
 if not success then status='Changes reverted after a MIDI error.' R.MB(tostring(err),'Articulation Manager',0) return false end
 editGeneration=editGeneration+1
 keyswitchGuard=captureKeyswitchGuard(take,verifiedScene)
 controllers.lastWrite={take=take,data=keyswitchGuard and keyswitchGuard.raw,scene=verifiedScene}
 if musicalGeometry then movementSnapshot={take=take,generation=editGeneration,signature=musicalGeometry(scene)} end
 status=endingAction and (endingAction.value and (endingAction.value.name..' — ending applied.') or 'Ending cleared.') or controlAction and (controlAction.value and (controlAction.value.name..' — controller applied to '..selected..' notes.') or 'Controller assignments cleared.') or sync and 'Keyswitches refreshed.' or clear and 'Assignment cleared.' or a.name..' — notes: '..selected
 if removedMissing>0 then status=status..'; deleted-switch assignments cleared: '..removedMissing end
 if shifted>0 then status=status..'; notes shifted: '..shifted end
 return true
end
function articulationGroups.applyEnding(a) return execute(nil,false,true,nil,nil,false,nil,{value=a}) end
local function apply(a) if a.trigger=='end' then return articulationGroups.applyEnding(a) end return execute(a,false,false) end
local function clear() return execute(nil,true,false) end
local function applyController(c) return execute(nil,false,true,nil,nil,false,{value=c}) end
local function sync(dropOrphans,background)
 local missing
 if dropOrphans then
  local take=activeTake() if not take then return false end
  local ok,scene=pcall(read,take) if not ok then status=tostring(scene) return false end
  missing={}
  for _,n in ipairs(scene.notes) do
   if n.a and n.a.mode~='ch' and not n.mute and not hasAnyOwnedSwitch(scene,n) then missing[n.key]=payload(n.a) end
  end
  if not next(missing) then missing=nil end
 end
 return execute(nil,false,true,nil,missing,background)
end
local function retime(lead,length) return execute(nil,false,true,{lead=lead,length=length,bank=bank().name}) end
local function clearMissingAssignments()
 local take=activeTake() if not take then return false end
 local ok,scene=pcall(read,take) if not ok then status=tostring(scene) return false end
 local missing={}
 for _,n in ipairs(scene.notes) do
  if not n.generated and n.a and n.a.mode~='ch' and not n.mute and not findOwnedSwitch(take,scene,n) then missing[n.key]=payload(n.a) end
 end
 if not next(missing) then status='No missing keyswitch assignments found.' return true end
 return execute(nil,false,true,nil,missing)
end
-- Watch previously observed pulse ownership. Moving musical notes or changing
-- tempo does not count as deleting a switch: its physical key must disappear.
local function watchDeletedSwitches(readyScene)
 local take=activeTake() if not take then deletionSnapshot=nil return end
 local ok,scene=true,readyScene
 if not scene then ok,scene=pcall(read,take) end
 if not ok then return end
 local present={} for _,n in ipairs(scene.notes) do if n.generated then present[n.key]=true end end
 local missing,missingEndings={},{}
 local geometry=musicalGeometry(scene)
 local structural=deletionSnapshot and deletionSnapshot.take==take and deletionSnapshot.geometry~=geometry
 if deletionSnapshot and deletionSnapshot.take==take then
  for _,n in ipairs(scene.notes) do
   local previous=deletionSnapshot.notes[n.key]
   local ending=(deletionSnapshot.endings or {})[n.key]
   if not structural and n.ending and ending and ending.data==payload(n.ending) and not present[ending.switch] then missingEndings[n.key]=ending.data end
   if not structural and n.a and previous and not previous.rebuild and previous.switch and previous.data==payload(n.a) and not present[previous.switch] then missing[n.key]=previous.data end
  end
 end
 if (next(missing) or next(missingEndings)) and execute(nil,false,true,nil,missing,true,nil,nil,missingEndings) then
  scene=controllers.lastWrite.scene
 end
 local snapshot={take=take,notes={},endings={},geometry=musicalGeometry(scene)}
 for _,n in ipairs(scene.notes) do
  if n.a and n.a.mode~='ch' and not n.mute then
   local previous=deletionSnapshot and deletionSnapshot.take==take and deletionSnapshot.notes[n.key]
   local owner=findOwnedSwitch(take,scene,n)
   -- Keep a known physical owner through tempo changes that alter the lead window.
   if not owner and previous and present[previous.switch] and previous.data==payload(n.a) then owner=previous.switch end
   local rebuild=not owner and previous and previous.data==payload(n.a) and (previous.rebuild or (structural and previous.switch and not present[previous.switch]))
   snapshot.notes[n.key]={data=payload(n.a),switch=owner,rebuild=rebuild or nil}
  end
 end
 for _,n in ipairs(scene.notes) do if n.ending then
  local ok,start,finish,ch=pcall(articulationGroups.endingPosition,take,n)
  if ok then snapshot.endings[n.key]={data=payload(n.ending),switch=key(start,ch,n.ending.pitch)} end
 end end
 deletionSnapshot=snapshot
end
-- NOTE notation follows native MIDI-editor moves/transposition. Rebuild owned
-- switches when musical geometry changes, after the drag ends. Selection-only
-- changes and our own writes do not generate additional MIDI edits.
musicalGeometry=function(scene)
 local values={}
 for _,n in ipairs(scene.notes) do if not n.generated then
  values[#values+1]=string.format('%.6f:%.6f:%d:%d:%d:%s',n.s,n.e,n.ch,n.p,n.mute and 1 or 0,(n.a and payload(n.a) or '')..':ctrl:'..controllers.pack(n.controllers,n.controllerShift)..':end:'..(n.ending and payload(n.ending) or ''))
 end end
 table.sort(values) return table.concat(values,'\n')
end
switchesMatch=function(scene,events)
 local actual,expected={},{}
 local function signature(n) return string.format('%.6f:%.6f:%d:%d:%d:%d',n.s,n.e,n.ch,n.p,n.v,n.mute and 1 or 0) end
 for _,n in ipairs(scene.notes) do if n.generated then actual[#actual+1]=signature(n) end end
 for _,n in ipairs(events) do expected[#expected+1]=signature(n) end
 table.sort(actual) table.sort(expected)
 return table.concat(actual,'\n')==table.concat(expected,'\n') and controllers.match(scene,scene.plannedControls)
end
local function watchMusicalEdits(readyScene)
 if R.JS_Mouse_GetState and R.JS_Mouse_GetState(1)&1~=0 then return end
 local take=activeTake() if not take then movementSnapshot=nil return end
 local ok,scene=true,readyScene
 if not scene then ok,scene=pcall(read,take) end
 if not ok then return end
 local signature=musicalGeometry(scene)
 local overlap=false local switches={}
 for _,n in ipairs(scene.notes) do if (n.generated or n.keyswitchRow) and not n.mute then switches[#switches+1]=n end end
 table.sort(switches,function(a,b) if a.ch~=b.ch then return a.ch<b.ch end return a.s<b.s end)
 for i,n in ipairs(switches) do
  for j=i+1,#switches do
   local later=switches[j]
   if later.ch~=n.ch then break end
   if later.s>n.s then if n.e>later.s then overlap=true end break end
  end
 end
 local previous=movementSnapshot
 if overlap or needsDefaultAssignments(scene) or (previous and previous.take==take and previous.generation==editGeneration and previous.signature~=signature) then
  local planned,events=pcall(plan,take,scene)
  if (needsDefaultAssignments(scene) or not planned or next(scene.manualEnds or {}) or not switchesMatch(scene,events)) and sync(false,true) then
   signature=musicalGeometry(controllers.lastWrite.scene)
  end
 end
 movementSnapshot={take=take,generation=editGeneration,signature=signature}
end
local function protectKeyswitchSelectionAndPitch(readyScene)
 if R.JS_Mouse_GetState and R.JS_Mouse_GetState(1)&1~=0 then return end
 local take=activeTake() if not take then return end
 local ok,scene=true,readyScene
 if not scene then ok,scene=pcall(read,take) end
 if not ok then return end
 local musicalSelected=false
 for _,n in ipairs(scene.notes) do if not n.generated and not n.keyswitchRow and n.sel then musicalSelected=true break end end
 if musicalSelected then
  local selected=false
  for _,n in ipairs(scene.notes) do if (n.generated or n.keyswitchRow) and n.sel then selected=true break end end
  if selected then
   local got,backup=R.MIDI_GetAllEvts(take,'') if not got then return end
   local success=xpcall(function()
    R.MIDI_DisableSort(take)
    for _,n in ipairs(scene.notes) do if (n.generated or n.keyswitchRow) and n.sel then
     assert(R.MIDI_SetNote(take,n.idx,false,nil,nil,nil,nil,nil,nil,true),'Keyswitch deselection failed')
     n.sel=false
    end end
    if R.MIDI_SetTextSysexEvt then for _,t in ipairs(scene.texts) do if t.ownedKS and t.sel then
     assert(R.MIDI_SetTextSysexEvt(take,t.idx,false,nil,nil,nil,nil,true),'Keyswitch notation deselection failed')
    end end end
    R.MIDI_Sort(take)
    local expected={}
    for _,n in ipairs(scene.notes) do local id=musicalSignature(n) expected[id]=(expected[id] or 0)+1 end
    for _,n in ipairs(read(take).notes) do
     local id=musicalSignature(n) assert(expected[id] and expected[id]>0,'Selection integrity check failed') expected[id]=expected[id]-1
    end
    for _,count in pairs(expected) do assert(count==0,'A note changed while deselecting switches') end
   end,debug.traceback)
   if not success then R.MIDI_SetAllEvts(take,backup) R.MIDI_Sort(take) return end
   R.UpdateItemInProject(R.GetMediaItemTake_Item(take))
   automaticHistory.remember(take,backup)
  end
 end
 -- Also repair a transpose performed before the observer could deselect the
 -- switches. NOTE ownership follows the native pitch edit; the mapping does not.
 -- Most edits only change a musical note's length or start. A full switch plan
 -- is unnecessary unless an owned switch left all assigned physical pitches.
 local pitches={}
 for _,n in ipairs(scene.notes) do if not n.generated and not n.keyswitchRow then
  for _,a in pairs({n.a,n.ending}) do if a and a.mode~='ch' then
   pitches[(a.kschannel==0 and n.ch or a.kschannel-1)..':'..a.pitch]=true
  end end
 end end
 local misplaced=false
 for _,n in ipairs(scene.notes) do if n.generated and not pitches[n.ch..':'..n.p] then misplaced=true break end end
 if not misplaced then return end
 local planned,events=pcall(plan,take,scene) if not planned then return end
 local expected={}
 for _,ev in ipairs(events) do expected[key(ev.s,ev.ch,0)]=ev.p end
 for _,n in ipairs(scene.notes) do if n.generated then
  local pitch=expected[key(n.s,n.ch,0)]
  if musicalSelected and pitch and pitch~=n.p then
   if sync(false,true) then deletionSnapshot=nil end
   return
  end
 end end
end
local function bakeProtectedTakePitch(take)
 if not isMidiTake(take) then return false end
 local pitch=R.GetMediaItemTakeInfo_Value(take,'D_PITCH')
 if math.abs(pitch)<0.000001 then return false end
 local ok,scene=pcall(read,take) if not ok then return false end
 local owned=false
 for _,n in ipairs(scene.notes) do if n.generated or n.keyswitchRow then owned=true break end end
 if not owned then return false end
 local shift=round(pitch)
 -- MIDI pitches are integers. Preserve the physical switch rows by applying
 -- the take transpose only to musical data and returning take pitch to zero.
 for _,n in ipairs(scene.notes) do if not n.generated and not n.keyswitchRow and (n.p+shift<0 or n.p+shift>127) then
  R.SetMediaItemTakeInfo_Value(take,'D_PITCH',0)
  R.UpdateItemInProject(R.GetMediaItemTake_Item(take))
  status='Transpose cancelled: a musical note would leave MIDI pitch range 0–127.'
  return false
 end end
 local got,backup=R.MIDI_GetAllEvts(take,'') if not got then return false end
 local success,err=xpcall(function()
  R.MIDI_DisableSort(take)
  for _,n in ipairs(scene.notes) do if not n.generated and not n.keyswitchRow then
   n.p=n.p+shift
   assert(R.MIDI_SetNote(take,n.idx,nil,nil,nil,nil,nil,n.p,nil,true),'Musical transpose failed')
  end end
  for _,t in ipairs(scene.texts) do
   local notes=scene.bykey[t.key] or {} local n=notes[1]
   if n and not n.generated and not n.keyswitchRow then
    assert(R.MIDI_SetTextSysexEvt(take,t.idx,nil,nil,nil,nil,'NOTE '..n.ch..' '..n.p..t.tail,true),'Transposed notation update failed')
   end
  end
  assert(R.SetMediaItemTakeInfo_Value(take,'D_PITCH',0),'Take pitch reset failed')
  R.MIDI_Sort(take)
  local expected={}
  for _,n in ipairs(scene.notes) do local id=musicalSignature(n) expected[id]=(expected[id] or 0)+1 end
  for _,n in ipairs(read(take).notes) do
   local id=musicalSignature(n) assert(expected[id] and expected[id]>0,'Transpose integrity check failed') expected[id]=expected[id]-1
  end
  for _,count in pairs(expected) do assert(count==0,'A note changed unexpectedly during transpose') end
 end,debug.traceback)
 if not success then
  R.MIDI_SetAllEvts(take,backup) R.MIDI_Sort(take)
  R.SetMediaItemTakeInfo_Value(take,'D_PITCH',0)
  status='Transpose cancelled after a MIDI error; the original notes were preserved.'
 else
  automaticHistory.remember(take,backup,pitch)
  editGeneration=editGeneration+1
  if movementSnapshot and movementSnapshot.take==take then movementSnapshot=nil end
  if deletionSnapshot and deletionSnapshot.take==take then deletionSnapshot=nil end
  if keyswitchGuard and keyswitchGuard.take==take then keyswitchGuard=captureKeyswitchGuard(take) end
 end
 R.UpdateItemInProject(R.GetMediaItemTake_Item(take))
 return success
end
local function watchItemTranspose()
 if not R.GetMediaItemTakeInfo_Value or not R.SetMediaItemTakeInfo_Value or not R.CountMediaItems or not R.CountTakes then return end
 if R.JS_Mouse_GetState and R.JS_Mouse_GetState(1)&1~=0 then return end
 local project=R.EnumProjects and R.EnumProjects(-1,'') or 0
 local changes=R.GetProjectStateChangeCount and R.GetProjectStateChangeCount(project)
 if changes and automaticHistory.transposeSnapshot and automaticHistory.transposeSnapshot.project==project and automaticHistory.transposeSnapshot.changes==changes then return end
 for i=0,R.CountMediaItems(project)-1 do
  local item=R.GetMediaItem(project,i)
  if validPointer(item,'MediaItem*',project) then
   for j=0,R.CountTakes(item)-1 do
    local take=R.GetTake(item,j)
    -- CountTakes includes empty take slots; GetTake can return nil for them.
    if isMidiTake(take,project) and math.abs(R.GetMediaItemTakeInfo_Value(take,'D_PITCH'))>0.000001 then bakeProtectedTakePitch(take) end
   end
  end
 end
 automaticHistory.transposeSnapshot={project=project,changes=R.GetProjectStateChangeCount and R.GetProjectStateChangeCount(project)}
end
local cleanupPreview=nil
local function noteSignature(n) return table.concat({n.s,n.e,n.ch,n.p,n.v,tostring(n.mute)},'/') end
local function legacyEdit(take,title,fn)
 local got,backup=R.MIDI_GetAllEvts(take,'') if not got then return false end
 R.Undo_BeginBlock()
 local ok,err=xpcall(fn,debug.traceback)
 if not ok then R.MIDI_SetAllEvts(take,backup) status='Cleanup reverted after an error.' end
 R.MIDI_Sort(take) R.UpdateItemInProject(R.GetMediaItemTake_Item(take)) R.Undo_EndBlock(title,-1)
 return ok
end
local function findLegacy()
 local take=activeTake() if not take then return end
 local ok,scene=pcall(read,take) if not ok then status=tostring(scene) return end
 local candidates=legacyCandidates(take,scene,false)
 if not next(candidates) then status='No legacy keyswitches match the bank mappings.' return end
 local sigs={} local count=0
 if legacyEdit(take,'Select legacy keyswitches for review',function()
  for _,n in ipairs(scene.notes) do
   if not R.MIDI_SetNote(take,n.idx,candidates[n.idx] or false,nil,nil,nil,nil,nil,nil,true) then error('Selection failed') end
   if candidates[n.idx] then count=count+1 sigs[noteSignature(n)]=true end
  end
 end) then cleanupPreview={take=take,sigs=sigs} status='Review the selected keyswitches ('..count..'), then remove them through Settings.' end
end
local function deleteLegacy()
 local take=activeTake() if not take then return end
 if not cleanupPreview or cleanupPreview.take~=take then status='First find legacy keyswitches and review the selection.' return end
 local ok,scene=pcall(read,take) if not ok then status=tostring(scene) return end
 local indexes={}
 for _,n in ipairs(scene.notes) do if n.sel then
  if n.generated or n.a or not cleanupPreview.sigs[noteSignature(n)] then status='Other notes are selected. Find legacy keyswitches again.' return end
  indexes[#indexes+1]=n.idx
 end end
 if #indexes==0 then status='No legacy keyswitches selected.' return end
 table.sort(indexes,function(a,b) return a>b end)
 if legacyEdit(take,'Remove reviewed legacy keyswitches',function()
  for _,i in ipairs(indexes) do if not R.MIDI_DeleteNote(take,i) then error('Delete failed') end end
 end) then status='Legacy keyswitches removed. Select musical notes.' cleanupPreview=nil end
end
-- Interface ------------------------------------------------------------------
-- Compositing/menu approach follows Gridbox (Ilias-Timon Poulakis, MIT).
local popupMode=rawget(_G,'ABART_QUICK_POPUP')==true and 'quick' or rawget(_G,'ABART_POPUP')==true
if R.set_action_options and not popupMode then R.set_action_options(3) end
if not R.JS_Composite and not popupMode then
 R.MB('js_ReaScriptAPI is required for the embedded MIDI editor field.','Articulation Manager',0) return
end
local host,bitmap,liceFont=nil,nil,nil
local running=true
local editorBusy=false
local box={x=0,y=0,w=140,h=24}
local fontSize=tonumber(R.GetExtState(SECTION,'boxFont')) or 13
local boxWidth=tonumber(R.GetExtState(SECTION,'boxWidth')) or 140
local boxHeight=tonumber(R.GetExtState(SECTION,'boxHeight')) or 24
local cachedState=nil
local currentLabel=nil
local lastHover=false
local refresh=0
local previousButtons=0
local lastClickTime=0
local ownedIntercepts={}
local popupTitle='ArticulationBox menu'
local positionLocked=R.GetExtState(SECTION,'lockPosition')~='0'
local gesture=nil
local lastDownTime,lastLeftUpTime,lastRightUpTime,lastRightDownTime=0,0,0,0
local leftPressed,rightPressed=false,false
local menuIgnoreUntil=0
local function togglePositionLock()
 positionLocked=not positionLocked
 R.SetExtState(SECTION,'lockPosition',positionLocked and '1' or '0',true)
 currentLabel=nil
end
local function edgeFlags(mx,my)
 local flags=0 local edge=4
 if mx-box.x<edge then flags=flags|1 elseif box.x+box.w-mx<=edge then flags=flags|4 end
 if my-box.y<edge then flags=flags|2 elseif box.y+box.h-my<=edge then flags=flags|8 end
 return flags
end
-- Pure geometry calculation, keeping the opposite resize edge anchored.
local function gestureRect(start,flags,dx,dy,w,h)
 local x,y,bw,bh=start.x,start.y,start.w,start.h
 local minW,maxW=math.min(90,w),math.min(600,w)
 local minH,maxH=math.min(18,h),math.min(60,h)
 local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
 if flags==0 then
  x=clamp(x+dx,0,math.max(0,w-bw)) y=clamp(y+dy,0,math.max(0,h-bh))
 else
  if flags&1~=0 then local right=x+bw x=clamp(x+dx,math.max(0,right-maxW),right-minW) bw=right-x end
  if flags&4~=0 then bw=clamp(bw+dx,minW,math.min(maxW,w-x)) end
  if flags&2~=0 then local bottom=y+bh y=clamp(y+dy,math.max(0,bottom-maxH),bottom-minH) bh=bottom-y end
  if flags&8~=0 then bh=clamp(bh+dy,minH,math.min(maxH,h-y)) end
 end
 return {x=round(x),y=round(y),w=round(bw),h=round(bh)}
end
local function saveLayout(h)
 R.SetExtState(SECTION,'attachX',tostring(box.x),true)
 R.SetExtState(SECTION,'attachBottom',tostring(math.max(0,h-box.y-box.h)),true)
 R.SetExtState(SECTION,'boxWidth',tostring(box.w),true)
 R.SetExtState(SECTION,'boxHeight',tostring(box.h),true)
end

local sec,cmd
if R.get_action_context then local _,_,s,c=R.get_action_context() sec,cmd=s,c end
-- Only this tagged block is changed; other startup actions are preserved.
local startupBegin='-- ArticulationBox startup: BEGIN'
local startupEnd='-- ArticulationBox startup: END'
local function startupPath() return R.GetResourcePath()..'/Scripts/__startup.lua' end
local function startupRead()
 local path=startupPath()
 if not R.file_exists(path) then return '' end
 local file,err=io.open(path,'rb')
 if not file then return nil,'Could not read startup script: '..tostring(err) end
 local content=file:read('*a') file:close()
 return content
end
local function startupBlock(content)
 local first=content:find(startupBegin,1,true)
 if not first then return end
 if first>1 and content:sub(first-1,first-1)~='\n' then return nil,nil,'Invalid ArticulationBox startup block.' end
 local last=content:find(startupEnd,first+#startupBegin,true)
 if not last or content:find(startupBegin,first+#startupBegin,true) then return nil,nil,'Invalid ArticulationBox startup block.' end
 last=last+#startupEnd-1
 if content:sub(last+1,last+2)=='\r\n' then last=last+2
 elseif content:sub(last+1,last+1)=='\n' then last=last+1 end
 return first,last
end
local function startupEnabled()
 local content=startupRead()
 if not content then return false end
 local first,last= startupBlock(content)
 return first~=nil and last~=nil
end
local function startupCommand()
 local _,path,section,command=R.get_action_context()
 if popupMode then path=(path:match('^(.*[\\/])') or '')..'Articulation_Manager.lua' end
 if section~=0 or popupMode then command=R.AddRemoveReaScript(true,0,path,true) end
 if not command or command==0 then return nil,'Could not register the Main startup action.' end
 local name=R.ReverseNamedCommandLookup(command)
 if not name or name=='' then return nil,'Could not resolve the startup action ID.' end
 return name:sub(1,1)=='_' and name or '_'..name
end
local function setStartupEnabled(enabled)
 local content,err=startupRead()
 if not content then return false,err end
 local first,last,blockError=startupBlock(content)
 if blockError then return false,blockError end
 local updated=first and (content:sub(1,first-1)..content:sub(last+1)) or content
 if enabled then
  local name,commandError=startupCommand()
  if not name then return false,commandError end
  local hook=table.concat({startupBegin,'do',
   '  local command = reaper.NamedCommandLookup('..string.format('%q',name)..')',
   '  if command ~= 0 then reaper.Main_OnCommand(command, 0) end',
   'end',startupEnd,''},'\n')
  updated=hook..updated
 end
 if updated==content then return true end
 local compiled,syntaxError=load(updated,'@__startup.lua','t')
 if not compiled then return false,'Startup script contains a syntax error. No changes made.\n'..tostring(syntaxError) end
 local path=startupPath()
 local temporary=path..'.ArticulationBox.tmp'
 local file,writeError=io.open(temporary,'wb')
 if not file then return false,'Could not write startup script: '..tostring(writeError) end
 local wrote,why=file:write(updated)
 local closed,closeError=file:close()
 if not wrote or not closed then os.remove(temporary) return false,'Could not save startup script: '..tostring(why or closeError) end
 -- Keep a timestamped recovery copy; never overwrite an existing backup.
 local backup
 if R.file_exists(path) then
  local base=path..'.ArticulationBox-'..os.date('%Y%m%d-%H%M%S') local i=0
  backup=base..'.bak'
  while R.file_exists(backup) do i=i+1 backup=base..'-'..i..'.bak' end
  local moved,moveError=os.rename(path,backup)
  if not moved then os.remove(temporary) return false,'Could not back up startup script: '..tostring(moveError) end
 end
 local moved,moveError=os.rename(temporary,path)
 if not moved then
  local restored,restoreError=true,nil
  if backup then restored,restoreError=os.rename(backup,path) end
  os.remove(temporary)
  return false,'Could not install startup script: '..tostring(moveError)..(not restored and ('\nRestore failed: '..tostring(restoreError)..'\nBackup: '..backup) or '')
 end
 return true
end
local function toggleStartup()
 local enabled=not startupEnabled()
 local ok,err=setStartupEnabled(enabled)
 status=ok and (enabled and 'Startup enabled. ArticulationBox will start with REAPER.' or 'Startup disabled.') or err
 if not ok then R.MB(status,'ArticulationBox startup',0) end
end

local function safeLabel(s) return (s:gsub('[|#!<>]',' '):gsub('&','&&')) end
local function prompt(caption,labels,values,count)
 local ok,result=R.GetUserInputs(caption,count,labels,values)
 if ok then return split(result,',') end
end
local function assignmentIdentity(a)
 return a.bank..'\t'..a.name..'\t'..config(a)
end
local function selectionState(readyScene)
 local editor=R.MIDIEditor_GetActive() local take=editor and R.MIDIEditor_GetTake(editor)
 take=take or controllers.editorTake()
 local default=defaultArt() local bankName=bank().name
 local state={take=take,total=0,none=0,buckets={},order={},notes={},label=default and default.name or '—'}
 if not take or not isMidiTake(take) then return state end
 local ok,scene=true,readyScene
 if not scene then ok,scene=pcall(read,take) end
 if not ok then state.error=tostring(scene) state.label='!' return state end
 for _,n in ipairs(scene.notes) do if n.sel and not n.generated and not n.keyswitchRow then
  state.total=state.total+1
  state.notes[#state.notes+1]=n
  if not n.a or n.a.implicit then state.none=state.none+1 end
  local a=n.manualArt or n.a
  if not a and default then
   a={bank=bankName} for k,v in pairs(default) do a[k]=v end
  end
  if a then
   local id=assignmentIdentity(a)
   if not state.buckets[id] then
    state.buckets[id]={a=a,count=0} state.order[#state.order+1]=id
   end
   state.buckets[id].count=state.buckets[id].count+1
  end
 end end
 if state.total>0 then state.label='—' end
 table.sort(state.order,function(a,b)
  local aa,bb=state.buckets[a].a,state.buckets[b].a
  if aa.name~=bb.name then return aa.name<bb.name end return a<b
 end)
 if #state.order==1 and state.buckets[state.order[1]].count==state.total then state.label=state.buckets[state.order[1]].a.name
 elseif #state.order>0 then state.label='Mixed' end
 return state
end
-- Scrolling and playback do not change MIDI. Keep the last field state instead
-- of decoding every note and notation marker through every observer each poll.
automaticHistory.observerState={}
function automaticHistory.rawSelection(data)
 -- Ignore only selection flags. Timing, notes, notation, CC and mute bytes
 -- remain part of the fingerprint; an actual edit always takes the full path.
 local events,plain,selected={}, {}, {}
 local offset,pos=1,0
 local ok=pcall(function()
  while offset<=#data do
   local first=offset
   local delta,flags,msg;delta,flags,msg,offset=string.unpack('<i4Bs4',data,offset)
   pos=pos+delta
   events[#events+1]={first=first,last=offset-1,pos=pos,flags=flags,msg=msg}
   plain[#plain+1]=data:sub(first,first+3)..string.char(flags&0xFE)..data:sub(first+5,offset-1)
   if #msg>=3 and msg:byte(1)&0xF0==0x90 and msg:byte(3)>0 then
    selected[key(pos,msg:byte(1)&15,msg:byte(2))]=flags&1~=0
   end
  end
 end)
 if not ok then return nil end
 return {plain=table.concat(plain),events=events,selected=selected}
end
function automaticHistory.selectionOnly(current,previous)
 if not previous.scene then return false end
 local raw=automaticHistory.rawSelection(current.data)
 local old=previous.selection or automaticHistory.rawSelection(previous.data)
 if not raw or not old or raw.plain~=old.plain then return false end
 local scene=previous.scene local musical=false local protected={}
 for _,n in ipairs(scene.notes) do
  if n.generated or n.keyswitchRow then
   protected[key(n.s,n.ch,n.p)]=true protected[key(n.e,n.ch,n.p)]=true
  elseif raw.selected[n.key] then musical=true end
 end
 local data=current.data
 if musical then
  local pieces={} local changed=false
  for _,ev in ipairs(raw.events) do
   local msg=ev.msg local keep=true
   if ev.flags&1~=0 then
    if #msg>=3 and (msg:byte(1)&0xF0==0x90 or msg:byte(1)&0xF0==0x80) then
     keep=not protected[key(ev.pos,msg:byte(1)&15,msg:byte(2))]
    elseif msg:sub(1,2)==string.char(0xFF,15) then
     local ch,p=msg:sub(3):match('^NOTE (%d+) (%d+) ')
     if ch then keep=not protected[key(ev.pos,tonumber(ch),tonumber(p))] end
    end
   end
   if keep then pieces[#pieces+1]=data:sub(ev.first,ev.last)
   else
    pieces[#pieces+1]=data:sub(ev.first,ev.first+3)..string.char(ev.flags&0xFE)..data:sub(ev.first+5,ev.last)
    changed=true
   end
  end
  if changed then
   local after=table.concat(pieces)
   if not R.MIDI_SetAllEvts(current.take,after) then return false end
   R.UpdateItemInProject(R.GetMediaItemTake_Item(current.take))
   automaticHistory.remember(current.take,data)
   data=after
  end
 end
 for _,n in ipairs(scene.notes) do n.sel=raw.selected[n.key] or false
  if musical and (n.generated or n.keyswitchRow) then n.sel=false end
 end
 cachedState=selectionState(scene)
 current.data=data current.scene=scene current.selection=raw
 -- The normalized bytes are unchanged by our selection-only write.
 automaticHistory.observerState=current
 return true
end
function automaticHistory.environment(take,project,changes)
 local saved=automaticHistory.tempoSnapshot
 if not saved or saved.project~=project or saved.changes~=changes then
  local values={R.Master_GetTempo and R.Master_GetTempo() or ''}
  if R.CountTempoTimeSigMarkers and R.GetTempoTimeSigMarker then
   for i=0,R.CountTempoTimeSigMarkers(project)-1 do
    local ok,time,measure,beat,bpm,num,den,linear=R.GetTempoTimeSigMarker(project,i)
    values[#values+1]=table.concat({tostring(ok),time,measure,beat,bpm,num,den,tostring(linear)},':')
   end
  end
  saved={project=project,changes=changes,signature=table.concat(values,'|')}
  automaticHistory.tempoSnapshot=saved
 end
 local item=R.GetMediaItemTake_Item(take)
 return table.concat({saved.signature,R.GetMediaItemInfo_Value(item,'D_POSITION'),R.GetMediaItemInfo_Value(item,'D_LENGTH'),
  R.GetMediaItemTakeInfo_Value and R.GetMediaItemTakeInfo_Value(take,'D_STARTOFFS') or 0,
  R.GetMediaItemTakeInfo_Value and R.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE') or 1},'|')
end
function automaticHistory.observerStamp()
 local take=activeTake() if not take then return nil end
 local project=R.EnumProjects and R.EnumProjects(-1,'') or 0
 local ok,data=R.MIDI_GetAllEvts(take,'')
 if not ok then return nil end
 local current=bank()
 local changes=R.GetProjectStateChangeCount and R.GetProjectStateChangeCount(project)
 local settings=table.concat({tostring(bankIndex),R.GetExtState(SECTION,'autoStagger'),R.GetExtState(SECTION,'staggerMs'),R.GetExtState(SECTION,'ksOverlap'),R.GetExtState(SECTION,'ksLengthMode'),R.GetExtState(SECTION,'nameKeyswitchRows')},'\n')
 return {take=take,project=project,data=data,bank=current,banks=loadedBankData,settings=settings,
  environment=automaticHistory.environment(take,project,changes),changes=changes}
end
function automaticHistory.nativeEditBusy()
 -- Quantize has a live preview buffer. Writing MIDI while it is open races
 -- that buffer and native Fix overlaps, so reconcile once the dialog closes.
 local window=R.JS_Window_Find and R.JS_Window_Find('Quantize Events',true)
 return window and (not R.JS_Window_IsVisible or R.JS_Window_IsVisible(window)) or false
end
function automaticHistory.pollObservers(force)
 if (R.JS_Mouse_GetState and R.JS_Mouse_GetState(1)&1~=0) or automaticHistory.nativeEditBusy() then automaticHistory.observerState.pending=true return end
 local current=automaticHistory.observerStamp()
 if not current then automaticHistory.observerState={} return end
 local previous=automaticHistory.observerState
 local sameContext=previous.take==current.take and previous.project==current.project
  and previous.bank==current.bank and previous.banks==current.banks and previous.settings==current.settings
  and previous.environment==current.environment
 if not force and sameContext then
  if previous.data==current.data then previous.pending=nil return end
  if automaticHistory.selectionOnly(current,previous) then return end
 end
 local take,data,scene=current.take,current.data,nil
 local function refreshScene()
  local got,updated=R.MIDI_GetAllEvts(take,'')
  if not got then scene=nil return end
  if scene and updated==data then return end
  data=updated
  local written=controllers.lastWrite
  if written and written.take==take and written.data==data then scene=written.scene
  else local ok,value=pcall(read,take) scene=ok and value or nil end
 end
 refreshScene()
 if scene then
  watchKeyswitchRows(scene,data) refreshScene()
  protectKeyswitchSelectionAndPitch(scene) refreshScene()
  watchDeletedSwitches(scene) refreshScene()
  watchMusicalEdits(scene) refreshScene()
 end
 rowNamesUpdate() cachedState=selectionState(scene)
 current=automaticHistory.observerStamp() or {}
 current.scene=scene
 automaticHistory.observerState=current
end
local function releaseIntercepts()
 if host and R.JS_Window_IsWindow(host) then
  for message in pairs(ownedIntercepts) do R.JS_WindowMessage_Release(host,message) end
 end
 ownedIntercepts={}
 if not gesture then leftPressed=false rightPressed=false end
end
local function unlink()
 releaseIntercepts()
 if host and bitmap and R.JS_Window_IsWindow(host) then R.JS_Composite_Unlink(host,bitmap,true) end
 host=nil currentLabel=nil gesture=nil
end
local function screenAnchor()
 if popupMode=='quick' then return R.GetMousePosition() end
 if host and R.JS_Window_IsWindow(host) then return R.JS_Window_ClientToScreen(host,box.x,box.y+box.h) end
 return R.GetMousePosition()
end
local function showNativeMenu(text)
 releaseIntercepts()
 local x,y=screenAnchor()
 local focus=R.JS_Window_GetFocus and R.JS_Window_GetFocus()
 if popupMode=='quick' then
  local title='ArticulationBox quick menu'
  gfx.init(title,0,0,0,x,y)
  gfx.x,gfx.y=0,0
  -- Keep the popup owner active, but hide its frame and macOS close button.
  local window=R.JS_Window_Find and R.JS_Window_Find(title,true)
  if window then R.JS_Window_SetOpacity(window,'ALPHA',0) end
  local n=gfx.showmenu(text)
  gfx.quit()
  if focus and R.JS_Window_IsWindow(focus) then R.JS_Window_SetFocus(focus) end
  return n
 end
 local wx,wy=x,y
 if host and R.JS_Window_IsWindow(host) then wx,wy=R.JS_Window_ClientToScreen(host,0,0) end
 gfx.init(popupTitle,24,0,0,wx+4,wy+4)
 gfx.x,gfx.y=gfx.screentoclient(x,y)
 if R.JS_Window_Find then
  local h=R.JS_Window_Find(popupTitle,true)
  if h then
   R.JS_Window_SetOpacity(h,'ALPHA',0)
   if R.GetOS():match('Other') then R.JS_Window_SetStyle(h,'POPUP') else R.JS_Window_Show(h,'HIDE') end
  end
 end
 if focus and R.JS_Window_SetFocus then R.JS_Window_SetFocus(focus) end
 local n=gfx.showmenu(text)
 gfx.quit()
 if focus and R.JS_Window_IsWindow(focus) then R.JS_Window_SetFocus(focus) end
 previousButtons=R.JS_Mouse_GetState and R.JS_Mouse_GetState(3) or 0
 refresh=0 menuIgnoreUntil=R.time_precise()+0.10
 return n
end
local function choose(labels)
 return showNativeMenu(table.concat(labels,'|'))
end
local function pickBank()
 loadTrackBanks()
 local names={} for i,b in ipairs(banks) do names[i]=(i==bankIndex and '!' or '')..safeLabel(b.name) end
 local n=choose(names) if n>0 then bankIndex=n save(false) end
end
local function articulationOrder()
 local arts=bank().arts local order={}
 for i in ipairs(arts) do order[#order+1]=i end
 table.sort(order,function(a,b)
  if arts[a].pitch~=arts[b].pitch then return arts[a].pitch>arts[b].pitch end
  return a<b
 end)
 return order
end
local function newArticulation()
 local a=defaults('','ks',1)
 a.lead=number(R.GetExtState(SECTION,'timingLead'),0.01,10000,false) or a.lead
 a.length=number(R.GetExtState(SECTION,'timingLength'),0.01,10000,false) or a.length
 local editor=R.MIDIEditor_GetActive()
 if editor and R.MIDIEditor_GetSetting_int then
  a.pitch=number(R.MIDIEditor_GetSetting_int(editor,'active_note_row'),0,127,true) or a.pitch
 end
 return a
end
local function bankNew()
 local f=prompt('New bank','Name,extrawidth=240','My library',1)
 if not f then return false end
 local name=f[1]:match('^%s*(.-)%s*$')
 if name=='' or name=='Empty bank' then
  R.MB('Enter a bank name other than Empty bank.','New bank',0) return false
 end
 for _,b in ipairs(banks) do if b.name==name then
  R.MB('A bank with this name already exists. Choose it from Banks or enter a different name.','New bank',0) return false
 end end
 banks[#banks+1]={name=name,arts={},controllers={}} bankIndex=#banks save()
 cachedState=nil refresh=0 currentLabel=nil
 status=name..' — bank created and selected.'
 return true
end
local function editArt(index)
 if editorBusy then return end
 local target=bank() local track=bankTrack
 if R.GetMediaItem_Track and not track then R.MB('Open a MIDI item on the destination track before editing its articulations.','ArticulationBox',0) return end
 if target.name=='Empty bank' then
  if not bankNew() then return end
  target=bank() track=bankTrack index=nil
 end
 local project=R.EnumProjects and R.EnumProjects(-1,'')
 local destinationEditor=R.MIDIEditor_GetActive() or host
 target.controllers=target.controllers or {}
 local function mapping(i) return i and (i>0 and target.arts[i] or target.controllers[-i]) end
 local function editorEntry(saved)
  local a=newArticulation()
  for k,v in pairs(saved or {}) do a[k]=v end
  local id=articulationGroups.key(a)
  a.groupName=id and (target.groupNames or {})[id] or nil
  a.grouped=articulationGroups.multiple(target,a)
  if a.grouped and not a.groupName then
   local best
   for _,other in ipairs(target.arts) do if articulationGroups.key(other)==id and (not best or other.velocity>best.velocity) then best=other end end
   a.groupName=best and best.name
  end
  return a
 end
 local source=mapping(index)
 local entry=editorEntry(source)
 local _,path=R.get_action_context()
 local folder=path:match('^(.*[\\/])') or ''
 local loaded,openEditor=pcall(dofile,folder..'Articulation_Editor.lua')
 if not loaded or type(openEditor)~='function' then
  R.MB('The articulation editor file is missing or could not load. Update the complete ArticulationBox package.\n\n'..tostring(openEditor),'ArticulationBox',0) return
 end
 local active=R.GetExtState(SECTION,'activeInstance')
 local function ready()
  if project and R.EnumProjects(-1,'')~=project then return false,'Return to the original project before saving this mapping.' end
  if R.MIDIEditor_GetActive() then loadTrackBanks() end
  if banks[bankIndex]~=target or bankTrack~=track or (track and not validPointer(track,'MediaTrack*')) then
   return false,'The active bank changed. Close this window and reopen it for the current track.'
  end
  return true
 end
 local function listMappings()
  local entries={}
  local order={} for i in ipairs(target.arts) do order[#order+1]=i end
  table.sort(order,function(i,j) if target.arts[i].pitch~=target.arts[j].pitch then return target.arts[i].pitch>target.arts[j].pitch end return i<j end)
  for _,i in ipairs(order) do
   local a=target.arts[i]
   local entry=editorEntry(a)
   entries[#entries+1]={index=i,entry=entry,label=a.name..(a.trigger=='end' and '  [Ending]' or '')..(a.mode~='ch' and ('  [KS '..a.pitch..', Vel '..a.velocity..']') or ('  [Ch '..a.channel..']'))}
  end
  for i,c in ipairs(target.controllers) do
   entries[#entries+1]={index=-i,entry=editorEntry(c),label=c.name..'  [Controller]'}
  end
  return entries
 end
 local function editorState(selected)
  return {bankName=target.name,entries=listMappings(),selected=selected or 0}
 end
 local function updateNames()
  rowNameSignature=nil rowNamesUpdate(track,target)
  if destinationEditor and R.JS_Window_IsWindow and R.JS_Window_IsWindow(destinationEditor) and R.JS_Window_InvalidateRect and R.JS_Window_GetClientSize then
   local view=R.JS_Window_FindChildByID and R.JS_Window_FindChildByID(destinationEditor,1001) or destinationEditor
   local ok,w,h=R.JS_Window_GetClientSize(view)
   if ok then R.JS_Window_InvalidateRect(view,0,0,w,h,false) end
  end
 end
 editorBusy=true
 controllers.editorContext={take=destinationEditor and R.MIDIEditor_GetTake(destinationEditor),editor=destinationEditor,project=project}
 local opened,ok,err=pcall(openEditor,R,{
  entry=entry,editing=index~=nil,bankName=target.name,selected=index or 0,entries=listMappings(),allowControllers=true,
  isAlive=function() return running and (popupMode or R.GetExtState(SECTION,'activeInstance')==active) end,
  onClose=function() editorBusy=false controllers.editorContext=nil end,
  onSelect=function(selected)
   local ok,why=ready() if not ok then return nil,why end
   if selected~=0 and not mapping(selected) then return nil,'This mapping was removed. Reopen the editor.' end
   index=selected~=0 and selected or nil
   source=mapping(index)
   return editorEntry(source)
  end,
  onSave=function(updated,nextEntry)
   local ok,why=ready() if not ok then return false,why end
   local standalone=updated.mode=='controller'
   if (standalone and (not updated.name:find('%S') or not controllers.enabled(updated) or not controllers.valid(updated))) or (not standalone and not valid(updated)) then return false,'Check the MIDI values and controller timing.' end
   if index and mapping(index)~=source then return false,'This mapping changed. Close this window and reopen it.' end
   if index and index>0 and (source.trigger=='end')~=(updated.trigger=='end') then index=nil source=nil end
   local id=articulationGroups.key(updated)
   if id and updated.grouped and (not updated.groupName or not updated.groupName:find('%S')) then return false,'Enter a group name.' end
   if id and updated.grouped then target.groupNames=target.groupNames or {};target.groupNames[id]=updated.groupName end
   updated.groupName=nil updated.grouped=nil
   if standalone then
    updated=controllers.copy(updated)
    if index and index<0 then target.controllers[-index]=updated
    else target.controllers[#target.controllers+1]=updated index=-#target.controllers end
    source=updated
   elseif index and index>0 then
    target.arts[index]=updated source=updated
    if target.default==index and (updated.mode=='ch' or updated.trigger=='end') then target.default=nil end
   else
    target.arts[#target.arts+1]=updated index=#target.arts source=updated
   end
   save() updateNames() cachedState=nil refresh=0 currentLabel=nil
   status=updated.name..' — mapping saved.'
   if nextEntry then index=nil source=nil end
   return true,editorState(index)
  end,
  onRemove=function()
   local ok,why=ready() if not ok then return false,why end
   if not index or mapping(index)~=source then return false,'Select a saved mapping first.' end
   local kind=index<0 and 'controller' or 'articulation'
   if R.MB('Remove '..kind..' mapping “'..source.name..'”? Existing MIDI assignments will be kept.','Remove '..kind,4)~=6 then return false end
   local name=source.name
   local nextEntry=index<0 and editorEntry(source) or newArticulation()
   nextEntry.name=''
   if index<0 then table.remove(target.controllers,-index)
   else
    table.remove(target.arts,index)
    if target.default==index then target.default=nil elseif target.default and target.default>index then target.default=target.default-1 end
   end
   index=nil source=nil save() updateNames() cachedState=nil refresh=0 currentLabel=nil
   status=name..' — mapping removed.'
   local result=editorState() result.entry=nextEntry
   return true,result
  end
 })
 if not opened then err=ok ok=false end
 if not ok then editorBusy=false controllers.editorContext=nil R.MB(tostring(err),'ArticulationBox',0) end
end
local function timingSettings()
 local f=prompt('Keyswitch timing for this bank','Timing distance (ms),Legacy length (ms),Legacy overlap (ms)',
  (R.GetExtState(SECTION,'timingLead')~='' and R.GetExtState(SECTION,'timingLead') or '1')..','..
  (R.GetExtState(SECTION,'timingLength')~='' and R.GetExtState(SECTION,'timingLength') or '1')..','..(R.GetExtState(SECTION,'ksOverlap')~='' and R.GetExtState(SECTION,'ksOverlap') or '1'),3)
 if not f then return end
 local lead,length,overlap=number(f[1],0.01,10000,false),number(f[2],0.01,10000,false),number(f[3],0,10000,false)
 if not lead or not length or not overlap then R.MB('Distance/length: 0.01–10000 ms; overlap: 0–10000 ms.','Keyswitch timing',0) return end
 local previous=R.GetExtState(SECTION,'ksOverlap') R.SetExtState(SECTION,'ksOverlap',tostring(overlap),true)
 if not retime(lead,length) then R.SetExtState(SECTION,'ksOverlap',previous,true) R.MB(status,'Keyswitch timing',0) return end
 for _,a in ipairs(bank().arts) do if a.mode~='ch' then a.lead=a.lead<0 and -lead or lead a.length=length end end
 save()
 R.SetExtState(SECTION,'timingLead',tostring(lead),true) R.SetExtState(SECTION,'timingLength',tostring(length),true)
 status='Bank timing saved; existing assignments for this bank in the active take were refreshed.'
end
local function export()
 local f=prompt('Export all banks','Full path',R.GetResourcePath()..'/Articulation_Manager_Banks.txt',1) if not f then return end
 local file,err=io.open(f[1],'w') if not file then status=tostring(err) return end
 file:write(serialize()) file:close() status='Banks exported.'
end
local function import()
 local ok,path=R.GetUserFileNameForRead('','Import banks','txt') if not ok then return end
 local file=io.open(path,'r') if not file then status='Could not open the file.' return end
 local parsed=parse(file:read('*a')) file:close()
 if not parsed then status='Invalid bank file format.' return end
 rememberLegacy(serialize())
 for _,b in ipairs(parsed) do
  banks[#banks+1]=b
  for _,a in ipairs(b.arts) do if a.mode~='ch' then legacyPatterns[#legacyPatterns+1]=a end end
 end
 bankIndex=#banks save()
 R.SetExtState(SECTION,'legacy',serialize(),true)
 status='Banks imported.'
end
local function bankRename()
 local f=prompt('Bank name','Name,extrawidth=240',bank().name,1)
 if f and f[1]~='' then
  local old=bank().name bank().name=f[1]
  for i=#presets,1,-1 do if presets[i].name==old then table.remove(presets,i) end end
  save()
 end
end
local function bankDelete()
 if R.MB('Remove bank mappings for “'..bank().name..'”? MIDI assignments will be preserved.','Bank',4)==6 then
  local name=bank().name
  for i=#presets,1,-1 do if presets[i].name==name then table.remove(presets,i) end end
  table.remove(banks,bankIndex) if #banks==0 then banks={{name='Empty bank',arts={}}} end bankIndex=1 save(false)
 end
end
local function sizeSettings()
 local f=prompt('Field size','Width,Height,Font size',boxWidth..','..boxHeight..','..fontSize,3)
 if not f then return end
 local w,h,font=number(f[1],90,600,true),number(f[2],18,60,true),number(f[3],8,28,true)
 if not w or not h or not font then status='Width 90–600; height 18–60; font size 8–28.' return end
 boxWidth=w boxHeight=h fontSize=font
 R.SetExtState(SECTION,'boxWidth',w,true) R.SetExtState(SECTION,'boxHeight',h,true) R.SetExtState(SECTION,'boxFont',font,true)
 currentLabel=nil
 if bitmap then if host then R.JS_Composite_Unlink(host,bitmap,true) end R.JS_LICE_DestroyBitmap(bitmap) bitmap=nil end
 if liceFont then R.JS_LICE_DestroyFont(liceFont) liceFont=nil end
end
local function positionSettings()
 if not host then status='Open the MIDI editor first.' return end
 local _,w=R.JS_Window_GetClientSize(host)
 local f=prompt('Position in MIDI editor','X from left,Bottom margin',R.GetExtState(SECTION,'attachX')~='' and (R.GetExtState(SECTION,'attachX')..','..R.GetExtState(SECTION,'attachBottom')) or math.floor(w*0.60)..',7',2)
 if not f then return end
 local x,bottom=number(f[1],0,100000,true),number(f[2],0,100000,true)
 if not x or not bottom then status='Enter non-negative whole-number coordinates.' return end
 R.SetExtState(SECTION,'attachX',x,true) R.SetExtState(SECTION,'attachBottom',bottom,true)
 currentLabel=nil
end
local function staggerDelaySettings()
 local f=prompt('Auto-stagger spacing','Delay (ms): 0.1–50',R.GetExtState(SECTION,'staggerMs')~='' and R.GetExtState(SECTION,'staggerMs') or '2',1)
 if not f then return end
 local delay=number(f[1],0.1,50,false)
 if not delay then R.MB('Enter a delay between 0.1 and 50 ms.','Auto-stagger',0) return end
 R.SetExtState(SECTION,'staggerMs',tostring(delay),true)
end
local function toggleStagger()
 local enabled=R.GetExtState(SECTION,'autoStagger')~='1'
 R.SetExtState(SECTION,'autoStagger',enabled and '1' or '0',true)
 status=enabled and 'Auto-stagger enabled: selected conflicting notes start later and become shorter; their ends stay fixed. Test playback with your library.' or 'Auto-stagger disabled.'
end
local function setDefaultArt(index)
 local previous=bank().default bank().default=index
 local take=activeTake()
 if take and not sync(true) then bank().default=previous R.MB(status,'Default articulation',0) return end
 save()
 status=index and ('Default articulation: '..bank().arts[index].name..'. Notes without overrides use it automatically.') or 'Default articulation disabled.'
end
local function defaultMenu()
 local entries={{label='None',checked=not bank().default,action=function() setDefaultArt(nil) end},{separator=true}}
 for _,i in ipairs(articulationOrder()) do local a=bank().arts[i] local index=i
  entries[#entries+1]={label=a.name,checked=bank().default==i,disabled=a.mode=='ch' or a.trigger=='end',action=function() setDefaultArt(index) end}
 end
 entries[#entries+1]={separator=true}
 entries[#entries+1]={label='Default requires a keyswitch mapping',disabled=true}
 return entries
end
local chaseCommand,chaseSection=nil,nil
local chaseLookedUp=false
local function findChaseAction()
 if chaseLookedUp then return chaseCommand,chaseSection end
 chaseLookedUp=true
 if not R.SectionFromUniqueID or not R.kbd_enumerateActions then return end
 for _,id in ipairs({0,32060}) do
  local section=R.SectionFromUniqueID(id)
  if section then
   local index=0
   while true do
    local command,name=R.kbd_enumerateActions(section,index)
    if not command or command==0 then break end
    name=name or (R.kbd_getTextFromCmd and R.kbd_getTextFromCmd(command,section)) or ''
    if name:lower():find('chase midi note%-ons in project playback') then chaseCommand=command chaseSection=id return command,id end
    index=index+1
   end
  end
 end
end
local function chaseEnabled()
 local command,section=findChaseAction()
 return command and R.GetToggleCommandStateEx and R.GetToggleCommandStateEx(section,command)==1 or false
end
local function toggleChase()
 local command,section=findChaseAction()
 if not command then R.MB('In the MIDI editor, enable Options > Chase MIDI note-ons in project playback.','Playback MIDI chase',0) return end
 if section==0 then R.Main_OnCommand(command,0)
 else local editor=R.MIDIEditor_GetActive() if editor then R.MIDIEditor_OnCommand(editor,command) end end
 status=chaseEnabled() and 'MIDI note chase enabled. Sustained keyswitches can be resent when playback starts inside them.' or 'MIDI note chase disabled.'
end

local function stop() running=false end
-- gfx menu indexes count leaf titles, including disabled headings, but not
-- separators/submenu headers. Build the callback map with exactly that rule.
local function compileMenu(entries)
 local parts,actions={},{}
 local function visit(items)
  for _,item in ipairs(items) do
   if item.separator then parts[#parts+1]=''
   elseif item.children then
    parts[#parts+1]='>'..safeLabel(item.label) visit(item.children) parts[#parts+1]='<'
   else
    parts[#parts+1]=(item.disabled and '#' or '')..(item.checked and '!' or '')..safeLabel(item.label)
    actions[#actions+1]=item.action or false
   end
  end
 end
 visit(entries)
 return table.concat(parts,'|'),actions
end
local function noteCount(n) return n..(n==1 and ' note' or ' notes') end
local function articulationEntries(state,endings)
 local menu,groups,emitted={},{},{}
 local current=bank()
 local order={}
 for _,i in ipairs(articulationOrder()) do
  local a=current.arts[i]
  if (a.trigger=='end')==(endings==true) then order[#order+1]=i end
 end
 local groupKey=articulationGroups.key
 for _,i in ipairs(order) do
  local a=current.arts[i] local id=groupKey(a)
  if id then
   groups[id]=groups[id] or {indices={},velocities={}}
   local group=groups[id]
   group.indices[#group.indices+1]=i group.velocities[a.velocity]=true
  end
 end
 for _,group in pairs(groups) do
  local variants=0 for _ in pairs(group.velocities) do variants=variants+1 end
  group.enabled=variants>1
  table.sort(group.indices,function(i,j)
   if current.arts[i].velocity~=current.arts[j].velocity then return current.arts[i].velocity>current.arts[j].velocity end
   return i<j
  end)
 end
 local function entry(index,variant)
  local a=current.arts[index]
  local saved={bank=current.name} for k,v in pairs(a) do saved[k]=v end
  local bucket=state.buckets[assignmentIdentity(saved)]
  local count=bucket and bucket.count or 0
  if endings then count=0;for _,n in ipairs(state.notes or {}) do if n.ending and n.ending.name==a.name and n.ending.pitch==a.pitch and n.ending.velocity==a.velocity then count=count+1 end end end
  local label=a.name..(variant and ('  [Vel '..a.velocity..']') or '')
  if count>0 and count<state.total then label=label..'  ('..noteCount(count)..')' end
  return {label=label,checked=count>0,disabled=state.total==0,action=function()
   if bank()~=current or current.arts[index]~=a then R.MB('The active bank changed. Open the menu again.','Articulation',0) return end
   local ok
   if endings then ok=articulationGroups.applyEnding(a) else ok=apply(a) end
   if not ok then R.MB(status,endings and 'Ending' or 'Articulation',0) end
  end}
 end
 for _,i in ipairs(order) do
  local a=current.arts[i] local id=groupKey(a) local group=id and groups[id]
  if group and group.enabled then
   if not emitted[id] then
    emitted[id]=true
    local children={} for _,index in ipairs(group.indices) do children[#children+1]=entry(index,true) end
    menu[#menu+1]={label=(current.groupNames or {})[id] or current.arts[group.indices[1]].name,children=children}
   end
  else menu[#menu+1]=entry(i,false) end
 end
 return menu
end
local function controllerEntries(state)
 local current=bank() local presets=current.controllers or {} local order={}
 local assigned=false
 for _,n in ipairs(state.notes or {}) do
  if #controllers.forNote(n)>0 then assigned=true break end
 end
 local function rank(c) return c.ctrl=='pitch' and -3 or c.ctrlCC==1 and -2 or c.ctrlCC==64 and -1 or c.ctrlCC end
 for i in ipairs(presets) do order[#order+1]=i end
 table.sort(order,function(i,j) if rank(presets[i])~=rank(presets[j]) then return rank(presets[i])<rank(presets[j]) end return i<j end)
 local menu={}
 for _,i in ipairs(order) do
  local c=presets[i] local count=0
  for _,n in ipairs(state.notes or {}) do
   for _,assigned in ipairs(controllers.forNote(n)) do if controllers.config(assigned)==controllers.config(c) then count=count+1 break end end
  end
  local label=c.name
  if count>0 and count<state.total then label=label..'  ('..noteCount(count)..')' end
  menu[#menu+1]={label=label,checked=count>0,disabled=state.total==0,action=function()
   if bank()~=current or current.controllers[i]~=c then R.MB('The active bank changed. Open the menu again.','Controller',0) return end
   if not applyController(c) then R.MB(status,'Controller',0) end
  end}
 end
 local available=#presets>0 or assigned
 if not available then
  for _,a in ipairs(current.arts) do if controllers.enabled(a) then available=true break end end
 end
 if available then
  if #menu>0 then menu[#menu+1]={separator=true} end
  menu[#menu+1]={label='Reset controllers',disabled=state.total==0 or not assigned,action=function()
   if not applyController(nil) then R.MB(status,'Controller',0) end
  end}
 end
 return menu
end
function articulationGroups.endingMenu(state)
 local entries=articulationEntries(state,true)
 local assigned=false for _,n in ipairs(state.notes or {}) do if n.ending then assigned=true break end end
 if #entries>0 or assigned then
  if #entries>0 then entries[#entries+1]={separator=true} end
  entries[#entries+1]={label='Clear ending',disabled=not assigned,action=function() if not articulationGroups.applyEnding(nil) then R.MB(status,'Ending',0) end end}
 end
 return entries
end
local function quickEntries(state)
 local menu=articulationEntries(state) local controls=controllerEntries(state)
 local endings=articulationGroups.endingMenu(state)
 if #endings>0 then table.insert(menu,1,{label='Ending',children=endings}) end
 if #controls>0 then
  if #menu>0 then table.insert(menu,1,{separator=true}) end
  table.insert(menu,1,{label='Controller',children=controls})
 end
 return menu
end
-- Offline help is built in so manual installations keep working without guide files.
local helpTopics={
 {title="Quick start",text=[[1. Open a MIDI item and keep Articulation_Manager.lua running.
2. Create a bank: Settings > Banks > New.
3. Add / Edit articulation: if Empty bank is selected, name and create a bank first. Then configure mappings. Use Save & Next to build a bank quickly.
4. Select musical notes, open the field menu and choose an articulation.
5. Optional: Default articulation for notes without an override.
6. Save the REAPER project.

Assign Articulation_Quick_Menu.lua to a MIDI Editor shortcut for ready articulation and controller choices at the mouse cursor.]]},
 {title="Articulations and defaults",text=[[Channel: routes musical notes to a channel.
Keyswitch: sends a MIDI note that selects a sound in your instrument.
KS + Channel: combines both methods.

Add / Edit articulation opens one compact parameter window. Bank shows the destination. Articulation selects Add New or a saved mapping. New names start empty. Add variant copies the selected name and settings into a new mapping, leaving the original intact. For keyswitch variants it first asks for a group name. Group name is shown when editing a velocity group and renames its submenu without changing variant names. Edit the copied name as needed; Save & Next still clears the name. Remove articulation deletes the selected mapping from this bank, preserving existing MIDI assignments. Keyswitch, Channel and KS + Channel show their relevant parameters and can include a linked Controller. Controller saves an independent preset. Ending saves a separate end-of-note keyswitch. Channel sets the musical-note channel; KS channel sets the keyswitch channel. KS channel 0 uses the musical note's channel.

Playing a MIDI key or clicking a piano-roll key automatically fills KS note and velocity. A mapped key also loads its saved name and parameters; an exact velocity match selects that variant. Both values remain editable. Save stores changes without closing the window. Save & Next stores the current mapping and always switches to Add New with an empty name and the current parameters. The last saved name stays visible. Piano-roll row names update immediately after every save. Cancel discards only the current unsaved entry. Resize the window by its edges; its size is remembered.

Mappings on the same keyswitch pitch and routing with different velocities are grouped in a submenu. Variants are sorted from higher to lower velocity; Group name sets the submenu title independently; older groups use the highest-velocity name until renamed. Each variant keeps its own name and velocity.

Select notes and choose a name to apply it. Clear articulation removes the explicit override; a configured default can apply again. Defaults require a keyswitch mapping.

The field shows the selected articulation, Mixed for different assignments, or a dash if none is assigned. With no notes selected, it shows the default name, if configured.]]},
 {title="Endings",text=[[Choose the Ending type in Add / Edit articulation and configure its KS note, velocity, channel and Delay. Only Ending-type presets appear in the Ending submenu. Select one to add an independent switch at the end of selected notes. Ordinary Keyswitch, Channel and KS + Channel mappings remain outside this menu. Select notes, choose a starting articulation such as Open or Slap, then select an Ending such as Slide Down. Ending is an independent assignment and does not replace the starting articulation or note channel.

Delay is the distance BEFORE note-off. The switch starts at least one MIDI tick before the musical end and ends with the note. Timing is clamped inside the note; notes too short for a separate ending are rejected without changes. Ending follows note moves and length edits while the manager runs.

Ending > Clear ending removes only the ending. Clear articulation removes only the primary override. Endings cannot be used as defaults. Their velocity and KS channel are independent of the musical note's velocity. MIDI channels still share one physical keyswitch timeline.

Changing an ending preset does not rewrite existing note snapshots: reapply it to selected notes. Save the project to retain assignments and the bank.]]},
 {title="Controllers",text=[[Choose Controller in Add / Edit articulation to save a named, independent preset. It appears under Controller in the full and quick menus. This submenu is also available to reset controllers linked to articulations or assigned to selected notes. Applying it preserves the selected notes' articulation. Other articulation types can include a linked Controller; choose None to leave it disabled.

The chooser starts with None (unassigned), followed by Pitch Bend, Mod Wheel (CC 1), Hold Pedal (CC 64), and the other CC numbers. Visiting Controller does not automatically assign Pitch Bend. CC values range from 0 to 127. Pitch Bend ranges from -8192 to 8191, with 0 at center. Hold Pedal normally uses 127 to hold and reset 0 to release.

Length: Full note sets the value before note-on and resets after note-off. Note start makes a short pulse across note-on. Note end sets the value while the note is still held and resets after note-off. Before and After set these margins in milliseconds, with at least one MIDI tick on either side. Reset value is the value sent at the end. Control channel 0 follows the musical note's channel.

Controllers follow musical note moves and length edits while the manager runs. At the item start, a note may move slightly later to leave room; at the end, the item may extend to play the reset. Undo/Redo keeps these changes together.

Controllers affect every sounding voice on their MIDI channel. Overlapping notes cannot have independent controller states on the same channel. A later assignment on the same controller lane replaces its earlier state. An independent preset overrides a linked controller on that lane until the articulation is applied again. Other controller lanes remain assigned.

Controller > Reset controllers removes all controller assignments from selected notes while preserving their articulation. The command is disabled when no selected notes have controllers. Settings > Clear controller assignments provides the same operation. Removing a preset from the bank preserves existing MIDI assignments. Controller presets are saved with this track's bank.]]},
 {title="Banks and saving",text=[[Banks selects the current track's bank. Settings > Banks creates, renames, removes, imports or exports banks. Export saves all banks of the current track.

Track banks are independent. New tracks start with Empty bank; saved bank templates remain available. Add / Edit articulation first asks you to create a named bank when Empty bank is selected; Cancel leaves the editor closed. The new bank is saved and selected before editing. Bank and articulation edits are saved automatically. Save the project to retain track bank choices and note assignments.

Appearance and common playback preferences persist between REAPER sessions. Timing changes also update the current bank's mappings.

Removing a bank or mapping does not erase existing MIDI assignments. Use Clear articulation on notes when you want to remove their overrides.]]},
 {title="Manual keyswitches",text=[[Draw or edit notes directly on mapped articulation rows. They are treated as manual switches and do not receive a default articulation. With no default, their last switch remains active until another switch. With a default configured, manual switches override notes in their drawn region; later unassigned notes return to the default.

A later switch shortens the earlier keyswitch at its start. Different switches at exactly the same time on one channel remain ambiguous.

Independently editing an automatic keyswitch's pitch, position, length or velocity makes it manual and removes its former automatic links. Musical notes are preserved. Move the musical note instead to keep an automatic link.]]},
 {title="Playback and timing",text=[[Trigger chooses Before note start or After note start. Delay (ms) sets the distance in milliseconds; Trigger chooses which side of the note start it applies to. Automatic keyswitches end with their musical notes, or sooner if another switch intervenes. Length/Overlap are legacy compatibility values.

For a loop ending, use After note start and a suitable Delay. KS velocity is independent of musical velocity: a chord with velocity 1 can trigger a keyswitch with velocity 100. The script preserves the chord velocity. MIDI tick resolution can impose a minimum delay.

Keyswitch timing updates the current bank and its assignments in the active take, preserving each mapping's Before/After direction; new articulations use the saved timing defaults.

Chase MIDI note-ons enables REAPER's option to resend sustained notes when playback starts inside them. Test the result with your instrument.

Auto-stagger conflicting notes delays conflicting musical starts slightly and shortens notes by the same amount, keeping their ends fixed. Spacing sets the delay in ms. It does not provide independent simultaneous articulations on one MIDI channel.]]},
 {title="Editing and transposition",text=[[Keep the main script running while editing. Moving or resizing musical notes updates their linked automatic keyswitches. Returning notes to the same articulation can restore starts previously delayed by auto-stagger.

At the item start, or with auto-stagger enabled when neighboring starts leave no MIDI tick for a switch, a musical note can move slightly later to leave room for a Before keyswitch; its end stays fixed. After keyswitches do not require this advance space.

Broad selection/transposition protects keyswitch pitches while musical notes change pitch. With item/take pitch changes, the script writes the transpose into musical notes and resets the take pitch control, so the P+ value may disappear.

Use REAPER Undo to reverse an edit. Protection and following require the running main script.]]},
 {title="Tools and troubleshooting",text=[[Name keyswitch rows labels piano-roll rows from the bank.
Refresh keyswitches rebuilds automatic switches in the active take from assignments.
Clear missing keyswitch assignments removes stale links after switches were deleted; a default may then apply.
Legacy keyswitches > Find for review selects possible older switches. Review the selection before Remove reviewed; manual switches can match too.
Status shows the latest operation message.

The parameter editor requires ReaImGui, installed through ReaPack. Restart REAPER after installing the extension.

No sounds change: check the instrument mapping, MIDI channel and velocity. Empty menu: choose this track's bank and add mappings. The quick menu has no settings: use the field or Articulation_Menu_Popup.lua for Help and Settings.]]},
 {title="Field, actions and startup",text=[[Articulation_Manager.lua runs the embedded field and background updates.
Articulation_Quick_Menu.lua opens ready articulation choices and saved Controller presets at the mouse cursor.
Articulation_Menu_Popup.lua opens the full menu.

Lock position prevents moving/resizing the field. Turn it off to drag the field or its edges. Appearance and position also offers numeric position, size and font settings.
Run script on startup starts the main script with REAPER. Close field stops it for this session; disable startup separately if needed.

Detailed English and Russian guides are included as USER_GUIDE.md and USER_GUIDE_RU.md beside the scripts and linked from the GitHub README.]]},
}
local function helpMenu()
 local entries={}
 for _,topic in ipairs(helpTopics) do
  local selected=topic
  entries[#entries+1]={label=selected.title..'…',action=function() R.MB(selected.text,'ArticulationBox — '..selected.title,0) end}
 end
 entries[#entries+1]={separator=true}
 entries[#entries+1]={label='Status…',action=function() R.MB(status,'ArticulationBox — Status',0) end}
 return entries
end
local function buildMenu(state)
 local menu={}
 menu[#menu+1]={label=bank().name,disabled=true}
 if defaultArt() then menu[#menu+1]={label='Default: '..defaultArt().name,disabled=true} end
 menu[#menu+1]={separator=true}
 menu[#menu+1]={label='Clear articulation'..(state.none>0 and state.none<state.total and ('  ('..noteCount(state.none)..')') or ''),checked=state.total>0 and state.none==state.total,disabled=state.total==0,action=clear}
 menu[#menu+1]={separator=true}
 menu[#menu+1]={label='Add / Edit articulation…',action=function() editArt() end}
 menu[#menu+1]={separator=true}
 local articulationMenu=articulationEntries(state)
 if #articulationMenu==0 then articulationMenu={{label='No articulations in this bank',disabled=true}} end
 menu[#menu+1]={label='Articulations',children=articulationMenu}
 local endings=articulationGroups.endingMenu(state)
 if #endings>0 then menu[#menu+1]={label='Ending',children=endings} end
 local controllerMenu=controllerEntries(state)
 if #controllerMenu>0 then menu[#menu+1]={label='Controller',children=controllerMenu} end
 local bankEntries={}
 for i,b in ipairs(banks) do local index=i
  bankEntries[#bankEntries+1]={label=b.name,checked=i==bankIndex,action=function() bankIndex=index save(false) end}
 end
 menu[#menu+1]={separator=true}
 menu[#menu+1]={label='Banks',children=bankEntries}
 menu[#menu+1]={label='Default articulation',disabled=bank().name=='Empty bank',children=bank().name~='Empty bank' and defaultMenu() or nil}
 menu[#menu+1]={label='Settings',children={
  {label='Banks',children={{label='New…',action=bankNew},{label='Rename…',action=bankRename},{label='Remove…',action=bankDelete},{separator=true},{label='Import…',action=import},{label='Export…',action=export}}},
  {label='Appearance and position',children={{label='Field position…',action=positionSettings},{label='Size and font…',action=sizeSettings}}},
  {label='Legacy keyswitches',children={{label='Find for review',action=findLegacy},{label='Remove reviewed',action=deleteLegacy}}},
  {separator=true},
  {label='Name keyswitch rows',checked=R.GetExtState(SECTION,'nameKeyswitchRows')~='0',action=toggleRowNames},
  {label='Keyswitch timing…',action=timingSettings},
  {label='Chase MIDI note-ons',checked=chaseEnabled(),action=toggleChase},
  {label='Auto-stagger conflicting notes',checked=R.GetExtState(SECTION,'autoStagger')=='1',action=toggleStagger},
  {label='Auto-stagger spacing…',action=staggerDelaySettings},
  {label='Clear missing keyswitch assignments',action=function() if not clearMissingAssignments() then R.MB(status,'Missing keyswitch assignments',0) end end},
  {label='Clear controller assignments',disabled=state.total==0,action=function() if not applyController(nil) then R.MB(status,'Controller',0) end end},
  {label='Refresh keyswitches',action=function() if not sync() then R.MB(status,'Refresh keyswitches',0) end end},
  {label='Status…',action=function() R.MB(status,'ArticulationBox — Status',0) end},
  {separator=true},
  {label='Run script on startup',checked=startupEnabled(),action=toggleStartup},
  {label='Close field',action=stop}
 }}
 menu[#menu+1]={label='Help',children=helpMenu()}
 menu[#menu+1]={separator=true}
 menu[#menu+1]={label='Lock position',checked=positionLocked,action=togglePositionLock}
 return menu
end
local function artMenu()
 local state=selectionState()
 if state.error then R.MB(state.error,'MIDI assignments',0) return end
 local entries=popupMode=='quick' and quickEntries(state) or buildMenu(state)
 if #entries==0 then R.MB('No articulations in this track\'s bank.','Articulation',0) return end
 local text,actions=compileMenu(entries)
 local n=showNativeMenu(text)
 if n>0 and actions[n] then actions[n]() end
 cachedState=nil refresh=0 currentLabel=nil
end
local function pixelRatio()
 if not R.GetOS():match('OS') then return 1 end
 local _,dpi=R.ThemeLayout_GetLayout('trans',-3)
 local _,ui=R.get_config_var_string('ui_scale')
 return math.max(1,(tonumber(dpi) or 512)/256/(tonumber(ui) or 1))
end
local function roundedFill(bm,x,y,w,h,r,color)
 R.JS_LICE_FillRect(bm,x+r,y,w-2*r,h,color,1,'COPY')
 R.JS_LICE_FillRect(bm,x,y+r,r,h-2*r,color,1,'COPY')
 R.JS_LICE_FillRect(bm,x+w-r,y+r,r,h-2*r,color,1,'COPY')
 for _,pt in ipairs({{x+r,y+r},{x+w-r-1,y+r},{x+r,y+h-r-1},{x+w-r-1,y+h-r-1}}) do R.JS_LICE_FillCircle(bm,pt[1],pt[2],r,color,1,'COPY',true) end
end
local bitmapWidth,bitmapHeight
local function draw(label,hover)
 local ratio=pixelRatio() local bw,bh=round(box.w*ratio),round(box.h*ratio)
 if bitmap and (bitmapWidth~=bw or bitmapHeight~=bh) then
  R.JS_Composite_Unlink(host,bitmap,true) R.JS_LICE_DestroyBitmap(bitmap) bitmap=nil
  if liceFont then R.JS_LICE_DestroyFont(liceFont) liceFont=nil end
 end
 if not bitmap then
  bitmapWidth=bw bitmapHeight=bh
  bitmap=R.JS_LICE_CreateBitmap(true,bw,bh)
  liceFont=R.JS_LICE_CreateFont()
  local gdi=R.JS_GDI_CreateFont(round(fontSize*ratio),0,0,false,false,false,'Arial')
  R.JS_LICE_SetFontFromGDI(liceFont,gdi,'') R.JS_GDI_DeleteObject(gdi)
 end
 R.JS_LICE_Clear(bitmap,0)
 roundedFill(bitmap,0,0,bw,bh,round(5*ratio),hover and 0xFF303030 or 0xFF242424)
 local purple=0xFF9F76FF local gray=0xFF4C4C4C local white=0xFFD5D5D5
 local scale=function(v) return round(v*ratio) end
 local cy=bh/2
 -- Small musical note and divider, in the visual style of Gridbox.
 R.JS_LICE_FillCircle(bitmap,scale(10),cy+scale(4),scale(3),purple,1,'COPY',true)
 R.JS_LICE_FillRect(bitmap,scale(12),round(cy-scale(7)),scale(2),scale(11),purple,1,'COPY')
 R.JS_LICE_FillRect(bitmap,scale(12),round(cy-scale(7)),scale(5),scale(2),purple,1,'COPY')
 R.JS_LICE_FillRect(bitmap,scale(25),scale(5),math.max(1,scale(1)),bh-scale(10),gray,1,'COPY')
 R.JS_LICE_SetFontColor(liceFont,white)
 gfx.setfont(1,'Arial',round(fontSize*ratio))
 local maxWidth=bw-scale(49)
 local displayed=label
 local textW,textH=gfx.measurestr(displayed)
 if textW>maxWidth then
  -- Trim at UTF-8 codepoint boundaries, not bytes.
  local codepoints={} for _,code in utf8.codes(label) do codepoints[#codepoints+1]=utf8.char(code) end
  repeat table.remove(codepoints) displayed=table.concat(codepoints)..'…' textW,textH=gfx.measurestr(displayed) until textW<=maxWidth or #codepoints==0
 end
 R.JS_LICE_DrawText(bitmap,liceFont,displayed,#displayed,scale(32),round((bh-textH)/2),bw-scale(16),bh)
 R.JS_LICE_FillTriangle(bitmap,bw-scale(11),round(cy-scale(2)),bw-scale(5),round(cy-scale(2)),bw-scale(8),round(cy+scale(2)),white,1,'COPY')
 R.JS_Composite(host,box.x,box.y,box.w,box.h,bitmap,0,0,bw,bh,true)
 R.JS_Window_InvalidateRect(host,box.x,box.y,box.x+box.w,box.y+box.h,false)
 if not positionLocked then
  R.JS_LICE_Line(bitmap,scale(3),scale(1),bw-scale(4),scale(1),purple,0.65,'COPY',false)
  R.JS_LICE_Line(bitmap,scale(3),bh-scale(2),bw-scale(4),bh-scale(2),purple,0.65,'COPY',false)
  R.JS_Composite(host,box.x,box.y,box.w,box.h,bitmap,0,0,bw,bh,true)
 end
 currentLabel=label lastHover=hover
end
local function startIntercepts()
 if next(ownedIntercepts) then return true end
 local _,list=R.JS_WindowMessage_ListIntercepts(host)
 local messages={'WM_SETCURSOR','WM_LBUTTONDOWN','WM_LBUTTONUP','WM_LBUTTONDBLCLK','WM_RBUTTONDOWN','WM_RBUTTONUP'}
 for _,message in ipairs(messages) do if (list or ''):find(message..':',1,true) then
  status='Another panel is capturing mouse input in this window. Adjust its placement.' return false
 end end
 for _,message in ipairs(messages) do
  if R.JS_WindowMessage_Intercept(host,message,false)==1 then ownedIntercepts[message]=true
  else releaseIntercepts() return false end
 end
 return true
end
local cursors={}
if R.JS_Mouse_LoadCursor then
 local os=R.GetOS() local linux=os:match('Other')
 cursors.normal=R.JS_Mouse_LoadCursor(os:match('Win') and 32512 or 0)
 cursors.move=R.JS_Mouse_LoadCursor(32646)
 cursors.horizontal=R.JS_Mouse_LoadCursor(32644) cursors.vertical=R.JS_Mouse_LoadCursor(32645)
 cursors.diag1=R.JS_Mouse_LoadCursor(linux and 32642 or 32643)
 cursors.diag2=R.JS_Mouse_LoadCursor(linux and 32643 or 32642)
end
local function pointerCursor(flags)
 if not R.JS_Mouse_SetCursor then return end
 local cursor=cursors.normal
 if not positionLocked then
  if flags==0 then cursor=cursors.move
  elseif flags==3 or flags==12 then cursor=cursors.diag2
  elseif flags==6 or flags==9 then cursor=cursors.diag1
  elseif flags&5~=0 then cursor=cursors.horizontal else cursor=cursors.vertical end
 end
 if cursor then R.JS_Mouse_SetCursor(cursor) end
end
local function exitUI()
 if gesture and host then local ok,_,h=R.JS_Window_GetClientSize(host) if ok then saveLayout(h) end end
 if cursors.normal and R.JS_Mouse_SetCursor then R.JS_Mouse_SetCursor(cursors.normal) end
 unlink()
 if bitmap then R.JS_LICE_DestroyBitmap(bitmap) end
 if liceFont then R.JS_LICE_DestroyFont(liceFont) end
 gfx.quit()
 if sec and cmd and not popupMode then R.SetToggleCommandState(sec,cmd,0) R.RefreshToolbar2(sec,cmd) end
end
R.atexit(exitUI)
if popupMode then
 host=R.MIDIEditor_GetActive()
 if host and R.JS_Window_IsWindow(host) then
  local ok,w,h=R.JS_Window_GetClientSize(host)
  if ok then
   box.w=boxWidth box.h=boxHeight
   box.x=math.min(tonumber(R.GetExtState(SECTION,'attachX')) or math.floor(w*0.60),math.max(0,w-box.w))
   box.y=math.max(0,h-box.h-(tonumber(R.GetExtState(SECTION,'attachBottom')) or 7))
  end
 end
 R.defer(artMenu) return
end
local instanceToken=tostring({})..':'..tostring(R.time_precise())
R.SetExtState(SECTION,'activeInstance',instanceToken,false)
if sec and cmd then R.SetToggleCommandState(sec,cmd,1) R.RefreshToolbar2(sec,cmd) end
automaticHistory.transposeCheckTime=0
local function loop()
 if not running or R.GetExtState(SECTION,'activeInstance')~=instanceToken then return end
 if R.time_precise()>automaticHistory.transposeCheckTime then
  if not automaticHistory.nativeEditBusy() then automaticHistory.restore() watchItemTranspose() end
  automaticHistory.transposeCheckTime=R.time_precise()+0.20
 end
 local editor=R.MIDIEditor_GetActive()
 if not editor and controllers.editorTake() then
  local context=controllers.editorContext
  if context.editor and R.JS_Window_IsWindow(context.editor) then editor=context.editor end
 end
 if editor~=host then unlink() host=editor end
 if host and R.JS_Window_IsWindow(host) then
  local ok,w,h=R.JS_Window_GetClientSize(host)
  if ok then
   local bx=math.min(tonumber(R.GetExtState(SECTION,'attachX')) or math.floor(w*0.60),math.max(0,w-boxWidth))
   local by=math.max(0,h-boxHeight-(tonumber(R.GetExtState(SECTION,'attachBottom')) or 7))
   if not gesture and (box.x~=bx or box.y~=by or box.w~=boxWidth or box.h~=boxHeight) then
    if bitmap then R.JS_Composite_Unlink(host,bitmap,true) end
    box.x=bx box.y=by box.w=boxWidth box.h=boxHeight currentLabel=nil
   end
   if R.time_precise()>refresh then automaticHistory.pollObservers(cachedState==nil) refresh=R.time_precise()+0.20 end
   local sx,sy=R.GetMousePosition()
   local mx,my=R.JS_Window_ScreenToClient(host,sx,sy)
   local mouseWindow=R.JS_Window_FromPoint(sx,sy)
   local hover=mouseWindow==host and mx>=box.x and mx<box.x+box.w and my>=box.y and my<box.y+box.h
   local buttons=R.JS_Mouse_GetState(3)
   local wasHover=lastHover
   local captures=(hover or gesture) and startIntercepts()
   if not hover and not gesture then
    if wasHover and cursors.normal and R.JS_Mouse_SetCursor then R.JS_Mouse_SetCursor(cursors.normal) end
    releaseIntercepts()
   end
   local clicked=false
   if captures and R.time_precise()>=menuIgnoreUntil then
    local available,_,when=R.JS_WindowMessage_Peek(host,'WM_LBUTTONDOWN')
    if available and when and when>lastDownTime then
     lastDownTime=when
     if hover then leftPressed=true end
     if hover and not positionLocked then
      gesture={mx=mx,my=my,flags=edgeFlags(mx,my),start={x=box.x,y=box.y,w=box.w,h=box.h},moved=false}
     end
    end
    if gesture then
     local dx,dy=mx-gesture.mx,my-gesture.my
     if gesture.moved or math.abs(dx)>2 or math.abs(dy)>2 then
      gesture.moved=true
      local rect=gestureRect(gesture.start,gesture.flags,dx,dy,w,h)
      if box.x~=rect.x or box.y~=rect.y or box.w~=rect.w or box.h~=rect.h then
       if bitmap then R.JS_Composite_Unlink(host,bitmap,true) end
       box.x=rect.x box.y=rect.y box.w=rect.w box.h=rect.h
       boxWidth=box.w boxHeight=box.h currentLabel=nil
      end
     end
    end
    local up,_,upTime=R.JS_WindowMessage_Peek(host,'WM_LBUTTONUP')
    local newUp=up and upTime and upTime>lastLeftUpTime
    if newUp then lastLeftUpTime=upTime end
    if gesture and (newUp or buttons&1==0) then
     local wasGesture=gesture
     saveLayout(h) gesture=nil
     clicked=hover and not wasGesture.moved and wasGesture.flags==0
    elseif newUp and hover and leftPressed then clicked=true end
    if newUp then leftPressed=false end
    local rightDown,_,rightDownTime=R.JS_WindowMessage_Peek(host,'WM_RBUTTONDOWN')
    if rightDown and rightDownTime and rightDownTime>lastRightDownTime then
     lastRightDownTime=rightDownTime if hover then rightPressed=true end
    end
    local right,_,rightTime=R.JS_WindowMessage_Peek(host,'WM_RBUTTONUP')
    if right and rightTime and rightTime>lastRightUpTime then
     lastRightUpTime=rightTime if hover and not gesture and rightPressed then clicked=true end rightPressed=false
    end
   end
   if hover or gesture then pointerCursor(gesture and gesture.flags or edgeFlags(mx,my)) end
   if (currentLabel~=(cachedState and cachedState.label or '—')) or hover~=lastHover then draw(cachedState and cachedState.label or '—',hover) end
   if clicked then artMenu() buttons=R.JS_Mouse_GetState(3) end
   previousButtons=buttons
  end
 elseif host then unlink() end
 R.defer(loop)
end
loop()
