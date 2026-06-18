-- ============================================================================
-- HOLLOW POCKET ARCHIVE ENGINE (LUA PORT FOR PSP-1000 - STABLE PRODUCTION)
-- ============================================================================

-- Game States Constants
local STATE_ACCOUNT_SELECT = 0
local STATE_GAMEPLAY       = 1
local STATE_MAP_SHOP       = 2
local STATE_INVENTORY      = 3
local STATE_GAME_OVER      = 4

-- Configuration Variables
local TILE_SIZE    = 16
local MAP_COLS     = 30
local MAP_ROWS     = 17
local TOTAL_ORBS   = 14
local TOTAL_SLOTS  = 8
local MAX_FLOORS   = 200

-- Physics Constants
local GRAVITY       = 0.8
local JUMP_FORCE    = -11.0
local WALK_SPEED    = 3.0
local DASH_SPEED    = 10.0
local DASH_COOLDOWN = 25

-- AI Behaviours
local BOSS_STALK  = 0
local BOSS_LEAP   = 1
local BOSS_DASH   = 2

-- Core Game Variables
local game_state = STATE_ACCOUNT_SELECT
local selected_account = 1
local current_floor = 1
local player_hp = 5
local player_max_hp = 5
local player_geo = 100
local player_soul = 0
local max_soul = 99

-- Systems Mapping Arrays
local tilemap = {}
local map_unlocked = {0, 0, 0, 0}
local player_orbs = {}
for i = 1, TOTAL_ORBS do player_orbs[i] = 0 end
local player_spells = {}

-- Player Vectors
local player_x = 30.0
local player_y = 200.0
local velocity_x = 0.0
local velocity_y = 0.0
local is_grounded = false
local player_direction = 1

local PLAYER_WIDTH = 12
local PLAYER_HEIGHT = 16

-- Timers
local dash_timer = 0
local dash_cooldown_timer = 0
local attack_active_timer = 0
local player_invuln_frames = 0

-- Boss Properties
local is_boss_room = false
local current_boss_idx = -1
local boss_x = 300.0
local boss_y = 200.0
local boss_vel_x = 1.8
local boss_hp = 100
local boss_max_hp = 100
local boss_direction = -1
local boss_ai_state = BOSS_STALK
local boss_ai_timer = 90
local boss_width = 24
local boss_height = 32

-- Shop Settings
local shop_selection = 1
local map_prices = {50, 120, 200, 300}

-- Dictionaries
local BOSS_NAMES = {
    "False Knight", "Hornet Protector", "Massive Moss Charger", "Mantis Lords",
    "Soul Master", "Dung Defender", "Broken Vessel", "Watcher Knights",
    "The Collector", "Traitor Lord", "Grimm (Troupe Master)", "Pure Vessel",
    "Grey Prince Zote", "The Radiance"
}

local MAP_NAMES = {
    "Forgotten Crossroads Map", "Greenpath Map", "City of Tears Map", "The Deepnest Abyss Map"
}

-- Procedural Room Blueprints
local MAP_CHUNKS = {
    {
        {0,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0},
        {0,0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,2,2,2,2,0,0,0,2,2,2,2,0,0,0,0,0},
        {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1}
    },
    {
        {0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,1,1,0,0,0,0,0},
        {0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0},
        {0,0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1}
    }
}

-- Initialize Global Randomizer seed once on startup
math.randomseed(os.time())

-- Graphics & Audio Asset Pipelines (Note: final_boss.wav used to guarantee compatibility)
local bg = Image.load("assets/background.png")
local music = Sound.load("assets/music.wav")
local final_boss_music = nil

if music then 
    Sound.play(music, true) 
end

-- ============================================================================
-- SYSTEM HELPER OPERATIONS
-- ============================================================================

local function getZoneName(floor)
    if floor <= 50  then return "Forgotten Crossroads", 1 end
    if floor <= 100 then return "Greenpath Caverns", 2 end
    if floor <= 150 then return "City of Tears", 3 end
    return "The Deepnest Abyss", 4
