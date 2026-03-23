-- ============================================================
--  NPC Poison Bullet  |  npc_poison_bullet_menu.lua
--  Client-side Options menu panel.
--
--  Registers under the shared "Bombin Addons" category inside
--  the Options tab of the spawnmenu, alongside NPC Smoke Throw.
-- ============================================================

if SERVER then return end

local ADDON_CATEGORY = "Bombin Addons"

-- ============================================================
--  Register the category (safe no-op if it already exists)
-- ============================================================
hook.Add("AddToolMenuCategories", "NPCPoisonBullet_AddCategory", function()
    spawnmenu.AddToolMenuCategory(ADDON_CATEGORY)
end)

-- ============================================================
--  Build the panel
-- ============================================================
hook.Add("PopulateToolMenu", "NPCPoisonBullet_PopulateMenu", function()
    spawnmenu.AddToolMenuOption(
        "Options",
        ADDON_CATEGORY,
        "npc_poison_bullet_settings",
        "NPC Poison Bullet",
        "",
        "",
        function(panel)

            panel:ClearControls()

            -- ------------------------------------------------
            --  Header
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "NPC Poison Bullet Settings",
                Height      = "40",
            })

            panel:CheckBox("Enable NPC Poison Bullets", "npc_poison_bullet_enabled")
            panel:ControlHelp("  Master on/off switch for the entire addon.")

            panel:CheckBox("Debug Announce in Console", "npc_poison_bullet_announce")
            panel:ControlHelp("  Print a console message every time an NPC fires a laced bullet.")

            panel:AddControl("Label", { Text = "" })    -- spacer

            -- ------------------------------------------------
            --  Probability & timing
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Probability & Timing",
                Height      = "30",
            })

            panel:NumSlider("Shot Chance",
                "npc_poison_bullet_chance", 0, 1, 2)
            panel:ControlHelp("  Probability (0.00 – 1.00) that an eligible NPC fires\n  a laced bullet each check.  Default: 0.15")

            panel:NumSlider("Check Interval (seconds)",
                "npc_poison_bullet_interval", 1, 30, 0)
            panel:ControlHelp("  Seconds between eligibility checks per NPC.  Default: 10")

            panel:NumSlider("Shot Cooldown (seconds)",
                "npc_poison_bullet_cooldown", 1, 60, 0)
            panel:ControlHelp("  Minimum seconds between laced shots from the same NPC.  Default: 25")

            panel:AddControl("Label", { Text = "" })

            -- ------------------------------------------------
            --  Alcohol effect duration
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Alcohol Effect Duration",
                Height      = "30",
            })

            panel:NumSlider("Min Duration (seconds)",
                "npc_poison_bullet_dur_min", 10, 300, 0)
            panel:ControlHelp("  Minimum duration of the alcohol effect when a laced\n  bullet connects.  Default: 60")

            panel:NumSlider("Max Duration (seconds)",
                "npc_poison_bullet_dur_max", 10, 600, 0)
            panel:ControlHelp("  Maximum duration of the alcohol effect when a laced\n  bullet connects.  Default: 180")

            panel:AddControl("Label", { Text = "" })

            -- ------------------------------------------------
            --  Bullet properties
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Bullet Properties",
                Height      = "30",
            })

            panel:NumSlider("Bullet Damage",
                "npc_poison_bullet_damage", 0, 50, 0)
            panel:ControlHelp("  Raw damage dealt by the laced bullet on hit.\n  Set to 0 for effect-only (no HP loss).  Default: 8")

            panel:AddControl("Label", { Text = "" })

            -- ------------------------------------------------
            --  Engagement range
            -- ------------------------------------------------
            panel:AddControl("Header", {
                Description = "Engagement Range",
                Height      = "30",
            })

            panel:NumSlider("Max Distance",
                "npc_poison_bullet_max_dist", 200, 6000, 0)
            panel:ControlHelp("  NPCs will not attempt a laced shot if the player is\n  farther than this many units.  Default: 2000")

            panel:NumSlider("Min Distance",
                "npc_poison_bullet_min_dist", 0, 500, 0)
            panel:ControlHelp("  NPCs will not attempt a laced shot if the player is\n  closer than this many units.  Default: 80")

            panel:AddControl("Label", { Text = "" })

            -- ------------------------------------------------
            --  Info footer
            -- ------------------------------------------------
            panel:ControlHelp("  Changes take effect immediately.\n  Requires the G-Drugs base (g_drug_base) to be installed.\n  Works on: Combine Soldier, Metrocop, Combine Elite.")

        end
    )
end)
