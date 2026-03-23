ENT.Type      = "anim"
ENT.Base      = "npc_poison_base"
ENT.PrintName = "NPC Poison Effect"
ENT.Author    = "narcan"
ENT.Spawnable = false

-- ============================================================
--  Effect parameters — identical to g_drug_vodka
--  Shader, motion blur, and toy town params are read by
--  NarcanBase_ApplyEffect() and sent to the client.
-- ============================================================
ENT.DrugMaterial = "effects/shaders/g_drug_alcohol"
ENT.DrugParams   = {
    ["$c0_x"] = { 0, 35 }
}

ENT.UseMotionBlur    = true
ENT.MotionBlurParams = {
    drawAlpha = { 0, 0.05 },
    addAlpha  = { 0, 1    },
    delay     = { 0, 0.05 },
}

ENT.UseToyTown    = true
ENT.ToyTownParams = {
    intensity = { 0, 10 }
}

ENT.EnableBloom = false

-- ============================================================
--  CustomBehavior — direct copy of g_drug_vodka
--  Runs every server Think tick while level > 0.
--  Causes random involuntary movement/attack inputs exactly
--  as the original vodka drug does.
-- ============================================================
ENT.CustomBehavior = {
    function(ply, level)
        if SERVER then
            if level > 0.2 then
                ply.DrugDrunkControl = ply.DrugDrunkControl or {}

                if not ply.DrugDrunkControl.NextMove
                or CurTime() >= ply.DrugDrunkControl.NextMove then

                    local moves = { "+forward", "+back", "+moveleft", "+moveright", "+attack" }
                    local stops = { "-forward", "-back", "-moveleft", "-moveright", "-attack" }

                    local i    = math.random(1, #moves)
                    local move = moves[i]
                    local stop = stops[i]

                    ply:ConCommand(move)

                    timer.Simple(math.Rand(0.5, 1), function()
                        if IsValid(ply) then
                            ply:ConCommand(stop)
                        end
                    end)

                    ply.DrugDrunkControl.NextMove = CurTime() + math.Rand(0.3, 0.9)
                end
            else
                -- Effect ending — flush any stuck inputs.
                if ply.DrugDrunkControl then
                    local stops = { "-forward", "-back", "-moveleft", "-moveright", "-attack" }
                    for _, cmd in ipairs(stops) do
                        ply:ConCommand(cmd)
                    end
                    ply.DrugDrunkControl = nil
                end
            end
        end
    end
}
