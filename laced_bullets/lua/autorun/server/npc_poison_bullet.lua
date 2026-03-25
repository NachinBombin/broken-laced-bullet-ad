-- ============================================================
--  NPC Laced Bullet  |  lua/autorun/server/npc_poison_bullet.lua
--
--  Causes eligible Combine NPCs to occasionally fire a laced
--  bullet at their player target.  On hit the player receives
--  the EXACT same stun-gas intoxication from ent_gas_stun:
--    - Same net message  : NPCStunGas_ApplyHigh
--    - Same NW floats    : npc_stungas_high_start / _high_end
--    - Same vaccine hook : NPCStunGas_NarcanClear(ply)
--    - Same gas mask skip: pl.GASMASK_Equiped
--
--  No external dependencies.  Works standalone alongside
--  the ent_gas_stun addon.
-- ============================================================

if not SERVER then return end

util.AddNetworkString("NPCPoisonBullet_Tracer")
-- NPCStunGas_ApplyHigh is registered by ent_gas_stun/shared.lua.
-- We declare it here as a fallback so this addon works even if
-- the gas grenade entity is not present on the map yet.
util.AddNetworkString("NPCStunGas_ApplyHigh")

-- ============================================================
--  ConVars
-- ============================================================
local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

local cv_enabled  = CreateConVar("npc_poison_bullet_enabled",  "1",    SHARED_FLAGS, "Enable/disable NPC laced bullet shots.")
local cv_chance   = CreateConVar("npc_poison_bullet_chance",   "0.15", SHARED_FLAGS, "Probability (0-1) that an eligible NPC fires a laced bullet each check.")
local cv_interval = CreateConVar("npc_poison_bullet_interval", "10",   SHARED_FLAGS, "Seconds between eligibility checks per NPC.")
local cv_cooldown = CreateConVar("npc_poison_bullet_cooldown", "25",   SHARED_FLAGS, "Minimum seconds between laced shots from the same NPC.")
local cv_dur_min  = CreateConVar("npc_poison_bullet_dur_min",  "30",   SHARED_FLAGS, "Minimum stun effect duration in seconds.")
local cv_dur_max  = CreateConVar("npc_poison_bullet_dur_max",  "75",   SHARED_FLAGS, "Maximum stun effect duration in seconds.")
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
--  ApplyStunHigh
--  1-to-1 copy of ent_gas_stun's ApplyStunHigh, so the bullet
--  and the gas grenade produce the exact same effect.
--  Uses the same net message, same NW floats, same gas mask
--  check, and same vaccine hook (NPCStunGas_NarcanClear).
-- ============================================================
local playerHighEnd = {}

