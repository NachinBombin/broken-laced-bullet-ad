-- ============================================================
--  NPC Poison Bullet  |  lua/autorun/client/npc_poison_bullet_cl.lua
--  Client-side tracer renderer.
--
--  Receives NPCPoisonBullet_Tracer from the server (broadcast
--  on confirmed hit) and draws a short-lived dark hairline
--  beam from the NPC's eye to the impact point.
--
--  The tracer is intentionally delayed by TRACER_DELAY seconds
--  after receipt.  Since hitscan travel is instant, the net
--  message arrives effectively simultaneous with the hit — the
--  delay makes the line appear a beat after impact rather than
--  before it, which reads as a "reveal" rather than a warning.
-- ============================================================

if SERVER then return end

-- ============================================================
--  Configuration
-- ============================================================

local TRACER_DELAY = 0.07   -- seconds after receipt before line appears
local TRACER_LIFE  = 0.30   -- seconds the line stays visible
local TRACER_WIDTH = 1.2    -- units wide  (hairline; keep ≤ 2)

-- Dark desaturated crimson — visible against most map surfaces
-- without reading as a bright or "magical" effect.
local TRACER_COLOR = Color(25, 8, 8)

-- cable/rope is a plain dark cord texture with no glow or bloom.
-- It stays flat regardless of HDR/bloom settings, which keeps the
-- tracer subtle even on brightly lit maps.
local MAT_TRACER = Material("cable/rope")

-- ============================================================
--  Active tracer pool
-- ============================================================

local activeTracers = {}   -- { src, hit, born }

net.Receive("NPCPoisonBullet_Tracer", function()
    local src = net.ReadVector()
    local hit = net.ReadVector()

    -- Slight delay so the line appears after the bullet lands,
    -- not while it is "in flight" (hitscan has no flight time).
    timer.Simple(TRACER_DELAY, function()
        activeTracers[#activeTracers + 1] = {
            src  = src,
            hit  = hit,
            born = CurTime(),
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

    render.SetMaterial(MAT_TRACER)

    for _, t in ipairs(activeTracers) do
        local age = now - t.born

        if age < TRACER_LIFE then
            -- Linear fade: full alpha at birth, gone at TRACER_LIFE.
            local frac  = 1 - (age / TRACER_LIFE)
            local alpha = math.floor(160 * frac)   -- max 160/255 — intentionally dim

            render.DrawBeam(
                t.src, t.hit,
                TRACER_WIDTH,
                0, 1,
                Color(TRACER_COLOR.r, TRACER_COLOR.g, TRACER_COLOR.b, alpha)
            )

            alive[#alive + 1] = t
        end
        -- Expired tracers are simply dropped (not added to alive).
    end

    activeTracers = alive
end)
