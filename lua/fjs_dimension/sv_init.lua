fjs_dimension = fjs_dimension or {}
fjs_dimension.ActiveNPCs = fjs_dimension.ActiveNPCs or {}
fjs_dimension.LastSpawnIntent = fjs_dimension.LastSpawnIntent or {}
fjs_dimension.EntitiesByDim = fjs_dimension.EntitiesByDim or {}
fjs_dimension.EntityDimCache = fjs_dimension.EntityDimCache or {}

util.AddNetworkString("FJS_Dim_BulletVisuals")
util.AddNetworkString("FJS_Dim_PlaySoundWorld")
util.AddNetworkString("FJS_Dim_CustomDecal")

local entMeta = FindMetaTable("Entity") or debug.getregistry().Entity

local og_sv_Decal = util.Decal
local og_sv_Effect = util.Effect
local Config = fjs_dimension.Config or {}
local ForceNPCPacify

local instantVisualClasses = {
    ["env_explosion"] = true,
    ["env_physexplosion"] = true,
    ["info_particle_system"] = true,
    ["env_spark"] = true,
    ["env_fire"] = true,
    ["ar2explosion"] = true
}

local instantClasses = {
    ["env_explosion"] = true,
    ["env_physexplosion"] = true,
    ["info_particle_system"] = true,
    ["env_spark"] = true,
    ["env_fire"] = true,
    ["ar2explosion"] = true,
    ["instanced_scripted_scene"] = true,
    ["logic_choreographed_scene"] = true,
    ["scripted_scene"] = true
}

fjs_dimension.Perf = fjs_dimension.Perf or {
    enabled = false,
    data = {}
}

local function FJSPerfStart(name)
    if not fjs_dimension.Perf.enabled then return nil end
    return SysTime()
end

local function FJSPerfEnd(name, startTime)
    if not fjs_dimension.Perf.enabled or not startTime then return end

    local elapsed = SysTime() - startTime
    local data = fjs_dimension.Perf.data[name]

    if not data then
        data = {
            calls = 0,
            total = 0,
            max = 0
        }

        fjs_dimension.Perf.data[name] = data
    end

    data.calls = data.calls + 1
    data.total = data.total + elapsed

    if elapsed > data.max then
        data.max = elapsed
    end
end

if Config.EnableDebugCommands then
concommand.Add("fjs_dim_perf_toggle", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end

    fjs_dimension.Perf.enabled = not fjs_dimension.Perf.enabled
    fjs_dimension.Perf.data = {}

    print("[FJS Dimension API] Perf enabled:", fjs_dimension.Perf.enabled)
end)

concommand.Add("fjs_dim_perf_print", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end

    print("========== FJS Dimension Performance ==========")

    for name, data in pairs(fjs_dimension.Perf.data) do
        local avg = data.total / math.max(data.calls, 1)

        print(string.format(
            "%s | calls: %d | avg: %.5f ms | max: %.5f ms | total: %.5f ms",
            name,
            data.calls,
            avg * 1000,
            data.max * 1000,
            data.total * 1000
        ))
    end

    print("==============================================")
end)

concommand.Add("fjs_dim_perf_reset", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end

    fjs_dimension.Perf.data = {}
    print("[FJS Dimension API] Perf data reset.")
end)

concommand.Add("fjs_dim_debug_counts", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end

    local dimPlayers = {}
    local dimNPCs = {}
    local dimEnts = {}

    for _, p in ipairs(player.GetAll()) do
        if not IsValid(p) or not p.GetDimension then continue end

        local dim = p:GetDimension()
        dimPlayers[dim] = (dimPlayers[dim] or 0) + 1
    end

    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) or not ent.GetDimension then continue end

        local dim = ent:GetDimension()
        dimEnts[dim] = (dimEnts[dim] or 0) + 1

        if ent:IsNPC() then
            dimNPCs[dim] = (dimNPCs[dim] or 0) + 1
        end
    end

    print("========== FJS Dimension Counts ==========")

    local printed = {}

    for dim, count in pairs(dimEnts) do
        printed[dim] = true

        print(string.format(
            "Dim %s | players: %d | npcs: %d | dimensional ents: %d",
            tostring(dim),
            dimPlayers[dim] or 0,
            dimNPCs[dim] or 0,
            count or 0
        ))
    end

    for dim, count in pairs(dimPlayers) do
        if printed[dim] then continue end

        print(string.format(
            "Dim %s | players: %d | npcs: %d | dimensional ents: %d",
            tostring(dim),
            count or 0,
            dimNPCs[dim] or 0,
            dimEnts[dim] or 0
        ))
    end

    print("==========================================")
end)

concommand.Add("fjs_dim_cache_counts", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end

    print("========== FJS Dimension Cache Counts ==========")

    for dim, bucket in pairs(fjs_dimension.EntitiesByDim or {}) do
        local count = 0

        for ent, _ in pairs(bucket) do
            if IsValid(ent) then
                count = count + 1
            else
                bucket[ent] = nil
                fjs_dimension.EntityDimCache[ent] = nil
            end
        end

        print(string.format("Dim %s | cached ents: %d", tostring(dim), count))
    end

    print("===============================================")
end)

concommand.Add("fjs_dim_cache_rebuild", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end

    if fjs_dimension.RebuildDimensionCache then
        fjs_dimension.RebuildDimensionCache()
    end

    print("[FJS Dimension API] Dimension cache rebuilt.")
end)

end

local function NormalizeDimension(id)
    if fjs_dimension.NormalizeDimension then
        return fjs_dimension.NormalizeDimension(id)
    end

    id = tonumber(id) or 0
    id = math.floor(id)
    if id < 0 then id = 0 end
    return id
end

local function EnsureDimBucket(dim)
    dim = NormalizeDimension(dim)

    fjs_dimension.EntitiesByDim[dim] = fjs_dimension.EntitiesByDim[dim] or {}

    return fjs_dimension.EntitiesByDim[dim]
end

local function RegisterEntityInDimensionCache(ent, dim)
    if not IsValid(ent) then return end

    dim = NormalizeDimension(dim)

    local oldDim = fjs_dimension.EntityDimCache[ent]

    if oldDim ~= nil and fjs_dimension.EntitiesByDim[oldDim] then
        fjs_dimension.EntitiesByDim[oldDim][ent] = nil
    end

    fjs_dimension.EntityDimCache[ent] = dim
    EnsureDimBucket(dim)[ent] = true
end

local function RemoveEntityFromDimensionCache(ent)
    local oldDim = fjs_dimension.EntityDimCache[ent]

    if oldDim ~= nil and fjs_dimension.EntitiesByDim[oldDim] then
        fjs_dimension.EntitiesByDim[oldDim][ent] = nil
    end

    fjs_dimension.EntityDimCache[ent] = nil
end

function fjs_dimension.RebuildDimensionCache()
    fjs_dimension.EntitiesByDim = {}
    fjs_dimension.EntityDimCache = {}

    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent.GetDimension then
            RegisterEntityInDimensionCache(ent, ent:GetDimension())
        end
    end
end

local function IsDimensional(ent)
    return IsValid(ent) and ent.GetDimension ~= nil
end

local function AddValidRecipientsByDimension(recipients, dim, exceptPlayer)
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:GetDimension() == dim and ply ~= exceptPlayer then
            table.insert(recipients, ply)
        end
    end
end

local function SendToStillValid(recipients, sendFn)
    local validRecipients = {}

    for _, ply in ipairs(recipients) do
        if IsValid(ply) then
            table.insert(validRecipients, ply)
        end
    end

    if #validRecipients <= 0 then return end
    sendFn(validRecipients)
