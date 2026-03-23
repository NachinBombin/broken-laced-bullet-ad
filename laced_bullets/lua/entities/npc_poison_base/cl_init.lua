include("shared.lua")

-- ============================================================
--  NPC Poison Base  |  entities/npc_poison_base/cl_init.lua
--
--  Client-side rendering pipeline. Direct copy of g_drug_base
--  cl_init.lua rewritten under our own net strings.
--
--  Changes vs g_drug_base:
--    - Net strings renamed to NarcanBase_*
--    - GDrugMusicController references removed (no music)
--    - NarcanBase_StopEffect receiver added (Narcan / death)
--    - CalcView sinusoidal camera sway added (extra drunk feel)
-- ============================================================

local activeEffects = {}

-- ============================================================
--  NarcanBase_StartEffect receiver
--  Byte-for-byte identical read order to g_drug_base's
--  DrugBase_StartEffect, only the net string name differs.
-- ============================================================
net.Receive("NarcanBase_StartEffect", function()

    local ent          = net.ReadEntity()
    local useSound     = net.ReadString()
    local music        = net.ReadString()
    local priority     = net.ReadUInt(8)
    local effectDuration = net.ReadFloat()

    -- Shader material params
    local matPath    = net.ReadString()
    local paramCount = net.ReadUInt(8)
    local params     = {}
    for i = 1, paramCount do
        local key     = net.ReadString()
        local isRange = net.ReadBool()
        if isRange then
            local from = net.ReadFloat()
            local to   = net.ReadFloat()
            params[key] = { from, to }
        else
            local to = net.ReadFloat()
            params[key] = { 0, to }
        end
    end

    -- Motion blur params
    local useMotionBlur = net.ReadBool()
    local motionBlur    = {}
    if useMotionBlur then
        local count = net.ReadUInt(8)
        for i = 1, count do
            local key  = net.ReadString()
            local from = net.ReadFloat()
            local to   = net.ReadFloat()
            motionBlur[key] = { from, to }
        end
    end

    -- Toy Town params
    local useToyTown = net.ReadBool()
    local toyTown    = {}
    if useToyTown then
        local count = net.ReadUInt(8)
        for i = 1, count do
            local key  = net.ReadString()
            local from = net.ReadFloat()
            local to   = net.ReadFloat()
            toyTown[key] = { from, to }
        end
    end

    -- Bloom params
    local enableBloom = net.ReadBool()
    local bloomParams = nil
    if enableBloom then
        bloomParams = {}
        local count = net.ReadUInt(8)
        for i = 1, count do
            local key  = net.ReadString()
            local from = net.ReadFloat()
            local to   = net.ReadFloat()
            bloomParams[key] = { from, to }
        end
    end

    -- Guard: don't re-trigger an already active priority slot.
    if activeEffects[priority] and activeEffects[priority].active then return end

    local mat = (matPath ~= "") and Material(matPath) or nil

    local class      = net.ReadString()
    local musicDelay = net.ReadFloat()

    local effect = {
        startTime     = CurTime(),
        active        = true,
        level         = 0,
        music         = music,
        priority      = priority,
        ent           = ent,
        duration      = effectDuration,
        drugMaterial  = mat,
        drugParams    = params,
        useMotionBlur = useMotionBlur,
        motionBlur    = motionBlur,
        useToyTown    = useToyTown,
        toyTown       = toyTown,
        class         = class,
        musicDelay    = musicDelay,
        enableBloom   = enableBloom,
        bloomParams   = bloomParams,
    }

    -- CustomBehavior on the entity (unused in our system but kept for parity).
    if IsValid(ent) and istable(ent.CustomBehavior) then
        effect.customBehavior = ent.CustomBehavior
    end

    activeEffects[priority] = effect
end)

-- ============================================================
--  NarcanBase_StopEffect receiver
--  Zeroes all active effects immediately so every rendering
--  hook returns early on the very next frame.
--  Sent by NPCPoisonBullet_NarcanClear and PlayerDeath.
-- ============================================================
net.Receive("NarcanBase_StopEffect", function()
    for priority, effect in pairs(activeEffects) do
        effect.active = false
        effect.level  = 0
    end
end)

