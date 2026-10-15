-- @description Articulation: Quick menu
-- Register in the MIDI Editor action section; keep beside Articulation_Manager.lua.
local _,path=reaper.get_action_context()
local folder=path:match('^(.*[\\/])')
ABART_QUICK_POPUP=true
local ok,err=pcall(dofile,folder..'Articulation_Manager.lua')
ABART_QUICK_POPUP=nil
if not ok then reaper.MB(tostring(err),'Articulation',0) end
