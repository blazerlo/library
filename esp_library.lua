--[[
    esp_library.lua
    Trident Survival - ESP library

    Owns every world ESP: Player, Car, Boat, Backpack and Ore.
    Loaded by the host script through the usual remote/disk loader and driven
    with a single Init call. The host keeps building its own UI and simply
    mutates the tables exposed on ESPLib.Settings.

    Usage:
        local ESPLib = loadoutlaw("esp_library.lua")
        ESPLib.Init({
            game_functions   = game_functions,
            LocalPlayer      = LocalPlayer,
            isSleeper        = isSleeper,
            isBot            = isBot,
            Is_Teammate      = Is_Teammate,
            isJunkName       = isJunkName,
            entityDisplayName= entityDisplayName,
            getItemInHand    = getItemInHand,
            armorInfo        = function(model) ... end,   -- optional, Armor icons
            wheelNames       = car_fly._WHEEL,            -- optional, vehicle detect
            hubNames         = car_fly._HUB,              -- optional, vehicle detect
            getOreSettings   = function() return misc_settings end, -- optional
        })
        -- every frame:
        ESPLib.Update()
]]

local ESPLib = {}
ESPLib.Version = "1.0.0"

local NO_VIRTUALIZE = function(f) return f end
if type(LPH_NO_VIRTUALIZE) == "function" then
    NO_VIRTUALIZE = LPH_NO_VIRTUALIZE
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local ctx = {}

------------------------------------------------------------------ settings --
local S = {}
ESPLib.Settings = S

S.esp = {
    enabled = false, box = false, fill_box = false, fillAlpha = 0.3,
    corner_box = false, name = false, distance = false, weapon = false,
    tracer = false, viewangle = false, sleeperCheck = false, botCheck = false, teamCheck = false,
    maxDist = 2000,
    colorBox = Color3.new(1,1,1), colorFill = Color3.new(1,1,1),
    colorName = Color3.new(1,1,1), colorDist = Color3.new(1,1,1),
    colorWeapon = Color3.new(1,1,1), colorTracer = Color3.new(1,1,1),
    colorViewAngle = Color3.new(1,1,1), outlineColor = Color3.new(0,0,0),
    _objects = {}, _lastPos = setmetatable({}, {__mode = "k"}), _missingTimer = {},
    _playerCache = {},
}

S.backpack = {
    enabled = false, only_visible = false, render_distance = 500,
    outline = true, outline_color = Color3.new(0, 0, 0),
    color_name = Color3.new(1, 1, 1), text_size = 12, font = 3,
}

S.car = {
    enabled = false, render_distance = 500,
    color = Color3.fromRGB(255, 60, 60),
    name_enabled = true, closest_only = false,
    show_car = true, show_atv = true, show_heli = true,
    _tracked = {},
}

S.boat = {
    enabled = false, render_distance = 500,
    color = Color3.new(1, 1, 1),
    name_enabled = true, closest_only = false,
    _tracked = {},
}

S.ore = {
    enabled = false, stone = false, iron = false, nitrate = false, maxDist = 500,
}

--------------------------------------------------------------------- utils --
local function oreSettings()
    if type(ctx.getOreSettings) == "function" then
        local ok, r = pcall(ctx.getOreSettings)
        if ok and type(r) == "table" then return r end
    end
    return S.ore
end

local esp_player_memory = setmetatable({}, { __mode = "k" })

------------------------------------------------------------- player esp -----
local function getEspObject(model)
    if not S.esp._objects[model] then
        S.esp._objects[model] = {
            box=Drawing.new("Square"), box_fill=Drawing.new("Square"),
            name=Drawing.new("Text"), distance=Drawing.new("Text"),
            weapon=Drawing.new("Text"), armoricon=Drawing.new("Image"), tracer=Drawing.new("Line"), viewangle=Drawing.new("Line"),
            corners = {
                Drawing.new("Line"), Drawing.new("Line"), Drawing.new("Line"), Drawing.new("Line"),
                Drawing.new("Line"), Drawing.new("Line"), Drawing.new("Line"), Drawing.new("Line"),
            },
        }
        local obj = S.esp._objects[model]
        for _, line in obj.corners do
            line.Thickness = 1
            line.Transparency = 1
            line.Visible = false
            line.Color = Color3.new(1,1,1)
        end
        obj.box.Thickness=1; obj.box.Filled=false; obj.box.Transparency=1
        obj.box_fill.Thickness=0; obj.box_fill.Filled=true; obj.box_fill.Transparency=0.5
        obj.name.Size=12; obj.name.Font=3; obj.name.Center=true; obj.name.Outline=true; obj.name.OutlineColor=Color3.new(0,0,0); obj.name.Transparency=1
        obj.distance.Size=10; obj.distance.Font=3; obj.distance.Center=true; obj.distance.Outline=true; obj.distance.OutlineColor=Color3.new(0,0,0); obj.distance.Transparency=1
        obj.weapon.Size=10; obj.weapon.Font=3; obj.weapon.Center=true; obj.weapon.Outline=true; obj.weapon.OutlineColor=Color3.new(0,0,0); obj.weapon.Transparency=1
        obj.tracer.Thickness=1; obj.tracer.Transparency=1
        obj.viewangle.Thickness=1; obj.viewangle.Transparency=1
    end
    return S.esp._objects[model]
