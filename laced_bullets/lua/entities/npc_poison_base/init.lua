AddCSLuaFile()
include("shared.lua")

-- ============================================================
--  NPC Poison Base  |  entities/npc_poison_base/init.lua
--
--  Server-side base for the NPC laced-bullet intoxication
--  system. This is a clean copy of g_drug_base/init.lua
--  rewritten under our own net strings, stripped of the
--  physical entity pickup flow and drug-combo damage, and
--  extended with:
--    NarcanBase_StopEffect  — instant Narcan clear
--    NarcanBase_ApplyEffect — global helper to trigger the
--                             effect from any server script
--    NPCPoisonBullet_NarcanClear — called by narcan.lua
-- ============================================================

util.AddNetworkString("NarcanBase_StartEffect")
util.AddNetworkString("NarcanBase_ReportEffectLevel")
util.AddNetworkString("NarcanBase_StopEffect")

-- ============================================================
--  Level tracking — populated by client reports
--  [Player][class] = level (0-1)
-- ============================================================
local playerEffectLevels = {}

-- ============================================================
--  Narcan clear timestamp — used to discard stale level reports.
--
--  Race condition this solves:
--    Frame N   (server) : NarcanClear fires → playerEffectLevels[ply] = nil
--                         StopEffect sent to client
--    Frame N   (client) : EffectThink runs before StopEffect arrives →
--                         sends ReportEffectLevel(0.7) to server
--    Frame N+1 (server) : Stale 0.7 report arrives → repopulates table
--    Frame N+1 (client) : StopEffect received → effect goes inactive →
--                         no more reports ever sent
--    Result: server stuck at level 0.7 → CustomBehavior keeps running
--            → movement disruption continues until a second Narcan clears it
--
--  Fix: ignore any incoming ReportEffectLevel that arrives within 1 second
--  of a NarcanClear.  The NPC cooldown is 25 s minimum so there is no
--  risk of discarding a legitimate report from a new hit.
-- ============================================================
local narcanClearTime = {}