end

function fjs_dimension.RequestNPCRelationshipUpdate(delay)
    delay = tonumber(delay) or 1.0

    if not timer.Exists("FJS_Dim_AI_DebouncedPlayerUpdate") then
        timer.Create("FJS_Dim_AI_DebouncedPlayerUpdate", delay, 1, function()
            if fjs_dimension.UpdateNPCPlayerRelationships then
                fjs_dimension.UpdateNPCPlayerRelationships()
            end
        end)
    end

    fjs_dimension.NPCNPCRelationshipsDirty = true

    if not timer.Exists("FJS_Dim_AI_DebouncedNPCNPCChunkStart") then
        timer.Create("FJS_Dim_AI_DebouncedNPCNPCChunkStart", math.max(delay + 1, 2), 1, function()
            if fjs_dimension.NPCNPCRelationshipsDirty and fjs_dimension.StartNPCNPCRelationshipChunkUpdate then
                fjs_dimension.StartNPCNPCRelationshipChunkUpdate()
            end
        end)
    end
end

function fjs_dimension.FastNPCEnemySanityCheck()
    local perf = FJSPerfStart("FastNPCEnemySanityCheck")

    for npc, _ in pairs(fjs_dimension.ActiveNPCs) do
        if not IsValid(npc) or not npc:IsNPC() or npc:Health() <= 0 then
            fjs_dimension.ActiveNPCs[npc] = nil
            continue
        end

        local npcDim = npc:GetDimension()

        local enemy = npc:GetEnemy()
        if IsValid(enemy) and enemy.GetDimension and enemy:GetDimension() ~= npcDim then
            ForceNPCPacify(npc, enemy)
        end

        local target = npc:GetTarget()
        if IsValid(target) and target.GetDimension and target:GetDimension() ~= npcDim then
            ForceNPCPacify(npc, target)
        end
    end

    FJSPerfEnd("FastNPCEnemySanityCheck", perf)
end

hook.Add("InitPostEntity", "FJS_Dim_RebuildDimensionCacheOnLoad", function()
    timer.Simple(1, function()
        if fjs_dimension.RebuildDimensionCache then
            fjs_dimension.RebuildDimensionCache()
        end
    end)
end)

duplicator.RegisterEntityModifier("m_dim_persistence", function(ply, ent, data)
    if IsValid(ent) and data and data.dimID ~= nil then
        ent:SetDimension(data.dimID)
    end
end)

function fjs_dimension.GetTrueEntityOwner(ent)
    if not IsValid(ent) then return NULL end

    local owner = NULL

    if ent.GetOwner and IsValid(ent:GetOwner()) then
        owner = ent:GetOwner()
    elseif ent.GetThrower and IsValid(ent:GetThrower()) then
        owner = ent:GetThrower()
    elseif ent.GetInstigator and IsValid(ent:GetInstigator()) then
        owner = ent:GetInstigator()
    elseif ent.GetSaveTable then
        local ok, st = pcall(ent.GetSaveTable, ent)

        if ok and st then
            if IsValid(st.m_hOwnerEntity) then
                owner = st.m_hOwnerEntity
            elseif IsValid(st.m_hThrower) then
                owner = st.m_hThrower
            end
        end
    end

    if IsValid(owner) then
        if owner:IsWeapon() and IsValid(owner:GetOwner()) then
            return owner:GetOwner()
        end

        return owner
    end

    return NULL
end


local function IsDimensionalCombatSound(soundName)
    local snd = string.lower(soundName or "")

    if snd == "" then return false end

    return string.find(snd, "weapons/", 1, true)
        or string.find(snd, "weapon_", 1, true)
        or string.find(snd, "gun", 1, true)
        or string.find(snd, "shot", 1, true)
        or string.find(snd, "bullet", 1, true)
        or string.find(snd, "hit", 1, true)
        or string.find(snd, "impact", 1, true)
        or string.find(snd, "rpg", 1, true)
        or string.find(snd, "rocket", 1, true)
        or string.find(snd, "missile", 1, true)
        or string.find(snd, "grenade", 1, true)
        or string.find(snd, "explode", 1, true)
        or string.find(snd, "explosion", 1, true)
        or string.find(snd, "ric", 1, true)
        or string.find(snd, "vo/", 1, true)
        or string.find(snd, "npc/", 1, true)
        or string.find(snd, "pain", 1, true)
        or string.find(snd, "die", 1, true)
        or string.find(snd, "death", 1, true)
        or string.find(snd, "groan", 1, true)
        or string.find(snd, "zombie", 1, true)
        or string.find(snd, "headcrab", 1, true)
        or string.find(snd, "combine", 1, true)
end

local function IsProjectileLike(ent)
    if not IsValid(ent) then return false end

    local class = string.lower(ent:GetClass() or "")

    return string.find(class, "projectile", 1, true)
        or string.find(class, "rocket", 1, true)
        or string.find(class, "missile", 1, true)
        or string.find(class, "grenade", 1, true)
        or string.find(class, "rpg", 1, true)
        or string.find(class, "bolt", 1, true)
        or string.find(class, "flechette", 1, true)
        or class == "prop_combine_ball"
        or class == "hunter_flechette"
        or class == "crossbow_bolt"
        or class == "npc_grenade_frag"
        or class == "grenade_ar2"
        or class == "rpg_missile"
end

local function FindNearestDimensionAtPosition(pos, radius)
    if not isvector(pos) then return nil end

    local maxDist = tonumber(radius) or tonumber(Config.ProjectileNearestOwnerRadius) or 900
    local bestDist = maxDist * maxDist
    local bestDim = nil

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply.GetDimension then continue end

        local dist = ply:GetPos():DistToSqr(pos)
        if dist < bestDist then
            bestDist = dist
            bestDim = ply:GetDimension()
        end
    end

    for npc, _ in pairs(fjs_dimension.ActiveNPCs or {}) do
        if not IsValid(npc) or not npc:IsNPC() or not npc.GetDimension then
            fjs_dimension.ActiveNPCs[npc] = nil
            continue
        end

        local dist = npc:GetPos():DistToSqr(pos)

        if dist < bestDist then
            bestDist = dist
            bestDim = npc:GetDimension()
        end
    end

    return bestDim
end

local function SendWorldSoundToDimension(dim, soundName, pos, volume, pitch, level)
    dim = NormalizeDimension(dim)

    local recipients = fjs_dimension.GetPlayersInDimension(dim)
    if #recipients <= 0 then return end

    net.Start("FJS_Dim_PlaySoundWorld")
        net.WriteString(soundName or "")
        net.WriteVector(pos or vector_origin)
        net.WriteFloat(tonumber(volume) or 1)
        net.WriteUInt(math.Clamp(math.floor(tonumber(pitch) or 100), 0, 255), 8)
        net.WriteUInt(math.Clamp(math.floor(tonumber(level) or 75), 0, 255), 8)
    net.Send(recipients)
end

-- Propagación recursiva estricta de visibilidad (Mejora Garry Phone)
local function RecursiveSetPreventTransmit(ent, ply, shouldHide)
    if not IsValid(ent) or not IsValid(ply) then return end

    ent.FJS_Dim_Hidden = shouldHide -- Caché rápida en Lua
    ent:SetPreventTransmit(ply, shouldHide)

    if ent.GetChildren then
        for _, child in ipairs(ent:GetChildren()) do
            RecursiveSetPreventTransmit(child, ply, shouldHide)
        end
    end
end