end

local function destroyEspObject(model, obj)
    obj = obj or S.esp._objects[model]
    if not obj then return end
    obj.box:Remove(); obj.box_fill:Remove(); obj.name:Remove()
    obj.distance:Remove(); obj.weapon:Remove(); obj.tracer:Remove(); obj.viewangle:Remove()
    for _, line in obj.corners do line:Remove() end
    S.esp._objects[model] = nil
    S.esp._missingTimer[model] = nil
end

local function hideEspObject(obj)
    obj.box.Visible=false; obj.box_fill.Visible=false; obj.name.Visible=false
    obj.distance.Visible=false; obj.weapon.Visible=false
    obj.tracer.Visible=false; obj.viewangle.Visible=false
    for _, line in obj.corners do line.Visible = false end
end

local function getPlayerBox(model)
    local head = model:FindFirstChild("Head")
    local root = model:FindFirstChild("HumanoidRootPart")
    if not root then root = model:FindFirstChildWhichIsA("BasePart") end
    local worldPos
    if root then
        worldPos = root.Position
        S.esp._lastPos[model] = worldPos
    else
        worldPos = S.esp._lastPos[model]
    end
    if not worldPos then return nil,nil,nil,nil end
    local headPos = head and (head.Position + Vector3.new(0, 0.5, 0)) or (worldPos + Vector3.new(0, 2.8, 0))
    local footPos = worldPos - Vector3.new(0, 2.8, 0)
    local hv = Camera:WorldToViewportPoint(headPos)
    local fv = Camera:WorldToViewportPoint(footPos)
    if hv.Z <= 0 then return nil,nil,nil,nil end
    local rawH   = fv.Y - hv.Y
    local height = math.max(rawH, 14)
    local width  = math.max(height * 0.45, 7)
    local cx     = (hv.X + fv.X) * 0.5
    return cx - width * 0.5, hv.Y, cx + width * 0.5, hv.Y + height
end

local function armorEnabled()
    if type(ctx.armorInfo) ~= "function" then return false end
    return true
end

local function drawArmorIcons(model, obj, width, bottom, subSize)
    if not armorEnabled() then return end
    local ok, err = pcall(function()
        local info = ctx.armorInfo(model)
        if not info then return end
        if not info.mapping or not next(info.mapping) then
            if not info.tried then
                info.tried = true
                pcall(ctx.armorTryInit)
            end
            return
        end
        local pieces = info.pieces or {}
        local n = info.n or 0

        local extra = obj._armorExtra
        if not extra then
            extra = {}
            obj._armorExtra = extra
        end
        if #extra < n - 1 then
            for i = #extra + 1, n - 1 do
                extra[i] = Drawing.new("Image")
            end
        end

        local sz = info.sz or 60
        local gap = info.gap or 66
        local totalW = n * gap - (gap - sz)
        local startX = math.floor((width - totalW) / 2)
        local rowY = bottom + 3 + subSize * 3 + 4

        for idx = 1, n do
            local src = info.mapping[pieces[idx]]
            local d = (idx == 1) and obj.armoricon or extra[idx]
            if d and src then
                d.Image = src.Image
                d.Size = Vector2.new(sz, sz)
                d.Position = Vector2.new(left + startX + (idx - 1) * gap, rowY)
                d.Transparency = 0
                d.Visible = true
            elseif d then
                d.Visible = false
            end
        end

        if n == 0 and obj.armoricon.Visible then
            obj.armoricon.Visible = false
        end
        for idx = n + 1, #extra do
            local d = extra[idx]
            if d and d.Visible then d.Visible = false end
        end
    end)
    if not ok and not S.esp._armorErr then
        S.esp._armorErr = true
        print("[esp armor] " .. tostring(err))
    end
end

