-- Load this action into the MIDI Editor section; keep both files together.
local _,path=reaper.get_action_context()
local folder=path:match('^(.*[\\/])')
ABART_POPUP=true
local ok,err=pcall(dofile,folder..'Articulation_Manager.lua')
ABART_POPUP=nil
if not ok then reaper.MB(tostring(err),'Articulation Manager',0) end