function fjs_dimension.SyncVisibility(targetEnt)
    local perf = FJSPerfStart("SyncVisibility")

    if not IsValid(targetEnt) then
        FJSPerfEnd("SyncVisibility", perf)
        return
    end

    if targetEnt.SetBloodColor then
        targetEnt:SetBloodColor(DONT_BLEED)
    end

    if targetEnt:IsPlayer() then
        local plyDim = targetEnt:GetDimension()

        for _, ent in ipairs(ents.GetAll()) do
            if not IsValid(ent) or ent == targetEnt then continue end
            if ent == targetEnt:GetActiveWeapon() or ent == targetEnt:GetViewModel() then continue end

            local class = ent:GetClass()
            if class == "gmod_hands" or class == "viewmodel" then continue end
            
            if ent.GetOwner and ent:GetOwner() == targetEnt then 
                RecursiveSetPreventTransmit(ent, targetEnt, false)
                continue 
            end
            
            if ent.GetDimension then
                local shouldHide = ent:GetDimension() ~= plyDim
                RecursiveSetPreventTransmit(ent, targetEnt, shouldHide)
            end
        end

    end

    local entDim = targetEnt:GetDimension()

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) then continue end

        if targetEnt.GetOwner and targetEnt:GetOwner() == ply then
            RecursiveSetPreventTransmit(targetEnt, ply, false)
            continue
        end

        local shouldHide = entDim ~= ply:GetDimension()
        RecursiveSetPreventTransmit(targetEnt, ply, shouldHide)

        if targetEnt.GetActiveWeapon and IsValid(targetEnt:GetActiveWeapon()) then
            RecursiveSetPreventTransmit(targetEnt:GetActiveWeapon(), ply, shouldHide)
        end
    end

    FJSPerfEnd("SyncVisibility", perf)
end

-- Función recursiva para propagar IDs de dimensión en jerarquías profundas
local function RecursiveSetChildDimension(ent, id)
    if not IsValid(ent) or not ent.GetChildren then return end

    for _, child in ipairs(ent:GetChildren()) do
        if IsValid(child) then
            RegisterEntityInDimensionCache(child, id)
            child:SetCustomCollisionCheck(true)
            child:SetNW2Int("m_dim_id", id)
            duplicator.StoreEntityModifier(child, "m_dim_persistence", { dimID = id })
            
            RecursiveSetChildDimension(child, id)
        end
    end
end

function entMeta:SetDimension(id)
    if not IsValid(self) then return end

    id = NormalizeDimension(id)

    local oldDim = self:GetDimension()

    if hook.Run("FJSDimensionCanChange", self, oldDim, id) == false then
        return false
    end

    RegisterEntityInDimensionCache(self, id)

    self:SetCustomCollisionCheck(true)
    self:SetNW2Int("m_dim_id", id)

    duplicator.StoreEntityModifier(self, "m_dim_persistence", { dimID = id })

    if self:IsNPC() then
        fjs_dimension.ActiveNPCs[self] = true

        timer.Simple(0, function()
            if not IsValid(self) or not self:IsNPC() then return end

            if fjs_dimension.FastNPCEnemySanityCheck then
                fjs_dimension.FastNPCEnemySanityCheck()
            end

            if fjs_dimension.UpdateNPCPlayerRelationships then
                fjs_dimension.UpdateNPCPlayerRelationships()
            end
        end)
    end

    if self:IsPlayer() and self.GetWeapons then
        for _, wep in ipairs(self:GetWeapons()) do
            if IsValid(wep) then
                RegisterEntityInDimensionCache(wep, id)
                wep:SetCustomCollisionCheck(true)
                wep:SetNW2Int("m_dim_id", id)
                RecursiveSetPreventTransmit(wep, self, false)
            end
        end
    elseif self.GetActiveWeapon and IsValid(self:GetActiveWeapon()) then
        local wep = self:GetActiveWeapon()

        RegisterEntityInDimensionCache(wep, id)
        wep:SetCustomCollisionCheck(true)
        wep:SetNW2Int("m_dim_id", id)
    end

    -- Propagar dimensión de manera completamente recursiva a todos los hijos
    RecursiveSetChildDimension(self, id)

    timer.Simple(0, function()
        if IsValid(self) then
            fjs_dimension.SyncVisibility(self)
        end
    end)

    if self:IsPlayer() then
        hook.Run("FJSDimensionPlayerChanged", self, oldDim, id)
        hook.Run("FJSDimensionChanged", self, oldDim, id)

        timer.Simple(0, function()
            if fjs_dimension.UpdateNPCPlayerRelationships then
                fjs_dimension.UpdateNPCPlayerRelationships()
            end
        end)

        timer.Simple(0.2, function()
            if fjs_dimension.UpdateNPCPlayerRelationships then
                fjs_dimension.UpdateNPCPlayerRelationships()
            end
        end)

        fjs_dimension.RequestNPCRelationshipUpdate(1.0)
    else
        hook.Run("FJSDimensionEntityChanged", self, oldDim, id)
        hook.Run("FJSDimensionChanged", self, oldDim, id)

        if self:IsNPC() then
            fjs_dimension.RequestNPCRelationshipUpdate(1.0)
        end
    end
end

function fjs_dimension.GetPlayersInDimension(dim)
    dim = NormalizeDimension(dim)

    local recipients = {}
    AddValidRecipientsByDimension(recipients, dim)

    return recipients
end


function fjs_dimension.SetEntityDimension(ent, dim)
    if not IsValid(ent) or not ent.SetDimension then return false end
    return ent:SetDimension(dim)
end

