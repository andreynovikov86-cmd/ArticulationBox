-- @description ArticulationBox
-- @version 1.0.3
-- @author Andrey Novikov
-- @provides
--   [main=main,midi_editor] .
--   [main=midi_editor] Articulation_Quick_Menu.lua
--   [main=midi_editor] Articulation_Menu_Popup.lua
--   [nomain] THIRD_PARTY_NOTICES.txt
--   [nomain] INSTALL_RU.txt
--   [nomain] USER_GUIDE.md
--   [nomain] USER_GUIDE_RU.md
--   [nomain] LICENSE.md
-- @about
--   Compact articulation field for REAPER MIDI Editor.
--   Requires js_ReaScriptAPI, installed separately through ReaPack.
--   Supports per-track banks, keyswitches and MIDI channels.
--   Personal banks are stored outside this package and are not distributed.
--   Licensed under MIT; see LICENSE.md and THIRD_PARTY_NOTICES.txt.
-- @changelog
--   Include the MIT license in the package and retain third-party notices.

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
local function valid(a)
 return a.name and a.name~='' and (a.mode=='ch' or a.mode=='ks' or a.mode=='both')
  and number(a.channel,1,16,true) and number(a.pitch,0,127,true)
  and number(a.velocity,1,127,true) and number(a.lead,0.01,10000,false)
  and number(a.length,0.01,10000,false) and number(a.kschannel,0,16,true)
end
local function defaults(name,mode,ch)
 return {name=name,mode=mode,channel=ch,pitch=24,velocity=100,lead=1,length=1,kschannel=0}