local function updatePlayerESP()
    local ArmorOn = armorEnabled()
    local AnyVisible = S.esp.box or S.esp.fill_box or S.esp.corner_box
        or S.esp.name or S.esp.distance or S.esp.weapon
        or S.esp.tracer or S.esp.viewangle or ArmorOn
    if not AnyVisible then
        for model, obj in pairs(S.esp._objects) do
            S.esp._missingTimer[model] = (S.esp._missingTimer[model] or 0) + 0.033
            hideEspObject(obj)
            if S.esp._missingTimer[model] > 1.5 then
                destroyEspObject(model, obj)
            end
        end
        return
    end
    local cam = Camera
    if not cam then return end
    local camPos = cam.CFrame.Position
    local viewSize = cam.ViewportSize
    local allPlayers = {}
    for _, plr in Players:GetPlayers() do
        if plr ~= LocalPlayer then
            local char = plr.Character
            if char and char:IsA("Model") then allPlayers[char] = true end
        end
    end
    for _, model in ipairs(S.esp._playerCache) do
        if model and model:IsA("Model") and model ~= LocalPlayer.Character then
            allPlayers[model] = true
        end
    end
    local gf = ctx.game_functions
    if gf and gf.loaded_players then
        for _, ent in next, gf.loaded_players do
            if type(ent) == "table" and ent.model and ent.model:IsA("Model")
                and ent.model ~= LocalPlayer.Character then
                allPlayers[ent.model] = true
            end
        end
    end
    for model, obj in pairs(S.esp._objects) do
        if not allPlayers[model] then
            S.esp._missingTimer[model] = (S.esp._missingTimer[model] or 0) + 0.033
            if S.esp._missingTimer[model] > 1.5 then
                destroyEspObject(model, obj)
            else
                hideEspObject(obj)
            end
        else
            S.esp._missingTimer[model] = nil
        end
    end
    for model in pairs(allPlayers) do
        local rootPart = model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("Head") or model:FindFirstChildWhichIsA("BasePart")
        if not rootPart then
            local obj = S.esp._objects[model]
            if obj then destroyEspObject(model, obj) end
        else
            local obj = getEspObject(model)
            local sleeper = type(ctx.isSleeper) == "function" and ctx.isSleeper(model) or false
            local bot = type(ctx.isBot) == "function" and ctx.isBot(model) or false
            local shouldShow = (not S.esp.sleeperCheck or not sleeper)
                and (not S.esp.botCheck or not bot)
                and (not S.esp.teamCheck or not (type(ctx.Is_Teammate) == "function" and ctx.Is_Teammate(model)))
            local dist = math.floor((camPos - rootPart.Position).Magnitude)
            local withinDist = dist <= S.esp.maxDist
            if shouldShow and withinDist then
                local left, top, right, bottom = getPlayerBox(model)
                if left then
                    local width = right - left
                    local height = bottom - top
                    local txtSize = dist > 800 and 13 or 12
                    local subSize = dist > 800 and 11 or 10

                    if S.esp.corner_box then
                        local cornerLength = math.min(width, height) * 0.15
                        local c = S.esp.colorBox
                        obj.box.Visible = false
                        obj.box_fill.Visible = false
                        local lines = obj.corners
                        lines[1].From = Vector2.new(left, top)
                        lines[1].To   = Vector2.new(left + cornerLength, top)
                        lines[2].From = Vector2.new(left, top)
                        lines[2].To   = Vector2.new(left, top + cornerLength)
                        lines[3].From = Vector2.new(right - cornerLength, top)
                        lines[3].To   = Vector2.new(right, top)
                        lines[4].From = Vector2.new(right, top)
                        lines[4].To   = Vector2.new(right, top + cornerLength)
                        lines[5].From = Vector2.new(left, bottom - cornerLength)
                        lines[5].To   = Vector2.new(left, bottom)
                        lines[6].From = Vector2.new(left, bottom)
                        lines[6].To   = Vector2.new(left + cornerLength, bottom)
                        lines[7].From = Vector2.new(right - cornerLength, bottom)
                        lines[7].To   = Vector2.new(right, bottom)
                        lines[8].From = Vector2.new(right, bottom - cornerLength)
                        lines[8].To   = Vector2.new(right, bottom)
                        for _, line in lines do
                            line.Color = c
                            line.Transparency = 1
                            line.Visible = true
                        end
                    else
                        for _, line in obj.corners do line.Visible = false end
                        obj.box.Visible   = S.esp.box
                        obj.box.Color     = S.esp.colorBox
                        obj.box.Position  = Vector2.new(left, top)
                        obj.box.Size      = Vector2.new(width, height)
                        obj.box.Transparency = 1
                        obj.box_fill.Visible      = S.esp.fill_box
                        obj.box_fill.Color        = S.esp.colorFill
                        obj.box_fill.Position     = Vector2.new(left, top)
                        obj.box_fill.Size         = Vector2.new(width, height)
                        obj.box_fill.Transparency = 1 - S.esp.fillAlpha
                    end

                    local name = esp_player_memory[model]
                    local plr = Players:GetPlayerFromCharacter(model)
                    if plr then
                        name = plr.Name
                        esp_player_memory[model] = name
                    end
                    if type(ctx.isJunkName) == "function" and ctx.isJunkName(name) then
                        name = ctx.entityDisplayName and ctx.entityDisplayName(model) or nil
                    end
                    if type(ctx.isJunkName) == "function" and ctx.isJunkName(name) then
                        name = bot and "NPC" or "Player"
                    elseif not name then
                        name = bot and "NPC" or "Player"
                    end
                    obj.name.Visible     = S.esp.name
                    obj.name.Color       = S.esp.colorName
                    obj.name.Text        = name .. (sleeper and " [Sleeping]" or "")
                    obj.name.Position    = Vector2.new(left + width*0.5, top - 15)
                    obj.name.Size        = txtSize
                    obj.name.Transparency = 1

                    obj.distance.Visible     = S.esp.distance
                    obj.distance.Color       = S.esp.colorDist
                    obj.distance.Text        = dist .. "m"
                    obj.distance.Position    = Vector2.new(left + width*0.5, bottom + 3)
                    obj.distance.Size        = subSize
                    obj.distance.Transparency = 1

                    obj.weapon.Visible     = S.esp.weapon
                    obj.weapon.Color       = S.esp.colorWeapon
                    obj.weapon.Text        = (S.esp.weapon and type(ctx.getItemInHand) == "function"
                        and ctx.getItemInHand(model)) or "None"

                    if ArmorOn then
                        drawArmorIcons(model, obj, left, width, bottom, subSize)
                    end

                    obj.weapon.Position    = Vector2.new(left + width*0.5, bottom + 3 + subSize + 2)
                    obj.weapon.Size        = subSize
                    obj.weapon.Transparency = 1

                    if S.esp.tracer then
                        local rp2 = model:FindFirstChild("HumanoidRootPart") or rootPart
                        local tv = cam:WorldToViewportPoint(rp2.Position)
                        if tv.Z > 0 then
                            obj.tracer.Visible = true
                            obj.tracer.Color   = S.esp.colorTracer
                            obj.tracer.From    = Vector2.new(viewSize.X*0.5, viewSize.Y)
                            obj.tracer.To      = Vector2.new(tv.X, tv.Y)
                            obj.tracer.Transparency = 1
                        else obj.tracer.Visible = false end
                    else obj.tracer.Visible = false end

                    if S.esp.viewangle then
                        local hd = model:FindFirstChild("Head")
                        if hd then
                            local endPos = hd.Position + hd.CFrame.LookVector * 4
                            local sv = cam:WorldToViewportPoint(hd.Position)
                            local ev = cam:WorldToViewportPoint(endPos)
                            if sv.Z > 0 and ev.Z > 0 then
                                obj.viewangle.Visible = true
                                obj.viewangle.Color   = S.esp.colorViewAngle
                                obj.viewangle.From    = Vector2.new(sv.X, sv.Y)
                                obj.viewangle.To      = Vector2.new(ev.X, ev.Y)
                                obj.viewangle.Transparency = 1
                            else obj.viewangle.Visible = false end
                        else obj.viewangle.Visible = false end
                    else obj.viewangle.Visible = false end
                else
                    hideEspObject(obj)
                end
            else
                hideEspObject(obj)
            end
        end
    end
