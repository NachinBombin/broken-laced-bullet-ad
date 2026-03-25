-- ============================================================
--  NPC Laced Bullet  |  lua/autorun/client/npc_poison_bullet_cl.lua
--  Client-side tracer renderer.
--
--  Three-layer tracer (core + glow shell + UV travel animation)
--  with an impact flash sprite and a small chemical particle
--  burst at the hit point. Color palette matches ent_gas_stun
--  orange exactly so both delivery systems read as the same agent.
-- ============================================================

if SERVER then return end

-- ============================================================
--  Timing
-- ============================================================
local TRACER_DELAY   = 0.07   -- seconds before tracer appears (post-impact reveal)
local TRACER_LIFE    = 0.55   -- total seconds the tracer is visible
local TRAVEL_FRAC   = 0.35   -- fraction of TRACER_LIFE spent "in flight" (UV scroll)
local FLASH_LIFE     = 0.12   -- seconds the impact flash sprite lives

-- ============================================================
--  Geometry
-- ============================================================
local CORE_WIDTH     = 1.5    -- inner bright core beam width
local GLOW_WIDTH     = 6.0    -- outer glow shell width
local FLASH_SIZE     = 28     -- impact flash sprite radius at peak

-- ============================================================
--  Colors  (matched to ent_gas_stun orange palette)
-- ============================================================
local COL_CORE  = Color(255, 210,  80)   -- hot yellow-orange core
local COL_GLOW  = Color(255, 120,  15)   -- deeper orange glow shell
local COL_FLASH = Color(255, 180,  40)   -- amber impact flash

-- ============================================================
--  Materials
-- ============================================================
-- glow04: tight bright spot — used for the hot core beam.
local MAT_CORE  = Material("sprites/glow04_noz")
-- light_glow02: wide soft halo — used for the orange shell.
local MAT_GLOW  = Material("sprites/light_glow02_noz")
-- glow: round additive sprite — used for the impact flash.
local MAT_FLASH = Material("sprites/glow04_noz")
-- smokesprites: same sheets used by ent_gas_stun particles.
local SMOKE_BASE = "particle/smokesprites_000"

-- ============================================================
--  Active tracer pool
--  Each entry: { src, hit, born, flashDone, emitter }
-- ============================================================
local activeTracers = {}

net.Receive("NPCPoisonBullet_Tracer", function()
    local src = net.ReadVector()
    local hit = net.ReadVector()

    timer.Simple(TRACER_DELAY, function()
        -- Impact particle burst — small chemical release on entry.
        local emitter = ParticleEmitter(hit, false)
        if emitter then
            local numParticles = math.random(4, 7)
            for i = 1, numParticles do
                local p = emitter:Add(SMOKE_BASE .. math.random(1, 9), hit)
                if p then
                    p:SetVelocity(Vector(
                        math.Rand(-30, 30),
                        math.Rand(-30, 30),
                        math.Rand(20, 60)
                    ))
                    p:SetDieTime(math.Rand(0.4, 0.9))
                    p:SetColor(
                        math.random(220, 255),
                        math.random(80, 140),
                        math.random(5, 20)
                    )
                    p:SetStartAlpha(math.Rand(180, 220))
                    p:SetEndAlpha(0)
                    p:SetStartSize(math.Rand(2, 5))
                    p:SetEndSize(math.Rand(18, 32))
                    p:SetRoll(math.Rand(0, 360))
                    p:SetRollDelta(math.Rand(-1, 1))
                    p:SetAirResistance(60)
                    p:SetGravity(Vector(0, 0, -14))
                end
            end
            emitter:Finish()
        end

        activeTracers[#activeTracers + 1] = {
            src       = src,
            hit       = hit,
            born      = CurTime(),
            flashDone = false,
        }
    end)
end)

-- ============================================================
--  Draw hook
-- ============================================================
hook.Add("PostDrawOpaqueRenderables", "NPCPoisonBullet_DrawTracer", function()
    if #activeTracers == 0 then return end

    local now   = CurTime()
    local alive = {}

    for _, t in ipairs(activeTracers) do
        local age  = now - t.born
        if age >= TRACER_LIFE then continue end  -- expired, drop it

        local lifeFrac = age / TRACER_LIFE       -- 0 → 1 over full life
        -- Ease-out fade: fast bright start, smooth tail-off
        local alpha_frac = (1 - lifeFrac) ^ 1.6

        -- ── Travel animation ─────────────────────────────────
        -- During the first TRAVEL_FRAC of life the beam "races"
        -- from src to hit by scrolling the UV start position.
        -- After that the full beam is visible and fading.
        local uStart = 0
        if lifeFrac < TRAVEL_FRAC then
            -- UV start moves 0→0 as travel completes; beam appears
            -- to grow from src toward hit.
            uStart = 1 - (lifeFrac / TRAVEL_FRAC)
        end

        local coreAlpha  = math.floor(255  * alpha_frac)
        local glowAlpha  = math.floor(110  * alpha_frac)

        -- ── Layer 1: glow shell (wide, soft orange) ───────────
        render.SetMaterial(MAT_GLOW)
        render.DrawBeam(
            t.src, t.hit,
            GLOW_WIDTH,
            uStart, 1,
            Color(COL_GLOW.r, COL_GLOW.g, COL_GLOW.b, glowAlpha)
        )

        -- ── Layer 2: core beam (tight, bright yellow-orange) ──
        render.SetMaterial(MAT_CORE)
        render.DrawBeam(
            t.src, t.hit,
            CORE_WIDTH,
            uStart, 1,
            Color(COL_CORE.r, COL_CORE.g, COL_CORE.b, coreAlpha)
        )

        -- ── Layer 3: impact flash sprite (first FLASH_LIFE s) ─
        if not t.flashDone then
            if age < FLASH_LIFE then
                local flashFrac  = 1 - (age / FLASH_LIFE)
                local flashAlpha = math.floor(220 * (flashFrac ^ 0.7))
                local flashSize  = FLASH_SIZE * (1 + (1 - flashFrac) * 1.4)

                render.SetMaterial(MAT_FLASH)
                render.DrawSprite(
                    t.hit,
                    flashSize, flashSize,
                    Color(COL_FLASH.r, COL_FLASH.g, COL_FLASH.b, flashAlpha)
                )
            else
                t.flashDone = true
            end
        end

        alive[#alive + 1] = t
    end

    activeTracers = alive
end)
