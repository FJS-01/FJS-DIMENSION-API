local Config = fjs_dimension.Config or {}
local transitionAlpha = 0
local allowLocalVisuals = false
local allowLocalSounds = false
local lastDimension = nil
local nextStopSoundTime = 0

local og_cl_Decal = util.Decal
local og_cl_Effect = util.Effect
local bulletTracers = {}
local bulletTracerMat = Material("trails/laser")

fjs_dimension_pending_sounds = fjs_dimension_pending_sounds or {}
fjs_dimension_active_patches = fjs_dimension_active_patches or {}

local function GetClientTrueOwner(ent)
    if not IsValid(ent) then return NULL end

    if ent.GetOwner and IsValid(ent:GetOwner()) then
        local owner = ent:GetOwner()
        if owner:IsWeapon() and IsValid(owner:GetOwner()) then
            return owner:GetOwner()
        end
        return owner
    end

    if ent.GetThrower and IsValid(ent:GetThrower()) then
        return ent:GetThrower()
    end

    return NULL
end

local function IsCombatEffectName(name)
    local effectName = string.lower(name or "")

    return string.find(effectName, "blood", 1, true)
        or string.find(effectName, "impact", 1, true)
        or string.find(effectName, "spark", 1, true)
        or string.find(effectName, "tracer", 1, true)
end

local function RunAllowedVisual(fn)
    allowLocalVisuals = true
    local ok, err = pcall(fn)
    allowLocalVisuals = false

    if not ok then
        ErrorNoHalt("[FJS Dimension API] Client visual error: " .. tostring(err) .. "\n")
    end
end

local function StopAllActivePatches()
    for ent, patches in pairs(fjs_dimension_active_patches) do
        if istable(patches) then
            for snd, patch in pairs(patches) do
                if patch and patch.Stop then
                    patch:Stop()
                end
            end
        end
    end
    fjs_dimension_active_patches = {}
    fjs_dimension_pending_sounds = {}
end

local function StopDimensionLoopingSounds()
    if CurTime() < nextStopSoundTime then return end

    nextStopSoundTime = CurTime() + 0.15
    StopAllActivePatches()
    timer.Simple(0, function() RunConsoleCommand("stopsound") end)
    timer.Simple(0.05, function() RunConsoleCommand("stopsound") end)
    timer.Simple(0.1, function() RunConsoleCommand("stopsound") end)
end

function util.Decal(name, startPos, endPos, filter)
    if Config.OverrideDecals == false then
        return og_cl_Decal(name, startPos, endPos, filter)
    end

    if not allowLocalVisuals then return end
    return og_cl_Decal(name, startPos, endPos, filter)
end

function util.Effect(name, eff, allowOverride, ignorePrediction)
    if Config.OverrideEffects == false then
        return og_cl_Effect(name, eff, allowOverride, ignorePrediction)
    end

    local ply = LocalPlayer()

    if not IsValid(ply) then
        return og_cl_Effect(name, eff, allowOverride, ignorePrediction)
    end

    if allowLocalVisuals then
        return og_cl_Effect(name, eff, allowOverride, ignorePrediction)
    end

    local ent = eff and eff:GetEntity() or NULL
    local trueOwner = GetClientTrueOwner(ent)
    local checkEnt = IsValid(trueOwner) and trueOwner or ent

    if IsValid(checkEnt) and checkEnt.GetDimension then
        if checkEnt:GetDimension() ~= ply:GetDimension() then
            return
        end
    elseif IsCombatEffectName(name) then
        return
    end

    return og_cl_Effect(name, eff, allowOverride, ignorePrediction)
end


net.Receive("FJS_Dim_CustomDecal", function()
    local name = net.ReadString()
    local startPos = net.ReadVector()
    local endPos = net.ReadVector()

    RunAllowedVisual(function()
        util.Decal(name, startPos, endPos)
    end)
end)