end
ESPLib.updatePlayerESP = updatePlayerESP

--------------------------------------------------------------- car esp ------
local function detectVehicleType(model)
    if not model or not model:IsA("Model") then return nil end
    local body = model:FindFirstChild("Body")
    if not body or not body:IsA("BasePart") then return nil end
    local bs = body.Size
    if bs.X < 2 or bs.Z < 2 then return nil end

    local hasBodyDummy = model:FindFirstChild("BodyDummy")
    local hasRearProp = model:FindFirstChild("RearProp")
    local hasHeadLock = model:FindFirstChild("HeadLockPart")
    if hasBodyDummy or hasRearProp or hasHeadLock then return "Helicopter" end

    local wheelSet = ctx.wheelNames or {}
    local hubSet = ctx.hubNames or {}
    local carWheels = 0
    local hubCount = 0
    local anyWheels = 0
    local hasRotor = false
    for _, child in model:GetChildren() do
        local n = child.Name
        if wheelSet[n] then carWheels = carWheels + 1 end
        if hubSet[n] then hubCount = hubCount + 1 end
        if child:IsA("BasePart") then
            local lower = n:lower()
            if lower:find("wheel") and not lower:find("hub") then
                anyWheels = anyWheels + 1
            end
        end
        local lower = n:lower()
        if lower:find("rotor") or lower:find("blade") or lower:find("propeller") or lower:find("tail") then
            hasRotor = true
        end
    end

    if hasRotor then return "Helicopter" end
    if carWheels >= 4 and hubCount >= 4 then
        local hasHandlebars = false
        local hasLights = false
        for _, child in model:GetChildren() do
            local n = child.Name:lower()
            if n == "handlebars" or n == "grip" or n == "frame" then hasHandlebars = true end
            if n:find("light") then hasLights = true end
        end
        if hasHandlebars then return "ATV" end
        return "Car"
    end
    if anyWheels >= 2 then return "ATV" end
    return nil
end

local function removeCarESP(model)
    local data = S.car._tracked[model]
    if data then
        if data.label then data.label:Remove() end
        S.car._tracked[model] = nil
    end
end

local function createCarESP(model)
    if S.car._tracked[model] then return end
    local vType = detectVehicleType(model)
    if not vType then return end
    local primaryPart = model.PrimaryPart or model:FindFirstChild("Body")
    if not primaryPart then return end

    local label = Drawing.new("Text")
    label.Center = true
    label.Size = 13
    label.Font = 3
    label.Outline = true
    label.OutlineColor = Color3.fromRGB(0, 0, 0)
    label.Color = S.car.color or Color3.fromRGB(255, 255, 255)
    label.Visible = false

    S.car._tracked[model] = {
        label = label,
        primaryPart = primaryPart,
        vehicleType = vType,
    }
    model.AncestryChanged:Connect(function(_, parent)
        if not parent then removeCarESP(model) end
    end)
end

function ESPLib.ScanCars()
    for _, child in workspace:GetChildren() do
        if child:IsA("Model") then
            createCarESP(child)
            for _, sub in child:GetChildren() do
                if sub:IsA("Model") then
                    createCarESP(sub)
                end
            end
        end
    end
end

local function watchForNewCars()
    workspace.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("Model") then
            task.wait(0.5)
            createCarESP(descendant)
        end
    end)
end

