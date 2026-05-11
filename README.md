FJS DIMENSION API v1.0.0-beta 
===============

Author: FJS (Credit required for any use or modification)

Status: UNSTABLE - ACTIVE DEVELOPMENT - USE AT YOUR OWN RISK

DISCLAIMER:
- This software is NOT stable. It may contain bugs, performance issues,
  or unexpected behavior.
- The developer is not responsible for any damage, data loss, or server
  crashes caused by this addon.
- You are allowed to modify, improve, and redistribute this code as long
  as you keep the original credits intact and do not claim it as your own.
- Active development is ongoing; API may change without notice.
- Known issues are listed at the end of this document.

CONFIGURATION OPTIONS
   ===================

All options are stored in the global table: fjs_dimension.Config
You can override defaults by setting them in a file loaded BEFORE this addon
(e.g., lua/autorun/server/my_dim_config.lua).

Example:
    fjs_dimension.Config = fjs_dimension.Config or {}
    fjs_dimension.Config.DefaultDimension = 0
    fjs_dimension.Config.MaxDimension = 100
    fjs_dimension.Config.OverrideBullets = true

List of options:

- DefaultDimension (default: 0)
  The dimension ID assigned to entities/players when none is explicitly set.
  Must be an integer.

- MaxDimension (default: 65535)
  Maximum allowed dimension ID. Any ID above this will be clamped.

- OverrideBullets (default: true)
  If true, the system intercepts all bullets (EntityFireBullets) and filters
  them so they only affect players/NPCs in the same dimension as the shooter.
  Also sends custom tracer and impact visuals to clients in that dimension.

- OverrideEffects (default: true)
  If true, visual effects (util.Effect) are filtered by dimension. Players
  will only see effects from entities that share their dimension.

- OverrideDecals (default: true)
  If true, decals (util.Decal) are only shown to players in the dimension
  where the decal was created.

- IsolateClientSounds (default: true)
  Currently internal. Controls client-side sound isolation via the
  EntityEmitSound hook. Recommended to keep true.

- DebugSoundIsolation (default: true)
  Internal debug flag. Can be ignored.

- ProjectileNearestOwnerRadius (default: 900)
  Distance in units to search for the nearest player or NPC when a projectile
  (rocket, grenade, etc.) has no clear owner. The projectile inherits the
  dimension of the closest combatant within this radius.

- NPCIsolation (default: true)
  Master switch for NPC relationship isolation. When true, NPCs from
  different dimensions are pacified (they ignore and cannot attack each
  other or players from other dimensions).

- EnableDebugCommands (default: false)
  If true, adds several console commands for SuperAdmins to debug the system.
  Commands:
    fjs_dim_perf_toggle     - enable/disable performance measurement.
    fjs_dim_perf_print      - print performance stats.
    fjs_dim_perf_reset      - reset performance data.
    fjs_dim_debug_counts    - show number of players/NPCs/entities per dim.
    fjs_dim_cache_counts    - show cache sizes per dimension.
    fjs_dim_cache_rebuild   - force rebuild of internal entity cache.

- EnableChatCommand (default: true)
  If true, SuperAdmins can type "!dim <id>" in chat to change their own
  dimension.

- BulletTracerLife (default: 0.055)
  Lifetime of bullet tracer beams (in seconds). Client-side only.

- BulletTracerWidth (default: 1.35)
  Width of bullet tracer beams (world units). Client-side only.

- NPCPlayerUpdateInterval (default: 5)
  Time in seconds between full updates of NPC vs player relationships.
  During these updates, any NPC that is in a different dimension from a
  player is pacified toward that player.

- NPCNPCUpdateInterval (default: 60)
  Time in seconds between full updates of NPC vs NPC relationships.
  This is more expensive, so it runs less frequently.

- NPCFastCheckInterval (default: 0.3)
  Time in seconds between quick sanity checks for NPC enemies/targets.
  If an NPC has an enemy or target in a different dimension, it is
  immediately pacified.

- NPCChunkInterval (default: 0.01)
  Time in seconds between processing each "chunk" of NPC-NPC relationship
  pairs during a full update. This spreads the work over multiple ticks
  to avoid lag.

- NPCChecksPerChunk (default: 150)
  Number of relationship pairs to process per chunk.

- ServerRagdollLifetime (default: 90)
  Time in seconds after which a server‑side ragdoll (created from an NPC
  death) is automatically removed to save resources.

SERVER-SIDE HOOKS
================================================================================

These hooks are called by the system and can be used in your own code.

- 2.1 hook "FJSDimensionPlayerChanged"
    Called after a player's dimension changes.
    Parameters:
        ply - Player
        oldDim - number (previous dimension)
        newDim - number (new dimension)