-- ============================================================
--  Think — easing curve
--  Direct copy of g_drug_base DrugBase_EffectThink.
--    0  → 50% duration : quadratic ease-in  (t^2)
--    50% → 100%        : linear fade-out
-- ============================================================
hook.Add("Think", "NarcanBase_EffectThink", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    for priority, effect in pairs(activeEffects) do
        if not effect.active then continue end

        if not ply:Alive() then
            effect.level  = 0
            effect.active = false
            continue
        end

        local t = (CurTime() - effect.startTime) / (effect.duration or 5)
        t = math.Clamp(t, 0, 1)

        if t < 0.5 then
            local up = t * 2
            effect.level = up ^ 2          -- quadratic ease-in (identical to g_drug_base)
        else
            local down = 1 - ((t - 0.5) * 2)
            effect.level = math.max(down, 0)  -- linear fade-out (identical to g_drug_base)
        end

        if t >= 1 then
            effect.level  = 0
            effect.active = false

            if IsValid(effect.ent) and effect.ent.OnEffectComplete then
                effect.ent:OnEffectComplete(ply)
            end
            continue
        end

        -- CustomBehavior (unused in our system; kept for parity).
        if istable(effect.customBehavior) then
            for _, func in ipairs(effect.customBehavior) do
                if isfunction(func) then func(ply, effect.level) end
            end
        end

        -- Report level to server (drives NarcanBase_ServerCustomBehavior).
        net.Start("NarcanBase_ReportEffectLevel")
            net.WriteString(effect.class)
            net.WriteFloat(effect.level or 0)
        net.SendToServer()
    end
end)

-- ============================================================
--  RenderScreenspaceEffects
--  Direct copy of g_drug_base DrugBase_RenderEffects.
--  Applies shader, motion blur, toy town, bloom at scaled level.
-- ============================================================
hook.Add("RenderScreenspaceEffects", "NarcanBase_RenderEffects", function()
    for _, effect in pairs(activeEffects) do
        if not effect.active then continue end

        local level = effect.level
        if level <= 0 then continue end

        -- ── Shader material ───────────────────────────────────
        if effect.drugMaterial then
            render.UpdateScreenEffectTexture()
            for key, range in pairs(effect.drugParams or {}) do
                local from = range[1] or 0
                local to   = range[2] or 0
                effect.drugMaterial:SetFloat(key, from + (to - from) * level)
            end
            render.SetMaterial(effect.drugMaterial)
            render.DrawScreenQuad()
        end

        -- ── Motion blur ───────────────────────────────────────
        if effect.useMotionBlur then
            local mb = effect.motionBlur

            local r  = mb.addAlpha
            local r2 = mb.drawAlpha
            local r3 = mb.delay

            local addAlpha  = r[1]  + (r[2]  - r[1])  * level
            local drawAlpha = r2[1] + (r2[2] - r2[1]) * level
            local delay     = r3[1] + (r3[2] - r3[1]) * level

            DrawMotionBlur(drawAlpha, addAlpha, delay)
        end

        -- ── Toy Town ──────────────────────────────────────────
        if effect.useToyTown then
            local intensity = 0
            if effect.toyTown.intensity then
                local r = effect.toyTown.intensity
                intensity = r[1] + (r[2] - r[1]) * level
            end
            DrawToyTown(intensity, ScrH())
        end

        -- ── Bloom ─────────────────────────────────────────────
        if effect.enableBloom and effect.bloomParams then
            local multiply = 0
            local darken   = 0
            if effect.bloomParams.multiply then
                local r = effect.bloomParams.multiply
                multiply = r[1] + (r[2] - r[1]) * level
            end
            if effect.bloomParams.darken then
                local r = effect.bloomParams.darken
                darken = r[1] + (r[2] - r[1]) * level
            end
            DrawBloom(darken, multiply, 4, 4, 4, 1, 1, 1, 1)
        end
    end
end)

-- ============================================================
--  CalcView — sinusoidal camera sway
--  Not present in g_drug_base; added here for drunk feel.
--  Uses the highest active effect level to scale sway.
-- ============================================================
hook.Add("CalcView", "NarcanBase_CameraSway", function(ply, origin, angles, fov)
    if not IsValid(ply) then return end

    local maxLevel = 0
    for _, effect in pairs(activeEffects) do
        if effect.active and effect.level > maxLevel then
            maxLevel = effect.level
        end
    end

    if maxLevel <= 0 then return end

    local t     = CurTime()
    local level = maxLevel

    local roll  = math.sin(t * 0.7)        * 10 * level   -- wide slow roll  (±10°)
    local pitch = math.sin(t * 1.1 + 0.5)  *  3 * level   -- queasy pitch    (±3°)
    local yaw   = math.sin(t * 0.4 + 1.8)  *  2 * level   -- subtle yaw      (±2°)

    return {
        origin = origin,
        angles = Angle(angles.p + pitch, angles.y + yaw, angles.r + roll),
        fov    = fov,
    }
end)