function fjs_dimension.GetEntitiesInDimension(dim)
    dim = NormalizeDimension(dim)

    local result = {}
    local bucket = fjs_dimension.EntitiesByDim and fjs_dimension.EntitiesByDim[dim]

    if not bucket then return result end

    for ent, _ in pairs(bucket) do
        if IsValid(ent) then
            result[#result + 1] = ent
        else
            bucket[ent] = nil
            if fjs_dimension.EntityDimCache then
                fjs_dimension.EntityDimCache[ent] = nil
            end
        end
    end

    return result
end

function fjs_dimension.SendNetToDimension(dim)
    local recipients = fjs_dimension.GetPlayersInDimension(dim)
    if #recipients <= 0 then return false end
    net.Send(recipients)
    return true
end

function fjs_dimension.PlaySoundInDimension(dim, snd, pos, volume, pitch, level)
    dim = NormalizeDimension(dim)

    local recipients = fjs_dimension.GetPlayersInDimension(dim)
    if #recipients <= 0 then return end

    net.Start("FJS_Dim_PlaySoundWorld", true)
        net.WriteString(tostring(snd or ""))
        net.WriteVector(pos or vector_origin)
        net.WriteFloat(tonumber(volume) or 1)
        net.WriteUInt(math.Clamp(math.floor(tonumber(pitch) or 100), 0, 255), 8)
        net.WriteUInt(math.Clamp(math.floor(tonumber(level) or 75), 0, 255), 8)
    net.Send(recipients)
end
fjs_dimension.InternalSoundGuard = fjs_dimension.InternalSoundGuard or false

hook.Add("EntityEmitSound", "M_Dimensions_StrictSoundIsolator", function(data)
    if fjs_dimension.InternalSoundGuard then return end

    local ent = data.Entity
    if not IsValid(ent) or ent:IsWorld() then return end 

    if IsProjectileLike(ent) then return end

    local trueOwner = fjs_dimension.GetTrueEntityOwner(ent)
    if IsValid(trueOwner) and trueOwner.GetDimension then
        local ownerDim = trueOwner:GetDimension()
        if ent.GetDimension and ent:GetDimension() ~= ownerDim then
            ent:SetDimension(ownerDim)
        end
    end

    local checkEnt = IsValid(trueOwner) and trueOwner or ent

    if checkEnt.GetDimension then
        local dim = checkEnt:GetDimension()
        local snd = string.lower(data.SoundName or "")
        
        local isPredicted = false
        if checkEnt:IsPlayer() then
            local isCombatPred = string.find(snd, "weapon") or string.find(snd, "step") or string.find(snd, "fire") or string.find(snd, "shot")
            if ent:IsWeapon() or data.Channel == CHAN_WEAPON or isCombatPred then
                isPredicted = true
            end
        end

        local filter = RecipientFilter()
        local hasRecipients = false

        for _, p in ipairs(player.GetAll()) do
            if p:GetDimension() == dim then
                if isPredicted and p == checkEnt then continue end
                filter:AddPlayer(p)
                hasRecipients = true
            end
        end

        if not hasRecipients then 
            return false 
        end

        -- =====================================================================
        -- RE-EMISIÓN NATIVA (La magia ocurre aquí)
        -- =====================================================================
        fjs_dimension.InternalSoundGuard = true

        checkEnt:EmitSound(
            data.SoundName,
            data.SoundLevel or 75,
            data.Pitch or 100,
            data.Volume or 1,
            data.Channel or CHAN_AUTO,
            data.SoundFlags or 0,
            data.Dsp or 0,
            filter 
        )

        fjs_dimension.InternalSoundGuard = false

        return false 
    end
end)

--[[
hook.Add("EntityEmitSound", "M_Dimensions_StrictSoundIsolator", function(data)
    local ent = data.Entity
    if not IsValid(ent) or ent:IsWorld() then return end 

    if ent:IsVehicle() then return end 


    local snd = string.lower(data.SoundName or "")
    if string.find(snd, "idle") and ent:GetClass() == "class_C_BaseEntity" then
        return
    end

    local trueOwner = fjs_dimension.GetTrueEntityOwner(ent)
    if IsValid(trueOwner) and trueOwner.GetDimension then
        local ownerDim = trueOwner:GetDimension()
        if ent.GetDimension and ent:GetDimension() != ownerDim then
            ent:SetDimension(ownerDim)
        end
    end

    local checkEnt = IsValid(trueOwner) and trueOwner or ent

    if checkEnt.GetDimension then
        local dim = checkEnt:GetDimension()
        
        local isPredicted = false
        if checkEnt:IsPlayer() then
            local isCombatPred = string.find(snd, "weapon") or string.find(snd, "step") or string.find(snd, "fire") or string.find(snd, "shot")
            if ent:IsWeapon() or data.Channel == CHAN_WEAPON or isCombatPred then
                isPredicted = true
            end
        end

        local recipients = {}
        for _, p in ipairs(player.GetAll()) do
            if p:GetDimension() == dim then
                if isPredicted and p == checkEnt then continue end
                table.insert(recipients, p)
            end
        end

        if #recipients > 0 then
            local sendSnd = data.SoundName
            local sendPos = data.Pos or checkEnt:GetPos()
            local sendVol = data.Volume or 1
            local sendPitch = math.Clamp(data.Pitch or 100, 0, 255)
            local entIndex = checkEnt:EntIndex() -- Capturamos el ID numérico bruto

            timer.Simple(0, function()
                local validRecipients = {}
                for _, p in ipairs(recipients) do
                    if IsValid(p) then table.insert(validRecipients, p) end
                end

                if #validRecipients > 0 then
                    net.Start("FJS_Dim_PlaySoundWorld", true) 
                        net.WriteString(sendSnd)
                        net.WriteUInt(entIndex, 16) -- MANDAMOS EL ID BRUTO (Evita el desface de red)
                        net.WriteVector(sendPos)
                        net.WriteFloat(sendVol)
                        net.WriteUInt(sendPitch, 8)
                    net.Send(validRecipients)
                end
            end)
        end
        
        return false 
    end
end)]]



function fjs_dimension.Decal(dim, name, startPos, endPos)
    dim = NormalizeDimension(dim)

    local recipients = fjs_dimension.GetPlayersInDimension(dim)
    if #recipients <= 0 then return end

    net.Start("FJS_Dim_CustomDecal", true)
        net.WriteString(tostring(name or ""))
        net.WriteVector(startPos or vector_origin)
        net.WriteVector(endPos or startPos or vector_origin)
    net.Send(recipients)
end

local isInternalBullet = false

hook.Add("EntityFireBullets", "FJS_Dim_BulletsMaster", function(shooter, data)
    if Config.OverrideBullets == false then return end

    local perf = FJSPerfStart("EntityFireBullets")

    if isInternalBullet then
        FJSPerfEnd("EntityFireBullets", perf)
        return
    end
    if not IsValid(shooter) or not shooter.GetDimension then
        FJSPerfEnd("EntityFireBullets", perf)
        return
    end

    if shooter:IsNPC() then
        local shooterDim = shooter:GetDimension()

        local enemy = shooter:GetEnemy()
        if IsValid(enemy) and enemy.GetDimension and enemy:GetDimension() ~= shooterDim then
            if fjs_dimension.FastNPCEnemySanityCheck then
                fjs_dimension.FastNPCEnemySanityCheck()
            end

            FJSPerfEnd("EntityFireBullets", perf)
            return false
        end

        local target = shooter:GetTarget()
        if IsValid(target) and target.GetDimension and target:GetDimension() ~= shooterDim then
            if fjs_dimension.FastNPCEnemySanityCheck then
                fjs_dimension.FastNPCEnemySanityCheck()
            end

            FJSPerfEnd("EntityFireBullets", perf)
            return false
        end
    end

    local shooterDim = shooter:GetDimension()
    local newData = table.Copy(data or {})
    local filter = {}

    if type(newData.Filter) == "table" then
        table.Add(filter, newData.Filter)
    elseif IsValid(newData.Filter) then
        table.insert(filter, newData.Filter)
    end

    for dim, bucket in pairs(fjs_dimension.EntitiesByDim or {}) do
        if dim == shooterDim then continue end

        for ent, _ in pairs(bucket) do
            if not IsValid(ent) then
                bucket[ent] = nil
                fjs_dimension.EntityDimCache[ent] = nil
                continue
            end

            if ent ~= shooter and ent.GetDimension and ent:GetDimension() ~= shooterDim then
                table.insert(filter, ent)
            end
        end
    end

    newData.Filter = filter

    local ogTracerName = newData.TracerName or "Tracer"
    local ogTracerFrequency = tonumber(newData.Tracer) or 0
    local ogDamage = tonumber(newData.Damage) or 0
    local ogCallback = newData.Callback

    newData.Tracer = 0

    newData.Callback = function(attacker, tr, dmginfo)
        local callbackRet

        if ogCallback then
            callbackRet = ogCallback(attacker, tr, dmginfo)
        end

        local recipients = {}
        AddValidRecipientsByDimension(recipients, shooterDim, shooter)

        if #recipients > 0 and tr then
            local startPos = tr.StartPos or newData.Src or vector_origin
            local hitPos = tr.HitPos or startPos
            local hitNormal = tr.HitNormal or vector_up
            local hitEnt = tr.Entity or NULL
            local dmgVal = math.Clamp(math.Round(ogDamage), 0, 65535)
            local shouldDrawTracer = ogTracerFrequency > 0 and math.random(1, ogTracerFrequency) == 1

            timer.Simple(0, function()
                SendToStillValid(recipients, function(validRecipients)
                    net.Start("FJS_Dim_BulletVisuals", true)
                        net.WriteVector(startPos)
                        net.WriteVector(hitPos)
                        net.WriteNormal(hitNormal)
                        net.WriteBool(shouldDrawTracer)
                        net.WriteString(shouldDrawTracer and ogTracerName or "")
                        net.WriteEntity(hitEnt)
                        net.WriteUInt(dmgVal, 16)
                        net.WriteUInt(math.Clamp(shooterDim, 0, 65535), 16)
                    net.Send(validRecipients)
                end)
            end)
        end

        return callbackRet
    end

    isInternalBullet = true

    local ok, err = pcall(function()
        shooter:FireBullets(newData, true)
    end)

    isInternalBullet = false

    if not ok then
        ErrorNoHalt("[FJS Dimension API] FireBullets error: " .. tostring(err) .. "\n")
    end

    FJSPerfEnd("EntityFireBullets", perf)
    return false
end)

local function GuessDimensionFromPosition(pos)
    local dim = 0
    local closestDist = math.huge

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) then continue end

        local d = ply:GetPos():DistToSqr(pos or vector_origin)

        if d < closestDist then
            closestDist = d
            dim = ply:GetDimension()
        end
    end

    return dim
