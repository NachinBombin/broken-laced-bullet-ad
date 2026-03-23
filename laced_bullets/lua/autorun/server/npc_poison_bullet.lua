-- ============================================================
--  NPC Poison Bullet  |  lua/autorun/server/npc_poison_bullet.lua
--
--  Periodically causes eligible Combine NPCs to fire a laced
--  bullet at their player target.  On hit the player receives
--  the "npc_poison_effect" intoxication — a vodka-identical
--  visual + movement disruption — via our own NarcanBase
--  rendering pipeline (no g_drug_base dependency).
--
--  Effect is triggered by calling:
--      NarcanBase_ApplyEffect(ply, "npc_poison_effect", dur)
--  which reads npc_poison_effect's entity definition, builds
--  the StartEffect net message, and sends it to the client.
--
--  Clearable instantly by Narcan (arctic_med_shots/narcan.lua)
--  via NPCPoisonBullet_NarcanClear(ply).
-- ============================================================

if not SERVER then return end

util.AddNetworkString("NPCPoisonBullet_Tracer")

-- ============================================================
--  ConVars
-- ============================================================
local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

local cv_enabled  = CreateConVar("npc_poison_bullet_enabled",  "1",    SHARED_FLAGS, "Enable/disable NPC poison bullet shots.")
local cv_chance   = CreateConVar("npc_poison_bullet_chance",   "0.15", SHARED_FLAGS, "Probability (0-1) that an eligible NPC fires a laced bullet each check.")
local cv_interval = CreateConVar("npc_poison_bullet_interval", "10",   SHARED_FLAGS, "Seconds between eligibility checks per NPC.")
local cv_cooldown = CreateConVar("npc_poison_bullet_cooldown", "25",   SHARED_FLAGS, "Minimum seconds between laced shots from the same NPC.")
local cv_dur_min  = CreateConVar("npc_poison_bullet_dur_min",  "60",   SHARED_FLAGS, "Minimum intoxication effect duration in seconds.")
local cv_dur_max  = CreateConVar("npc_poison_bullet_dur_max",  "180",  SHARED_FLAGS, "Maximum intoxication effect duration in seconds.")
local cv_damage   = CreateConVar("npc_poison_bullet_damage",   "8",    SHARED_FLAGS, "Damage dealt by the laced bullet on hit.")
local cv_max_dist = CreateConVar("npc_poison_bullet_max_dist", "2000", SHARED_FLAGS, "Max engagement distance in units.")
local cv_min_dist = CreateConVar("npc_poison_bullet_min_dist", "80",   SHARED_FLAGS, "Min engagement distance in units.")
local cv_announce = CreateConVar("npc_poison_bullet_announce", "0",    SHARED_FLAGS, "Print debug info on each laced shot.")

-- ============================================================
--  NPC whitelist
-- ============================================================
local POISON_SHOOTERS = {
    ["npc_combine_s"]     = true,
    ["npc_metropolice"]   = true,
    ["npc_combine_elite"] = true,
}

local function IsEligibleShooter(npc)
    if not IsValid(npc) or not npc:IsNPC() then return false end
    return POISON_SHOOTERS[npc:GetClass()] == true
end

-- ============================================================
--  FirePoisonBullet
--  Plays a reload gesture to telegraph the special round,
--  waits 1 second, then fires and applies the effect on hit.
-- ============================================================
local function FirePoisonBullet(npc, target)

    -- ACT_SIGNAL_ADVANCE: arm-raised point gesture — highly visible
    -- in combat and clearly signals to the player that this NPC
    -- is doing something deliberate before the shot fires.
    do
        local seq = npc:SelectWeightedSequence(ACT_SIGNAL_ADVANCE)
        if seq <= 0 then
            -- Fallback: melee attack covers the 1-second window if
            -- the NPC's model lacks a signal animation.
            seq = npc:SelectWeightedSequence(ACT_MELEE_ATTACK1)
        end
        if seq > 0 then npc:AddGesture(ACT_SIGNAL_ADVANCE) end
    end

    npc.__poison_lastShot = CurTime()

    local distAtTrigger = npc:GetPos():Distance(target:GetPos())

    timer.Simple(1, function()
        if not IsValid(npc) or not IsValid(target) then return end
        if not target:Alive() then return end

        local duration = math.Rand(
            math.max(cv_dur_min:GetFloat(), 1),
            math.max(cv_dur_max:GetFloat(), 1)
        )

        npc:FireBullets({
            Attacker = npc,
            Num      = 1,
            Src      = npc:EyePos(),
            Dir      = (target:EyePos() - npc:EyePos()):GetNormalized(),
            Spread   = Vector(0, 0, 0),
            Tracer   = 1,
            Force    = 2,
            Damage   = cv_damage:GetFloat(),
            AmmoType = "AR2",

            Callback = function(attacker, tr, dmginfo)
                if not IsValid(tr.Entity) or not tr.Entity:IsPlayer() then return end

                -- Broadcast tracer to all clients so bystanders see it too.
                net.Start("NPCPoisonBullet_Tracer")
                    net.WriteVector(npc:EyePos())
                    net.WriteVector(tr.HitPos)
                net.Broadcast()

                -- Trigger our self-contained vodka-identical effect.
                NarcanBase_ApplyEffect(tr.Entity, "npc_poison_effect", duration)

                if cv_announce:GetBool() then
                    print(string.format(
                        "[NPC Poison Bullet] %s hit %s — %.0fs  (dist %.0f)",
                        npc:GetClass(), tr.Entity:Nick(), duration, distAtTrigger
                    ))
                end
            end,
        })
    end)
end

-- ============================================================
--  Per-NPC lazy state init
-- ============================================================
local function InitNPCState(npc)
    if npc.__poison_hooked then return end
    npc.__poison_hooked    = true
    npc.__poison_nextCheck = CurTime() + math.Rand(1, cv_interval:GetFloat())
    npc.__poison_lastShot  = 0
end

-- ============================================================
--  Main Think loop (runs every 0.5 s)
-- ============================================================
timer.Create("NPCPoisonBullet_Think", 0.5, 0, function()
    if not cv_enabled:GetBool() then return end

    local now      = CurTime()
    local interval = cv_interval:GetFloat()
    local cooldown = cv_cooldown:GetFloat()
    local chance   = cv_chance:GetFloat()
    local maxDist  = cv_max_dist:GetFloat()
    local minDist  = cv_min_dist:GetFloat()

    for _, npc in ipairs(ents.GetAll()) do
        if not IsValid(npc) or not npc:IsNPC() then continue end
        if not IsEligibleShooter(npc) then continue end

        InitNPCState(npc)

        if now < (npc.__poison_nextCheck or 0) then continue end
        npc.__poison_nextCheck = now + interval + math.Rand(-1, 1)

        if now - (npc.__poison_lastShot or 0) < cooldown then continue end
        if npc:Health() <= 0 then continue end

        local enemy = npc:GetEnemy()
        if not IsValid(enemy) or not enemy:IsPlayer() then continue end
        if not enemy:Alive() then continue end

        local dist = npc:GetPos():Distance(enemy:GetPos())
        if dist > maxDist or dist < minDist then continue end

        -- Line-of-sight check.
        local tr = util.TraceLine({
            start  = npc:EyePos(),
            endpos = enemy:EyePos(),
            filter = { npc },
            mask   = MASK_SOLID,
        })
        if tr.Entity ~= enemy and tr.Fraction < 0.85 then continue end

        if math.random() > chance then continue end

        FirePoisonBullet(npc, enemy)
    end
end)

print("[NPC Poison Bullet] Loaded. NarcanBase pipeline active.")