end

local function injectProceduralMap(floor, is_boss)
    tilemap = {}
    for r = 1, MAP_ROWS do
        tilemap[r] = {}
        for c = 1, MAP_COLS do
            if r == 1 or r == MAP_ROWS or c == 1 or c == MAP_COLS then
                tilemap[r][c] = 1
            else
                tilemap[r][c] = 0
            end
        end
    end

    if not is_boss then
        local chunk = MAP_CHUNKS[math.random(1, #MAP_CHUNKS)]
        for r = 1, #chunk do
            for c = 1, #chunk[1] do
                tilemap[r + 5][c + 4] = chunk[r][c]
            end
        end
    else
        -- Clean Boss arena floor
        for c = 2, MAP_COLS - 1 do
            tilemap[MAP_ROWS - 1][c] = 1
        end
    end
end

local function checkMapCollision(cx, cy)
    local left   = math.floor(cx / TILE_SIZE) + 1
    local right  = math.floor((cx + PLAYER_WIDTH) / TILE_SIZE) + 1
    local top    = math.floor(cy / TILE_SIZE) + 1
    local bottom = math.floor((cy + PLAYER_HEIGHT) / TILE_SIZE) + 1

    -- Boundary Guarding
    if left < 1 or right > MAP_COLS or top < 1 or bottom > MAP_ROWS then 
        return true 
    end
    
    -- Safe Nil Matrix Checks
    if not tilemap[top] or not tilemap[bottom] then
        return true
    end

    if tilemap[top][left] == 1 or tilemap[top][right] == 1 or
       tilemap[bottom][left] == 1 or tilemap[bottom][right] == 1 then
        return true
    end
    return false
end

local function checkSpikeHazard(cx, cy)
    local left   = math.floor((cx + 2) / TILE_SIZE) + 1
    local right  = math.floor((cx + PLAYER_WIDTH - 2) / TILE_SIZE) + 1
    local top    = math.floor((cy + 2) / TILE_SIZE) + 1
    local bottom = math.floor((cy + PLAYER_HEIGHT) / TILE_SIZE) + 1

    if left < 1 or right > MAP_COLS or top < 1 or bottom > MAP_ROWS then 
        return false 
    end
    if not tilemap[top] or not tilemap[bottom] then
        return false
    end

    if tilemap[top][left] == 2 or tilemap[top][right] == 2 or
       tilemap[bottom][left] == 2 or tilemap[bottom][right] == 2 then
        return true
    end
    return false
end

local function resetPlayer()
    player_x = 30.0
    player_y = 180.0
    velocity_x = 0.0
    velocity_y = 0.0
    is_grounded = false
    attack_active_timer = 0
end

local function checkFloorState()
    if current_floor == MAX_FLOORS or current_floor % 15 == 0 then
        is_boss_room = true
        current_boss_idx = math.min(math.floor(current_floor / 15), #BOSS_NAMES)
        if current_floor == MAX_FLOORS then
            current_boss_idx = 14
        end
        
        boss_x = 320.0
        boss_y = 200.0
        boss_hp = 50 + (current_floor * 2)
        boss_max_hp = boss_hp
        boss_ai_state = BOSS_STALK
        boss_ai_timer = 90
        
        if current_floor == MAX_FLOORS and music then
            Sound.stop(music)
            final_boss_music = Sound.load("assets/final_boss.wav")
            if final_boss_music then 
                Sound.play(final_boss_music, true) 
            end
        end
    else
        is_boss_room = false
        current_boss_idx = -1
    end
    injectProceduralMap(current_floor, is_boss_room)
end

local function saveProfile()
    -- Create structural paths to protect low-level I/O environments if engine supports it
    if System and System.createDirectory then
        System.createDirectory("ms0:/PSP/SAVEDATA/")
    end

    local file = io.open("ms0:/PSP/SAVEDATA/HOLLOWPK0" .. selected_account .. ".TXT", "w")
    if file then
        file:write(current_floor .. "\n" .. player_geo .. "\n" .. player_hp .. "\n" .. player_soul .. "\n")
        for i = 1, 4 do 
            file:write(map_unlocked[i] .. "\n") 
        end
        for i = 1, TOTAL_ORBS do 
            file:write(player_orbs[i] .. "\n") 
        end
        file:close()
    end
end

local function loadProfile()
    local file = io.open("ms0:/PSP/SAVEDATA/HOLLOWPK0" .. selected_account .. ".TXT", "r")
    if file then
        current_floor = tonumber(file:read() or 1)
        player_geo = tonumber(file:read() or 100)
        player_hp = tonumber(file:read() or 5)
        player_soul = tonumber(file:read() or 0)
        for i = 1, 4 do 
            map_unlocked[i] = tonumber(file:read() or 0) 
        end
        for i = 1, TOTAL_ORBS do 
            player_orbs[i] = tonumber(file:read() or 0) 
        end
        file:close()
    else
        current_floor = 1
        player_hp = 5
        player_geo = 100
        player_soul = 0
        for i = 1, 4 do 
            map_unlocked[i] = 0 
        end
        for i = 1, TOTAL_ORBS do 
            player_orbs[i] = 0 
        end
    end
    checkFloorState()
end

local function advanceFloor()
    player_geo = player_geo + 20 + math.random(1, 15)
    if is_boss_room and current_boss_idx > 0 then 
        player_orbs[current_boss_idx] = 1 
    end
    current_floor = current_floor + 1
    saveProfile()
    checkFloorState()
    resetPlayer()
end

local function fireSpell()
    if player_soul < 33 then 
        return 
    end
    table.insert(player_spells, {
        x = player_x + (16 * player_direction),
        y = player_y + 4,
        vx = 6.0 * player_direction,
        width = 12,
        height = 8,
        life = 40
    })
    player_soul = math.max(0, player_soul - 33)
end

-- ============================================================================
-- MAIN RUNTIME EXECUTION ENVIRONMENT
-- ============================================================================

while true do
    local pad = Controls.read()
    screen:clear(Color.new(15, 16, 20))

    if game_state == STATE_ACCOUNT_SELECT then
        screen:print(15, 15, "HOLLOW KNIGHT: POCKET ARCHIVE ENGINE (LUA)", Color.new(230, 225, 215))
        for i = 1, TOTAL_SLOTS do
            local color = Color.new(110, 110, 115)
            local prefix = "   Slot "
            if i == selected_account then
                color = Color.new(135, 195, 215)
                prefix = "=> PROFILE SLOT "
            end
            screen:print(15, 50 + (i * 18), prefix .. i, color)
        end

        if pad:down() then 
            selected_account = (selected_account % TOTAL_SLOTS) + 1 
        end
        if pad:up()   then 
            selected_account = (selected_account - 2 + TOTAL_SLOTS) % TOTAL_SLOTS + 1 
        end
        if pad:cross() then
            loadProfile()
            game_state = STATE_GAMEPLAY
        end

    elseif game_state == STATE_GAMEPLAY then
        -- Timers tick down
        if player_invuln_frames > 0 then 
            player_invuln_frames = player_invuln_frames - 1 
        end

        -- Spell Trigger Processing
        if pad:triangle() then
            if pad:down() and player_soul >= 33 then
                if player_hp < player_max_hp then
                    player_hp = math.min(player_hp + 1, player_max_hp)
                    player_soul = math.max(0, player_soul - 33)
                end
            else
                fireSpell()
            end
        end

        -- Horizontal Movement Processing
        if dash_timer > 0 then
            velocity_x = DASH_SPEED * player_direction
            velocity_y = 0
            dash_timer = dash_timer - 1
        else
            velocity_x = 0
            if pad:left() then 
                velocity_x = -WALK_SPEED 
                player_direction = -1 
            end
            if pad:right() then 
                velocity_x = WALK_SPEED 
                player_direction = 1 
            end
            
            velocity_y = velocity_y + GRAVITY
            if velocity_y > 10 then 
                velocity_y = 10 
            end
        end

        -- Jump & Dash Processing
        if pad:cross() then
            if is_grounded then
                velocity_y = JUMP_FORCE 
                is_grounded = false 
            end
        end
        
        if pad:square() then
            if dash_cooldown_timer == 0 then
                dash_timer = 8 
                dash_cooldown_timer = DASH_COOLDOWN 
            end
        end
        
        if dash_cooldown_timer > 0 then 
            dash_cooldown_timer = dash_cooldown_timer - 1 
        end

        -- Nail Attack Range Verification
        if pad:circle() then
            if attack_active_timer == 0 then
                attack_active_timer = 6 
            end
        end
        
        if attack_active_timer > 0 then 
            attack_active_timer = attack_active_timer - 1 
        end

        -- 2D AABB Matrix Axis Separation Collision Processing
        player_x = player_x + velocity_x
        if checkMapCollision(player_x, player_y) then 
            player_x = player_x - velocity_x 
        end

        player_y = player_y + velocity_y
        if checkMapCollision(player_x, player_y) then
            if velocity_y > 0 then 
                is_grounded = true 
            end
            player_y = player_y - velocity_y
            velocity_y = 0
        end

        -- Spike Hazard Detection
        if checkSpikeHazard(player_x, player_y) and player_invuln_frames == 0 then
            player_hp = player_hp - 1
            player_invuln_frames = 30
            resetPlayer()
        end

        -- Update and Render Projectile Table Array
        for i = #player_spells, 1, -1 do
            local spell = player_spells[i]
            spell.x = spell.x + spell.vx
            spell.life = spell.life - 1
            
            -- Draw active spell object
            screen:fillRect(math.floor(spell.x), math.floor(spell.y), spell.width, spell.height, Color.new(255, 255, 255))
            
            -- Collision against Boss Target
            if is_boss_room and spell.x + spell.width >= boss_x and spell.x <= boss_x + boss_width and
               spell.y + spell.height >= boss_y and spell.y <= boss_y + boss_height then
                boss_hp = boss_hp - 15
                table.remove(player_spells, i)
            elseif spell.life <= 0 or checkMapCollision(spell.x, spell.y) then
                table.remove(player_spells, i)
            end
        end

        -- Active Boss AI Routine Engine Process
        if is_boss_room then
            boss_ai_timer = boss_ai_timer - 1
            if boss_ai_timer <= 0 then
                boss_ai_state = math.random(0, 2)
                boss_ai_timer = math.random(60, 120)
            end

            if boss_ai_state == BOSS_STALK then
                boss_direction = (player_x > boss_x) and 1 or -1
                boss_x = boss_x + (boss_vel_x * boss_direction)
            elseif boss_ai_state == BOSS_DASH then
                boss_x = boss_x + (boss_vel_x * 2.5 * boss_direction)
                if boss_x < 20 or boss_x > 440 then boss_direction = -boss_direction end
            elseif boss_ai_state == BOSS_LEAP then
                boss_x = boss_x + (boss_vel_x * boss_direction)
                -- Simulating basic horizontal leap float oscillation
                boss_y = 160 + math.sin(boss_ai_timer * 0.1) * 30
            end

            -- Verify Melee Damage from Player Nail Focus
            if attack_active_timer > 0 then
                local ax = (player_direction == 1) and player_x + PLAYER_WIDTH or player_x - 24
                if ax + 24 >= boss_x and ax <= boss_x + boss_width and
                   player_y + 12 >= boss_y and player_y <= boss_y + boss_height then
                    boss_hp = boss_hp - 2
                    player_soul = math.min(max_soul, player_soul + 11)
                end
            end

            -- Handle Contact Damage to Player Matrix
            if player_invuln_frames == 0 and
               player_x + PLAYER_WIDTH >= boss_x and player_x <= boss_x + boss_width and
               player_y + PLAYER_HEIGHT >= boss_y and player_y <= boss_y + boss_height then
                player_hp = player_hp - 1
                player_invuln_frames = 40
            end

            -- Validate Boss Health Status Defeat
            if boss_hp <= 0 then
                advanceFloor()
            end
        else
            -- Check Progression Boundary Threshold Exit Condition
            if player_x >= (480 - TILE_SIZE - PLAYER_WIDTH) then 
                advanceFloor() 
            end
        end

        -- Validate Critical Global Lifeline Health Integrity
        if player_hp <= 0 then
            game_state = STATE_GAME_OVER
        end

        -- Render Room Geometry Layers
        if bg then screen:blit(0, 0, bg) end
        
        for r = 1, MAP_ROWS do
            for c = 1, MAP_COLS do
                if tilemap[r][c] == 1 then
                    screen:fillRect((c-1)*TILE_SIZE, (r-1)*TILE_SIZE, TILE_SIZE, TILE_SIZE, Color.new(55, 60, 70))
                elseif tilemap[r][c] == 2 then
                    screen:fillRect((c-1)*TILE_SIZE, (r-1)*TILE_SIZE + 8, TILE_SIZE, 8, Color.new(190, 50, 45))
                end
            end
        end

        -- Render Entities Blocks
        if player_invuln_frames % 4 < 2 then
            screen:fillRect(math.floor(player_x), math.floor(player_y), PLAYER_WIDTH, PLAYER_HEIGHT, Color.new(240, 235, 220))
        end

        if attack_active_timer > 0 then
            local ax = (player_direction == 1) and player_x + PLAYER_WIDTH or player_x - 24
            screen:fillRect(math.floor(ax), math.floor(player_y + 4), 24, 8, Color.new(135, 190, 210))
        end

        if is_boss_room then
            screen:fillRect(math.floor(boss_x), math.floor(boss_y), boss_width, boss_height, Color.new(155, 90, 180))
            screen:fillRect(140, 12, 200, 6, Color.new(50, 20, 20))
            screen:fillRect(140, 12, math.floor((boss_hp / boss_max_hp) * 200), 6, Color.new(210, 40, 40))
        end

        -- UI HUD Analytics Output Render
        local hp_str = "MASKS: "
        for i = 1, player_hp do hp_str = hp_str .. "<3 " end
        local zone_name, zone_idx = getZoneName(current_floor)

        screen:print(12, 12, hp_str, Color.new(255, 255, 255))
        screen:print(12, 24, "SOUL: " .. player_soul .. "/99 | GEO: " .. player_geo, Color.new(255, 255, 255))
        screen:print(12, 36, "ZONE: " .. zone_name .. " (F " .. current_floor .. ")", Color.new(255, 255, 255))

        -- State Intercept Controls Check
        if pad:select() then game_state = STATE_INVENTORY end
        if pad:note()   then game_state = STATE_MAP_SHOP end

    elseif game_state == STATE_INVENTORY then
        screen:fillRect(10, 10, 460, 2, Color.new(140, 150, 165))
        screen:print(25, 22, "=== INVENTORY COMPASS & JOURNAL ===", Color.new(200, 210, 225))

        -- Column Left: Radar Display Checks
        screen:print(25, 50, "[ MAP ARCHIVES ]", Color.new(135, 185, 210))
        local current_zone_name, active_zone_idx = getZoneName(current_floor)

        for i = 1, 4 do
            local item_y = 70 + (i - 1) * 16
            if map_unlocked[i] == 1 then
                screen:print(25, item_y, "* " .. MAP_NAMES[i], Color.new(255, 255, 255))
                if i == active_zone_idx then
                    screen:print(210, item_y, "(Active)", Color.new(120, 230, 150))
                end
            else
                screen:print(25, item_y, "[ Locked Map Slot ]", Color.new(80, 85, 95))
            end
        end

        -- Live Radar Tracking Visual Canvas Area Draw
        screen:fillRect(25, 145, 210, 100, Color.new(24, 28, 38))
        if map_unlocked[active_zone_idx] == 1 then
            screen:print(35, 152, "MAP STATUS: ONLINE", Color.new(140, 165, 190))
            screen:fillRect(35 + math.floor(player_x / 3), 165 + math.floor(player_y / 4), 6, 6, Color.new(255, 70, 70))
        else
            screen:print(35, 185, "No Map Object Available", Color.new(120, 125, 135))
            screen:print(35, 200, "Buy layout from Cornifer", Color.new(120, 125, 135))
        end

        -- Column Right: Journal Targets Records Track
        screen:print(265, 50, "[ MASTERED BOSS ORBS ]", Color.new(230, 180, 110))
        for i = 1, TOTAL_ORBS do
            local col = math.floor((i-1) / 7)
            local row = (i-1) % 7
            local ox = 265 + (col * 105)
            local oy = 70 + (row * 22)

            if player_orbs[i] == 1 then
                screen:fillRect(ox, oy + 4, 8, 8, Color.new(120, 210, 255))
                screen:print(ox + 12, oy, "Orb " .. string.format("%02d", i), Color.new(245, 245, 250))
            else
                screen:fillRect(ox, oy + 4, 8, 8, Color.new(45, 50, 60))
                screen:print(ox + 12, oy, "Missing", Color.new(85, 90, 100))
            end
        end

        screen:print(265, 235, "Press [SELECT] to return to game", Color.new(140, 145, 155))
        if pad:select() then game_state = STATE_GAMEPLAY end

    elseif game_state == STATE_MAP_SHOP then
        screen:fillRect(10, 10, 460, 2, Color.new(215, 180, 100))
        screen:print(25, 22, "=== ISALDA'S CARTOGRAPHY MAP SHOP ===", Color.new(235, 220, 180))
        screen:print(25, 45, "Your Wallet Balance: " .. player_geo .. " Geo", Color.new(255, 255, 255))

        for i = 1, 4 do
            local item_y = 80 + (i - 1) * 24
            local color = Color.new(130, 135, 145)
            local prefix = "   "
            
            if i == shop_selection then
                color = Color.new(230, 190, 90)
                prefix = "=> "
            end
            
            local display_text = prefix .. MAP_NAMES[i]
            screen:print(25, item_y, display_text, color)
            
            if map_unlocked[i] == 1 then
                screen:print(320, item_y, "[ PURCHASED ]", Color.new(100, 210, 120))
            else
                screen:print(320, item_y, map_prices[i] .. " Geo", Color.new(210, 215, 225))
            end
        end

        -- Handle Menu Selections
        if pad:down() then 
            shop_selection = (shop_selection % 4) + 1 
        end
        if pad:up()   then 
            shop_selection = (shop_selection - 2 + 4) % 4 + 1 
        end
        
        if pad:cross() then
            if map_unlocked[shop_selection] == 0 and player_geo >= map_prices[shop_selection] then
                player_geo = player_geo - map_prices[shop_selection]
                map_unlocked[shop_selection] = 1
                saveProfile()
            end
        end

        screen:print(25, 220, "Press [CROSS] to Purchase | Press [NOTE] to exit shop", Color.new(150, 155, 165))
        if pad:note() then game_state = STATE_GAMEPLAY end

    elseif game_state == STATE_GAME_OVER then
        screen:print(160, 100, "GEOMETRY COLLAPSED", Color.new(220, 50, 40))
        screen:print(135, 130, "Press [CROSS] to Load Auto-Save", Color.new(190, 195, 200))
        
        if pad:cross() then
            loadProfile()
            resetPlayer()
            game_state = STATE_GAMEPLAY
        end
    end

    screen.flip()
    screen.waitVblankStart()
end