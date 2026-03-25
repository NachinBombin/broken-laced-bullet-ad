-- ============================================================
--  NPC Laced Bullet  |  npc_poison_bullet_menu.lua
--  Client-side Options menu panel.
--
--  Found in: Options -> Bombin Addons -> NPC Laced Bullet
--  "Bombin Addons" category is registered by the family's
--  other addons (e.g. NPC Incendiary Bullets). No category
--  registration needed here.
-- ============================================================

if SERVER then return end

local ADDON_TITLE    = "NPC Laced Bullet"
local ADDON_CATEGORY = "Bombin Addons"

local function BuildLacedBulletOptions()
    spawnmenu.AddToolMenuOption("Options", ADDON_CATEGORY, "NPC_LacedBullet_Panel", ADDON_TITLE, "", "", function(panel)
        panel:ClearControls()

        -- ----------------------------------------------------------------
        --  Header
        -- ----------------------------------------------------------------
        panel:Help("NPC LACED BULLET")
        panel:Help(
            "Gives Combine soldiers a chance to fire a chemically laced\n" ..
            "round. On hit the player receives the same stun-gas effect\n" ..
            "as ent_gas_stun — identical visuals, same Narcan vaccine."
        )

        -- ----------------------------------------------------------------
        --  Master switch
        -- ----------------------------------------------------------------
        panel:Help("\n-----  Master Switch  -----")
        panel:CheckBox("Enable Laced Bullets", "npc_poison_bullet_enabled")
        panel:ControlHelp("Turns the entire addon on or off without uninstalling.")

        panel:CheckBox("Debug Announce in Console", "npc_poison_bullet_announce")
        panel:ControlHelp("Prints a console message every time an NPC fires a laced bullet.")

        -- ----------------------------------------------------------------
        --  Probability & timing
        -- ----------------------------------------------------------------
        panel:Help("\n-----  Probability & Timing  -----")
        panel:NumSlider("Shot Chance", "npc_poison_bullet_chance", 0, 1, 2)
        panel:ControlHelp("Probability (0.00 – 1.00) that an eligible NPC fires a laced bullet each check.  Default: 0.15")

        panel:NumSlider("Check Interval (seconds)", "npc_poison_bullet_interval", 1, 30, 0)
        panel:ControlHelp("Seconds between eligibility checks per NPC.  Default: 10")

        panel:NumSlider("Shot Cooldown (seconds)", "npc_poison_bullet_cooldown", 1, 60, 0)
        panel:ControlHelp("Minimum seconds between laced shots from the same NPC.  Default: 25")

        -- ----------------------------------------------------------------
        --  Stun effect duration
        -- ----------------------------------------------------------------
        panel:Help("\n-----  Stun Effect Duration  -----")
        panel:NumSlider("Min Duration (seconds)", "npc_poison_bullet_dur_min", 10, 300, 0)
        panel:ControlHelp("Minimum duration of the stun effect on hit.  Default: 30")

        panel:NumSlider("Max Duration (seconds)", "npc_poison_bullet_dur_max", 10, 300, 0)
        panel:ControlHelp("Maximum duration of the stun effect on hit.  Default: 75")

        -- ----------------------------------------------------------------
        --  Bullet properties
        -- ----------------------------------------------------------------
        panel:Help("\n-----  Bullet Properties  -----")
        panel:NumSlider("Bullet Damage", "npc_poison_bullet_damage", 0, 50, 0)
        panel:ControlHelp("Raw damage dealt by the laced bullet on hit.  Set to 0 for effect-only.  Default: 8")

        -- ----------------------------------------------------------------
        --  Engagement range
        -- ----------------------------------------------------------------
        panel:Help("\n-----  Engagement Range  -----")
        panel:NumSlider("Max Distance", "npc_poison_bullet_max_dist", 200, 6000, 0)
        panel:ControlHelp("NPCs will not attempt a laced shot beyond this range.  Default: 2000")

        panel:NumSlider("Min Distance", "npc_poison_bullet_min_dist", 0, 500, 0)
        panel:ControlHelp("NPCs will not attempt a laced shot closer than this.  Default: 80")

        -- ----------------------------------------------------------------
        --  Footer
        -- ----------------------------------------------------------------
        panel:Help("\n-----  Info  -----")
        panel:Help(
            "Changes take effect immediately.\n" ..
            "Works on: Combine Soldier, Metrocop, Combine Elite.\n" ..
            "Effect is cancelled by the Narcan vaccine (NPCStunGas_NarcanClear)."
        )

    end)
end

hook.Add("PopulateToolMenu", "NPC_LacedBullet_AddOptionsMenu", BuildLacedBulletOptions)