local function ApplyStunHigh(pl)
    if not IsValid(pl) or not pl:IsPlayer() then return end
    if not pl:Alive() then return end
    if pl.GASMASK_Equiped then return end

    local now = CurTime()
    local uid = pl:UserID()
    local highDuration = math.Rand(
        math.max(cv_dur_min:GetFloat(), 1),
        math.max(cv_dur_max:GetFloat(), 1)
    )

    -- Stack duration if already intoxicated.
    if (playerHighEnd[uid] or 0) > now then
        playerHighEnd[uid] = math.max(playerHighEnd[uid], now + highDuration)
        pl:SetNWFloat("npc_stungas_high_end", playerHighEnd[uid])
        return
    end

    playerHighEnd[uid] = now + highDuration

    net.Start("NPCStunGas_ApplyHigh")
    net.WriteFloat(now)
    net.WriteFloat(playerHighEnd[uid])
    net.Send(pl)

    pl:SetNWFloat("npc_stungas_high_start", now)
    pl:SetNWFloat("npc_stungas_high_end", playerHighEnd[uid])

    -- Random involuntary movement inputs — identical timing to gas grenade.
    local commands = { "left", "right", "moveleft", "moveright", "duck", "attack" }
    local numHits  = math.random(1, 3)

    for i = 1, numHits do
        timer.Simple(math.Rand(2, 8), function()
            if not IsValid(pl) or not pl:Alive() then return end
            if (playerHighEnd[uid] or 0) < CurTime() then return end
            local cmd = commands[math.random(1, #commands)]
            pl:ConCommand("+" .. cmd)
            timer.Simple(math.Rand(0.3, 0.9), function()
                if not IsValid(pl) then return end
                pl:ConCommand("-" .. cmd)
            end)
        end)
    end

    timer.Simple(highDuration * 0.45, function()
        if not IsValid(pl) or not pl:Alive() then return end
        if (playerHighEnd[uid] or 0) < CurTime() then return end
        local cmd = commands[math.random(1, #commands)]
        pl:ConCommand("+" .. cmd)
        timer.Simple(math.Rand(0.4, 1.0), function()
            if not IsValid(pl) then return end
            pl:ConCommand("-" .. cmd)
        end)
    end)

    timer.Simple(highDuration * 0.75, function()
        if not IsValid(pl) or not pl:Alive() then return end
        if (playerHighEnd[uid] or 0) < CurTime() then return end
        local numLate = math.random(1, 2)
        for i = 1, numLate do
            local cmd = commands[math.random(1, #commands)]
            pl:ConCommand("+" .. cmd)
            timer.Simple(math.Rand(0.5, 1.2), function()
                if not IsValid(pl) then return end
                pl:ConCommand("-" .. cmd)
            end)
        end
    end)
end

-- ============================================================
--  NPCStunGas_NarcanClear extension
--  ent_gas_stun already defines this global.  We wrap it so
--  both the gas grenade AND the laced bullet state are cleared
--  by a single Narcan injection.
--  If ent_gas_stun is not loaded, we define it from scratch.
-- ============================================================
local _prev_NarcanClear = NPCStunGas_NarcanClear  -- nil if gas addon absent

function NPCStunGas_NarcanClear(ply)
    if not IsValid(ply) then return end

    -- Clear laced-bullet state.
    local uid = ply:UserID()
    playerHighEnd[uid] = nil

    -- Clear gas grenade state (if the gas addon is also loaded).
    if isfunction(_prev_NarcanClear) then
        _prev_NarcanClear(ply)
    else
        -- Standalone fallback: zero NW floats and send stop message.
        ply:SetNWFloat("npc_stungas_high_start", 0)
        ply:SetNWFloat("npc_stungas_high_end", 0)
        net.Start("NPCStunGas_ApplyHigh")
        net.WriteFloat(0)
        net.WriteFloat(0)
        net.Send(ply)
    end
end

-- ============================================================
--  Death cleanup
-- ============================================================
hook.Add("PlayerDeath", "NPCLacedBullet_ClearOnDeath", function(pl)
    if not IsValid(pl) then return end
    local uid = pl:UserID()
    playerHighEnd[uid] = nil
    -- NW floats and net message are handled by ent_gas_stun's
    -- own PlayerDeath hook.  If gas addon is absent, clean up here.
    if not isfunction(_prev_NarcanClear) then
        pl:SetNWFloat("npc_stungas_high_start", 0)
        pl:SetNWFloat("npc_stungas_high_end", 0)
        net.Start("NPCStunGas_ApplyHigh")
        net.WriteFloat(0)
        net.WriteFloat(0)
        net.Send(pl)
    end
end)

-- ============================================================
--  FireLacedBullet
-- ============================================================
local function FireLacedBullet(npc, target)
    do
        local seq = npc:SelectWeightedSequence(ACT_SIGNAL_ADVANCE)
        if seq <= 0 then
            seq = npc:SelectWeightedSequence(ACT_MELEE_ATTACK1)
        end
        if seq > 0 then npc:AddGesture(ACT_SIGNAL_ADVANCE) end
    end

    npc.__poison_lastShot = CurTime()

    local distAtTrigger = npc:GetPos():Distance(target:GetPos())

    timer.Simple(1, function()
        if not IsValid(npc) or not IsValid(target) then return end
        if not target:Alive() then return end

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

                net.Start("NPCPoisonBullet_Tracer")
                    net.WriteVector(npc:EyePos())
                    net.WriteVector(tr.HitPos)
                net.Broadcast()

                -- Apply the stun gas effect directly.
                ApplyStunHigh(tr.Entity)

                if cv_announce:GetBool() then
                    print(string.format(
                        "[NPC Laced Bullet] %s hit %s (dist %.0f)",
                        npc:GetClass(), tr.Entity:Nick(), distAtTrigger
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

        local tr = util.TraceLine({
            start  = npc:EyePos(),
            endpos = enemy:EyePos(),
            filter = { npc },
            mask   = MASK_SOLID,
        })
        if tr.Entity ~= enemy and tr.Fraction < 0.85 then continue end

        if math.random() > chance then continue end

        FireLacedBullet(npc, enemy)
    end
end)

print("[NPC Laced Bullet] Loaded. Wired directly to NPCStunGas pipeline.")