function ESPLib.updateCarESPVisibility()
    if not S.car.enabled then
        if S.car._hidden then return end
        S.car._hidden = true
        for _, data in pairs(S.car._tracked) do
            if data.label then data.label.Visible = false end
        end
        return
    end
    S.car._hidden = false
    local cam = Workspace.CurrentCamera
    if not cam then
        for _, data in pairs(S.car._tracked) do
            if data.label then data.label.Visible = false end
        end
        return
    end
    local camPos = cam.CFrame.Position

    if S.car.closest_only then
        local bestModel, bestDist = nil, math.huge
        for model, data in pairs(S.car._tracked) do
            if model.Parent and data.primaryPart and data.primaryPart.Parent then
                local vt = data.vehicleType
                local showType = (vt == "Car" and S.car.show_car)
                    or (vt == "ATV" and S.car.show_atv)
                    or (vt == "Helicopter" and S.car.show_heli)
                if showType then
                    local dist = (data.primaryPart.Position - camPos).Magnitude
                    if dist >= 25 and dist <= S.car.render_distance and dist < bestDist then
                        bestDist = dist; bestModel = model
                    end
                end
            end
        end
        for model, data in pairs(S.car._tracked) do
            if not model.Parent or not data.primaryPart or not data.primaryPart.Parent then
                if data.label then data.label.Visible = false end
            else
                local show = (model == bestModel) and S.car.name_enabled
                if show and data.label then
                    local sp, on = cam:WorldToViewportPoint(data.primaryPart.Position + Vector3.new(0, 3, 0))
                    if on then
                        data.label.Position = Vector2.new(sp.X, sp.Y)
                        data.label.Text = string.format("%s [%d m]", data.vehicleType or model.Name, math.floor(bestDist))
                        data.label.Color = S.car.color or data.label.Color
                        data.label.Visible = true
                    else
                        data.label.Visible = false
                    end
                elseif data.label then
                    data.label.Visible = false
                end
            end
        end
    else
        local closest = {}
        for model, data in pairs(S.car._tracked) do
            if model.Parent and data.primaryPart and data.primaryPart.Parent then
                local vt = data.vehicleType
                local showType = (vt == "Car" and S.car.show_car)
                    or (vt == "ATV" and S.car.show_atv)
                    or (vt == "Helicopter" and S.car.show_heli)
                if showType then
                    local dist = (data.primaryPart.Position - camPos).Magnitude
                    if dist >= 25 and dist <= S.car.render_distance then
                        if not closest[vt] or dist < closest[vt].dist then
                            closest[vt] = { model = model, dist = dist }
                        end
                    end
                end
            end
        end
        for model, data in pairs(S.car._tracked) do
            if not model.Parent or not data.primaryPart or not data.primaryPart.Parent then
                if data.label then data.label.Visible = false end
            else
                local isClosest = false
                for _, c in pairs(closest) do
                    if c.model == model then isClosest = true; break end
                end
                local show = isClosest and S.car.name_enabled
                if show and data.label then
                    local sp, on = cam:WorldToViewportPoint(data.primaryPart.Position + Vector3.new(0, 3, 0))
                    if on then
                        local cData = closest[data.vehicleType]
                        data.label.Position = Vector2.new(sp.X, sp.Y)
                        data.label.Text = string.format("%s [%d m]", data.vehicleType or model.Name, math.floor(cData and cData.dist or 0))
                        data.label.Color = S.car.color or data.label.Color
                        data.label.Visible = true
                    else
                        data.label.Visible = false
                    end
                elseif data.label then
                    data.label.Visible = false
                end
            end
        end
    end
end

-------------------------------------------------------------- boat esp ------
local function removeBoatESP(model)
    local data = S.boat._tracked[model]
    if data then
        if data.label then data.label:Remove() end
        S.boat._tracked[model] = nil
    end
end

local function detectBoat(model)
    if not model or not model:IsA("Model") then return false end
    local hull = model:FindFirstChild("Hull")
    if not hull or not hull:IsA("BasePart") then return false end
    if hull.Size.X < 1 or hull.Size.Z < 1 then return false end
    if hull.Transparency >= 1 then return false end
    if not hull.Parent then return false end
    return true
end

local function createBoatESP(model)
    if S.boat._tracked[model] then return end
    if not detectBoat(model) then return end
    local hull = model:FindFirstChild("Hull")
    if not hull then return end

    local label = Drawing.new("Text")
    label.Center = true
    label.Size = 13
    label.Font = 3
    label.Outline = true
    label.OutlineColor = Color3.fromRGB(0, 0, 0)
    label.Color = S.boat.color
    label.Visible = false

    S.boat._tracked[model] = { label = label, primaryPart = hull }
    model.AncestryChanged:Connect(function(_, parent)
        if not parent then removeBoatESP(model) end
    end)
end

function ESPLib.ScanBoats()
    for _, child in workspace:GetChildren() do
        if child:IsA("Model") then
            createBoatESP(child)
        end
    end
end

local function watchForNewBoats()
    workspace.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("Model") then
            task.wait(0.5)
            createBoatESP(descendant)
        end
    end)
end