end

function util.Decal(name, startPos, endPos, filter)
    if Config.OverrideDecals == false then
        return og_sv_Decal(name, startPos, endPos, filter)
    end

    if filter ~= nil then
        return og_sv_Decal(name, startPos, endPos, filter)
    end

    local dim = GuessDimensionFromPosition(startPos)

    return fjs_dimension.Decal(dim, name, startPos, endPos)
end

function util.Effect(name, eff, allowOverride, filter)
    if Config.OverrideEffects == false then
        return og_sv_Effect(name, eff, allowOverride, filter)
    end

    if filter ~= nil then
        return og_sv_Effect(name, eff, allowOverride, filter)
    end

    if allowOverride == nil then
        allowOverride = true
    end

    local ent = eff and eff:GetEntity() or NULL
    local pos = eff and eff:GetOrigin() or vector_origin
    local dim = 0

    if IsDimensional(ent) then
        dim = ent:GetDimension()
    else
        dim = GuessDimensionFromPosition(pos)
    end

    local strictFilter = RecipientFilter()

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:GetDimension() == dim then
            strictFilter:AddPlayer(ply)
        end
    end

    return og_sv_Effect(name, eff, allowOverride, strictFilter)
end

fjs_dimension.LastSpawnIntent = fjs_dimension.LastSpawnIntent or {}

local function MarkSpawnIntent(ply)
    if not IsValid(ply) then return end

    fjs_dimension.LastSpawnIntent[ply] = {
        time = CurTime(),
        dim = ply:GetDimension()
    }
end

hook.Add("PlayerSpawnProp", "FJS_Dim_RememberSpawnProp", MarkSpawnIntent)
hook.Add("PlayerSpawnNPC", "FJS_Dim_RememberSpawnNPC", MarkSpawnIntent)
hook.Add("PlayerSpawnSENT", "FJS_Dim_RememberSpawnSENT", MarkSpawnIntent)
hook.Add("PlayerSpawnVehicle", "FJS_Dim_RememberSpawnVehicle", MarkSpawnIntent)
hook.Add("PlayerSpawnRagdoll", "FJS_Dim_RememberSpawnRagdoll", MarkSpawnIntent)
hook.Add("PlayerSpawnSWEP", "FJS_Dim_RememberSpawnSWEP", MarkSpawnIntent)
hook.Add("PlayerSpawnEffect", "FJS_Dim_RememberSpawnEffect", MarkSpawnIntent)

local function GetMostRecentSpawnIntent()
    local newestPly = NULL
    local newestTime = 0
    local now = CurTime()

    for ply, data in pairs(fjs_dimension.LastSpawnIntent) do
        if not IsValid(ply) then
            fjs_dimension.LastSpawnIntent[ply] = nil
            continue
        end

        local t = data and data.time or 0

        if now - t <= 2 and t > newestTime then
            newestPly = ply
            newestTime = t
        end
    end

    return newestPly
end

local function ResolveSpawnOwner(ent)
    if not IsValid(ent) then return NULL end

    -- Escalado de jerarquía de padres (Mejora inspirada en Garry Phone)
    local parent = ent:GetParent()
    while IsValid(parent) do
        if parent.GetDimension and parent:GetDimension() ~= 0 then
            return parent
        end
        if parent.GetOwner and IsValid(parent:GetOwner()) then
            return parent:GetOwner()
        end
        parent = parent:GetParent()
    end

    if IsValid(ent.PlayerCreator) then
        return ent.PlayerCreator
    end

    if ent.GetCreator then
        local ok, creator = pcall(ent.GetCreator, ent)

        if ok and IsValid(creator) then
            return creator
        end
    end

    if ent.CPPIGetOwner then
        local ok, owner = pcall(ent.CPPIGetOwner, ent)

        if ok and IsValid(owner) then
            return owner
        end
    end

    if ent.GetInternalVariable then
        local ok, internalOwner = pcall(ent.GetInternalVariable, ent, "m_hOwnerEntity")

        if ok and IsValid(internalOwner) then
            return internalOwner
        end
    end

    local trueOwner = fjs_dimension.GetTrueEntityOwner(ent)

    if IsValid(trueOwner) then
        return trueOwner
    end

    return GetMostRecentSpawnIntent()
end

local function TryApplyInheritedDimension(ent, attempt)
    if not IsValid(ent) or ent:IsWorld() then return end

    local class = ent:GetClass() or ""

    if string.StartWith(class, "phys_") or string.StartWith(class, "info_") then
        return
    end

    if class == "instanced_scripted_scene"
    or class == "logic_choreographed_scene"
    or class == "scripted_scene"
    or string.find(class, "scene", 1, true) then
        timer.Simple(0, function()
            if not IsValid(ent) then return end

            local pos = ent:GetPos()
            local bestDim = nil
            local bestDist = 250000

            for _, npc in ipairs(ents.GetAll()) do
                if not IsValid(npc) then continue end
                if not npc:IsNPC() then continue end
                if not npc.GetDimension then continue end

                local dist = npc:GetPos():DistToSqr(pos)

                if dist < bestDist then
                    bestDist = dist
                    bestDim = npc:GetDimension()
                end
            end

            if bestDim ~= nil then
                ent:SetDimension(bestDim)
            else
                ent:SetCustomCollisionCheck(true)
                fjs_dimension.SyncVisibility(ent)
            end
        end)

        return
    end

    if ent:GetDimension() ~= 0 then return end

    local owner = ResolveSpawnOwner(ent)

    if IsValid(owner) and owner.GetDimension then
        ent:SetDimension(owner:GetDimension())
        return
    end

    if IsProjectileLike(ent) then
        local nearestDim = FindNearestDimensionAtPosition(ent:GetPos(), Config.ProjectileNearestOwnerRadius)

        if nearestDim ~= nil then
            ent:SetDimension(nearestDim)
            return
        end
    end

    if attempt < 6 then
        timer.Simple(({0, 0.03, 0.08, 0.16, 0.30, 0.50})[attempt + 1], function()
            TryApplyInheritedDimension(ent, attempt + 1)
        end)

        return
    end

    RegisterEntityInDimensionCache(ent, ent:GetDimension())

    ent:SetCustomCollisionCheck(true)
    fjs_dimension.SyncVisibility(ent)
end

