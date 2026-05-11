local root = "fjs_dimension/"

if SERVER then
    AddCSLuaFile(root .. "sh_core.lua")
    AddCSLuaFile(root .. "cl_init.lua")
    
    include(root .. "sh_core.lua")
    include(root .. "sv_init.lua")
else
    include(root .. "sh_core.lua")
    include(root .. "cl_init.lua")
end