function ESPLib.updateBoatESPVisibility()
    if not S.boat.enabled then
        if S.boat._hidden then return end
        S.boat._hidden = true
        for _, data in pairs(S.boat._tracked) do
            if data.label then data.label.Visible = false end
        end
        return
    end
    S.boat._hidden = false
    local cam = Workspace.CurrentCamera
    if not cam then
        for _, data in pairs(S.boat._tracked) do
            if data.label then data.label.Visible = false end
        end
        return
    end
    local camPos = cam.CFrame.Position

    if S.boat.closest_only then
        local bestModel, bestDist = nil, math.huge
        for model, data in pairs(S.boat._tracked) do
            if model.Parent and data.primaryPart and data.primaryPart.Parent then
                local dist = (data.primaryPart.Position - camPos).Magnitude
                if dist >= 10 and dist <= S.boat.render_distance and dist < bestDist then
                    bestDist = dist; bestModel = model
                end
            end
        end
        for model, data in pairs(S.boat._tracked) do
            if not model.Parent or not data.primaryPart or not data.primaryPart.Parent then
                if data.label then data.label.Visible = false end
            else
                local show = (model == bestModel) and S.boat.name_enabled
                if show and data.label then
                    local sp, on = cam:WorldToViewportPoint(data.primaryPart.Position + Vector3.new(0, 3, 0))
                    if on then
                        data.label.Position = Vector2.new(sp.X, sp.Y)
                        data.label.Text = string.format("Boat [%d m]", math.floor(bestDist))
                        data.label.Color = S.boat.color
                        data.label.Visible = true
                    else
                        data.label.Visible = false
                    end
                elseif data.label then
                    data.label.Visible = false
                end
            end
        end
    else
        for model, data in pairs(S.boat._tracked) do
            if not model.Parent or not data.primaryPart or not data.primaryPart.Parent then
                if data.label then data.label.Visible = false end
            else
                local dist = (data.primaryPart.Position - camPos).Magnitude
                local show = S.boat.name_enabled and dist >= 10 and dist <= S.boat.render_distance
                if show and data.label then
                    local sp, on = cam:WorldToViewportPoint(data.primaryPart.Position + Vector3.new(0, 3, 0))
                    if on then
                        data.label.Position = Vector2.new(sp.X, sp.Y)
                        data.label.Text = string.format("Boat [%d m]", math.floor(dist))
                        data.label.Color = S.boat.color
                        data.label.Visible = true
                    else
                        data.label.Visible = false
                    end
                elseif data.label then
                    data.label.Visible = false
                end
            end
        end
    end
end

--------------------------------------------------------- backpack esp -------
local function IdentifyBackpack(model)
    if not model or not model:IsA("Model") then return false end
    if S.backpack._cache[model] ~= nil then return S.backpack._cache[model] end
    if model:FindFirstChild("Humanoid") or model:FindFirstChild("HumanoidRootPart") then
        S.backpack._cache[model] = false; return false
    end
    local children = model:GetChildren()
    if #children ~= 2 then S.backpack._cache[model] = false; return false end
    local hasUnionFabric = false
    local hasMetalPart   = false
    for _, child in children do
        if child:IsA("BasePart") then
            if child:IsA("UnionOperation") and child.Material == Enum.Material.Fabric and child.Anchored == true then
                hasUnionFabric = true
            end
            if child.ClassName == "Part" and child.Material == Enum.Material.Metal and child.Anchored == true
                and child.Size.X <= 0.5 and child.Size.Y <= 0.5 and child.Size.Z <= 0.5 then
                hasMetalPart = true
            end
        end
    end
    local result = hasUnionFabric and hasMetalPart
    S.backpack._cache[model] = result
    return result
end

local function createBackpackLabel(model)
    if S.backpack._labels[model] then
        if S.backpack._labels[model].name then S.backpack._labels[model].name:Remove() end
        if S.backpack._labels[model].dist then S.backpack._labels[model].dist:Remove() end
        S.backpack._labels[model] = nil
    end
    local nameLabel = Drawing.new("Text")
    nameLabel.Text = "Backpack"
    nameLabel.Color = S.backpack.color_name
    nameLabel.Size = S.backpack.text_size
    nameLabel.Center = true
    nameLabel.Outline = S.backpack.outline
    nameLabel.OutlineColor = S.backpack.outline_color
    nameLabel.Font = S.backpack.font
    nameLabel.Visible = false
    local distLabel = Drawing.new("Text")
    distLabel.Text = "[?m]"
    distLabel.Color = S.backpack.color_name
    distLabel.Size = math.max(S.backpack.text_size - 2, 8)
    distLabel.Center = true
    distLabel.Outline = S.backpack.outline
    distLabel.OutlineColor = S.backpack.outline_color
    distLabel.Font = S.backpack.font
    distLabel.Visible = false
    S.backpack._labels[model] = { name = nameLabel, dist = distLabel }
    return S.backpack._labels[model]
end

local function getBackpackCenter(model)
    local totalPos = Vector3.new(0,0,0); local count = 0
    for _, child in pairs(model:GetChildren()) do
        if child:IsA("BasePart") then totalPos = totalPos + child.Position; count = count+1 end
    end
    if count > 0 then return totalPos / count end
    local root = model:FindFirstChild("PrimaryPart") or model:FindFirstChildWhichIsA("BasePart")
    return root and root.Position or nil
end

function ESPLib.ScanBackpacks()
    for _, model in pairs(workspace:GetChildren()) do
        if model:IsA("Model") and not S.backpack._labels[model] then
            if S.backpack._cache[model] == nil then
                if IdentifyBackpack(model) then createBackpackLabel(model) end
            elseif S.backpack._cache[model] == true then
                createBackpackLabel(model)
            end
        end
    end
end
ESPLib.scanForBackpacks = ESPLib.ScanBackpacks

