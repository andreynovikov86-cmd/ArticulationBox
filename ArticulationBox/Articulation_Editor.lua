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
 local mode=entry.mode=='ch' and 0 or entry.mode=='both' and 2 or 1
 local after=entry.lead<0 and 1 or 0
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
 local windowDrag
 local channels={} for n=1,16 do channels[#channels+1]=tostring(n) end
 channels=table.concat(channels,'\0')..'\0'
 local ksChannels='0 — Note channel\0'..channels
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
  result.mode=({'ch','ks','both'})[mode+1]
  result.lead=after==1 and -distance or distance
  return result
 end
 local function setEntry(updated)
  entry={} for k,v in pairs(updated) do entry[k]=v end
  mode=entry.mode=='ch' and 0 or entry.mode=='both' and 2 or 1
  after=entry.lead<0 and 1 or 0 distance=math.abs(entry.lead)
  editing=selected>0 first=true errorText=nil
 end
 local function updateState(state)
  if type(state)~='table' then return end
  options.bankName=state.bankName or options.bankName
  options.entries=state.entries or options.entries
  selected=state.selected or 0
 end
 local function selectEntry(index,preserveMessage)
  if not options.onSelect then return false end
  local updated,why=options.onSelect(index)
  if not updated then errorText=why or 'Could not open the articulation.' return false end
  drafts[selected]=snapshot() selected=index
  setEntry(drafts[index] or updated)
  variantMode=false
  if not preserveMessage then savedMessage=nil end
  return true
 end
 local function candidate()
  if not entry.name:find('%S') then return nil,'Enter an articulation name.' end
  if not integer(entry.channel,1,16) then return nil,'Note channel must be between 1 and 16.' end
  if not integer(entry.pitch,0,127) then return nil,'KS note must be between 0 and 127.' end
  if not integer(entry.velocity,1,127) then return nil,'KS velocity must be between 1 and 127.' end
  if not integer(entry.kschannel,0,16) then return nil,'KS channel must be between 0 and 16.' end
  if not distance or distance~=distance or distance<0.01 or distance>10000 then return nil,'Timing distance must be between 0.01 and 10000 ms.' end
  if not entry.length or entry.length~=entry.length or entry.length<0.01 or entry.length>10000 then return nil,'KS length must be between 0.01 and 10000 ms.' end
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
  if mode~=0 and learned then
   if not variantMode and options.onSelect then
    local fallback,current,exact
    for _,item in ipairs(options.entries or {}) do
     local a=item.entry
     if a and a.mode~='ch' and a.pitch==learned then
      fallback=fallback or item
      if item.index==selected then current=item end
      if a.velocity==learnedVelocity and (not exact or item.index==selected) then exact=item end
     end
    end
    local match=exact or current or fallback
    if match and match.index~=selected then selectEntry(match.index) end
   end
   entry.pitch=learned
   if learnedVelocity then entry.velocity=learnedVelocity end
  end
 end
 local function saveEntry(nextEntry)
  local result,why=candidate()
  if not result then errorText=why return false end
  local previous=selected
  local saved,message=options.onSave(result,nextEntry and previous==0)
  if not saved then errorText=message or 'Could not save the articulation.' return false end
  drafts[previous]=nil updateState(message)
  savedMessage='Saved: '..entry.name errorText=nil
  if nextEntry and previous==0 then
   if options.onSelect then options.onSelect(0) end
   selected=0 drafts[0]=nil
   entry.name='' editing=false first=true variantMode=false
  elseif nextEntry then
   local order=options.entries or {}
   for i,item in ipairs(order) do if item.index==selected then
    if order[i+1] then selectEntry(order[i+1].index,true) end
    break
   end end
  else editing=selected>0 end
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
  I.SetNextWindowSizeConstraints(ctx,380,mode==2 and 460 or 430,800,900)
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
   I.DrawList_AddText(drawList,x+23,y+1,0xEEEEEEFF,'Add / Edit articulation')
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
    row('Articulation',function()
     local nextChoice
     changed,nextChoice=I.Combo(ctx,'##articulation',choice,table.concat(labels,'\0')..'\0')
     if changed and nextChoice~=choice then
      selectEntry(indices[nextChoice+1])
     end
    end)
   end
   row('Name',function()
    if focusName then I.SetKeyboardFocusHere(ctx) end
    changed,entry.name=I.InputText(ctx,'##name',entry.name)
   end)
   I.Spacing(ctx)
   I.Text(ctx,'Articulation type (choose one)')
   local buttonWidth=(I.GetContentRegionAvail(ctx)-16)/3
   for i,label in ipairs({'Keyswitch','Channel','KS + Channel'}) do
    local value=({1,0,2})[i]
    if i>1 then I.SameLine(ctx) end
    local selected=mode==value
    if selected then I.PushStyleColor(ctx,I.Col_Button,0x7750BAFF) end
    if I.Button(ctx,label,buttonWidth,29) then mode=value end
    if selected then I.PopStyleColor(ctx) end
   end
   I.Spacing(ctx)
    if mode~=1 then
     row('Channel',function()
      local n
      changed,n=I.Combo(ctx,'##noteChannel',entry.channel-1,channels)
      entry.channel=n+1
     end)
    end
    if mode~=0 then
    row('KS note (auto)',function() changed,entry.pitch=I.InputInt(ctx,'##pitch',entry.pitch,1,12) end)
    row('KS velocity (1–127)',function() changed,entry.velocity=I.InputInt(ctx,'##velocity',entry.velocity,1,10) end)
    row('KS channel',function() changed,entry.kschannel=I.Combo(ctx,'##ksChannel',entry.kschannel,ksChannels) end)
    row('Trigger',function() changed,after=I.Combo(ctx,'##trigger',after,'Before note start\0After note start\0') end)
    row('Delay (ms)',function() changed,distance=I.InputDouble(ctx,'##distance',distance,0.1,1,'%.2f') end)
    end
   I.Spacing(ctx)
   I.Separator(ctx)
   if mode==0 then
    I.TextDisabled(ctx,savedMessage or 'Musical velocity stays unchanged.')
   else
    I.TextDisabled(ctx,savedMessage or 'Play a MIDI key or click a piano-roll key.')
    I.TextDisabled(ctx,'Note and velocity are detected. You can edit them.')
   end
   if errorText then
    I.Spacing(ctx) I.PushStyleColor(ctx,I.Col_Text,0xFF9B8CFF)
    I.TextWrapped(ctx,errorText) I.PopStyleColor(ctx)
   end
   if selected>0 and options.onRemove then
    I.Spacing(ctx)
    if I.Button(ctx,'Add variant',130,0) then
     local copy=snapshot() local sourceName=entry.name
     if selectEntry(0,true) then
      copy.name='' setEntry(copy) selected=0 editing=false variantMode=true first=true
      savedMessage='New variant of '..sourceName
     end
    end
    I.SameLine(ctx)
    if I.Button(ctx,'Remove articulation',160,0) then
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