- 2.2 hook "FJSDimensionEntityChanged"
    Called after any non-player entity's dimension changes.
    Parameters:
        ent - Entity
        oldDim - number
        newDim - number

- 2.3 hook "FJSDimensionChanged"
    Called for any entity (players and non-players) after dimension change.
    Parameters: same as above.

- 2.4 hook "FJSDimensionCanChange"
    Called BEFORE a dimension change. Return false to prevent the change.
    Parameters:
        ent - Entity
        oldDim - number
        newDim - number

- 2.5 hook "FJSDimensionLocalPlayerChanged" (also on client)
    Called on the client when the local player's dimension changes.
    Parameters:
        oldDim - number
        newDim - number

EXAMPLE (place in any server Lua file):
```lua
    -- Print a message when a player changes dimension
    hook.Add("FJSDimensionPlayerChanged", "MyDebug", function(ply, oldDim, newDim)
        print(ply:Nick() .. " moved from dimension " .. oldDim .. " to " .. newDim)
        ply:ChatPrint("Welcome to dimension " .. newDim)
    end)

    -- Prevent players from entering dimension 333
    hook.Add("FJSDimensionCanChange", "BlockEvilDim", function(ent, oldDim, newDim)
        if ent:IsPlayer() and newDim == 333 then
            ent:ChatPrint("Dimension 333 is forbidden!")
            return false
        end
    end)
```

UTILITY FUNCTIONS
================================================================================

These functions are provided for interacting with the dimension system.

- 3.1 Entity:SetDimension(id)
    Sets the dimension of an entity. Handles network propagation, collision
    checks, visibility updates, and NPC relationship updates.
    Parameters: id (number)
    Returns: nothing

- 3.2 Entity:GetDimension()
    Returns the current dimension ID of the entity (number).

- 3.3 fjs_dimension.GetPlayersInDimension(dim)
    Returns a table (array) of all Player objects currently in that dimension.

- 3.4 fjs_dimension.GetEntitiesInDimension(dim)
    Returns a table (array) of all entities (props, NPCs, etc.) that are
    cached as belonging to that dimension. Note: the cache updates
    automatically but may have a slight delay.

- 3.5 fjs_dimension.PlaySoundInDimension(dim, soundPath, pos, volume, pitch, level)
    Plays a sound only for players in the specified dimension.
    Parameters:
        dim (number)
        soundPath (string)
        pos (Vector)
        volume (number, 0-1)
        pitch (number, 0-255)
        level (number, sound level, default 75)
    Returns: nothing

- 3.6 fjs_dimension.Decal(dim, decalName, startPos, endPos)
    Sends a decal to all players in the specified dimension.
    Parameters:
        dim (number)
        decalName (string, e.g., "Impact.Concrete", "Blood")
        startPos (Vector)
        endPos (Vector)

- 3.7 fjs_dimension.SyncVisibility(ent)
    Forces a visibility recalculation for an entity. Normally called
    automatically after dimension changes, but can be used if you manually
    alter visibility flags.

- 3.8 fjs_dimension.RebuildDimensionCache()
    Rebuilds the internal lookup table of entities per dimension. Useful
    after duplicator operations or if you suspect the cache is out of sync.

- 3.9 fjs_dimension.GetTrueEntityOwner(ent)
    Recursively finds the ultimate player owner of an entity, even through
    weapons or projectiles. Returns NULL if none found.

- 3.10 fjs_dimension.SetEntityDimension(ent, dim)
    Alternative way to set an entity's dimension. Equivalent to ent:SetDimension(dim).

- 3.11 fjs_dimension.SendNetToDimension(dim)
    Sends the current net message (must have been defined with net.Start)
    to all players in the given dimension. Returns true if at least one
    recipient existed.

EXAMPLES:
```lua
    -- Teleport all players in dimension 5 to a new location
    for _, ply in ipairs(fjs_dimension.GetPlayersInDimension(5)) do
        ply:SetPos(Vector(0,0,100))
    end

    -- Play an explosion sound only in dimension 3
    fjs_dimension.PlaySoundInDimension(3, "ambient/explosions/explode_1.wav", Vector(500,0,100), 1, 100, 75)

    -- Send a custom net message to dimension 7
    net.Start("MyCustomMessage")
    net.WriteString("Hello!")
    fjs_dimension.SendNetToDimension(7)
```

CLIENT-SIDE FUNCTIONS
=============

Most client functionality is internal, but you can use the following:

- 4.1 LocalPlayer():GetDimension()
    Works on the client like on the server.