net.Receive("NarcanBase_ReportEffectLevel", function(_, ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local class = net.ReadString()
    local level = net.ReadFloat()

    -- Discard stale reports that arrive in the window after a Narcan clear.
    if narcanClearTime[ply] and (CurTime() - narcanClearTime[ply]) < 1 then return end

    playerEffectLevels[ply]        = playerEffectLevels[ply] or {}
    playerEffectLevels[ply][class] = level
end)

-- ============================================================
--  Narcan clear — server receiver
--  Zeroes tracked levels for the player so the server
--  CustomBehavior Think stops running movement disruption.
-- ============================================================
net.Receive("NarcanBase_StopEffect", function(_, ply)
    -- This net string flows server → client only.
    -- This receiver is a no-op safety stub.
end)

-- ============================================================
--  Send the full StartEffect message to a player.
--
--  Reads effect parameters from the scripted entity definition
--  so adding new effects only requires a new entity file.
--
--  Message format is byte-for-byte identical to g_drug_base
--  so cl_init.lua's reader works without modification.
-- ============================================================
function NarcanBase_ApplyEffect(ply, class, duration)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not ply:Alive() then return end

    -- Guard: do not re-trigger while the effect is active.
    local levels = playerEffectLevels[ply]
    if levels and (levels[class] or 0) > 0 then return end

    local def = scripted_ents.Get(class)
    if not def then
        ErrorNoHalt("[NarcanBase] Unknown effect class: " .. tostring(class) .. "\n")
        return
    end

    net.Start("NarcanBase_StartEffect")

        -- Entity (no physical pickup in our system; send world).
        net.WriteEntity(game.GetWorld())

        -- Sounds.
        net.WriteString(def.UseSound   or "")
        net.WriteString(def.MusicSound or "")
        net.WriteUInt(def.MusicPriority or 1, 8)

        -- Duration (caller-supplied so each hit can vary).
        net.WriteFloat(duration)

        -- ── Shader material ───────────────────────────────────
        net.WriteString(def.DrugMaterial or "")
        local drugParams = def.DrugParams or {}
        net.WriteUInt(table.Count(drugParams), 8)
        for key, val in pairs(drugParams) do
            net.WriteString(key)
            if istable(val) then
                net.WriteBool(true)
                net.WriteFloat(val[1] or 0)
                net.WriteFloat(val[2] or 1)
            else
                net.WriteBool(false)
                net.WriteFloat(val)
            end
        end

        -- ── Motion blur ───────────────────────────────────────
        net.WriteBool(def.UseMotionBlur or false)
        if def.UseMotionBlur then
            local p = def.MotionBlurParams or {}
            net.WriteUInt(table.Count(p), 8)
            for k, v in pairs(p) do
                net.WriteString(k)
                net.WriteFloat(v[1] or 0)
                net.WriteFloat(v[2] or 1)
            end
        end

        -- ── Toy Town ──────────────────────────────────────────
        net.WriteBool(def.UseToyTown or false)
        if def.UseToyTown then
            local p = def.ToyTownParams or {}
            net.WriteUInt(table.Count(p), 8)
            for k, v in pairs(p) do
                net.WriteString(k)
                net.WriteFloat(v[1] or 0)
                net.WriteFloat(v[2] or 1)
            end
        end

        -- ── Bloom ─────────────────────────────────────────────
        net.WriteBool(def.EnableBloom or false)
        if def.EnableBloom then
            local p = def.BloomParams or {}
            net.WriteUInt(table.Count(p), 8)
            for k, v in pairs(p) do
                net.WriteString(k)
                net.WriteFloat(v[1] or 0)
                net.WriteFloat(v[2] or 0)
            end
        end

        -- Class name (used by client to report level back).
        net.WriteString(class)

        -- Music delay.
        net.WriteFloat(def.MusicDelay or 0)

    net.Send(ply)

    -- Play use sound server-side too (heard by nearby players).
    if def.UseSound and def.UseSound ~= "" then
        ply:EmitSound(def.UseSound)
    end
end

-- ============================================================
--  NPCPoisonBullet_NarcanClear
--  Called by arctic_med_shots/narcan.lua on injection.
--  Zeroes server-side level tracking and sends StopEffect
--  to the client so all visual layers halt immediately.
-- ============================================================
function NPCPoisonBullet_NarcanClear(ply)
    if not IsValid(ply) then return end

    -- Record timestamp BEFORE clearing the table so that any stale
    -- ReportEffectLevel packets already queued in the network buffer
    -- are silently discarded by the receiver (1-second window).
    narcanClearTime[ply] = CurTime()

    -- Zero every tracked class level for this player.
    playerEffectLevels[ply] = nil

    -- Directly clear the movement disruption state so the server
    -- CustomBehavior Think can't issue any more movement inputs.
    -- (narcan.lua also does this via timer.Simple(0.05) as a fallback.)
    ply.DrugDrunkControl = nil

    -- Flush any movement commands that are currently held.
    for _, cmd in ipairs({ "-forward", "-back", "-moveleft", "-moveright", "-attack" }) do
        ply:ConCommand(cmd)
    end

    -- Tell the client to zero activeEffects and stop rendering.
    net.Start("NarcanBase_StopEffect")
    net.Send(ply)
end

-- ============================================================
--  Server CustomBehavior Think
--  Direct copy of DrugBase_ServerCustomBehavior from
--  g_drug_base/init.lua, renamed and stripped of combo damage.
--  Calls each active effect's CustomBehavior functions every
--  tick, passing the current level — this is what drives
--  movement disruption from npc_poison_effect/shared.lua.
-- ============================================================
hook.Add("Think", "NarcanBase_ServerCustomBehavior", function()
    for _, ply in ipairs(player.GetAll()) do
        local levels = playerEffectLevels[ply]
        if not levels then continue end

        for class, level in pairs(levels) do
            if not level or level <= 0 then continue end

            local def = scripted_ents.Get(class)
            if def and istable(def.CustomBehavior) then
                for _, func in ipairs(def.CustomBehavior) do
                    if isfunction(func) then
                        func(ply, level)
                    end
                end
            end
        end
    end
end)

-- ============================================================
--  Cleanup on disconnect / death
-- ============================================================
hook.Add("PlayerDisconnected", "NarcanBase_PlayerCleanup", function(ply)
    playerEffectLevels[ply] = nil
end)

hook.Add("PlayerDeath", "NarcanBase_ClearOnDeath", function(ply)
    if not IsValid(ply) then return end
    narcanClearTime[ply]    = CurTime()
    playerEffectLevels[ply] = nil
    ply.DrugDrunkControl    = nil
    net.Start("NarcanBase_StopEffect")
    net.Send(ply)
end)