local function ResolveSpawnOwner(ent)
    if not IsValid(ent) then return NULL end

    local parent = ent:GetParent()
    while IsValid(parent) do
        if parent.GetDimension and parent:GetDimension() ~= 0 then return parent end
        if parent.GetOwner and IsValid(parent:GetOwner()) then return parent:GetOwner() end
        parent = parent:GetParent()
    end

    if IsValid(ent:GetOwner()) then return ent:GetOwner() end
    if ent.GetCreator and IsValid(ent:GetCreator()) then return ent:GetCreator() end
    if ent.GetPlayer and IsValid(ent:GetPlayer()) then return ent:GetPlayer() end
    if IsValid(ent.PlayerCreator) then return ent.PlayerCreator end

    if ent.CPPIGetOwner then
        local ok, owner = pcall(ent.CPPIGetOwner, ent)
        if ok and IsValid(owner) then return owner end
    end

    if ent.GetInternalVariable then
        local ok, internalOwner = pcall(ent.GetInternalVariable, ent, "m_hOwnerEntity")
        if ok and IsValid(internalOwner) then return internalOwner end
    end

    local trueOwner = fjs_dimension.GetTrueEntityOwner(ent)
    if IsValid(trueOwner) then return trueOwner end

    return GetMostRecentSpawnIntent()
end

hook.Add("OnEntityCreated", "FJS_Dim_AutoSetup", function(ent)
    if ent:IsWeapon() then
        timer.Simple(0, function()
            if IsValid(ent) then
                local owner = ent:GetOwner()
                if IsValid(owner) and owner.GetDimension then
                    ent:SetDimension(owner:GetDimension())
                end
            end
        end)
        return
    end
    
    local class = ent:GetClass() or ""

    if instantClasses[class] or string.find(class, "explosion") or string.find(class, "scene") or IsProjectileLike(ent) then
        local owner = ResolveSpawnOwner(ent)
        local targetDim = 0

        if IsValid(owner) and owner.GetDimension then
            targetDim = owner:GetDimension()
        else
            local pos = ent:GetPos()
            local searchRadius = (pos.x == 0 and pos.y == 0 and pos.z == 0) and 30000 or 500
            
            targetDim = FindNearestDimensionAtPosition(pos, searchRadius) or 0
        end

        ent:SetNW2Int("m_dim_id", targetDim)
        RegisterEntityInDimensionCache(ent, targetDim)
        ent:SetCustomCollisionCheck(true)

        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply:GetDimension() ~= targetDim then
                ent:SetPreventTransmit(ply, true)
                if ent.GetChildren then
                    for _, child in ipairs(ent:GetChildren()) do
                        if IsValid(child) then child:SetPreventTransmit(ply, true) end
                    end
                end
            end
        end
        return
    end

    timer.Simple(0, function()
        TryApplyInheritedDimension(ent, 1)
    end)
end)

hook.Add("EntityRemoved", "FJS_Dim_CleanCache", function(ent)
    fjs_dimension.ActiveNPCs[ent] = nil
    RemoveEntityFromDimensionCache(ent)
end)

local function BlockCrossDimensionInteraction(ply, ent)
    if not IsValid(ply) or not IsValid(ent) then return end
    if ent:IsWorld() then return end
    if not ent.GetDimension then return end

    if ply:GetDimension() ~= ent:GetDimension() then
        return false
    end
end

hook.Add("PhysgunPickup", "FJS_Dim_Physgun", BlockCrossDimensionInteraction)
hook.Add("PlayerUse", "FJS_Dim_Use", BlockCrossDimensionInteraction)
hook.Add("GravGunPickupAllowed", "FJS_Dim_GravGun", BlockCrossDimensionInteraction)
hook.Add("GravGunPunt", "FJS_Dim_GravGunPunt", BlockCrossDimensionInteraction)

hook.Add("CanTool", "FJS_Dim_Toolgun", function(ply, tr, toolname)
    local ent = tr and tr.Entity

    if IsValid(ent) and not ent:IsWorld() and ent.GetDimension then
        if ply:GetDimension() ~= ent:GetDimension() then
            return false
        end
    end
end)

hook.Add("ShouldCollide", "FJS_Dim_Collisions", function(ent1, ent2)
    if not IsValid(ent1) or not IsValid(ent2) then return end
    if ent1:IsWorld() or ent2:IsWorld() then return end
    if not ent1.GetDimension or not ent2.GetDimension then return end

    if ent1:GetDimension() ~= ent2:GetDimension() then
        return false
    end
end)

hook.Add("EntityTakeDamage", "FJS_Dim_Damage", function(target, dmginfo)
    local attacker = dmginfo:GetAttacker()

    if not IsValid(target) or not IsValid(attacker) or attacker:IsWorld() then return end

    local trueAttacker = fjs_dimension.GetTrueEntityOwner(attacker)

    if not IsValid(trueAttacker) then
        trueAttacker = attacker
    end

    if target.GetDimension and trueAttacker.GetDimension then
        if target:GetDimension() ~= trueAttacker:GetDimension() then
            return true
        end
    end
end)

hook.Add("PlayerCanHearPlayersVoice", "FJS_Dim_VoiceIsolation", function(listener, talker)
    if not IsValid(listener) or not IsValid(talker) then return end

    if listener:GetDimension() ~= talker:GetDimension() then
        return false, false
    end
end)

hook.Add("PlayerSpawn", "FJS_Dim_RestoreDimension", function(ply)
    local savedDim = ply:GetNW2Int("m_dim_id", fjs_dimension.Config.DefaultDimension or 0)
    
    timer.Simple(0.1, function()
        if IsValid(ply) then
            ply:SetDimension(savedDim)
            RecursiveSetPreventTransmit(ply, ply, false) 
        end
    end)
end)

hook.Add("PlayerLoadout", "FJS_Dim_EnsureLoadoutVisibility", function(ply)
    local dim = ply:GetNW2Int("m_dim_id", fjs_dimension.Config.DefaultDimension or 0)
    
    timer.Simple(0.15, function()
        if IsValid(ply) and ply.GetWeapons then
            for _, wep in ipairs(ply:GetWeapons()) do
                if IsValid(wep) then
                    wep:SetDimension(dim)
                    RecursiveSetPreventTransmit(wep, ply, false)
                end
            end
        end
    end)
end)



local function ApplyDimensionInSpawn(ply, ent)
    if not IsValid(ply) or not IsValid(ent) then return end

    local targetDim = ply:GetDimension()

    ent:SetDimension(targetDim)

    timer.Simple(0, function()
        if IsValid(ply) and IsValid(ent) then
            ent:SetDimension(targetDim)
        end
    end)
end

local function ApplyNPCDimensionInSpawn(ply, ent)
    if not IsValid(ply) or not IsValid(ent) then return end

    ApplyDimensionInSpawn(ply, ent)

    if ent:IsNPC() then
        fjs_dimension.ActiveNPCs[ent] = true
        fjs_dimension.RequestNPCRelationshipUpdate(1.0)
    end
end

hook.Add("PlayerSpawnedProp", "FJS_Dim_SpawnProp", ApplyDimensionInSpawn)
hook.Add("PlayerSpawnedNPC", "FJS_Dim_SpawnNPC", ApplyNPCDimensionInSpawn)
hook.Add("PlayerSpawnedVehicle", "FJS_Dim_SpawnVehicle", ApplyDimensionInSpawn)
hook.Add("PlayerSpawnedSENT", "FJS_Dim_SpawnSENT", ApplyDimensionInSpawn)
hook.Add("PlayerSpawnedRagdoll", "FJS_Dim_SpawnRagdoll", ApplyDimensionInSpawn)
hook.Add("PlayerSpawnedSWEP", "FJS_Dim_SpawnSWEP", ApplyDimensionInSpawn)
hook.Add("PlayerSpawnedEffect", "FJS_Dim_SpawnEffect", ApplyDimensionInSpawn)