- 4.2 hook "FJSDimensionLocalPlayerChanged"
    Triggered when the local player's dimension changes.

- 4.3 The client automatically blocks visual effects, sounds, and decals from
    other dimensions. Bullet tracers and impact effects are also filtered.

EXAMPLE (client-side):
```lua
    hook.Add("FJSDimensionLocalPlayerChanged", "MyClientEffect", function(oldDim, newDim)
        print("Local player entered dimension " .. newDim)
        -- Play a local sound or show a HUD notification
        surface.PlaySound("ui/buttonclick.wav")
    end)
```

COMPLETE USAGE EXAMPLES
============

```lua
Example 1: Admin command to change own dimension (already included but you can extend)
    -- In server or shared file
    concommand.Add("my_dim", function(ply, cmd, args)
        if not ply:IsAdmin() then return end
        local dim = tonumber(args[1]) or 0
        ply:SetDimension(dim)
        ply:ChatPrint("Dimension set to " .. dim)
    end)

Example 2: Spawn a protected zone that only players in dimension 2 can enter
    -- Map a trigger_hurt or trigger_multiple, then in its OnTouch hook:
    function OnTouch(trigger, toucher)
        if toucher:IsPlayer() and toucher:GetDimension() ~= 2 then
            toucher:ChatPrint("You cannot enter this zone in your dimension!")
            return false  -- block entry
        end
    end

Example 3: Make certain weapons usable only in dimension 0
    hook.Add("CanWeaponEquip", "DimRestrict", function(ply, wepClass)
        if ply:GetDimension() ~= 0 and wepClass == "weapon_rpg" then
            ply:ChatPrint("RPGs can only be used in dimension 0")
            return false
        end
    end)

Example 4: Server-side NPC spawner that respects the player's dimension
    -- When a player spawns an NPC via admin command, inherit his dimension
    function SpawnNPCForPlayer(ply, npcClass)
        local npc = ents.Create(npcClass)
        if IsValid(npc) then
            npc:SetPos(ply:GetPos() + ply:GetForward() * 100)
            npc:Spawn()
            npc:SetDimension(ply:GetDimension())
        end
    end
```


KNOWN ISSUES & LIMITATIONS (as of v1.0.0-beta)
===========

1. Sound Leakage
   - Some weapon sounds from addons may still be heard across dimensions.
   - This happens because certain sounds are emitted without an entity
     reference (orphan sounds) or bypass the EntityEmitSound hook.
   - Workaround: Adjust the sound isolation filters in cl_init.lua or
     use fjs_dimension.PlaySoundInDimension manually.

2. NPC Relationship Chunk Updates
   - With 100+ NPCs, the chunked update system may occasionally miss
     pacifying an NPC pair until the next full update (up to 60 seconds).
   - The fast sanity check (every 0.3s) catches most cases, but there is
     a small window where two NPCs from different dimensions could briefly
     attack each other.
   - Workaround: Decrease NPCNPCUpdateInterval (e.g., to 30) for better
     reactivity, but that increases server load.

3. Projectile Dimension Inheritance
   - Projectiles fired from weapons correctly inherit the shooter's dimension.
   - However, grenades thrown by NPCs or environmental explosions may
     default to dimension 0 if no owner can be resolved within the
     configured ProjectileNearestOwnerRadius.
   - This can cause invisible explosions for players in other dimensions.
   - Workaround: Increase ProjectileNearestOwnerRadius or explicitly set
     the dimension of projectiles in their OnSpawn hooks.

4. Client-Side Ragdolls
   - The client-side ragdoll hiding (CreateClientsideRagdoll) sometimes
     leaves a ghost ragdoll visible for a split second before hiding.
   - This is a limitation of Garry's Mod's entity creation and network timing.
   - No reliable workaround, but it does not affect gameplay.

5. Duplicator / Saving
   - Entities saved with duplicator or map saves may lose their dimension
     after server restart if they are not reloaded with the proper modifier.
   - The system tries to persist dimension via an entity modifier
     ("m_dim_persistence"), but some addons may override it.
   - Workaround: Manually restore dimensions on PostEntityLoad.

6. Performance with Many Dimensions
   - The system caches entities per dimension, but iterating over all
     entities is still O(N) on dimension changes. With thousands of entities
     and many dimensions, there may be brief spikes.
   - The chunked NPC updates and fast sanity checks help, but keep an eye
     on performance if you have over 5000 entities.


SUPPORT & CONTRIBUTIONS
==================

- This is an open-source project under active development.
- You are encouraged to fix bugs and improve the code.
- If you distribute a modified version, you MUST keep the original credits
  and clearly state your changes.
- For bug reports or feature requests, contact in discord: fjs01.