local fleshImpactSounds = {
    "physics/flesh/flesh_impact_bullet1.wav",
    "physics/flesh/flesh_impact_bullet2.wav",
    "physics/flesh/flesh_impact_bullet3.wav",
    "physics/flesh/flesh_impact_bullet4.wav",
    "physics/flesh/flesh_impact_bullet5.wav"
}

local concreteImpactSounds = {
    "physics/concrete/concrete_impact_bullet1.wav",
    "physics/concrete/concrete_impact_bullet2.wav",
    "physics/concrete/concrete_impact_bullet3.wav",
    "physics/concrete/concrete_impact_bullet4.wav"
}

local function PlayLocalDimensionalImpactSound(hitPos, isFlesh)
    local tbl = isFlesh and fleshImpactSounds or concreteImpactSounds
    local snd = tbl[math.random(#tbl)]

    allowLocalSounds = true
    sound.Play(snd, hitPos or vector_origin, 75, math.random(95, 105), 1)
    allowLocalSounds = false
end

net.Receive("FJS_Dim_BulletVisuals", function()
    local startPos = net.ReadVector()
    local hitPos = net.ReadVector()
    local hitNormal = net.ReadNormal()
    local shouldDrawTracer = net.ReadBool()
    net.ReadString()
    local hitEnt = net.ReadEntity()
    local damage = net.ReadUInt(16)
    local bulletDim = net.ReadUInt(16)

    local ply = LocalPlayer()
    if not IsValid(ply) or ply:GetDimension() ~= bulletDim then return end

    if shouldDrawTracer and startPos:DistToSqr(hitPos) > 256 then
        bulletTracers[#bulletTracers + 1] = {
            startPos = startPos,
            endPos = hitPos,
            dieTime = CurTime() + (tonumber(Config.BulletTracerLife) or 0.055)
        }
    end

    local isFleshImpact = IsValid(hitEnt) and (hitEnt:IsPlayer() or hitEnt:IsNPC())

    RunAllowedVisual(function()
        if isFleshImpact then
            local blood = EffectData()
            blood:SetOrigin(hitPos)
            blood:SetNormal(hitNormal)
            blood:SetColor(0)
            util.Effect("BloodImpact", blood, true, true)
            util.Decal("Blood", hitPos + hitNormal, hitPos - hitNormal)
        else
            local impact = EffectData()
            impact:SetOrigin(hitPos)
            impact:SetNormal(hitNormal)
            impact:SetMagnitude(math.Clamp(damage / 10, 1, 5))
            impact:SetScale(1)
            util.Effect("Impact", impact, true, true)
            util.Decal("Impact.Concrete", hitPos + hitNormal, hitPos - hitNormal)
        end
    end)

    PlayLocalDimensionalImpactSound(hitPos, isFleshImpact)
end)

net.Receive("FJS_Dim_PlaySoundWorld", function()
    local snd = net.ReadString()
    local entID = net.ReadUInt(16)
    local pos = net.ReadVector()
    local vol = net.ReadFloat()
    local pitch = net.ReadUInt(8)

    local ent = Entity(entID)
    local isLoop = string.find(string.lower(snd), "engine") or string.find(string.lower(snd), "loop") or string.find(string.lower(snd), "missile")

    if IsValid(ent) and not ent:IsWorld() then
        if fjs_dimension_active_patches[ent] and fjs_dimension_active_patches[ent][snd] then
            local old = fjs_dimension_active_patches[ent][snd]
            if old and old.Stop then old:Stop() end
        end
        
        local patch = CreateSound(ent, snd)
        patch:SetSoundLevel(75)
        patch:PlayEx(vol, pitch)
        
        fjs_dimension_active_patches[ent] = fjs_dimension_active_patches[ent] or {}
        fjs_dimension_active_patches[ent][snd] = patch
        
    elseif entID > 0 and entID < 65535 then
        fjs_dimension_pending_sounds[entID] = {
            snd = snd, pitch = pitch, vol = vol, expire = CurTime() + 0.4
        }
        
        if not isLoop then
            sound.Play(snd, pos, 75, pitch, vol)
        end
    else
        sound.Play(snd, pos, 75, pitch, vol)
    end
end)

hook.Add("PostDrawTranslucentRenderables", "FJS_Dim_DrawBulletTracers", function()
    if not IsValid(LocalPlayer()) then return end
    if Config.OverrideEffects == false then return end
    if #bulletTracers <= 0 then return end

    local now = CurTime()
    local life = tonumber(Config.BulletTracerLife) or 0.055
    local width = tonumber(Config.BulletTracerWidth) or 1.35

    render.SetMaterial(bulletTracerMat)

    for i = #bulletTracers, 1, -1 do
        local tr = bulletTracers[i]

        if not tr or now >= tr.dieTime then
            table.remove(bulletTracers, i)
        else
            local alpha = math.Clamp((tr.dieTime - now) / life, 0, 1) * 180
            render.DrawBeam(tr.startPos, tr.endPos, width, 0, 1, Color(255, 255, 255, alpha))
        end
    end
end)

hook.Add("OnEntityCreated", "FJS_Dim_AttachPendingSounds", function(ent)
    if not IsValid(ent) then return end
    local id = ent:EntIndex()
    
    if fjs_dimension_pending_sounds[id] then
        local data = fjs_dimension_pending_sounds[id]
        
        if CurTime() <= data.expire then
            if fjs_dimension_active_patches[ent] and fjs_dimension_active_patches[ent][data.snd] then
                local old = fjs_dimension_active_patches[ent][data.snd]
                if old and old.Stop then old:Stop() end
            end
            
            local patch = CreateSound(ent, data.snd)
            patch:SetSoundLevel(75)
            patch:PlayEx(data.vol, data.pitch)
            
            fjs_dimension_active_patches[ent] = fjs_dimension_active_patches[ent] or {}
            fjs_dimension_active_patches[ent][data.snd] = patch
        end
        
        fjs_dimension_pending_sounds[id] = nil
    end
end)

hook.Add("EntityRemoved", "FJS_Dim_KillOrphanedSounds", function(ent)
    if fjs_dimension_active_patches[ent] then
        for _, patch in pairs(fjs_dimension_active_patches[ent]) do
            if patch and patch.Stop then
                patch:Stop()
            end
        end
        fjs_dimension_active_patches[ent] = nil
    end
    
    fjs_dimension_pending_sounds[ent:EntIndex()] = nil
end)

local function IsOrphanDimensionalLeak(soundName)
    local snd = string.lower(soundName or "")
    if snd == "" then return false end

    return string.find(snd, "weapon", 1, true)
        or string.find(snd, "gun", 1, true)
        or string.find(snd, "shot", 1, true)
        or string.find(snd, "impact", 1, true)
        or string.find(snd, "ric", 1, true)
        or string.find(snd, "bullet", 1, true)
        or string.find(snd, "explode", 1, true)
        or string.find(snd, "explosion", 1, true)
        or string.find(snd, "c4", 1, true)
        or string.find(snd, "rpg", 1, true)
        or string.find(snd, "rocket", 1, true)
        or string.find(snd, "missile", 1, true)
        or string.find(snd, "grenade", 1, true)
        or string.find(snd, "flesh", 1, true)
        or string.find(snd, "blood", 1, true)
        or string.find(snd, "pain", 1, true)
        or string.find(snd, "die", 1, true)
        or string.find(snd, "death", 1, true)
        or string.find(snd, "groan", 1, true)
        or string.find(snd, "cry", 1, true)
        or string.find(snd, "npc", 1, true)
        or string.find(snd, "vo/", 1, true)
        or string.find(snd, "physics", 1, true)
        or string.find(snd, "phx", 1, true)
        or string.find(snd, "zombie", 1, true)
        or string.find(snd, "headcrab", 1, true)
        or string.find(snd, "combine", 1, true)
end

hook.Add("EntityEmitSound", "FJS_Dim_ClientAudioSilencer", function(data)
    if Config.OverrideEffects == false then return end
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local myDim = ply:GetDimension()
    local ent = data.Entity
    local snd = string.lower(data.SoundName or "")

    local isProjectileSound = string.find(snd, "rocket") 
        or string.find(snd, "missile") 
        or string.find(snd, "rpg") 
        or string.find(snd, "grenade")

    local targetDim = -1

    if IsValid(ent) and not ent:IsWorld() then
        local nwDim = ent:GetNW2Int("m_dim_id", -1)
        if nwDim ~= -1 then 
            targetDim = nwDim 
        end

        if targetDim == -1 or (targetDim == 0 and isProjectileSound) then
            local owner = ent:GetOwner()
            if not IsValid(owner) and ent.GetThrower then owner = ent:GetThrower() end
            if not IsValid(owner) and ent.GetParent and IsValid(ent:GetParent()) then 
                owner = ent:GetParent() 
            end

            if IsValid(owner) and owner.GetDimension then
                targetDim = owner:GetDimension()
            else
                local pos = data.Pos or ent:GetPos()
                local bestDist = 400 * 400
                for _, p in ipairs(player.GetAll()) do
                    local dist = p:GetPos():DistToSqr(pos)
                    if dist < bestDist then
                        bestDist = dist
                        targetDim = p:GetDimension()
                    end
                end
            end
        end
    end

    if targetDim ~= -1 and targetDim ~= myDim then
        return false
    end

    if not IsValid(ent) or ent:IsWorld() then
        local isCombatBleed = isProjectileSound 
            or string.find(snd, "weapon") 
            or string.find(snd, "explode") 
            or string.find(snd, "c4")
            or string.find(snd, "hit")

        if isCombatBleed then
            return false -- Silencio absoluto
        end
    end
end)

hook.Add("EntityNetworkedVarChanged", "FJS_Dim_Transition", function(ent, name, oldValue, newValue)
    if ent ~= LocalPlayer() then return end
    if name ~= "m_dim_id" then return end
    if oldValue == newValue then return end

    transitionAlpha = 255
    bulletTracers = {}
    StopDimensionLoopingSounds()
    hook.Run("FJSDimensionLocalPlayerChanged", oldValue, newValue)
end)

hook.Add("Think", "FJS_Dim_DetectDimensionChange", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local currentDim = ply:GetDimension()

    if lastDimension == nil then
        lastDimension = currentDim
        return
    end

    if currentDim ~= lastDimension then
        local oldDim = lastDimension
        lastDimension = currentDim
        transitionAlpha = 255
        bulletTracers = {}
        StopDimensionLoopingSounds()
        hook.Run("FJSDimensionLocalPlayerChanged", oldDim, currentDim)
    end
end)

hook.Add("CreateClientsideRagdoll", "FJS_Dim_IsolateRagdolls", function(ent, ragdoll)
    local ply = LocalPlayer()
    if not IsValid(ply) or not IsValid(ragdoll) then return end

    local shouldHide = false

    if IsValid(ent) and ent.GetDimension then
        shouldHide = ent:GetDimension() ~= ply:GetDimension()
    end

    if shouldHide then
        ragdoll:SetNoDraw(true)
        ragdoll:SetNotSolid(true)
        ragdoll:DrawShadow(false)
    else
        timer.Simple(0.05, function()
            if not IsValid(ragdoll) then return end
            ragdoll:SetNoDraw(true)
            ragdoll:SetNotSolid(true)
            ragdoll:DrawShadow(false)
        end)
    end
end)

hook.Add("HUDPaint", "FJS_Dim_TransitionOverlay", function()
    if transitionAlpha <= 0 then return end

    surface.SetDrawColor(255, 255, 255, transitionAlpha)
    surface.DrawRect(0, 0, ScrW(), ScrH())
    transitionAlpha = math.Approach(transitionAlpha, 0, FrameTime() * 400)
end)