local function CreateDimensionalServerRagdoll(npc)
    local perf = FJSPerfStart("CreateDimensionalServerRagdoll")

    if not IsValid(npc) or not npc:IsNPC() then
        FJSPerfEnd("CreateDimensionalServerRagdoll", perf)
        return
    end

    local dim = npc:GetDimension()
    local mdl = npc:GetModel()

    if not mdl or mdl == "" then
        FJSPerfEnd("CreateDimensionalServerRagdoll", perf)
        return
    end

    local rag = ents.Create("prop_ragdoll")
    if not IsValid(rag) then
        FJSPerfEnd("CreateDimensionalServerRagdoll", perf)
        return
    end

    rag:SetModel(mdl)
    rag:SetPos(npc:GetPos())
    rag:SetAngles(npc:GetAngles())
    rag:SetSkin(npc:GetSkin() or 0)
    rag:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    rag:Spawn()
    rag:Activate()

    rag.FJSDimensionalServerRagdoll = true

    for i = 0, npc:GetNumBodyGroups() - 1 do
        rag:SetBodygroup(i, npc:GetBodygroup(i))
    end

    rag:SetColor(npc:GetColor())
    rag:SetMaterial(npc:GetMaterial() or "")

    timer.Simple(0, function()
        if not IsValid(rag) or not IsValid(npc) then return end

        for i = 0, rag:GetPhysicsObjectCount() - 1 do
            local phys = rag:GetPhysicsObjectNum(i)

            if IsValid(phys) then
                local bone = rag:TranslatePhysBoneToBone(i)

                if bone and bone >= 0 then
                    local matrix = npc:GetBoneMatrix(bone)

                    if matrix then
                        phys:SetPos(matrix:GetTranslation())
                        phys:SetAngles(matrix:GetAngles())
                    end
                end

                phys:SetVelocity(npc:GetVelocity())
                phys:Wake()
            end
        end
    end)

    rag:SetDimension(dim)

    timer.Simple(0, function()
        if IsValid(rag) then
            rag:SetDimension(dim)
            fjs_dimension.SyncVisibility(rag)
        end
    end)

    timer.Simple(0.1, function()
        if IsValid(rag) then
            rag:SetDimension(dim)
            fjs_dimension.SyncVisibility(rag)
        end
    end)

    timer.Simple(tonumber(Config.ServerRagdollLifetime) or 90, function()
        if IsValid(rag) then
            rag:Remove()
        end
    end)

    FJSPerfEnd("CreateDimensionalServerRagdoll", perf)
    return rag
end

hook.Add("CreateEntityRagdoll", "FJS_Dim_ServerRagdolls", function(owner, ragdoll)
    if not IsValid(owner) or not IsValid(ragdoll) then return end
    if not owner.GetDimension then return end

    local dim = owner:GetDimension()

    ragdoll:SetDimension(dim)
    ragdoll:SetCustomCollisionCheck(true)

    timer.Simple(0, function()
        if IsValid(ragdoll) then
            ragdoll:SetDimension(dim)
            fjs_dimension.SyncVisibility(ragdoll)
        end
    end)

    timer.Simple(0.1, function()
        if IsValid(ragdoll) then
            ragdoll:SetDimension(dim)
            fjs_dimension.SyncVisibility(ragdoll)
        end
    end)
end)

hook.Add("OnNPCKilled", "FJS_Dim_NPCRagdollsFix", function(npc, attacker, inflictor)
    if not IsValid(npc) then return end

    local dim = npc:GetDimension()
    local deathPos = npc:GetPos()

    fjs_dimension.ActiveNPCs[npc] = nil
    fjs_dimension.RequestNPCRelationshipUpdate(1.0)

    CreateDimensionalServerRagdoll(npc)

    local function FixNearbyRagdoll()
        for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
            if not IsValid(rag) then continue end

            local closeEnough = rag:GetPos():DistToSqr(deathPos) <= 250000

            if closeEnough then
                rag:SetDimension(dim)
                rag:SetCustomCollisionCheck(true)
                fjs_dimension.SyncVisibility(rag)
            end
        end
    end

    timer.Simple(0, FixNearbyRagdoll)
    timer.Simple(0.05, FixNearbyRagdoll)
    timer.Simple(0.15, FixNearbyRagdoll)
end)
hook.Add("PlayerCanPickupWeapon", "FJS_Dim_PickupWeapon", function(ply, wep)
    if not IsValid(ply) or not IsValid(wep) then return end
    if not wep.GetDimension then return end

    local wepDim = wep:GetDimension()
    local plyDim = ply:GetDimension()

    if wepDim == 0 and plyDim ~= 0 then
        wep:SetDimension(plyDim)
        return true
    end

    if wepDim ~= plyDim then
        return false
    end
end)


hook.Add("PlayerCanPickupItem", "FJS_Dim_PickupItem", function(ply, item)
    if not IsValid(ply) or not IsValid(item) then return end
    if not item.GetDimension then return end

    local itemDim = item:GetDimension()
    local plyDim = ply:GetDimension()

    if itemDim == 0 and plyDim ~= 0 then
        item:SetDimension(plyDim)
        return true
    end

    if itemDim ~= plyDim then
        return false
    end
end)

fjs_dimension.NPCNPCChunkState = fjs_dimension.NPCNPCChunkState or nil
fjs_dimension.NPCNPCRelationshipsDirty = fjs_dimension.NPCNPCRelationshipsDirty or false

local function IsValidTrackedNPC(npc)
    return IsValid(npc) and npc:IsNPC() and npc:Health() > 0
end

ForceNPCPacify = function(npc, target)
    if not IsValidTrackedNPC(npc) then return end
    if not IsValid(target) then return end

    npc.DimRelationships = npc.DimRelationships or {}

    if npc.DimRelationships[target] == nil then
        npc.DimRelationships[target] = npc:Disposition(target)
    end

    npc:AddEntityRelationship(target, D_NU, 99)

    if npc:GetEnemy() == target or npc:GetTarget() == target then
        npc:ClearEnemyMemory(target)
        npc:SetEnemy(NULL)
        npc:StopMoving()

        if npc.ClearCondition then
            npc:ClearCondition(13)
            npc:ClearCondition(18)
            npc:ClearCondition(14)
        end

        npc:SetSchedule(SCHED_IDLE_STAND)
    end
end

local function IsCrossDimensionPair(a, b)
    if not IsValid(a) or not IsValid(b) then return false end
    if not a.GetDimension or not b.GetDimension then return false end

    return a:GetDimension() ~= b:GetDimension()
end

local function BlockCrossDimensionNPCCombat(npc, target)
    if not IsValid(npc) or not npc:IsNPC() then return end
    if not IsValid(target) then return end
    if not IsCrossDimensionPair(npc, target) then return end

    ForceNPCPacify(npc, target)
    return true
end

local function BuildActiveNPCList()
    local list = {}

    for npc, _ in pairs(fjs_dimension.ActiveNPCs) do
        if IsValidTrackedNPC(npc) then
            npc.DimRelationships = npc.DimRelationships or {}
            table.insert(list, npc)
        else
            fjs_dimension.ActiveNPCs[npc] = nil
        end
    end

    return list
end