local function hideBackpackLabel(lbl)
    if lbl then
        if lbl.name then lbl.name.Visible = false end
        if lbl.dist then lbl.dist.Visible = false end
    end
end
ESPLib.hideBackpackLabel = hideBackpackLabel

local function updateBackpackESP()
    if not S.backpack.enabled then
        for _, lbl in pairs(S.backpack._labels) do hideBackpackLabel(lbl) end
        return
    end
    if not Camera then return end
    local camPos = Camera.CFrame.Position
    for model, lbl in pairs(S.backpack._labels) do
        if model and model.Parent then
            if not S.backpack._cache[model] then
                hideBackpackLabel(lbl)
            else
                local centerPos = getBackpackCenter(model)
                if centerPos then
                    local distance = (camPos - centerPos).Magnitude
                    if distance <= S.backpack.render_distance then
                        local visible = true
                        if S.backpack.only_visible then
                            local rp = RaycastParams.new()
                            rp.FilterType = Enum.RaycastFilterType.Exclude
                            rp.FilterDescendantsInstances = {
                                LocalPlayer and LocalPlayer.Character,
                                Workspace.Const and Workspace.Const.Ignore,
                            }
                            local res = Workspace:Raycast(camPos, (centerPos - camPos).Unit * distance, rp)
                            if res and not res.Instance:IsDescendantOf(model) then visible = false end
                        end
                        if visible then
                            local screenPos, onScreen = Camera:WorldToViewportPoint(centerPos)
                            if onScreen then
                                local sz = S.backpack.text_size
                                lbl.name.Text     = "Backpack"
                                lbl.name.Position = Vector2.new(screenPos.X, screenPos.Y)
                                lbl.name.Color    = S.backpack.color_name
                                lbl.name.Size     = sz
                                lbl.name.Outline  = S.backpack.outline
                                lbl.name.OutlineColor = S.backpack.outline_color
                                lbl.name.Font     = S.backpack.font
                                lbl.name.Visible  = true
                                lbl.dist.Text     = "[" .. math.floor(distance) .. "m]"
                                lbl.dist.Position = Vector2.new(screenPos.X, screenPos.Y + sz + 2)
                                lbl.dist.Color    = S.backpack.color_name
                                lbl.dist.Size     = math.max(sz - 2, 8)
                                lbl.dist.Outline  = S.backpack.outline
                                lbl.dist.OutlineColor = S.backpack.outline_color
                                lbl.dist.Font     = S.backpack.font
                                lbl.dist.Visible  = true
                            else hideBackpackLabel(lbl) end
                        else hideBackpackLabel(lbl) end
                    else hideBackpackLabel(lbl) end
                else hideBackpackLabel(lbl) end
            end
        else
            if lbl then
                if lbl.name then lbl.name:Remove() end
                if lbl.dist then lbl.dist:Remove() end
            end
            S.backpack._labels[model] = nil
            S.backpack._cache[model]  = nil
        end
    end
end

