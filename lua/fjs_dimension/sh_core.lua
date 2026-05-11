fjs_dimension = fjs_dimension or {}
fjs_dimension.Version = "1.0.0-beta"
fjs_dimension.Config = fjs_dimension.Config or {}

local defaults = {
    DefaultDimension = 0,
    MaxDimension = 65535,
    OverrideBullets = true,
    OverrideEffects = true,
    OverrideDecals = true,
    IsolateClientSounds = true,
    DebugSoundIsolation = true,
    ProjectileNearestOwnerRadius = 900,
    NPCIsolation = true,
    EnableDebugCommands = false,
    EnableChatCommand = true,
    BulletTracerLife = 0.055,
    BulletTracerWidth = 1.35,
    NPCPlayerUpdateInterval = 5,
    NPCNPCUpdateInterval = 60,
    NPCFastCheckInterval = 0.3,
    NPCChunkInterval = 0.01,
    NPCChecksPerChunk = 150,
    ServerRagdollLifetime = 90
}

for key, value in pairs(defaults) do
    if fjs_dimension.Config[key] == nil then
        fjs_dimension.Config[key] = value
    end
end

function fjs_dimension.NormalizeDimension(id)
    id = tonumber(id) or fjs_dimension.Config.DefaultDimension or 0
    id = math.floor(id)

    if id < 0 then
        id = 0
    end

    local maxDim = tonumber(fjs_dimension.Config.MaxDimension) or 65535
    if id > maxDim then
        id = maxDim
    end

    return id
end

local entMeta = FindMetaTable("Entity") or debug.getregistry().Entity
local plyMeta = FindMetaTable("Player") or debug.getregistry().Player

function entMeta:GetDimension()
    if not IsValid(self) then return fjs_dimension.Config.DefaultDimension or 0 end
    return self:GetNW2Int("m_dim_id", fjs_dimension.Config.DefaultDimension or 0)
end

function plyMeta:GetDimension()
    if not IsValid(self) then return fjs_dimension.Config.DefaultDimension or 0 end
    return self:GetNW2Int("m_dim_id", fjs_dimension.Config.DefaultDimension or 0)
end