function fjs_dimension.UpdateNPCPlayerRelationships()
    local perf = FJSPerfStart("UpdateNPCPlayerRelationships")

    local allPlayers = player.GetAll()

    for npc, _ in pairs(fjs_dimension.ActiveNPCs) do
        if not IsValidTrackedNPC(npc) then
            fjs_dimension.ActiveNPCs[npc] = nil
            continue
        end

        npc.DimRelationships = npc.DimRelationships or {}

        local npcDim = npc:GetDimension()

        for _, ply in ipairs(allPlayers) do
            if not IsValid(ply) then continue end

            if npcDim ~= ply:GetDimension() then
                if npc.DimRelationships[ply] == nil then
                    npc.DimRelationships[ply] = npc:Disposition(ply)
                end

                ForceNPCPacify(npc, ply)
            elseif npc.DimRelationships[ply] ~= nil then
                npc:AddEntityRelationship(ply, npc.DimRelationships[ply], 99)
                npc.DimRelationships[ply] = nil
            end
        end

        for entKey, _ in pairs(npc.DimRelationships) do
            if not IsValid(entKey) then
                npc.DimRelationships[entKey] = nil
            end
        end
    end

    FJSPerfEnd("UpdateNPCPlayerRelationships", perf)
end

function fjs_dimension.StartNPCNPCRelationshipChunkUpdate()
    if fjs_dimension.NPCNPCChunkState then return end

    local npcs = BuildActiveNPCList()

    if #npcs <= 1 then
        fjs_dimension.NPCNPCRelationshipsDirty = false
        return
    end

    fjs_dimension.NPCNPCRelationshipsDirty = false

    fjs_dimension.NPCNPCChunkState = {
        npcs = npcs,
        i = 1,
        j = 1,
        started = SysTime()
    }

    if timer.Exists("FJS_Dim_AI_NPCNPCChunkThink") then
        timer.Remove("FJS_Dim_AI_NPCNPCChunkThink")
    end

    timer.Create("FJS_Dim_AI_NPCNPCChunkThink", tonumber(Config.NPCChunkInterval) or 0.01, 0, function()
        if fjs_dimension.ProcessNPCNPCRelationshipChunk then
            fjs_dimension.ProcessNPCNPCRelationshipChunk()
        end
    end)
end

function fjs_dimension.ProcessNPCNPCRelationshipChunk()
    local perf = FJSPerfStart("UpdateNPCNPCRelationships_Chunk")

    local state = fjs_dimension.NPCNPCChunkState

    if not state or not state.npcs then
        timer.Remove("FJS_Dim_AI_NPCNPCChunkThink")
        FJSPerfEnd("UpdateNPCNPCRelationships_Chunk", perf)
        return
    end

    local npcs = state.npcs

    local checksPerTick = tonumber(Config.NPCChecksPerChunk) or 150
    local checks = 0

    while checks < checksPerTick do
        local npc = npcs[state.i]

        if not IsValidTrackedNPC(npc) then
            state.i = state.i + 1
            state.j = 1
        else
            local otherNPC = npcs[state.j]

            if IsValidTrackedNPC(otherNPC) and otherNPC ~= npc then
                local npcDim = npc:GetDimension()
                local otherDim = otherNPC:GetDimension()

                if npcDim ~= otherDim then
                    if npc.DimRelationships[otherNPC] == nil then
                        npc.DimRelationships[otherNPC] = npc:Disposition(otherNPC)
                    end

                    ForceNPCPacify(npc, otherNPC)
                elseif npc.DimRelationships[otherNPC] ~= nil then
                    npc:AddEntityRelationship(otherNPC, npc.DimRelationships[otherNPC], 99)
                    npc.DimRelationships[otherNPC] = nil
                end
            end

            state.j = state.j + 1

            if state.j > #npcs then
                for entKey, _ in pairs(npc.DimRelationships or {}) do
                    if not IsValid(entKey) then
                        npc.DimRelationships[entKey] = nil
                    end
                end

                state.i = state.i + 1
                state.j = 1
            end
        end

        checks = checks + 1

        if state.i > #npcs then
            fjs_dimension.NPCNPCChunkState = nil
            timer.Remove("FJS_Dim_AI_NPCNPCChunkThink")

            FJSPerfEnd("UpdateNPCNPCRelationships_Chunk", perf)
            return
        end
    end

    FJSPerfEnd("UpdateNPCNPCRelationships_Chunk", perf)
end

function fjs_dimension.UpdateNPCNPCRelationships()
    fjs_dimension.StartNPCNPCRelationshipChunkUpdate()
end

function fjs_dimension.UpdateAllNPCRelationships()
    fjs_dimension.UpdateNPCPlayerRelationships()

    fjs_dimension.NPCNPCRelationshipsDirty = true
    fjs_dimension.StartNPCNPCRelationshipChunkUpdate()
end

hook.Add("OnEntityRelationshipChanged", "FJS_Dim_BlockNPCRelationshipChange", function(ent, target, oldDisp, newDisp)
    if not IsValid(ent) or not ent:IsNPC() then return end
    if not IsValid(target) then return end
    if not target.GetDimension then return end

    if ent.GetDimension and ent:GetDimension() ~= target:GetDimension() then
        timer.Simple(0, function()
            if IsValid(ent) and IsValid(target) then
                ForceNPCPacify(ent, target)
            end
        end)
    end
end)

hook.Add("OnEntityCreated", "FJS_Dim_ImmediateNPCPacifyOnCreate", function(ent)
    timer.Simple(0, function()
        if not IsValid(ent) or not ent:IsNPC() then return end
        if not ent.GetDimension then return end

        local npcDim = ent:GetDimension()

        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply.GetDimension and ply:GetDimension() ~= npcDim then
                ForceNPCPacify(ent, ply)
            end
        end

        for otherNPC, _ in pairs(fjs_dimension.ActiveNPCs or {}) do
            if IsValid(otherNPC)
            and otherNPC:IsNPC()
            and otherNPC ~= ent
            and otherNPC.GetDimension
            and otherNPC:GetDimension() ~= npcDim then
                ForceNPCPacify(ent, otherNPC)
                ForceNPCPacify(otherNPC, ent)
            end
        end
    end)
end)

if Config.NPCIsolation ~= false then
timer.Remove("FJS_Dim_AI_Fix")
timer.Remove("FJS_Dim_AI_NPCFix")
timer.Remove("FJS_Dim_AI_PlayerFix")

timer.Create("FJS_Dim_AI_PlayerFix", tonumber(Config.NPCPlayerUpdateInterval) or 5, 0, function()
    if fjs_dimension.UpdateNPCPlayerRelationships then
        fjs_dimension.UpdateNPCPlayerRelationships()
    end
end)

timer.Create("FJS_Dim_AI_NPCFix", tonumber(Config.NPCNPCUpdateInterval) or 60, 0, function()
    if fjs_dimension.NPCNPCRelationshipsDirty and fjs_dimension.UpdateNPCNPCRelationships then
        fjs_dimension.UpdateNPCNPCRelationships()
    end
end)

timer.Remove("FJS_Dim_AI_FastEnemySanity")

timer.Create("FJS_Dim_AI_FastEnemySanity", tonumber(Config.NPCFastCheckInterval) or 0.3, 0, function()
    if fjs_dimension.FastNPCEnemySanityCheck then
        fjs_dimension.FastNPCEnemySanityCheck()
    end
end)

end

if Config.EnableChatCommand then
hook.Add("PlayerSay", "FJS_Dim_Commands", function(ply, text)
    local args = string.Explode(" ", text or "")

    if string.lower(args[1] or "") == "!dim" and IsValid(ply) and ply:IsSuperAdmin() then
        local targetDim = NormalizeDimension(args[2])

        ply:SetDimension(targetDim)
        ply:ChatPrint("[FJS Dimension API] Dimension: " .. targetDim)

        return ""
    end
end)
end