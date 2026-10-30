-- @noindex

-- ArticulationBox by Andrey Novikov. License: MIT.
-- One parameter window shared by Add articulation and Edit articulation.
return function(R,options)
 if not R.ImGui_GetBuiltinPath then
  return false,'The parameter window requires ReaImGui. Install “ReaImGui: ReaScript binding for Dear ImGui” through ReaPack, restart REAPER, and try again.'
 end
 local loaded,I=pcall(function()
  return dofile(R.ImGui_GetBuiltinPath()..'/imgui.lua')('0.9.3')
 end)
 if not loaded then return false,'Could not load ReaImGui. Update the extension through ReaPack.\n\n'..tostring(I) end
 local ctx=I.CreateContext('ArticulationBox articulation editor')
 local font=I.CreateFont('sans-serif',14)
 I.Attach(ctx,font)
 local entry={} for k,v in pairs(options.entry) do entry[k]=v end
 local mode=entry.mode=='controller' and 3 or entry.trigger=='end' and 4 or entry.mode=='ch' and 0 or entry.mode=='both' and 2 or 1
 local after=entry.trigger=='end' and 2 or entry.lead<0 and 1 or 0
 local distance=math.abs(entry.lead)
 local function savedSize(key,fallback,lo,hi)
  local value=R.GetExtState and tonumber(R.GetExtState('ArticulationManager_v4',key))
  return value and value==value and math.max(lo,math.min(hi,value)) or fallback
 end
 local windowWidth=savedSize('editorWidth',400,380,800)
 local windowHeight=savedSize('editorHeight',440,430,900)
 local first,closed,errorText=true,false,nil
 local editing,savedMessage=options.editing,nil
 local selected=options.selected or 0
 local drafts={}
 local variantMode=false
 local nameRevision=0
 local windowDrag
 local channels={} for n=1,16 do channels[#channels+1]=tostring(n) end
 channels=table.concat(channels,'\0')..'\0'
 local ksChannels='0 — Note channel\0'..channels
 local controlNames={[0]='Bank Select',[1]='Mod Wheel',[2]='Breath',[4]='Foot Pedal',[5]='Portamento Time',[6]='Data Entry',[7]='Volume',[8]='Balance',[10]='Pan',[11]='Expression',[64]='Hold Pedal',[65]='Portamento',[66]='Sostenuto',[67]='Soft Pedal',[68]='Legato',[69]='Hold 2',[71]='Resonance',[72]='Release',[73]='Attack',[74]='Brightness',[91]='Reverb',[93]='Chorus'}
 local controlLabels={'None','Pitch Bend','Mod Wheel (CC 1)','Hold Pedal (CC 64)'}
 local controlValues={-2,-1,1,64}
 for cc=0,127 do if cc~=1 and cc~=64 then
  controlLabels[#controlLabels+1]='CC '..cc..(controlNames[cc] and (' — '..controlNames[cc]) or '')
  controlValues[#controlValues+1]=cc
 end end
 local function initControl(a)
  a.ctrl=a.ctrl or 'none' a.ctrlCC=a.ctrlCC or 1 a.ctrlValue=a.ctrlValue or 0
  a.ctrlChannel=a.ctrlChannel or 0 a.ctrlTiming=a.ctrlTiming or 'full'
  a.ctrlLead=a.ctrlLead or 0.1 a.ctrlTail=a.ctrlTail or 0.1 a.ctrlReset=a.ctrlReset or 0
 end
 initControl(entry)
 local function finish()
  if closed then return end
  closed=true
  if R.SetExtState then
   R.SetExtState('ArticulationManager_v4','editorWidth',tostring(windowWidth),true)
   R.SetExtState('ArticulationManager_v4','editorHeight',tostring(windowHeight),true)
  end
  ctx=nil
  if options.onClose then options.onClose() end
 end
 local function integer(value,lo,hi) return type(value)=='number' and value%1==0 and value>=lo and value<=hi end
 local function snapshot()
  local result={} for k,v in pairs(entry) do result[k]=v end
  result.mode=({'ch','ks','both','controller','ks'})[mode+1]
  result.lead=after==1 and -distance or distance
  result.trigger=mode==4 and 'end' or nil
  if result.trigger=='end' then result.mode='ks' end
  return result
 end
 local function setEntry(updated)
  nameRevision=nameRevision+1
  entry={} for k,v in pairs(updated) do entry[k]=v end
  initControl(entry)
  mode=entry.mode=='controller' and 3 or entry.trigger=='end' and 4 or entry.mode=='ch' and 0 or entry.mode=='both' and 2 or 1
  after=entry.trigger=='end' and 2 or entry.lead<0 and 1 or 0 distance=math.abs(entry.lead)
  editing=selected~=0 first=true errorText=nil
 end
 local function updateState(state)
  if type(state)~='table' then return end
  options.bankName=state.bankName or options.bankName
  options.entries=state.entries or options.entries
  selected=state.selected or 0
 end
 local function selectEntry(index,preserveMessage)
  if not options.onSelect then return false end
  local controllerDraft=index==0 and mode==3 and snapshot() or nil
  if controllerDraft then controllerDraft.name='' end
  local updated,why=options.onSelect(index)
  if not updated then errorText=why or 'Could not open the articulation.' return false end
  drafts[selected]=snapshot() selected=index
  setEntry(controllerDraft or drafts[index] or updated)
  variantMode=false
  if not preserveMessage then savedMessage=nil end
  return true
 end
 local function candidate()
  if not entry.name:find('%S') then return nil,'Enter an articulation name.' end
  if entry.grouped and (mode==1 or mode==2 or mode==4) and (not entry.groupName or not entry.groupName:find('%S')) then return nil,'Enter a group name.' end
  if not integer(entry.channel,1,16) then return nil,'Note channel must be between 1 and 16.' end
  if not integer(entry.pitch,0,127) then return nil,'KS note must be between 0 and 127.' end
  if not integer(entry.velocity,1,127) then return nil,'KS velocity must be between 1 and 127.' end
  if not integer(entry.kschannel,0,16) then return nil,'KS channel must be between 0 and 16.' end
  if not distance or distance~=distance or distance<0.01 or distance>10000 then return nil,'Timing distance must be between 0.01 and 10000 ms.' end
  if not entry.length or entry.length~=entry.length or entry.length<0.01 or entry.length>10000 then return nil,'KS length must be between 0.01 and 10000 ms.' end
  if mode==3 and entry.ctrl=='none' then return nil,'Choose a controller.' end
  if entry.ctrl~='none' then
   local low,high=entry.ctrl=='pitch' and -8192 or 0,entry.ctrl=='pitch' and 8191 or 127
   if not integer(entry.ctrlValue,low,high) or not integer(entry.ctrlReset,low,high) then return nil,'Check the controller value and reset value.' end
   if not integer(entry.ctrlCC,0,127) or not integer(entry.ctrlChannel,0,16) then return nil,'Check the controller number and channel.' end
   for _,v in ipairs({entry.ctrlLead,entry.ctrlTail}) do if type(v)~='number' or v~=v or v<0.01 or v>10000 then return nil,'Controller timing must be between 0.01 and 10000 ms.' end end
  end
  return snapshot()
 end
 -- Read incoming note-ons only; never record, insert or audition a note here.
 local inputSequence=R.MIDI_GetRecentInputEvent and R.MIDI_GetRecentInputEvent(0) or 0
 local midiEditor=R.MIDIEditor_GetActive and R.MIDIEditor_GetActive()
 local lastRow=midiEditor and R.MIDIEditor_GetSetting_int and R.MIDIEditor_GetSetting_int(midiEditor,'active_note_row')
 local lastMouse=R.JS_Mouse_GetState and R.JS_Mouse_GetState(1) or 0
 local function learnPitch()
  local learned,learnedVelocity
  if R.MIDI_GetRecentInputEvent then
   local newest
   for i=0,127 do
    local sequence,msg=R.MIDI_GetRecentInputEvent(i)
    if i==0 then newest=sequence end
    if sequence==0 or sequence==inputSequence then break end
    if not learned and msg and #msg>=3 then
     local status,pitch,velocity=msg:byte(1,3)
     if status&0xF0==0x90 and velocity>0 then learned,learnedVelocity=pitch,velocity end
    end
   end
   inputSequence=newest or inputSequence
  end
  local active=R.MIDIEditor_GetActive and R.MIDIEditor_GetActive()
  if active then midiEditor=active end
  local mouse=R.JS_Mouse_GetState and R.JS_Mouse_GetState(1) or 0
  local clicked=mouse~=0 and lastMouse==0
  lastMouse=mouse
  if midiEditor and R.MIDIEditor_GetSetting_int and (not R.MIDIEditor_GetMode or R.MIDIEditor_GetMode(midiEditor)>=0) then
   local row=R.MIDIEditor_GetSetting_int(midiEditor,'active_note_row')
   local editorFocused=false
   if clicked and R.JS_Window_GetFocus and R.JS_Window_GetParent then
    local window=R.JS_Window_GetFocus()
    for i=1,32 do
     if not window then break end
     if window==midiEditor then editorFocused=true break end
     window=R.JS_Window_GetParent(window)
    end
   end
   if integer(row,0,127) and (row~=lastRow or editorFocused) and not learned then
    learned=row
    local velocity=R.MIDIEditor_GetSetting_int(midiEditor,'default_note_vel')
    if integer(velocity,1,127) then learnedVelocity=velocity end
   end
   lastRow=row
  end
  if (mode==1 or mode==2 or mode==4) and learned then
   if not variantMode and options.onSelect then
    local fallback,current,exact
    for _,item in ipairs(options.entries or {}) do
     local a=item.entry
     if item.index>0 and a and (a.mode=='ks' or a.mode=='both') and (a.trigger=='end')==(mode==4) and a.pitch==learned then
      fallback=fallback or item
      if item.index==selected then current=item end
      if a.velocity==learnedVelocity and (not exact or item.index==selected) then exact=item end
     end
    end
    local match=exact or current or fallback
    if match and match.index~=selected then
     selectEntry(match.index)
    elseif not match and (selected>0 or entry.pitch~=learned) then
     -- A different, unmapped key starts a new mapping. Do not silently
     -- repurpose the last saved articulation just because learning is active.
     local nextEntry=snapshot() nextEntry.name='' nextEntry.grouped=false nextEntry.groupName=nil
     if selectEntry(0) then
      setEntry(nextEntry) drafts[0]=nil
     else return end
    end
   end
   entry.pitch=learned
   if learnedVelocity then entry.velocity=learnedVelocity end
  end
 end
 local function saveEntry(nextEntry)
  local result,why=candidate()
  if not result then errorText=why return false end
  local previous=selected
  local saved,message=options.onSave(result,nextEntry)
  if not saved then errorText=message or 'Could not save the articulation.' return false end
  drafts[previous]=nil updateState(message)
  savedMessage='Saved: '..entry.name errorText=nil
  if nextEntry then
   selected=0 drafts[0]=nil
   entry.name='' entry.grouped=false entry.groupName=nil nameRevision=nameRevision+1 editing=false first=true variantMode=false
  else editing=selected~=0 end
  return false
 end
 local function row(label,draw)
  I.AlignTextToFramePadding(ctx) I.Text(ctx,label)
  I.SameLine(ctx,153) I.SetNextItemWidth(ctx,-1) draw()
 end
 local function draw()
  local close=false
  local focusName=first first=false
  I.SetNextWindowSize(ctx,windowWidth,windowHeight,I.Cond_Appearing)
  local minimum=mode==2 and 460 or 430
  if options.allowControllers then
   local rows=(mode==3 and 0 or mode==0 and 1 or mode==2 and 6 or 5)+1+(entry.ctrl~='none' and 6 or 0)+(entry.grouped and (mode==1 or mode==2 or mode==4) and 1 or 0)
   minimum=math.max(465,335+rows*25+(selected~=0 and 35 or 0))
  end
  I.SetNextWindowSizeConstraints(ctx,380,minimum,800,900)
  if windowDrag then
   if I.IsMouseDown(ctx,0) then
    local mx,my=I.GetMousePos(ctx)
    I.SetNextWindowPos(ctx,mx-windowDrag.x,my-windowDrag.y,I.Cond_Always)
   else windowDrag=nil end
  end
  local centerX,centerY=I.Viewport_GetCenter(I.GetMainViewport(ctx))
  if not windowDrag then I.SetNextWindowPos(ctx,centerX,centerY,I.Cond_Appearing,0.5,0.5) end
  I.PushStyleColor(ctx,I.Col_WindowBg,0x292929FF)
  I.PushStyleColor(ctx,I.Col_TitleBg,0x333333FF)
  I.PushStyleColor(ctx,I.Col_TitleBgActive,0x333333FF)
  I.PushStyleColor(ctx,I.Col_FrameBg,0x414141FF)
  I.PushStyleColor(ctx,I.Col_FrameBgHovered,0x505050FF)
  I.PushStyleColor(ctx,I.Col_FrameBgActive,0x595959FF)
  I.PushStyleColor(ctx,I.Col_Button,0x454545FF)
  I.PushStyleColor(ctx,I.Col_ButtonHovered,0x5A5A5AFF)
  I.PushStyleColor(ctx,I.Col_ButtonActive,0x696969FF)
  I.PushStyleColor(ctx,I.Col_Header,0x704CA8FF)
  I.PushStyleColor(ctx,I.Col_HeaderHovered,0x8460BCFF)
  I.PushStyleColor(ctx,I.Col_HeaderActive,0x9670CEFF)
  I.PushStyleVar(ctx,I.StyleVar_WindowRounding,10)
  I.PushStyleVar(ctx,I.StyleVar_FrameRounding,4)
  I.PushStyleVar(ctx,I.StyleVar_WindowBorderSize,1)
  I.PushFont(ctx,font)
  local title='ArticulationBox — Add / Edit articulation###ArticulationBoxEditor'
  local visible,open=I.Begin(ctx,title,nil,I.WindowFlags_NoTitleBar|I.WindowFlags_NoCollapse|I.WindowFlags_NoDocking)
  if visible then
   windowWidth,windowHeight=I.GetWindowSize(ctx)
   local x,y=I.GetCursorScreenPos(ctx)
   local width=I.GetContentRegionAvail(ctx)
   if I.InvisibleButton(ctx,'##close',20,22) then close=true end
   I.SameLine(ctx,0,0)
   I.InvisibleButton(ctx,'##dragHeader',math.max(1,width-20),22)
   if I.IsItemActive(ctx) and not windowDrag then
    local mx,my=I.GetMousePos(ctx)
    local wx,wy=I.GetWindowPos(ctx)
    windowDrag={x=mx-wx,y=my-wy}
   end
   local drawList=I.GetWindowDrawList(ctx)
   local cx,cy=math.floor(x+8)+0.5,math.floor(y+9)+0.5
   I.DrawList_AddCircleFilled(drawList,cx,cy,7,0xFF5F57FF,32)
   I.DrawList_AddQuadFilled(drawList,cx-3,cy-1.8,cx-1.8,cy-3,cx+3,cy+1.8,cx+1.8,cy+3,0x72120EFF)
   I.DrawList_AddQuadFilled(drawList,cx-3,cy+1.8,cx-1.8,cy+3,cx+3,cy-1.8,cx+1.8,cy-3,0x72120EFF)
   I.DrawList_AddText(drawList,x+23,y+1,0xEEEEEEFF,mode==3 and 'Add / Edit controller' or mode==4 and 'Add / Edit ending' or 'Add / Edit articulation')
   I.Separator(ctx) I.Spacing(ctx)
   I.PushTextWrapPos(ctx,0)
   I.TextDisabled(ctx,'Bank: '..(options.bankName or ''))
   I.PopTextWrapPos(ctx)
   local changed
   if options.onSelect then
    local labels={'Add New'} local indices={0} local choice=0
    for _,item in ipairs(options.entries or {}) do
     labels[#labels+1]=item.label:gsub('%z',' ') indices[#indices+1]=item.index
     if item.index==selected then choice=#indices-1 end
    end
    row(mode==3 and 'Controller preset' or 'Articulation',function()
     local nextChoice
     changed,nextChoice=I.Combo(ctx,'##articulation',choice,table.concat(labels,'\0')..'\0')
     if changed and nextChoice~=choice then
      selectEntry(indices[nextChoice+1])
     end
    end)
   end
   row('Name',function()
    if focusName then I.SetKeyboardFocusHere(ctx) end
    changed,entry.name=I.InputText(ctx,'##name'..nameRevision,entry.name)
   end)
   if entry.grouped and (mode==1 or mode==2 or mode==4) then
    row('Group name',function() changed,entry.groupName=I.InputText(ctx,'##groupName'..nameRevision,entry.groupName or '') end)
   end
   I.Spacing(ctx)
   I.Text(ctx,options.allowControllers and 'Type (choose one)' or 'Articulation type (choose one)')
   local typeLabels=options.allowControllers and {'Keyswitch','Channel','KS + Channel','Controller','Ending'} or {'Keyswitch','Channel','KS + Channel'}
   local columns=options.allowControllers and 2 or 3
   local buttonWidth=(I.GetContentRegionAvail(ctx)-(columns-1)*8)/columns
   for i,label in ipairs(typeLabels) do
    local value=({1,0,2,3,4})[i]
    if (i-1)%columns~=0 then I.SameLine(ctx) end
    local isSelected=mode==value
    if isSelected then I.PushStyleColor(ctx,I.Col_Button,0x7750BAFF) end
    if I.Button(ctx,label,i==5 and I.GetContentRegionAvail(ctx) or buttonWidth,29) then
     local oldClass=mode==3 and 'controller' or mode==4 and 'ending' or 'primary'
     local newClass=value==3 and 'controller' or value==4 and 'ending' or 'primary'
     if oldClass~=newClass then
      local copy=snapshot() copy.name='' copy.mode=({'ch','ks','both','controller','ks'})[value+1]
      copy.trigger=value==4 and 'end' or nil copy.grouped=false copy.groupName=nil
      if not options.onSelect or selectEntry(0,true) then
       selected=0 drafts[0]=nil setEntry(copy)
      end
     end
     mode=value after=mode==4 and 2 or (after==2 and 0 or after)
    end
    if isSelected then I.PopStyleColor(ctx) end
   end
   I.Spacing(ctx)
    if mode==0 or (mode==2 and after~=2) then
     row('Channel',function()
      local n
      changed,n=I.Combo(ctx,'##noteChannel',entry.channel-1,channels)
      entry.channel=n+1
     end)
    end
    if mode==1 or mode==2 or mode==4 then
    row('KS note (auto)',function() changed,entry.pitch=I.InputInt(ctx,'##pitch',entry.pitch,1,12) end)
    row('KS velocity (1–127)',function() changed,entry.velocity=I.InputInt(ctx,'##velocity',entry.velocity,1,10) end)
    row('KS channel',function() changed,entry.kschannel=I.Combo(ctx,'##ksChannel',entry.kschannel,ksChannels) end)
    if mode==4 then row('Trigger',function() I.TextDisabled(ctx,'Note end') end)
    else row('Trigger',function() changed,after=I.Combo(ctx,'##trigger',after,'Before note start\0After note start\0') end) end
    row('Delay (ms)',function() changed,distance=I.InputDouble(ctx,'##distance',distance,0.1,1,'%.2f') end)
    end
   if options.allowControllers then
    I.Spacing(ctx)
    row('Controller',function()
     local choice=0
     for i,v in ipairs(controlValues) do if (entry.ctrl=='pitch' and v==-1) or (entry.ctrl=='cc' and v==entry.ctrlCC) then choice=i-1 break end end
     local nextChoice
     changed,nextChoice=I.Combo(ctx,'##controller',choice,table.concat(controlLabels,'\0')..'\0')
     if changed and nextChoice~=choice then
      local value=controlValues[nextChoice+1]
      entry.ctrl=value==-2 and 'none' or value==-1 and 'pitch' or 'cc'
      entry.ctrlCC=value>=0 and value or 1
      entry.ctrlValue=value==-1 and 0 or 127 entry.ctrlReset=0
     end
    end)
    if entry.ctrl~='none' then
     local pitch=entry.ctrl=='pitch'
     row(pitch and 'Bend (-8192–8191)' or 'Value (0–127)',function() changed,entry.ctrlValue=I.InputInt(ctx,'##ctrlValue',entry.ctrlValue,1,pitch and 1024 or 10) end)
     row('Control channel',function() changed,entry.ctrlChannel=I.Combo(ctx,'##ctrlChannel',entry.ctrlChannel,ksChannels) end)
     row('Length',function()
      local value=entry.ctrlTiming=='start' and 1 or entry.ctrlTiming=='end' and 2 or 0
      changed,value=I.Combo(ctx,'##ctrlTiming',value,'Full note\0Note start\0Note end\0')
      entry.ctrlTiming=({'full','start','end'})[value+1]
     end)
     row('Before (ms)',function() changed,entry.ctrlLead=I.InputDouble(ctx,'##ctrlLead',entry.ctrlLead,0.1,1,'%.2f') end)
     row('After (ms)',function() changed,entry.ctrlTail=I.InputDouble(ctx,'##ctrlTail',entry.ctrlTail,0.1,1,'%.2f') end)
     row('Reset value',function() changed,entry.ctrlReset=I.InputInt(ctx,'##ctrlReset',entry.ctrlReset,1,pitch and 1024 or 10) end)
    end
   end
   I.Spacing(ctx)
   I.Separator(ctx)
   if mode==3 then
    I.TextDisabled(ctx,savedMessage or 'Save this controller for the Controller menu.')
   elseif mode==0 then
    I.TextDisabled(ctx,savedMessage or 'Musical velocity stays unchanged.')
   else
    I.TextDisabled(ctx,savedMessage or 'Play a MIDI key or click a piano-roll key.')
    I.TextDisabled(ctx,after==2 and 'Ending is added separately; the starting articulation stays.' or 'Note and velocity are detected. You can edit them.')
   end
   if errorText then
    I.Spacing(ctx) I.PushStyleColor(ctx,I.Col_Text,0xFF9B8CFF)
    I.TextWrapped(ctx,errorText) I.PopStyleColor(ctx)
   end
   if selected~=0 and options.onRemove then
    I.Spacing(ctx)
    if I.Button(ctx,'Add variant',130,0) then
     local copy=snapshot() local sourceName=entry.name
     local proceed=true
     if mode==1 or mode==2 or mode==4 then
      local accepted,name=R.GetUserInputs('Articulation group',1,'Group name,extrawidth=240',entry.groupName or sourceName)
      if not accepted then proceed=false
      elseif not name:find('%S') then errorText='Enter a group name.' proceed=false
      else copy.groupName=name copy.grouped=true end
     end
     if proceed and selectEntry(0,true) then
      setEntry(copy) selected=0 editing=false variantMode=true first=true
      savedMessage='New variant of '..sourceName
     end
    end
    I.SameLine(ctx)
    if I.Button(ctx,selected<0 and 'Remove controller' or 'Remove articulation',160,0) then
     local removed,state=options.onRemove()
     if removed then
      drafts={} updateState(state) setEntry(state.entry) savedMessage='Articulation removed.'
     elseif state then errorText=state end
    end
   end
   I.Spacing(ctx)
   I.PushStyleColor(ctx,I.Col_Button,0x7750BAFF)
   I.PushStyleColor(ctx,I.Col_ButtonHovered,0x9065D5FF)
   if I.Button(ctx,'Save',90,0) then close=saveEntry(false) end
   I.SameLine(ctx)
   if I.Button(ctx,'Save & Next',125,0) then saveEntry(true) end
   I.PopStyleColor(ctx,2)
   I.SameLine(ctx)
   if I.Button(ctx,'Cancel',90,0) then close=true end
   if I.IsKeyPressed(ctx,I.Key_Escape) then close=true end
   I.End(ctx)
  end
  I.PopFont(ctx)
  I.PopStyleColor(ctx,12)
  I.PopStyleVar(ctx,3)
  if open==false or close then finish() end
 end
 local function tick()
  if closed then return end
  if options.isAlive and not options.isAlive() then finish() return end
  local ok,err=xpcall(function() learnPitch() draw() end,debug.traceback)
  if not ok then finish() R.MB(tostring(err),'ArticulationBox parameter window',0)
  elseif not closed then R.defer(tick) end
 end
 R.defer(tick)
 return true
end