-------------------------------------------------------------- ore esp -------
local function IdentifyOre(model)
    if model.Name ~= "Model" then return nil end
    if S.backpack._oreCache[model] then
        return S.backpack._oreCache[model].name, S.backpack._oreCache[model].config
    end
    local children = model:GetChildren()
    local result, resultConfig = nil, nil
    local maxChecks = math.min(#children, 5)
    for configName, config in pairs(S.backpack._OreConfigs) do
        local p1Match = false
        local p2Match = (configName == "Cobblestone")
        for i = 1, maxChecks do
            local child = children[i]
            if child and (child:IsA("MeshPart") or child:IsA("Part")) then
                local idMatch = true
                if child:IsA("MeshPart") then idMatch = child.MeshId == config.TextureID end
                if idMatch then
                    if not p1Match and child.Color == config.Part1Color then p1Match = true
                    elseif config.Part2Color and not p2Match and child.Color == config.Part2Color then p2Match = true end
                end
            end
            if p1Match and p2Match then result = configName; resultConfig = config; break end
        end
        if p1Match and p2Match then break end
    end
    if result then S.backpack._oreCache[model] = {name=result, config=resultConfig} end
    return result, resultConfig
end

local function createOreLabel(oreModel, oreName, config)
    if S.backpack._oreLabels[oreModel] then S.backpack._oreLabels[oreModel]:Remove() end
    local lbl = Drawing.new("Text")
    lbl.Text = oreName; lbl.Color = config.Color; lbl.Size = 12
    lbl.Center = true; lbl.Outline = false; lbl.Font = 3; lbl.Visible = false
    S.backpack._oreLabels[oreModel] = lbl
    return lbl
end

local function getOreCenter(model)
    local totalPos = Vector3.new(0,0,0); local count = 0
    for _, child in pairs(model:GetChildren()) do
        if child:IsA("BasePart") then totalPos = totalPos + child.Position; count = count+1 end
    end
    if count > 0 then return totalPos / count end
    local root = model:FindFirstChild("Part") or model:FindFirstChildWhichIsA("BasePart")
    return root and root.Position or nil
end

function ESPLib.checkForOres()
    for _, model in pairs(workspace:GetChildren()) do
        if model:IsA("Model") and not S.backpack._oreLabels[model] and not S.backpack._oreCache[model] then
            local oreName, config = IdentifyOre(model)
            if oreName then createOreLabel(model, oreName, config) end
        end
    end
end

local function updateOreESP()
    local ore = oreSettings()
    if not (ore.ore_enabled or ore.enabled) then return end
    if not Camera then return end
    local camPos = Camera.CFrame.Position
    for model, label in pairs(S.backpack._oreLabels) do
        if model and model.Parent then
            local oreName = IdentifyOre(model)
            if oreName then
                local show = (oreName == "Cobblestone" and ore.stone)
                    or (oreName == "Iron Ore" and ore.iron)
                    or (oreName == "Nitrate Ore" and ore.nitrate)
                if show then
                    local cp = getOreCenter(model)
                    if cp and (camPos - cp).Magnitude <= (ore.ore_maxDist or ore.maxDist or 500) then
                        local sp, on = Camera:WorldToViewportPoint(cp)
                        if on then
                            label.Position = Vector2.new(sp.X, sp.Y); label.Visible = true
                        else label.Visible = false end
                    else label.Visible = false end
                else label.Visible = false end
            else label.Visible = false end
        else
            if label then label:Remove() end
            S.backpack._oreLabels[model] = nil
            S.backpack._oreCache[model] = nil
        end
    end
end

------------------------------------------------------------------ frame -----
function ESPLib.Update()
    updatePlayerESP()
    updateBackpackESP()
    updateOreESP()
    ESPLib.updateCarESPVisibility()
    ESPLib.updateBoatESPVisibility()
end

function ESPLib.Clear()
    for model, obj in pairs(S.esp._objects) do
        destroyEspObject(model, obj)
    end
    for _, lbl in pairs(S.backpack._labels or {}) do hideBackpackLabel(lbl) end
    for _, lbl in pairs(S.backpack._oreLabels or {}) do
        if lbl then pcall(function() lbl:Remove() end) end
    end
    S.backpack._labels = {}
    S.backpack._oreLabels = {}
    for model, data in pairs(S.car._tracked) do
        if data.label then pcall(function() data.label:Remove() end) end
    end
    S.car._tracked = {}
    for model, data in pairs(S.boat._tracked) do
        if data.label then pcall(function() data.label:Remove() end) end
    end
    S.boat._tracked = {}
end

------------------------------------------------------------------ init -----
-- Init lives here, at the very bottom of the file, on purpose. Every helper it
-- touches is a file-scope local declared further up, and Lua binds locals
-- lexically: a reference that appears textually before the declaration is a
-- global, not an upvalue. Declaring Init last is what makes watchForNewCars,
-- IdentifyOre, IdentifyBackpack and friends resolve to the real locals.
function ESPLib.Init(context)
    context = context or {}
    ctx = context
    if context.LocalPlayer then LocalPlayer = context.LocalPlayer end
    if context.Camera then Camera = context.Camera end

    S.backpack._cache = setmetatable({}, {__mode = "v"})
    S.backpack._labels = {}
    S.backpack._oreCache = setmetatable({}, {__mode = "v"})
    S.backpack._oreLabels = {}
    S.backpack._OreConfigs = {
        ["Nitrate Ore"] = { Name="NITRATE", Color=Color3.fromRGB(255,255,255), Part1Color=Color3.fromRGB(248,248,248), Part2Color=Color3.fromRGB(72,72,72), TextureID="rbxassetid://12939036056" },
        ["Iron Ore"]    = { Name="IRON",    Color=Color3.fromRGB(255,255,0),   Part1Color=Color3.fromRGB(199,172,120), Part2Color=Color3.fromRGB(72,72,72), TextureID="rbxassetid://12939036056" },
        ["Cobblestone"] = { Name="STONE",   Color=Color3.fromRGB(128,128,128), Part1Color=Color3.fromRGB(72,72,72),   TextureID="rbxassetid://12939036056" },
    }

    task.spawn(function()
        ESPLib.ScanCars()
        ESPLib.ScanBoats()
    end)
    watchForNewCars()
    watchForNewBoats()

    ESPLib.checkForOres()
    workspace.ChildAdded:Connect(function(obj)
        task.wait(1.0)
        if obj:IsA("Model") and obj.Parent and not S.backpack._oreLabels[obj] then
            local oreName, config = IdentifyOre(obj)
            if oreName then createOreLabel(obj, oreName, config) end
        end
    end)
    workspace.ChildRemoved:Connect(function(obj)
        if S.backpack._oreLabels[obj] then
            S.backpack._oreLabels[obj]:Remove()
            S.backpack._oreLabels[obj] = nil
            S.backpack._oreCache[obj] = nil
        end
    end)
    workspace.ChildAdded:Connect(function(obj)
        task.wait(0.5)
        if obj and obj.Parent and obj:IsA("Model") and not S.backpack._labels[obj] then
            if IdentifyBackpack(obj) then createBackpackLabel(obj) end
        end
    end)
    workspace.ChildRemoved:Connect(function(obj)
        if S.backpack._labels[obj] then
            if S.backpack._labels[obj].name then S.backpack._labels[obj].name:Remove() end
            if S.backpack._labels[obj].dist then S.backpack._labels[obj].dist:Remove() end
            S.backpack._labels[obj] = nil
            S.backpack._cache[obj] = nil
        end
    end)
end

return ESPLib