end
local function parse(data)
 if data:sub(1,5)=='ABP1:' then data=unhex(data:sub(6)) if not data then return nil end end
 local result,b={},nil
 for line in data:gmatch('[^\r\n]+') do
  local f=split(line,'\t')
  if f[1]=='B' and f[2] and f[2]~='' then b={name=dec(f[2]),arts={},default=tonumber(f[3]),ksLengthMode=f[4]=='follow' and 'follow' or 'short',overlap=tonumber(f[5])} result[#result+1]=b
  elseif b and (f[1]=='A' or f[1]=='C' or f[1]=='D') then
   local a
   if f[1]=='C' then a=defaults(dec(f[2] or ''),'ch',tonumber(f[3]))
   else a={name=dec(f[2] or ''),mode=f[3],channel=tonumber(f[4]),pitch=tonumber(f[5]),velocity=tonumber(f[6]),lead=tonumber(f[7]),length=tonumber(f[8]),kschannel=tonumber(f[9]) or (f[1]=='A' and tonumber(f[4]) or nil)} end
   if not valid(a) then return nil end b.arts[#b.arts+1]=a
  else return nil end
 end
 for _,bank in ipairs(result) do
  if bank.overlap and not number(bank.overlap,0,10000,false) then return nil end
  if bank.default and (not number(bank.default,1,#bank.arts,true) or bank.arts[bank.default].mode=='ch') then return nil end
 end
 return #result>0 and result or nil
end
local function serialize(collection)
 local lines={}
 for _,b in ipairs(collection or banks) do
  lines[#lines+1]='B\t'..enc(b.name)..((b.default or b.ksLengthMode or b.overlap) and table.concat({'',b.default or '',b.ksLengthMode or 'short',b.overlap or 0},'\t') or '')
  for _,a in ipairs(b.arts) do lines[#lines+1]=table.concat({'D',enc(a.name),a.mode,a.channel,a.pitch,a.velocity,a.lead,a.length,a.kschannel},'\t') end
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
 return hex(table.concat(values,'|'))
end
local function assignment(s)
 local raw=unhex(s) if not raw then return nil end
 local f=split(raw,'|')
 local a={mode=f[1],base=tonumber(f[2]),channel=tonumber(f[3]),pitch=tonumber(f[4]),velocity=tonumber(f[5]),lead=tonumber(f[6]),length=tonumber(f[7]),kschannel=tonumber(f[8]),bank=unhex(f[9] or ''),name=unhex(f[10] or '')}
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
local function extractMarker(tail)
 local user=userValue(tail) if not user then return nil,tail end
 local marker=user:match('^'..ART..':(%x+)$')
 if marker then return marker,setUser(tail,nil) end
 marker=user:match('~'..ART..':(%x+)$')
 if marker then return marker,setUser(tail,user:gsub('~'..ART..':%x+$','')) end
 return nil,tail
end
local function appendMarker(tail,data)
 local user=userValue(tail)
 return setUser(tail,(user and user~='' and (user..'~') or '')..ART..':'..data)
end
local function key(s,ch,p) return string.format('%.6f:%d:%d',s,ch,p) end
local function round(v) return math.floor(v+0.5) end
local function activeTake()
 local editor=R.MIDIEditor_GetActive() local take=editor and R.MIDIEditor_GetTake(editor)
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
local function read(take)
 local ok,count,_,textCount=R.MIDI_CountEvts(take) if not ok then error('Could not read MIDI.') end
 local scene={notes={},texts={},bykey={},groups={},generated={}}
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
    t.ownedKS=userValue(tail)==KS..':1'
    t.manualKS=userValue(tail)==KS..':manual'
    t.managed=marker~=nil or t.ownedKS
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
     end
    end
   end
  end
 end
 local rows=keyswitchRows()
 for _,n in ipairs(scene.notes) do n.keyswitchRow=not n.generated and (n.manualKS or rows[n.ch..':'..n.p]) or false end
 -- Untagged notes on mapped rows are manual switches. Their last note-on wins
 -- until an explicit automatic assignment is encountered on that channel.
 local controls,explicit={},{}
 for _,n in ipairs(scene.notes) do
  if n.keyswitchRow and not n.mute then
   local a
   for _,mapped in ipairs(bank().arts) do
    local ch=mapped.kschannel==0 and (mapped.mode=='both' and mapped.channel-1 or n.ch) or mapped.kschannel-1
    if mapped.mode~='ch' and mapped.pitch==n.p and ch==n.ch then
     a={bank=bank().name} for k,v in pairs(mapped) do a[k]=v end break
    end
   end
   a=a or {bank=bank().name,name='KS '..n.p,mode='ks',channel=n.ch+1,pitch=n.p,velocity=n.v,lead=1,length=1,kschannel=n.ch+1}
   controls[n.ch]=controls[n.ch] or {} controls[n.ch][#controls[n.ch]+1]={s=n.s,a=a}
  elseif not n.generated and n.a and not n.a.implicit and n.a.mode~='ch' and not n.mute then
   local ch=n.a.kschannel==0 and n.ch or n.a.kschannel-1
   explicit[ch]=explicit[ch] or {} explicit[ch][#explicit[ch]+1]=n.s
  end
 end
 for _,n in ipairs(scene.notes) do if not n.generated and not n.keyswitchRow then
  local ch=n.a and n.a.mode~='ch' and n.a.kschannel~=0 and n.a.kschannel-1 or n.ch
  local latest,reset
  for _,ev in ipairs(controls[ch] or {}) do if ev.s<=n.s and (not latest or ev.s>latest.s) then latest=ev end end
  for _,pos in ipairs(explicit[ch] or {}) do if pos<n.s and (not reset or pos>reset) then reset=pos end end
  if latest and (not reset or latest.s>reset) then
   n.manualSignal=latest.a
   if not n.a or n.a.implicit then n.manualArt=latest.a end
  end
 end end
 return scene
end
local function config(a)
 return table.concat({a.mode,a.channel,a.pitch,a.velocity,a.lead,a.length,a.kschannel},':')
end
-- Per-track ownership preserves prior names independently for every channel.
local rowNameTrack,rowNameSignature=nil,nil
local rowNameKey='P_EXT:ABART_ROW_NAMES'
local function rowNamesUpdate()
 if not R.GetMediaItem_Track or not R.SetTrackMIDINoteNameEx or not R.GetTrackMIDINoteNameEx or not R.GetSetMediaTrackInfo_String then return end
 local editor=R.MIDIEditor_GetActive() local take=editor and R.MIDIEditor_GetTake(editor)
 if not take or not isMidiTake(take) then return end
 local track=R.GetMediaItem_Track(R.GetMediaItemTake_Item(take))
 loadTrackBanks()
 local enabled=R.GetExtState(SECTION,'nameKeyswitchRows')~='0'
 local signature=tostring(enabled)..':'..bankIndex..':'..serialize()
 if track==rowNameTrack and signature==rowNameSignature then return end
 local _,stored=R.GetSetMediaTrackInfo_String(track,rowNameKey,'',false)
 local owned={}
 for line in (stored or ''):gmatch('[^\r\n]+') do
  local f=split(line,'\t') local pitch=number(f[1],0,127,true) local channel=number(f[2],0,15,true)
  if pitch and channel and f[3] and f[4] then owned[pitch..':'..channel]={pitch=pitch,channel=channel,previous=dec(f[3]),applied=dec(f[4])} end
 end
 local wanted={}
 if enabled then for _,a in ipairs(bank().arts) do if a.mode~='ch' then
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
 return a and a.mode~='ch' and a or nil
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
 local groups,order={},{}
 for _,n in ipairs(scene.notes) do
  if not n.generated and not n.mute and ((n.sel and n.changed) or includeExisting) and n.a and n.a.mode~='ch' then
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
  local conflict=false
  for _,n in ipairs(scene.notes) do
   if not g.members[n] and not n.generated and not n.mute and n.effective and n.ch==g.ch and key(n.s,n.ch,0)==key(g.s,g.ch,0) and config(n.effective)~=g.choice then conflict=true break end
  end
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
 local groups,order={},{}
 for _,n in ipairs(scene.notes) do
  local needsRoom=math.floor(n.s)<=left
  if not needsRoom and n.a and n.a.mode~='ch' and math.floor(n.s)==left+1 then
   local ch=n.a.kschannel==0 and n.ch or n.a.kschannel-1
   for _,other in ipairs(scene.notes) do
    if other~=n and not other.generated and not other.mute and not other.a and other.ch==ch and other.s<n.s and math.floor(other.s)==left then needsRoom=true break end
   end
  end
  if not n.generated and not n.mute and n.a and n.a.mode~='ch' and needsRoom then
   local id=key(n.s,n.ch,0)..':'..config(n.a)
   if not groups[id] then
    groups[id]={notes={},members={},choice=config(n.a),ch=n.a.kschannel==0 and n.ch or n.a.kschannel-1}
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
  local candidate=left+1
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
  for _,n in ipairs(g.notes) do
   if n.e-candidate<1 then error('This note is too short to leave room for a keyswitch at the item start. No notes were changed.') end
  end
  for _,n in ipairs(g.notes) do
   local offset=candidate-n.s
   n.olds=n.olds or n.s n.olde=n.olde or n.e
   n.s=candidate n.a.shift=(n.a.shift or 0)+offset n.changed=true moved=moved+1
  end
 end
 return moved
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
   if seen[conflict] and seen[conflict]~=choice then error('Different articulations start together on one channel. Use separate channels.') end
   seen[conflict]=choice
   if a.mode~='ch' and not n.skipDefaultSwitch and not n.manualArt and not (n.manualSignal and n.manualSignal.pitch==a.pitch and (a.kschannel==0 or a.kschannel==n.manualSignal.kschannel)) then
    local time=R.MIDI_GetProjTimeFromPPQPos(take,n.s)
    local ch=a.kschannel==0 and n.ch or a.kschannel-1
    local onset=math.floor(n.s)
    local previous=precedingStart(ch,n.s)
    local earliest=math.max(math.ceil(left),previous and (math.floor(previous)+1) or math.ceil(left))
    local desired=round(R.MIDI_GetPPQPosFromProjTime(take,time-a.lead/1000))
    local s=math.max(earliest,math.min(onset-1,desired))
    if s>=onset then error('No MIDI tick available before this note for a keyswitch. Move the note slightly later or use separate channels.') end
    local switchTime=R.MIDI_GetProjTimeFromPPQPos(take,s)
    local mode,overlap=keyswitchLengthSettings(a)
    local e
    if mode=='follow' then e=math.max(onset+1,math.floor(n.e))
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
 for i,entry in ipairs(timeline) do
  local nextStart
  for j=i+1,#timeline do
   local later=timeline[j]
   if later.ch~=entry.ch then break end
   if later.s>entry.s then nextStart=later.s break end
  end
  if nextStart and entry.e>nextStart then
   if entry.event then entry.event.e=nextStart
   else scene.manualEnds[entry.note.idx]=nextStart end
  end
 end
 for _,ev in ipairs(ordered) do
  for _,n in ipairs(occupancy[tostring(ev.ch)..':'..ev.p] or {}) do
   if ev.s<n.e and n.s<ev.e then error('A keyswitch overlaps a musical note of the same pitch and channel.') end
  end
 end
 return ordered
end
local function write(take,scene,events)
 -- Keep note/text indexes stable through the ENTIRE edit, including deletes.
 R.MIDI_DisableSort(take)
 -- Update the musical notes while their original indexes are still valid.
 for _,n in ipairs(scene.notes) do if not n.generated and ((n.oldch and n.ch~=n.oldch) or n.olds) then
  if not R.MIDI_SetNote(take,n.idx,nil,nil,n.olds and n.s or nil,n.olde and n.e or nil,n.ch,nil,nil,true) then error('MIDI_SetNote failed') end
 end end
 -- Rebuild note-notation records only for notes with our assignment or changed channel.
 local textsToDelete={}
 for _,t in ipairs(scene.texts) do
  local matches=scene.bykey[t.key] or {} local n=matches[1]
  if t.managed or (n and not n.generated and (n.a or n.changed)) then textsToDelete[#textsToDelete+1]=t.idx end
 end
 table.sort(textsToDelete,function(a,b) return a>b end)
 for _,idx in ipairs(textsToDelete) do if not R.MIDI_DeleteTextSysexEvt(take,idx) then error('MIDI_DeleteTextSysexEvt failed') end end
 local generated={} for idx in pairs(scene.generated) do generated[#generated+1]=idx end
 table.sort(generated,function(a,b) return a>b end)
 for _,idx in ipairs(generated) do if not R.MIDI_DeleteNote(take,idx) then error('MIDI_DeleteNote failed') end end
 for _,n in ipairs(scene.notes) do if not n.generated and (n.a or n.changed) then
  local tail=n.extras
  if n.a then tail=appendMarker(tail,payload(n.a)) end
  if tail:find('%S') then
   if not R.MIDI_InsertTextSysexEvt(take,false,n.mute,n.s,15,'NOTE '..n.ch..' '..n.p..tail) then error('MIDI_InsertTextSysexEvt failed') end
  end
 end end
 for _,ev in ipairs(events) do
  if not R.MIDI_InsertNote(take,false,false,ev.s,ev.e,ev.ch,ev.p,ev.v,true) then error('MIDI_InsertNote failed') end
  if not R.MIDI_InsertTextSysexEvt(take,false,false,ev.s,15,'NOTE '..ev.ch..' '..ev.p..' user '..KS..':1') then error('Keyswitch marker failed') end
 end
end
-- Verify the complete planned musical-note multiset after native sorting.
-- If an API unexpectedly reindexes, deletes or changes a voice, roll back all MIDI.
local function musicalSignature(n)
 return string.format('%.6f:%.6f:%d:%d:%d:%d:%d',n.s,n.e,n.ch,n.p,n.v,n.sel and 1 or 0,n.mute and 1 or 0)
end
local function verifyWrittenNotes(take,scene,events)
 local expected={} local expectedCount=0
 for _,n in ipairs(scene.notes) do if not n.generated then
  local id=musicalSignature(n) expected[id]=(expected[id] or 0)+1 expectedCount=expectedCount+1
 end end
 local actual=read(take) local count,generatedCount=0,0
 for _,n in ipairs(actual.notes) do
  if n.generated then generatedCount=generatedCount+1
  else
   count=count+1 local id=musicalSignature(n)
   if not expected[id] or expected[id]==0 then error('Musical-note integrity check failed. The MIDI edit has been reverted.') end
   expected[id]=expected[id]-1
  end
 end
 if count~=expectedCount or generatedCount~=#events then error('MIDI note count changed unexpectedly. The MIDI edit has been reverted.') end
 for _,remaining in pairs(expected) do if remaining~=0 then error('A musical note is missing. The MIDI edit has been reverted.') end end
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
 local time=R.MIDI_GetProjTimeFromPPQPos(take,n.s)
 local earliest=math.floor(R.MIDI_GetPPQPosFromProjTime(take,time-a.lead/1000))-1
 local found
 for _,sw in ipairs(scene.notes) do
  if sw.generated and sw.ch==channel and sw.p==a.pitch and sw.s>=earliest and sw.s<n.s and (not found or sw.s>found.s) then found=sw end
 end
 return found and found.key or nil
end
local function hasAnyOwnedSwitch(scene,n)
 local a=n.a local channel=a.kschannel==0 and n.ch or a.kschannel-1
 if n.manualSignal and n.manualSignal.pitch==a.pitch then return true end
 for _,sw in ipairs(scene.notes) do if sw.generated and sw.ch==channel and sw.p==a.pitch then return true end end
 return false
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
 for _,n in ipairs(scene.notes) do if not n.generated then
  if n.keyswitchRow and n.a and n.a.implicit then return true end
  if not n.keyswitchRow then
  if n.manualArt then if n.a and n.a.implicit then return true end
  elseif default and (not n.a or (n.a.implicit and (n.a.bank~=bank().name or config(n.a)~=config(default)))) then return true end
  if not n.manualArt and not default and n.a and n.a.implicit then return true end
  end
 end end
 return false
end
local function assignDefaults(scene)
 local default=defaultArt()
 for _,n in ipairs(scene.notes) do
  if n.keyswitchRow and n.a and n.a.implicit then detachAssignment(n) end
  if not n.generated and not n.keyswitchRow and (not n.a or n.a.implicit) then
  if n.manualArt then if n.a then n.a=nil n.changed=true end
  elseif not default then if n.a then detachAssignment(n) end
  elseif not n.a or n.a.bank~=bank().name or config(n.a)~=config(default) then
   local base=n.a and n.a.base or n.ch
   restoreStaggerStart(n)
   n.oldch=n.oldch or n.ch n.changed=true
   n.a={base=base,bank=bank().name,implicit=true}
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
local function rawKeyNotes(take)
 local ok,count,_,textCount=R.MIDI_CountEvts(take) if not ok then return nil end
 local state={take=take,count=count,notes={},counts={},onsets={},owned={},owners={},validOwned={}}
 local assignments,switches={},{}
 for i=0,count-1 do
  local yes,sel,mute,s,e,ch,p,v=R.MIDI_GetNote(take,i)
  if yes then
   local n={idx=i,sel=sel,mute=mute,s=s,e=e,ch=ch,p=p,v=v}
   n.id=string.format('%.6f:%.6f:%d:%d:%d:%d',s,e,ch,p,v,mute and 1 or 0)
   n.key=key(s,ch,p) state.notes[#state.notes+1]=n
   state.counts[n.id]=(state.counts[n.id] or 0)+1
   state.onsets[n.key]=(state.onsets[n.key] or 0)+1
  end
 end
 for i=0,textCount-1 do
  local yes,_,_,pos,typ,msg=R.MIDI_GetTextSysexEvt(take,i)
  if yes and typ==15 then
   local ch,p,tail=msg:match('^NOTE (%d+) (%d+)(.*)$')
   if ch then
    local id=key(pos,tonumber(ch),tonumber(p))
    if userValue(tail)==KS..':1' then
     if state.onsets[id] then
      state.owned[id]=true local row=ch..':'..p
      state.owners[row]=(state.owners[row] or 0)+1
      switches[#switches+1]={key=id,s=pos,ch=tonumber(ch),p=tonumber(p)}
     end
    elseif state.onsets[id] then
     local marker=extractMarker(tail) local a=marker and assignment(marker)
     if a and a.mode~='ch' then assignments[#assignments+1]={s=pos,ch=tonumber(ch),p=tonumber(p),a=a} end
    end
   end
  end
 end
 local rows=keyswitchRows()
 for _,n in ipairs(assignments) do if not rows[n.ch..':'..n.p] then
  local ch=n.a.kschannel==0 and n.ch or n.a.kschannel-1
  local time=R.MIDI_GetProjTimeFromPPQPos(take,n.s)
  local earliest=math.floor(R.MIDI_GetPPQPosFromProjTime(take,time-n.a.lead/1000))-1
  for _,sw in ipairs(switches) do
   if sw.ch==ch and sw.p==n.a.pitch and sw.s>=earliest and sw.s<n.s then state.validOwned[sw.key]=true end
  end
 end end
 return state
end
local function captureKeyswitchGuard(take)
 local state=rawKeyNotes(take) if not state then return nil end
 local ok,raw=R.MIDI_GetAllEvts(take,'') if not ok then return nil end
 state.raw=raw state.scene=read(take) return state
end
local function watchKeyswitchRows()
 local take=activeTake() if not take then keyswitchGuard=nil return end
 if R.JS_Mouse_GetState and R.JS_Mouse_GetState(1)&1~=0 then return end
 local ok,current=pcall(captureKeyswitchGuard,take) if not ok or not current then return end
 local previous=keyswitchGuard
 keyswitchGuard=current
 if not previous or previous.take~=take then return end
 local function musicSignature(scene)
  local result={}
  for _,n in ipairs(scene.notes) do if not n.generated and not n.keyswitchRow then
   result[#result+1]=string.format('%.6f:%.6f:%d:%d:%d:%s',n.s,n.e,n.ch,n.p,n.v,n.a and payload(n.a) or '')
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
 local ownerKeys={}
 for _,n in ipairs(previous.scene.notes) do if n.a and n.a.mode~='ch' then
  local owner=findOwnedSwitch(take,previous.scene,n)
  if owner and removed[owner] then ownerKeys[n.key]=true end
 end end
 local success,err=xpcall(function()
  R.MIDI_DisableSort(take)
  -- Only our notation changes; all MIDI notes keep the user's exact edits.
  local edits={}
  for _,t in ipairs(current.scene.texts) do
   local tail
   if t.ownedKS and changed[t.key] then tail=setUser(t.tail,KS..':manual')
   elseif ownerKeys[t.key] then local marker,extras=extractMarker(t.tail) if marker then tail=extras end end
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
 else deletionSnapshot=nil status='Manual keyswitch edit preserved.' end
 R.UpdateItemInProject(R.GetMediaItemTake_Item(take))
 keyswitchGuard=captureKeyswitchGuard(take)
end
local function execute(a,clear,sync,timing,removedKeys)
 local take=activeTake() if not take then return false end
 local ok,scene=pcall(read,take) if not ok then status=tostring(scene) return false end
 local removedMissing=0
 for _,n in ipairs(scene.notes) do
  if not n.generated and n.a and n.a.mode~='ch' and not n.mute then
   local explicitRemoval=removedKeys and removedKeys[n.key]==payload(n.a)
   local orphan=not sync and not hasAnyOwnedSwitch(scene,n)
   if explicitRemoval or orphan then detachAssignment(n) removedMissing=removedMissing+1 end
  end
 end
 if timing then
  for _,n in ipairs(scene.notes) do
   if not n.generated and n.a and n.a.mode~='ch' and n.a.bank==timing.bank then
    n.a.lead=timing.lead n.a.length=timing.length n.changed=true
   end
  end
 end
 local selected=0
 for _,n in ipairs(scene.notes) do if n.sel and not n.generated and not n.keyswitchRow then
  selected=selected+1
  local base=n.a and n.a.base or n.ch
  if not sync then
   n.restoredShift=restoreStaggerStart(n)
   n.oldch=n.oldch or n.ch n.changed=true
   if clear then n.ch=base n.a=nil
   else
    n.a={base=base,bank=bank().name}
    n.manualArt=nil
    for k,v in pairs(a) do n.a[k]=v end
    n.ch=a.mode=='ks' and base or a.channel-1
   end
  end
 end end
 assignDefaults(scene)
 prepareDefaults(take,scene)
 local room,moved=pcall(ensureBoundaryRoom,take,scene) if not room then status=tostring(moved) return false end
 -- If auto-stagger was disabled after an earlier edit, keep its old offset
 -- while a conflict still exists. Common articulations always restore alignment.
 prepareDefaults(take,scene)
 if not sync and not clear and R.GetExtState(SECTION,'autoStagger')~='1' then
  for _,n in ipairs(scene.notes) do if n.sel and n.restoredShift and n.restoredShift>0 and n.a then
   for _,other in ipairs(scene.notes) do
    if other~=n and not other.generated and not other.mute and other.effective and other.ch==n.ch and other.s==n.s and config(other.effective)~=config(n.a) then
     n.s=n.s+n.restoredShift n.a.shift=n.restoredShift break
    end
   end
  end end
 end
 if not sync and selected==0 then status='No musical notes selected.' return false end
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
 R.Undo_BeginBlock()
 local success,err=xpcall(function() write(take,scene,events) R.MIDI_Sort(take) verifyWrittenNotes(take,scene,events) end,debug.traceback)
 if not success then R.MIDI_SetAllEvts(take,backup) end
 R.MIDI_Sort(take) R.UpdateItemInProject(R.GetMediaItemTake_Item(take))
 R.Undo_EndBlock(removedKeys and 'Clear deleted keyswitch assignments' or timing and 'Change keyswitch timing' or sync and 'Refresh keyswitches' or clear and 'Clear articulation' or 'Replace articulation: '..a.name,-1)
 if not success then status='Changes reverted after a MIDI error.' R.MB(tostring(err),'Articulation Manager',0) return false end
 editGeneration=editGeneration+1
 keyswitchGuard=captureKeyswitchGuard(take)
 if musicalGeometry then movementSnapshot={take=take,generation=editGeneration,signature=musicalGeometry(scene)} end
 status=sync and 'Keyswitches refreshed.' or clear and 'Assignment cleared.' or a.name..' — notes: '..selected
 if removedMissing>0 then status=status..'; deleted-switch assignments cleared: '..removedMissing end
 if shifted>0 then status=status..'; notes shifted: '..shifted end
 return true
end
local function apply(a) return execute(a,false,false) end
local function clear() return execute(nil,true,false) end
local function sync(dropOrphans)
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
 return execute(nil,false,true,nil,missing)
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
local function watchDeletedSwitches()
 local take=activeTake() if not take then deletionSnapshot=nil return end
 local ok,scene=pcall(read,take) if not ok then return end
 local present={} for _,n in ipairs(scene.notes) do if n.generated then present[n.key]=true end end
 local missing={}
 if deletionSnapshot and deletionSnapshot.take==take then
  for _,n in ipairs(scene.notes) do
   local previous=deletionSnapshot.notes[n.key]
   if n.a and previous and previous.switch and previous.data==payload(n.a) and not present[previous.switch] then missing[n.key]=previous.data end
  end
 end
 if next(missing) and execute(nil,false,true,nil,missing) then
  local reread,updated=pcall(read,take) if reread then scene=updated end
 end
 local snapshot={take=take,notes={}}
 for _,n in ipairs(scene.notes) do
  if n.a and n.a.mode~='ch' and not n.mute then
   local previous=deletionSnapshot and deletionSnapshot.take==take and deletionSnapshot.notes[n.key]
   local owner=findOwnedSwitch(take,scene,n)
   -- Keep a known physical owner through tempo changes that alter the lead window.
   if not owner and previous and present[previous.switch] and previous.data==payload(n.a) then owner=previous.switch end
   snapshot.notes[n.key]={data=payload(n.a),switch=owner}
  end
 end
 deletionSnapshot=snapshot
end
-- NOTE notation follows native MIDI-editor moves/transposition. Rebuild owned
-- switches when musical geometry changes, after the drag ends. Selection-only
-- changes and our own writes do not generate additional MIDI edits.
musicalGeometry=function(scene)
 local values={}
 for _,n in ipairs(scene.notes) do if not n.generated then
  values[#values+1]=string.format('%.6f:%.6f:%d:%d:%d:%s',n.s,n.e,n.ch,n.p,n.mute and 1 or 0,n.a and payload(n.a) or '')
 end end
 table.sort(values) return table.concat(values,'\n')
end
switchesMatch=function(scene,events)
 local actual,expected={},{}
 local function signature(n) return string.format('%.6f:%.6f:%d:%d:%d:%d',n.s,n.e,n.ch,n.p,n.v,n.mute and 1 or 0) end
 for _,n in ipairs(scene.notes) do if n.generated then actual[#actual+1]=signature(n) end end
 for _,n in ipairs(events) do expected[#expected+1]=signature(n) end
 table.sort(actual) table.sort(expected)
 return table.concat(actual,'\n')==table.concat(expected,'\n')
end
local function watchMusicalEdits()
 if R.JS_Mouse_GetState and R.JS_Mouse_GetState(1)&1~=0 then return end
 local take=activeTake() if not take then movementSnapshot=nil return end
 local ok,scene=pcall(read,take) if not ok then return end
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
  if (needsDefaultAssignments(scene) or not planned or next(scene.manualEnds or {}) or not switchesMatch(scene,events)) and sync() then
   local reread,updated=pcall(read,take) if reread then signature=musicalGeometry(updated) end
  end
 end
 movementSnapshot={take=take,generation=editGeneration,signature=signature}
end
local function protectKeyswitchSelectionAndPitch()
 if R.JS_Mouse_GetState and R.JS_Mouse_GetState(1)&1~=0 then return end
 local take=activeTake() if not take then return end
 local ok,scene=pcall(read,take) if not ok then return end
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
  end
 end
 -- Also repair a transpose performed before the observer could deselect the
 -- switches. NOTE ownership follows the native pitch edit; the mapping does not.
 local planned,events=pcall(plan,take,scene) if not planned then return end
 local expected={}
 for _,ev in ipairs(events) do expected[key(ev.s,ev.ch,0)]=ev.p end
 for _,n in ipairs(scene.notes) do if n.generated then
  local pitch=expected[key(n.s,n.ch,0)]
  if musicalSelected and pitch and pitch~=n.p then
   if sync() then deletionSnapshot=nil end
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
local quickPopupMode=rawget(_G,'ABART_QUICK_POPUP')==true
local popupMode=rawget(_G,'ABART_POPUP')==true or quickPopupMode
if R.set_action_options and not popupMode then R.set_action_options(3) end
if not R.JS_Composite and not popupMode then
 R.MB('js_ReaScriptAPI is required for the embedded MIDI editor field.','Articulation Manager',0) return
end
local host,bitmap,liceFont=nil,nil,nil
local running=true
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

local function safeLabel(s) return (s:gsub('[|#!<>]',' ')) end
local function prompt(caption,labels,values,count)
 local ok,result=R.GetUserInputs(caption,count,labels,values)
 if ok then return split(result,',') end
end
local function assignmentIdentity(a)
 return a.bank..'\t'..a.name..'\t'..config(a)
end
local function selectionState()
 local editor=R.MIDIEditor_GetActive() local take=editor and R.MIDIEditor_GetTake(editor)
 local state={take=take,total=0,none=0,buckets={},order={},label=defaultArt() and defaultArt().name or '—'}
 if not take or not isMidiTake(take) then return state end
 local ok,scene=pcall(read,take)
 if not ok then state.error=tostring(scene) state.label='!' return state end
 for _,n in ipairs(scene.notes) do if n.sel and not n.generated and not n.keyswitchRow then
  state.total=state.total+1
  if not n.a or n.a.implicit then state.none=state.none+1 end
  local a=n.manualArt or n.a
  if not a and defaultArt() then
   a={bank=bank().name} for k,v in pairs(defaultArt()) do a[k]=v end
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
 if quickPopupMode then return R.GetMousePosition() end
 if host and R.JS_Window_IsWindow(host) then return R.JS_Window_ClientToScreen(host,box.x,box.y+box.h) end
 return R.GetMousePosition()
end
local function showNativeMenu(text)
 releaseIntercepts()
 local x,y=screenAnchor()
 local focus=R.JS_Window_GetFocus and R.JS_Window_GetFocus()
 if quickPopupMode then
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
 local a=defaults('New articulation','ks',1)
 a.lead=number(R.GetExtState(SECTION,'timingLead'),0.01,10000,false) or a.lead
 a.length=number(R.GetExtState(SECTION,'timingLength'),0.01,10000,false) or a.length
 local editor=R.MIDIEditor_GetActive()
 if editor and R.MIDIEditor_GetSetting_int then
  a.pitch=number(R.MIDIEditor_GetSetting_int(editor,'active_note_row'),0,127,true) or a.pitch
 end
 return a
end
local function editArt(index)
 local a=index and bank().arts[index] or newArticulation()
 local modes={'ch','ks','both'}
 local labels={'MIDI channel','Keyswitch','Channel + keyswitch'}
 for i,mode in ipairs(modes) do if mode==a.mode then labels[i]='!'..labels[i] end end
 local choice=choose(labels) if choice==0 then return end
 local mode=modes[choice] local f
 local entry={} for k,v in pairs(a) do entry[k]=v end entry.mode=mode
 if mode=='ch' then
  f=prompt('Articulation — MIDI channel','Name,MIDI channel 1–16',table.concat({a.name,a.channel},','),2)
  if f then entry.name=f[1] entry.channel=tonumber(f[2]) end
 elseif mode=='ks' then
  f=prompt('Articulation — keyswitch','Name,KS pitch 0–127,Velocity 1–127,Lead time (ms),Length (ms),KS channel 0=note channel',table.concat({a.name,a.pitch,a.velocity,a.lead,a.length,a.kschannel},','),6)
  if f then entry.name=f[1] entry.pitch=tonumber(f[2]) entry.velocity=tonumber(f[3]) entry.lead=tonumber(f[4]) entry.length=tonumber(f[5]) entry.kschannel=tonumber(f[6]) end
 else
  f=prompt('Articulation — channel + keyswitch','Name,Note channel 1–16,KS pitch 0–127,Velocity 1–127,Lead time (ms),Length (ms),KS channel 0=note channel',table.concat({a.name,a.channel,a.pitch,a.velocity,a.lead,a.length,a.kschannel},','),7)
  if f then entry.name=f[1] entry.channel=tonumber(f[2]) entry.pitch=tonumber(f[3]) entry.velocity=tonumber(f[4]) entry.lead=tonumber(f[5]) entry.length=tonumber(f[6]) entry.kschannel=tonumber(f[7]) end
 end
 if not f then return end
 if not valid(entry) then status='Check the MIDI pitch, channel and numeric values.' return end
 if index then bank().arts[index]=entry if bank().default==index and entry.mode=='ch' then bank().default=nil end
 else
  if bank().name=='Empty bank' and #bank().arts==0 then
   local name='New bank' local used={} for _,b in ipairs(presets) do used[b.name]=true end
   local suffix=2 while used[name] do name='New bank '..suffix suffix=suffix+1 end
   bank().name=name
  end
  bank().arts[#bank().arts+1]=entry
 end save()
end
local function timingSettings()
 local f=prompt('Keyswitch timing for this bank','Lead time (ms),Length (ms),Overlap after note (ms)',
  (R.GetExtState(SECTION,'timingLead')~='' and R.GetExtState(SECTION,'timingLead') or '1')..','..
  (R.GetExtState(SECTION,'timingLength')~='' and R.GetExtState(SECTION,'timingLength') or '1')..','..(R.GetExtState(SECTION,'ksOverlap')~='' and R.GetExtState(SECTION,'ksOverlap') or '1'),3)
 if not f then return end
 local lead,length,overlap=number(f[1],0.01,10000,false),number(f[2],0.01,10000,false),number(f[3],0,10000,false)
 if not lead or not length or not overlap then R.MB('Lead/length: 0.01–10000 ms; overlap: 0–10000 ms.','Keyswitch timing',0) return end
 local previous=R.GetExtState(SECTION,'ksOverlap') R.SetExtState(SECTION,'ksOverlap',tostring(overlap),true)
 if not retime(lead,length) then R.SetExtState(SECTION,'ksOverlap',previous,true) R.MB(status,'Keyswitch timing',0) return end
 for _,a in ipairs(bank().arts) do if a.mode~='ch' then a.lead=lead a.length=length end end
 save()
 R.SetExtState(SECTION,'timingLead',tostring(lead),true) R.SetExtState(SECTION,'timingLength',tostring(length),true)
 status='Bank timing saved; existing assignments for this bank in the active take were refreshed.'
end
local function pickArtIndex()
 local order=articulationOrder()
 local names={} for _,i in ipairs(order) do names[#names+1]=safeLabel(bank().arts[i].name) end
 if #names==0 then status='This bank has no articulations.' return end
 local n=choose(names) return n>0 and order[n] or nil
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
local function bankNew()
 local f=prompt('New bank','Name','My library',1)
 if f and f[1]~='' then banks[#banks+1]={name=f[1],arts={}} bankIndex=#banks save() end
end
local function bankRename()
 local f=prompt('Bank name','Name',bank().name,1)
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
local function editSelectedArt() local i=pickArtIndex() if i then editArt(i) end end
local function deleteSelectedArt()
 local i=pickArtIndex()
 if i and R.MB('Remove articulation mapping “'..bank().arts[i].name..'”?','Articulation',4)==6 then table.remove(bank().arts,i) if bank().default==i then bank().default=nil elseif bank().default and bank().default>i then bank().default=bank().default-1 end save() end
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
  entries[#entries+1]={label=a.name,checked=bank().default==i,disabled=a.mode=='ch',action=function() setDefaultArt(index) end}
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
local function articulationEntries(state)
 local menu={}
 for _,i in ipairs(articulationOrder()) do local a=bank().arts[i]
  local saved={bank=bank().name} for k,v in pairs(a) do saved[k]=v end
  local bucket=state.buckets[assignmentIdentity(saved)]
  local count=bucket and bucket.count or 0
  local label=a.name
  if count>0 and count<state.total then label=label..'  ('..noteCount(count)..')' end
  local index=i
  menu[#menu+1]={label=label,checked=count>0,disabled=state.total==0,action=function()
   if not apply(bank().arts[index]) then R.MB(status,'Articulation',0) end
  end}
 end
 return menu
end
-- Offline help is built in so manual installations keep working without guide files.
local helpTopics={
 {title="Quick start",text=[[1. Open a MIDI item and keep Articulation_Manager.lua running.
2. Create a bank: Settings > Banks > New.
3. Add articulation: choose the switching method and enter your instrument's mapping.
4. Select musical notes, open the field menu and choose an articulation.
5. Optional: Settings > Default articulation for notes without an override.
6. Save the REAPER project.

Assign Articulation_Quick_Menu.lua to a MIDI Editor shortcut for an articulation-only menu at the mouse cursor.]]},
 {title="Articulations and defaults",text=[[MIDI channel: routes musical notes to a channel.
Keyswitch: sends a MIDI note that selects a sound in your instrument.
Channel + keyswitch: combines both methods.

Use the pitch, velocity and channels required by your instrument. KS channel 0 means the musical note's channel. New KS pitch uses the active piano-roll row.

Select notes and choose a name to apply it. Clear articulation removes the explicit override; a configured default can apply again. Defaults require a keyswitch mapping.

The field shows the selected articulation, Mixed for different assignments, or a dash if none is assigned. With no notes selected, it shows the default name, if configured.]]},
 {title="Banks and saving",text=[[Banks selects the current track's bank. Settings > Banks creates, renames, removes, imports or exports banks. Export saves all banks of the current track.

Track banks are independent. New tracks start with Empty bank; saved bank templates remain available. Bank and articulation edits are saved automatically. Save the project to retain track bank choices and note assignments.

Appearance and common playback preferences persist between REAPER sessions. Timing changes also update the current bank's mappings.

Removing a bank or mapping does not erase existing MIDI assignments. Use Clear articulation on notes when you want to remove their overrides.]]},
 {title="Manual keyswitches",text=[[Draw or edit notes directly on mapped articulation rows. They are treated as manual switches and do not receive a default articulation. Their last switch remains active until another manual switch or an explicit automatic assignment on that MIDI channel.

A later switch shortens the earlier keyswitch at its start. Different switches at exactly the same time on one channel remain ambiguous.

Independently editing an automatic keyswitch's pitch, position, length or velocity makes it manual and removes its former automatic links. Musical notes are preserved. Move the musical note instead to keep an automatic link.]]},
 {title="Playback and timing",text=[[Automatic keyswitches start before their musical notes and follow their length, ending sooner if another switch intervenes. Lead time controls the advance. Length and Overlap fields are retained for compatibility; they do not set the final duration in Follow musical note behavior.

Keyswitch timing updates the current bank and its assignments in the active take; new articulations use the saved timing defaults.

Chase MIDI note-ons enables REAPER's option to resend sustained notes when playback starts inside them. Test the result with your instrument.

Auto-stagger conflicting notes delays conflicting musical starts slightly and shortens notes by the same amount, keeping their ends fixed. Spacing sets the delay in ms. It does not provide independent simultaneous articulations on one MIDI channel.]]},
 {title="Editing and transposition",text=[[Keep the main script running while editing. Moving or resizing musical notes updates their linked automatic keyswitches. Returning notes to the same articulation can restore starts previously delayed by auto-stagger.

At the item start, a musical note can move slightly later to leave room for its keyswitch; its end stays fixed.

Broad selection/transposition protects keyswitch pitches while musical notes change pitch. With item/take pitch changes, the script writes the transpose into musical notes and resets the take pitch control, so the P+ value may disappear.

Use REAPER Undo to reverse an edit. Protection and following require the running main script.]]},
 {title="Tools and troubleshooting",text=[[Name keyswitch rows labels piano-roll rows from the bank.
Refresh keyswitches rebuilds automatic switches in the active take from assignments.
Clear missing keyswitch assignments removes stale links after switches were deleted; a default may then apply.
Legacy keyswitches > Find for review selects possible older switches. Review the selection before Remove reviewed; manual switches can match too.
Status shows the latest operation message.

No sounds change: check the instrument mapping, MIDI channel and velocity. Empty menu: choose this track's bank and add mappings. An articulation-only menu has no settings: use the field or Articulation_Menu_Popup.lua for Help and Settings.]]},
 {title="Field, actions and startup",text=[[Articulation_Manager.lua runs the embedded field and background updates.
Articulation_Quick_Menu.lua opens only articulations at the mouse cursor.
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
 menu[#menu+1]={label='Add articulation…',action=function() editArt() end}
 menu[#menu+1]={label='Edit articulation…',action=editSelectedArt}
 menu[#menu+1]={label='Remove articulation…',action=deleteSelectedArt}
 menu[#menu+1]={separator=true}
 for _,entry in ipairs(articulationEntries(state)) do menu[#menu+1]=entry end
 local bankEntries={}
 for i,b in ipairs(banks) do local index=i
  bankEntries[#bankEntries+1]={label=b.name,checked=i==bankIndex,action=function() bankIndex=index save(false) end}
 end
 menu[#menu+1]={separator=true}
 menu[#menu+1]={label='Banks',children=bankEntries}
 menu[#menu+1]={label='Settings',children={
  {label='Banks',children={{label='New…',action=bankNew},{label='Rename…',action=bankRename},{label='Remove…',action=bankDelete},{separator=true},{label='Import…',action=import},{label='Export…',action=export}}},
  {label='Appearance and position',children={{label='Field position…',action=positionSettings},{label='Size and font…',action=sizeSettings}}},
  {label='Legacy keyswitches',children={{label='Find for review',action=findLegacy},{label='Remove reviewed',action=deleteLegacy}}},
  {separator=true},
  {label='Name keyswitch rows',checked=R.GetExtState(SECTION,'nameKeyswitchRows')~='0',action=toggleRowNames},
  {label='Default articulation',children=defaultMenu()},
  {label='Keyswitch timing…',action=timingSettings},
  {label='Chase MIDI note-ons',checked=chaseEnabled(),action=toggleChase},
  {label='Auto-stagger conflicting notes',checked=R.GetExtState(SECTION,'autoStagger')=='1',action=toggleStagger},
  {label='Auto-stagger spacing…',action=staggerDelaySettings},
  {label='Clear missing keyswitch assignments',action=function() if not clearMissingAssignments() then R.MB(status,'Missing keyswitch assignments',0) end end},
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
 local entries=quickPopupMode and articulationEntries(state) or buildMenu(state)
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
local transposeCheckTime=0
local function loop()
 if not running or R.GetExtState(SECTION,'activeInstance')~=instanceToken then return end
 if R.time_precise()>transposeCheckTime then watchItemTranspose() transposeCheckTime=R.time_precise()+0.20 end
 local editor=R.MIDIEditor_GetActive()
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
   if R.time_precise()>refresh then watchKeyswitchRows() protectKeyswitchSelectionAndPitch() watchDeletedSwitches() watchMusicalEdits() rowNamesUpdate() cachedState=selectionState() refresh=R.time_precise()+0.20 end
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
