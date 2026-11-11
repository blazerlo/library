--// library.lua — Outlaw-style UI library (Roblox)
--// Дизайн портирован с outlaw.lua: острые углы, двойные рамки (Border + Outline),
--// градиентный блик, accent-линии, пиксельный шрифт SmallestPixel.
--// Элементы: Toggle / Slider / ColorPicker / Button / Label / Dropdown / TextBox / KeyPicker.
--// Страницы в 2 колонки, внутри колонок — секции-«окна» (SubTab:AddSection),
--// в которых лежат элементы. Над табами — статус-бокс (Window:SetStatus / Window:SetConfig).
--// Виджет: Library:Watermark — draggable-плашка с шиммером и fps/датой.
--// Library:KeybindList — draggable-плашка со списком биндов (см. пример внизу).
--// Section:AddESPreview — ESP-preview: манекен + box/name/health/distance/skeleton,
--// привязывается к флагам (Box = "esp_box" и т.д.) и обновляется в реальном времени.
--// Library:CreateWidget — плавающее draggable-окно, внутри те же элементы
--// (AddToggle/AddSlider/AddColorPicker/AddButton/AddLabel/AddDropdown/AddTextBox/AddKeyPicker).
--// Library:Notify — всплывающие уведомления в правом нижнем углу (стиль outlaw).
--// Кастомный курсор (как в outlaw) включается автоматически при открытом меню.
--// Подключение: local Library = loadstring(readfile("library.lua"))()
--// Рядом в workspace должен лежать smallest-pixel7.ttf (если нет — fallback на Gotham).

local Library = {}
Library.Flags = {}
Library.SetFlags = {}          --// flag -> setter(функция), которым пользуется SaveManager
Library.ActivePicker = nil
Library.ActiveSettings = nil
Library.UIVisible = true
Library.WindowOpenState = false
Library._LoadingConfig = false
Library._visibilityCbs = {}
Library._keybinds = {}
Library.Fonts = { Cache = {} }

Library.Theme = {
    Background   = Color3.fromRGB(16, 17, 20),
    Section      = Color3.fromRGB(20, 21, 25),
    Element      = Color3.fromRGB(28, 29, 35),
    ElementHover = Color3.fromRGB(36, 38, 45),
    Outline      = Color3.fromRGB(36, 38, 45),
    Border       = Color3.fromRGB(7, 8, 10),
    Border2      = Color3.fromRGB(5, 10, 14),
    LightBorder  = Color3.fromRGB(12, 8, 12),
    Accent       = Color3.fromRGB(152, 188, 255),
    AccentDark   = Color3.fromRGB(110, 145, 210),
    Risky        = Color3.fromRGB(255, 50, 50),
    Safe         = Color3.fromRGB(80, 200, 120),
    Text         = Color3.fromRGB(180, 180, 180),
    TextDark     = Color3.fromRGB(100, 100, 100),
    ToggleActive = Color3.fromRGB(152, 188, 255),
    SliderActive = Color3.fromRGB(152, 188, 255),

    --// алиасы под старое API
    Topbar       = Color3.fromRGB(20, 21, 25),
    Sidebar      = Color3.fromRGB(20, 21, 25),
}

local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")
local CoreGui          = game:GetService("CoreGui")
local HttpService      = game:GetService("HttpService")
local GuiService       = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer

local ScreenGui = nil
local WindowOffset = 0

--// при IgnoreGuiInset=true AbsolutePosition НЕ включает инсет топбара, а
--// GetMouseLocation включает — конвертируем через GuiInset (как в outlaw)
local GuiInset = 0
pcall(function()
    GuiInset = GuiService:GetGuiInset().Y
end)
--// ---------------- pixel font ----------------

local function LoadPixelFont()
    if not (writefile and getcustomasset and isfile) then
        return nil
    end
    local ok, face = pcall(function()
        if not isfile("smallest-pixel7.ttf") then
            return nil
        end
        local ttfAsset = getcustomasset("smallest-pixel7.ttf")
        local fontData = {
            name = "SmallestPixel",
            faces = {
                { name = "Regular", weight = 400, style = "normal", assetId = ttfAsset },
            },
        }
        writefile("smallest-pixel7.font", HttpService:JSONEncode(fontData))
        return Font.new(getcustomasset("smallest-pixel7.font"))
    end)
    if ok then
        return face
    end
    return nil
end

Library.Font = LoadPixelFont()
Library.FontSize = Library.Font and 9 or 12
Library.Fonts.Cache.SmallestPixel = Library.Font
Library.Fonts.Cache.Minecraftia = Library.Font

--// применяет шрифт к текстовому элементу; bold учитывается только в fallback
local function ApplyFont(inst, sizeOffset, bold)
    if Library.Font then
        inst.FontFace = Library.Font
        inst.TextSize = Library.FontSize + (sizeOffset or 0)
    else
        inst.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
        inst.TextSize = 12 + (sizeOffset or 0)
    end
end

--// ---------------- helpers ----------------

local function New(class, props, children)
    local inst = Instance.new(class)
    local parent = nil
    for k, v in pairs(props or {}) do
        if k == "Parent" then
            parent = v
        else
            inst[k] = v
        end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    if parent then
        inst.Parent = parent
    end
    return inst
end

--// текстовый элемент сразу со шрифтом библиотеки
local function Txt(class, props, sizeOffset, bold)
    local inst = New(class, props)
    ApplyFont(inst, sizeOffset, bold)
    return inst
end

local function Tween(obj, props, t)
    local tw = TweenService:Create(obj, TweenInfo.new(t or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function Clamp(n, a, b)
    if n < a then return a end
    if n > b then return b end
    return n
end


--// ===== [patch2] shared helpers (dropdown/keypicker/notify) =====

--// accent-линер сверху поп-апа
local function AccentLiner(parent, z)
    return New("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Library.Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = z or 61,
        Parent = parent,
    })
end

--// проверка попадания курсора в прямоугольник GUI
local function InputInRect(input, gui)
    if not gui then return false end
    local p = input.Position
    local gp = gui.AbsolutePosition
    local gs = gui.AbsoluteSize
    return p.X >= gp.X and p.X <= gp.X + gs.X and p.Y >= gp.Y and p.Y <= gp.Y + gs.Y
end

--// безопасная позиция поп-апа под анкором с клампом в вьюпорт
local function ResolvePopupPos(anchor, w, h)
    local p = anchor.AbsolutePosition
    local s = anchor.AbsoluteSize
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
    local x = Clamp(p.X, 0, math.max(vp.X - w, 0))
    local y = Clamp(p.Y + s.Y + 10 + GuiInset, 0, math.max(vp.Y - h, 0))
    return UDim2.fromOffset(x, y)
end

--// KeyCode <-> строка
local function KeyCodeToString(kc)
    if not kc then return "None" end
    if type(kc) == "string" then return kc end
    local ok, name = pcall(function() return kc.Name end)
    return ok and name or "None"
end

local function StringToKeyCode(s)
    s = tostring(s or ""):upper()
    if s == "" or s == "NONE" then return nil end
    local ok, kc = pcall(function() return Enum.KeyCode[s] end)
    return ok and kc or nil
end

local function IsModifierKey(kc)
    return kc == Enum.KeyCode.LeftShift or kc == Enum.KeyCode.RightShift
        or kc == Enum.KeyCode.LeftControl or kc == Enum.KeyCode.RightControl
        or kc == Enum.KeyCode.LeftAlt or kc == Enum.KeyCode.RightAlt
end

--// ===== [/patch2] shared helpers =====

local function Round(n, d)
    local m = 10 ^ (d or 0)
    return math.floor(n * m + 0.5) / m
end

local function FormatNumber(n, d)
    if d and d > 0 then
        return string.format("%." .. tostring(d) .. "f", n)
    end
    return tostring(math.floor(n + 0.5))
end

local function ColorToHex(c)
    return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function HexToColor(hex)
    hex = tostring(hex):gsub("#", ""):gsub("%s", "")
    if #hex == 3 then
        hex = hex:gsub("(.)", "%1%1")
    end
    if #hex ~= 6 then return nil end
    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)
    if not (r and g and b) then return nil end
    return Color3.fromRGB(r, g, b)
end

local function RichEscape(s)
    return tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

local function MousePos()
    return UserInputService:GetMouseLocation()
end

--// реальная видимость: Visible у всех предков + Enabled у ScreenGui
local function IsActuallyVisible(inst)
    while inst do
        if inst:IsA("GuiObject") then
            if not inst.Visible then return false end
        elseif inst:IsA("ScreenGui") then
            if not inst.Enabled then return false end
        end
        inst = inst.Parent
    end
    return true
end

--// outlaw-стиль: тонкая рамка с miter-углами; offset 1 = внешняя тёмная рамка
local function Stroke(parent, key, offset)
    return New("UIStroke", {
        Color = Library.Theme[key] or Library.Theme.Border,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        LineJoinMode = Enum.LineJoinMode.Miter,
        BorderOffset = UDim.new(0, offset or 0),
        Parent = parent,
    })
end

--// градиентный блик white -> gray (фирменная заливка outlaw)
local function Sheen(parent)
    return New("UIGradient", {
        Rotation = -90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(172, 172, 172)),
        }),
        Parent = parent,
    })
end

local function GetGuiParent()
    local ok, gui = pcall(function()
        if gethui then
            return gethui()
        end
        return nil
    end)
    if ok and gui then
        return gui
    end
    local ok2 = pcall(function() return CoreGui.Name end)
    if ok2 then
        return CoreGui
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function EnsureGui()
    if ScreenGui and ScreenGui.Parent then
        return ScreenGui
    end
    ScreenGui = New("ScreenGui", {
        Name = "FortunaUI",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 1000,
        Parent = GetGuiParent(),
    })
    pcall(function()
        if syn and syn.protect_gui then
            syn.protect_gui(ScreenGui)
        elseif protectgui then
            protectgui(ScreenGui)
        end
    end)
    return ScreenGui
end

local function MakeDraggable(handle, target)
    local dragging = false
    local dragStart = Vector3.zero
    local startPos = UDim2.new()
    local dragDelta = Vector2.new(0,0)
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
            dragDelta = Vector2.new(0,0)
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    -- fallback: global delta when locked (handle.InputChanged won't fire when MouseBehavior==LockCenter)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if not Library.UIVisible then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local isLocked = (UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCurrentPosition)
        if not isLocked then return end
        -- input.Delta is available even when locked
        dragDelta = dragDelta + Vector2.new(input.Delta.X, input.Delta.Y)
        target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + dragDelta.X, startPos.Y.Scale, startPos.Y.Offset + dragDelta.Y)
    end)
    handle.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local isLocked = (UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCurrentPosition)
            if isLocked then
                -- handled by global delta above, ignore absolute Position
                return
            end
            local d = input.Position - dragStart
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            -- also reset dragDelta to keep sync if we unlock mid-drag
            dragDelta = Vector2.new(d.X, d.Y)
        end
    end)
end

local function DragArea(frame, onUpdate)
    local holding = false
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            holding = true
            onUpdate()
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            holding = false
        end
    end)
    RunService.RenderStepped:Connect(function()
        --// реальная видимость, а не Library.UIVisible: плавающие виджеты работают и при скрытом меню
        if holding and IsActuallyVisible(frame) then
            onUpdate()
        end
    end)
end

--// ---------------- class tables ----------------

local WindowMt = {}
WindowMt.__index = WindowMt
local TabMt = {}
TabMt.__index = TabMt
local SubTabMt = {}
SubTabMt.__index = SubTabMt

--// колонка для очередного элемента: нечётные влево, чётные вправо
function SubTabMt:_nextColumn()
    return (self._order % 2 == 1) and self.ColL or self.ColR
end

--// секция («окно в окне») наследует все Add*-методы SubTab, но кладёт элементы в свой Content
local SectionMt = setmetatable({}, { __index = SubTabMt })
SectionMt.__index = SectionMt

function SectionMt:_nextColumn()
    return self.Content
end

--// ---------------- sections ----------------

function SubTabMt:AddSection(name, cfg)
    cfg = cfg or {}
    local Theme = Library.Theme

    self._order = self._order + 1

    local side = cfg.Side or cfg.Column
    local parentCol
    if side == 2 then
        parentCol = self.ColR
    elseif side == 1 then
        parentCol = self.ColL
    else
        parentCol = self:_nextColumn()
    end

    local Outline = New("Frame", {
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundColor3 = Theme.Outline,
        AutomaticSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0,
        LayoutOrder = self._order,
        Parent = parentCol,
    })

    local Inner = New("Frame", {
        Size = UDim2.new(1, -2, 1, -2),
        Position = UDim2.fromOffset(1, 1),
        BackgroundColor3 = Theme.Section,
        AutomaticSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0,
        Parent = Outline,
    })

    local Title = Txt("TextLabel", {
        Size = UDim2.new(0, 0, 0, 12),
        Position = UDim2.fromOffset(8, 0),
        BackgroundColor3 = Theme.Section,
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.X,
        Text = tostring(name or "Section"),
        TextColor3 = Theme.Text,
        Parent = Outline,
    }, 0, false)
    New("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = Title })

    local Content = New("Frame", {
        Size = UDim2.new(1, -16, 0, 0),
        Position = UDim2.fromOffset(8, 14),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = Inner,
    })
    New("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = Content })
    New("UIPadding", { PaddingBottom = UDim.new(0, 8), Parent = Content })

    local Section = setmetatable({
        Type = "Section",
        Name = name,
        SubTab = self,
        Content = Content,
        _order = 0,
    }, SectionMt)

    function Section:SetTitle(t)
        Title.Text = tostring(t)
    end

    return Section
end

--// ---------------- elements ----------------

function SubTabMt:AddToggle(id, cfg)
    cfg = cfg or {}
    local Theme = Library.Theme
    local text = cfg.Text or id or "Toggle"
    local callback = cfg.Callback or function() end

    local Toggle = { Type = "Toggle", Value = false, _changed = {} }

    self._order = self._order + 1

    local Row = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = self._order,
        Parent = self:_nextColumn(),
    })
    Toggle.Instance = Row
    Toggle.Row = Row

    local Box = New("Frame", {
        Size = UDim2.fromOffset(10, 10),
        Position = UDim2.new(0, 2, 0.5, -5),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        Parent = Row,
    })
    Stroke(Box, "Border")

    local Inline = New("Frame", {
        Size = UDim2.fromScale(0, 0),
        BackgroundColor3 = Theme.ToggleActive or Theme.Accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = Box,
    })

    local TxtLabel = Txt("TextLabel", {
        Size = UDim2.new(1, -22, 1, 0),
        Position = UDim2.fromOffset(20, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.TextDark,
        Parent = Row,
    }, 0, false)

    function Toggle:Set(v, silent)
        self.Value = v and true or false
        if self.Value then
            Tween(Inline, { BackgroundTransparency = 0, Size = UDim2.fromScale(1, 1) }, 0.12)
            Tween(TxtLabel, { TextColor3 = Library.Theme.Text }, 0.12)
        else
            Tween(Inline, { BackgroundTransparency = 1, Size = UDim2.fromScale(0, 0) }, 0.12)
            Tween(TxtLabel, { TextColor3 = Library.Theme.TextDark }, 0.12)
        end
        if not silent then
            callback(self.Value)
            for _, fn in ipairs(self._changed) do
                pcall(fn, self.Value)
            end
        end
    end

    function Toggle:OnChanged(fn)
        if type(fn) == "function" then
            table.insert(self._changed, fn)
        end
        return fn
    end

    Row.MouseEnter:Connect(function()
        Tween(Box, { BackgroundColor3 = Theme.ElementHover }, 0.1)
    end)
    Row.MouseLeave:Connect(function()
        Tween(Box, { BackgroundColor3 = Theme.Element }, 0.1)
    end)
    Row.MouseButton1Click:Connect(function()
        Toggle:Set(not Toggle.Value)
    end)

    --// виджет на шестерёнке (как Toggle:Settings() в outlaw):
    --// справа от тогла появляется шестерёнка, клик открывает плавающее окно с элементами
    function Toggle:Settings()
        if self._settings then
            return self._settings
        end

        TxtLabel.Size = UDim2.new(1, -40, 1, 0)

        local Gear = New("ImageButton", {
            Size = UDim2.fromOffset(12, 12),
            Position = (function()
                local n = self._kpN or 0
                if n > 0 then
                    return UDim2.new(1, -(n * 37 + 16), 0.5, -6)
                else
                    return UDim2.new(1, -14, 0.5, -6)
                end
            end)(),
            BackgroundTransparency = 1,
            Image = "rbxassetid://124244905334583",
            ImageColor3 = Theme.Text,
            AutoButtonColor = false,
            BorderSizePixel = 0,
            Parent = Row,
        })

        local Holder = New("Frame", {
            Size = UDim2.fromOffset(254, 40),
            BackgroundColor3 = Theme.Background,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 60,
            Parent = EnsureGui(),
        })
        Stroke(Holder, "Outline")
        Stroke(Holder, "Border", 1)

        New("ImageLabel", {
            Size = UDim2.fromOffset(12, 12),
            Position = UDim2.fromOffset(10, 9),
            BackgroundTransparency = 1,
            Image = "rbxassetid://124244905334583",
            ImageColor3 = Theme.Text,
            BorderSizePixel = 0,
            ZIndex = 61,
            Parent = Holder,
        })
        Txt("TextLabel", {
            Size = UDim2.new(1, -36, 0, 12),
            Position = UDim2.fromOffset(28, 9),
            BackgroundTransparency = 1,
            Text = text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.Text,
            ZIndex = 61,
            Parent = Holder,
        }, 0, false)

        local Content = New("ScrollingFrame", {
            Size = UDim2.new(1, 0, 1, -30),
            Position = UDim2.fromOffset(0, 30),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = Theme.Outline,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ZIndex = 61,
            Parent = Holder,
        })
        New("UIPadding", {
            PaddingTop = UDim.new(0, 5),
            PaddingBottom = UDim.new(0, 5),
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 10),
            Parent = Content,
        })
        local Layout = New("UIListLayout", {
            Padding = UDim.new(0, 5),
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = Content,
        })

        local host = setmetatable({ _order = 0 }, SectionMt)
        host.Content = Content
        host.Instance = Holder
        host.IsOpen = false

        local function Fit()
            local h = Clamp(math.ceil(Layout.AbsoluteContentSize.Y) + 40, 40, 242)
            Holder.Size = UDim2.fromOffset(254, h)
        end
        Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(Fit)

        local function ResolvePos()
            local p = Gear.AbsolutePosition
            local s = Gear.AbsoluteSize
            local cam = workspace.CurrentCamera
            local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
            local x = Clamp(p.X, 0, math.max(vp.X - 254, 0))
            local y = Clamp(p.Y + s.Y + 10 + GuiInset, 0, math.max(vp.Y - Holder.AbsoluteSize.Y, 0))
            return UDim2.fromOffset(x, y)
        end

        local repositionConn = nil

        function host:SetOpen(b)
            b = b and true or false
            if b == self.IsOpen then return end
            self.IsOpen = b
            if b then
                if Library.ActivePicker then
                    Library.ActivePicker:Close()
                end
                if Library.ActiveSettings and Library.ActiveSettings ~= self then
                    Library.ActiveSettings:SetOpen(false)
                end
                Library.ActiveSettings = self
                Fit()
                Holder.Position = ResolvePos()
                Holder.Visible = true
                repositionConn = RunService.RenderStepped:Connect(function()
                    if not IsActuallyVisible(Gear) then
                        self:SetOpen(false)
                        return
                    end
                    Holder.Position = ResolvePos()
                end)
            else
                Holder.Visible = false
                local ap = Library.ActivePicker
                if ap and ap.Preview and ap.Preview:IsDescendantOf(Holder) then
                    ap:Close()
                end
                if Library.ActiveSettings == self then
                    Library.ActiveSettings = nil
                end
                if repositionConn then
                    repositionConn:Disconnect()
                    repositionConn = nil
                end
            end
        end

        Gear.MouseButton1Down:Connect(function()
            host:SetOpen(not host.IsOpen)
        end)

        UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
            if not host.IsOpen then return end
            local p = input.Position
            local function over(gui)
                local gp = gui.AbsolutePosition
                local gs = gui.AbsoluteSize
                return p.X >= gp.X and p.X <= gp.X + gs.X and p.Y >= gp.Y and p.Y <= gp.Y + gs.Y
            end
            if over(Holder) or over(Gear) then return end
            local ap = Library.ActivePicker
            if ap and ap.Popup and over(ap.Popup) then return end
            host:SetOpen(false)
        end)

        self._settings = host
        return host
    end

    -- // [INLINE KEYPICKER] бинд напротив тогла, попадает в KeybindList
    do
        local _host = self
        function Toggle:AddKeyPicker(pid, pcfg)
            pcfg = pcfg or {}
            -- создаём пикер через секцию (host), чтобы переиспользовать логику KeyList
            local picker = _host:AddKeyPicker(pid, pcfg)
            local _uiOk, _uiErr = pcall(function()
                local btn = picker.Button
                local ownRow = picker.Instance
                local togRow = self.Row or self.Instance
                if not (btn and ownRow and togRow) then return end
                local n = self._kpN or 0
                local gear = self._settings and 16 or 0
                local cpN = self._cpN or 0
                -- переносим кнопку бинда на строку тогла
                btn.Parent = togRow
                -- позиция: правее всех, левее шестерёнки и колор-пикеров
                btn.Position = UDim2.new(1, -(33 + 4 + n * 37), 0.5, -7)
                -- прячем оригинальную строку пикера
                ownRow.Visible = false
                -- убираем её из layout (не занимать место)
                pcall(function() ownRow.Size = UDim2.fromOffset(0,0) end)
                pcall(function() ownRow.LayoutOrder = 9999 end)
                -- уменьшаем текст тогла чтобы не наезжал
                local lbl
                for _, ch in ipairs(togRow:GetChildren()) do
                    if ch:IsA("TextLabel") then lbl = ch break end
                end
                if lbl then
                    lbl.Size = UDim2.new(1, -(22 + gear + cpN * 26 + (n+1)*37 + 8), 1, 0)
                end
                self._kpN = n + 1
                -- reposition gear left of binds
                pcall(function()
                    local gearBtn = nil
                    for _, ch in ipairs(togRow:GetChildren()) do
                        if ch:IsA("ImageButton") and ch.Image:find("124244905334583") then
                            gearBtn = ch
                            break
                        end
                    end
                    if gearBtn then
                        local nBinds = self._kpN or 0
                        if nBinds > 0 then
                            gearBtn.Position = UDim2.new(1, -(nBinds * 37 + 16), 0.5, -6)
                        else
                            gearBtn.Position = UDim2.new(1, -14, 0.5, -6)
                        end
                    end
                    -- reposition existing color pickers left of gear
                    if self._cpButtons then
                        local nBinds2 = self._kpN or 0
                        local gearLeft = -14
                        if nBinds2 > 0 then
                            gearLeft = -(nBinds2 * 37 + 16)
                        elseif gearBtn then
                            gearLeft = -14
                        else
                            gearLeft = 0
                        end
                        for j, cpBtn in ipairs(self._cpButtons) do
                            local offset
                            if gearBtn or nBinds2>0 then
                                -- left of gear
                                local base = gearLeft
                                if nBinds2==0 and not gearBtn then
                                    base = 0
                                end
                                offset = base - 4 - 22 - (j-1)*26
                            else
                                offset = -(24 + (j-1)*26)
                            end
                            cpBtn.Position = UDim2.new(1, offset, 0.5, -6)
                        end
                    end
                end)
            end)
            if not _uiOk then warn("[Toggle:AddKeyPicker UI] "..tostring(_uiErr)) end
            -- SyncToggleState: бинд переключает тогл и показывается в KeybindList (вне UI-pcall чтобы не потерять Bind)
            if pcfg.SyncToggleState then
                -- найдём флаг тогла
                local tFlag
                for kk, vv in pairs(Library.Flags) do if vv == self then tFlag = kk break end end
                if tFlag and picker.BindToggle then
                    local okBT, errBT = pcall(function() picker:BindToggle(tFlag) end)
                    if not okBT then warn("[BindToggle] failed: "..tostring(errBT)) end
                end
                -- флип тогла по нажатию клавиши (mode читается live, поддерживает Always On)
                do
                    local okB, errB = pcall(function()
                        picker:Bind(function(down)
                            if not picker.Value then return end
                            local curMode = tostring(picker.Mode or pcfg.Mode or pcfg.mode or "toggle"):lower()
                            if curMode:find("hold") then
                                pcall(function() self:Set(down and true or false) end)
                            elseif curMode:find("always") then
                                pcall(function() if down then self:Set(true) end end)
                            else -- toggle по умолчанию
                                if down then pcall(function() self:Set(not self.Value) end) end
                            end
                        end)
                    end)
                    if not okB then warn("[ToggleBind] failed: "..tostring(errB)) end
                end
                -- фиксация отображения в KeybindList даже когда тогл выключен (если mode all)
                pcall(function()
                    local toggle = self
                    local kp = picker
                    if Library.KeyList and Library.KeyList.Rows then
                        for _, row in ipairs(Library.KeyList.Rows) do
                            if row.Name == (pcfg.Text or pid) and row.Key == KeyCodeToString(kp.Value) then
                                local function upd()
                                    local isOn = toggle.Value == true
                                    if Library.KeyList.Mode == "all" then
                                        row:Set(KeyCodeToString(kp.Value), pcfg.Text or pid, kp.Mode)
                                        row:SetVis(true)
                                        row:SetStatus(isOn)
                                    else
                                        if isOn then
                                            row:Set(KeyCodeToString(kp.Value), pcfg.Text or pid, kp.Mode)
                                            row:SetVis(true)
                                            row:SetStatus(true)
                                        else
                                            row:SetVis(false)
                                        end
                                    end
                                end
                                toggle:OnChanged(upd)
                                local oldSet = kp.Set
                                function kp:Set(kc, silent)
                                    oldSet(kp, kc, silent)
                                    upd()
                                end
                                upd()
                                break
                            end
                        end
                    end
                end)
            end
            return picker
        end
    end

    Toggle:Set(cfg.Default == true)

    if id then
        Library.Flags[id] = Toggle
    end
    return Toggle
end

function SubTabMt:AddSlider(id, cfg)
    cfg = cfg or {}
    local Theme = Library.Theme
    local text = cfg.Text or id or "Slider"
    local min = cfg.Min or 0
    local max = cfg.Max or 100
    if max == min then max = min + 1 end
    local decimals = cfg.Decimals or cfg.Rounding or 0
    local suffix = cfg.Suffix or ""
    local callback = cfg.Callback or function() end

    local Slider = { Type = "Slider", Value = min, Min = min, Max = max, _changed = {} }

    self._order = self._order + 1

    local Row = New("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundTransparency = 1,
        LayoutOrder = self._order,
        Parent = self:_nextColumn(),
    })

    Txt("TextLabel", {
        Size = UDim2.new(1, -80, 0, 14),
        Position = UDim2.fromOffset(2, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Text,
        Parent = Row,
    }, 0, false)

    local ValueLabel = Txt("TextLabel", {
        Size = UDim2.new(0, 78, 0, 14),
        Position = UDim2.new(1, -78, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextXAlignment = Enum.TextXAlignment.Right,
        TextColor3 = Theme.Text,
        Parent = Row,
    }, 0, true)
    New("UIStroke", {
        Color = Theme.Border,
        Thickness = 1,
        LineJoinMode = Enum.LineJoinMode.Miter,
        Parent = ValueLabel,
    })

    local Bar = New("TextButton", {
        Size = UDim2.new(1, -4, 0, 6),
        Position = UDim2.new(0, 2, 1, -8),
        BackgroundColor3 = Theme.Element,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        Parent = Row,
    })
    Stroke(Bar, "Border")

    local Fill = New("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Theme.SliderActive or Theme.Accent,
        BorderSizePixel = 0,
        Parent = Bar,
    })
    Sheen(Fill)

    function Slider:Set(v, silent)
        v = Clamp(tonumber(v) or min, min, max)
        v = Round(v, decimals)
        self.Value = v
        local a = (v - min) / (max - min)
        Tween(Fill, { Size = UDim2.fromScale(a, 1) }, 0.1)
        local display = FormatNumber(v, decimals) .. suffix
        if max == 101 and min == 0 and v >= 101 then
            display = "Force Lethal"
        end
        ValueLabel.Text = display
        if not silent then
            callback(v)
            for _, fn in ipairs(self._changed) do
                pcall(fn, v)
            end
        end
    end

    function Slider:OnChanged(fn)
        if type(fn) == "function" then
            table.insert(self._changed, fn)
        end
        return fn
    end

    Bar.MouseEnter:Connect(function()
        Tween(Bar, { BackgroundColor3 = Theme.ElementHover }, 0.1)
    end)
    Bar.MouseLeave:Connect(function()
        Tween(Bar, { BackgroundColor3 = Theme.Element }, 0.1)
    end)

    DragArea(Bar, function()
        local m = MousePos()
        local a = Clamp((m.X - Bar.AbsolutePosition.X) / Bar.AbsoluteSize.X, 0, 1)
        Slider:Set(min + (max - min) * a)
    end)

    Slider:Set(cfg.Default or min)

    if id then
        Library.Flags[id] = Slider
    end
    return Slider
end

function SubTabMt:AddColorPicker(id, cfg)
    cfg = cfg or {}
    local Theme = Library.Theme
    local text = cfg.Text or id or "Color"
    local callback = cfg.Callback or function() end
    local default = cfg.Default or Color3.fromRGB(255, 255, 255)
    local useTrans = (cfg.Transparency ~= nil)

    local Picker = { Type = "ColorPicker", Value = default, Transparency = cfg.Transparency or 0, IsOpen = false }

    local hue, sat, val = Color3.toHSV(default)
    local trans = Clamp(cfg.Transparency or 0, 0, 1)

    self._order = self._order + 1

    local Row = New("Frame", {
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        LayoutOrder = self._order,
        Parent = self:_nextColumn(),
    })

    Txt("TextLabel", {
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.fromOffset(2, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Text,
        Parent = Row,
    }, 0, false)

    --// превью-кнопка как в outlaw (22x12, Border + блик)
    local Preview = New("TextButton", {
        Size = UDim2.fromOffset(22, 12),
        Position = UDim2.new(1, -24, 0.5, -6),
        BackgroundColor3 = default,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        Parent = Row,
    })
    Stroke(Preview, "Border")
    Sheen(Preview)

    --// окно пикера — по референсу (191px): заголовок, SV-палитра + hue,
    --// alpha-полоса и hex-поле. Цвета берём из темы библиотеки.
    local POPUP_W = 191
    local PAL_X, PAL_Y, PAL_W, PAL_H = 8, 29, 151, 135
    local HUE_X, HUE_Y, HUE_W, HUE_H = 167, 29, 15, 135
    local HEX_Y = useTrans and 194 or 170
    local POPUP_H = useTrans and 225 or 201

    local Popup = New("TextButton", {
        Size = UDim2.fromOffset(POPUP_W, POPUP_H),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Visible = false,
        ZIndex = 60,
        Parent = EnsureGui(),
    })
    Stroke(Popup, "Outline")
    Stroke(Popup, "Border", 1)

    New("Frame", { --// AccentLiner
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 61,
        Parent = Popup,
    })

    --// заголовок секции
    Txt("TextLabel", {
        Size = UDim2.new(1, -16, 0, 14),
        Position = UDim2.fromOffset(8, 5),
        BackgroundTransparency = 1,
        Text = text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextColor3 = Theme.Text,
        ZIndex = 61,
        Parent = Popup,
    }, 0, false)

    --// палитра sat/value: слева цвет -> справа белый, сверху светло -> снизу тёмно
    local Palette = New("TextButton", {
        Size = UDim2.fromOffset(PAL_W, PAL_H),
        Position = UDim2.fromOffset(PAL_X, PAL_Y),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        ZIndex = 61,
        Parent = Popup,
    })
    Stroke(Palette, "Border")
    do
        local satF = New("Frame", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
            ZIndex = 62,
            Parent = Palette,
        })
        New("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = satF,
        })
        local valF = New("Frame", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BorderSizePixel = 0,
            ZIndex = 63,
            Parent = Palette,
        })
        New("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(1, 0),
            }),
            Parent = valF,
        })
    end
    --// ручка палитры — полый квадрат со светлой обводкой
    local PaletteDragger = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(6, 6),
        BackgroundTransparency = 1,
        ZIndex = 64,
        Parent = Palette,
    })
    New("UIStroke", {
        Color = Theme.Text,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        LineJoinMode = Enum.LineJoinMode.Miter,
        Parent = PaletteDragger,
    })

    --// hue — вертикальная радуга справа
    local Hue = New("TextButton", {
        Size = UDim2.fromOffset(HUE_W, HUE_H),
        Position = UDim2.fromOffset(HUE_X, HUE_Y),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        ZIndex = 61,
        Parent = Popup,
    })
    Stroke(Hue, "Border")
    New("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
            ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
        }),
        Parent = Hue,
    })
    --// индикатор hue — тонкая светлая полоса
    local HueDragger = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(1, 0, 0, 3),
        BackgroundColor3 = Theme.Text,
        BorderSizePixel = 0,
        ZIndex = 64,
        Parent = Hue,
    })
    Stroke(HueDragger, "Border")

    --// alpha — горизонтальная полоса (только с cfg.Transparency)
    local Alpha, AlphaColor, AlphaDragger = nil, nil, nil
    if useTrans then
        Alpha = New("TextButton", {
            Size = UDim2.fromOffset(174, 12),
            Position = UDim2.fromOffset(8, 174),
            BackgroundColor3 = Theme.Background,
            Text = "",
            AutoButtonColor = false,
            BorderSizePixel = 0,
            ZIndex = 61,
            Parent = Popup,
        })
        Stroke(Alpha, "Border")
        AlphaColor = New("Frame", {
            Size = UDim2.new(1, 0, 1, 0),
            BorderSizePixel = 0,
            BackgroundColor3 = default,
            ZIndex = 62,
            Parent = Alpha,
        })
        New("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(1, 0),
            }),
            Parent = AlphaColor,
        })
        AlphaDragger = New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0),
            Size = UDim2.new(0, 3, 1, 0),
            BackgroundColor3 = Theme.Text,
            BorderSizePixel = 0,
            ZIndex = 64,
            Parent = Alpha,
        })
        Stroke(AlphaDragger, "Border")
    end

    --// hex-поле: редактируемое, парсится по FocusLost
    local HexField = New("Frame", {
        Size = UDim2.fromOffset(175, 19),
        Position = UDim2.fromOffset(8, HEX_Y),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        ZIndex = 61,
        Parent = Popup,
    })
    Stroke(HexField, "Border")

    local HexBox = Txt("TextBox", {
        Size = UDim2.new(1, -12, 1, 0),
        Position = UDim2.fromOffset(6, 0),
        BackgroundTransparency = 1,
        Text = ColorToHex(default),
        PlaceholderText = "#RRGGBB",
        PlaceholderColor3 = Theme.TextDark,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Text,
        ZIndex = 62,
        Parent = HexField,
    }, 0, false)

    --// логика — порт с outlaw: драги через Input.Position
    --// (при IgnoreGuiInset=true совпадает с AbsolutePosition — без рассинхрона)
    local function PlaceDraggers()
        PaletteDragger.Position = UDim2.fromScale(sat, 1 - val)
        HueDragger.Position = UDim2.fromScale(0, hue)
        if AlphaDragger then
            AlphaDragger.Position = UDim2.fromScale(1 - trans, 0)
        end
    end

    local function Update(fire)
        local c = Color3.fromHSV(hue, sat, val)
        Picker.Value = c
        Picker.Transparency = trans
        Palette.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
        if AlphaColor then
            AlphaColor.BackgroundColor3 = c
        end
        Preview.BackgroundColor3 = c
        if not HexBox:IsFocused() then
            HexBox.Text = ColorToHex(c)
        end
        if fire then
            callback(c, trans)
        end
    end

    local SlidingPalette = false
    local SlidingHue = false
    local SlidingAlpha = false

    local function SlidePalette(input)
        if not input or not SlidingPalette then return end
        local p = Palette.AbsolutePosition
        local s = Palette.AbsoluteSize
        local sx = Clamp((input.Position.X - p.X) / s.X, 0, 1)
        local sy = Clamp((input.Position.Y - p.Y) / s.Y, 0, 1)
        sat = sx
        val = 1 - sy
        PaletteDragger.Position = UDim2.fromScale(sx, sy)
        Update(true)
    end

    local function SlideHue(input)
        if not input or not SlidingHue then return end
        local sy = Clamp((input.Position.Y - Hue.AbsolutePosition.Y) / Hue.AbsoluteSize.Y, 0, 1)
        hue = sy
        HueDragger.Position = UDim2.fromScale(0, sy)
        Update(true)
    end

    local function SlideAlpha(input)
        if not input or not SlidingAlpha then return end
        local sx = Clamp((input.Position.X - Alpha.AbsolutePosition.X) / Alpha.AbsoluteSize.X, 0, 1)
        trans = 1 - sx
        AlphaDragger.Position = UDim2.fromScale(sx, 0)
        Update(true)
    end

    Palette.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        SlidingPalette = true
        SlidePalette(input)
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                SlidingPalette = false
            end
        end)
    end)

    Hue.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        SlidingHue = true
        SlideHue(input)
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                SlidingHue = false
            end
        end)
    end)

    if Alpha then
        Alpha.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
            SlidingAlpha = true
            SlideAlpha(input)
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    SlidingAlpha = false
                end
            end)
        end)
    end

    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if SlidingPalette then SlidePalette(input) end
        if SlidingHue then SlideHue(input) end
        if SlidingAlpha then SlideAlpha(input) end
    end)

    --// позиция под превью-кнопкой (AbsolutePosition без инсета -> + GuiInset)
    local function ResolvePos(w, h)
        local p = Preview.AbsolutePosition
        local s = Preview.AbsoluteSize
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
        local x = Clamp(p.X, 0, math.max(vp.X - w, 0))
        local y = Clamp(p.Y + s.Y + 10 + GuiInset, 0, math.max(vp.Y - h, 0))
        return UDim2.fromOffset(x, y)
    end

    local repositionConn = nil

    function Picker:Open()
        if Library.ActivePicker and Library.ActivePicker ~= self then
            Library.ActivePicker:Close()
        end
        --// пикер внутри виджета-шестерёнки не закрывает своё окно
        if Library.ActiveSettings and not Preview:IsDescendantOf(Library.ActiveSettings.Instance) then
            Library.ActiveSettings:SetOpen(false)
        end
        Library.ActivePicker = self
        self.IsOpen = true
        Popup.Position = ResolvePos(POPUP_W, POPUP_H)
        Popup.Visible = true
        repositionConn = RunService.RenderStepped:Connect(function()
            Popup.Position = ResolvePos(POPUP_W, POPUP_H)
        end)
    end

    function Picker:Close()
        self.IsOpen = false
        Popup.Visible = false
        if Library.ActivePicker == self then
            Library.ActivePicker = nil
        end
        if repositionConn then
            repositionConn:Disconnect()
            repositionConn = nil
        end
    end

    Preview.MouseButton1Down:Connect(function()
        if Picker.IsOpen then
            Picker:Close()
        else
            Picker:Open()
        end
    end)

    --// ввод hex: по FocusLost/Enter; невалидный текст откатываем
    local function CommitHex()
        local c = HexToColor(HexBox.Text)
        if c then
            Picker:Set(c, Picker.Transparency)
        end
        HexBox.Text = ColorToHex(Picker.Value)
    end
    HexBox.FocusLost:Connect(CommitHex)

    local function InputInRect(input, gui)
        local p = input.Position
        local gp = gui.AbsolutePosition
        local gs = gui.AbsoluteSize
        return p.X >= gp.X and p.X <= gp.X + gs.X and p.Y >= gp.Y and p.Y <= gp.Y + gs.Y
    end

    UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if Picker.IsOpen and not InputInRect(input, Popup) and not InputInRect(input, Preview) then
            Picker:Close()
        end
    end)

    function Picker:Set(c, t, silent)
        if type(c) == "table" then
            c = Color3.fromRGB(c[1] or 255, c[2] or 255, c[3] or 255)
        elseif type(c) == "string" then
            c = HexToColor(c) or Color3.fromRGB(255, 255, 255)
        end
        local h, s, v = Color3.toHSV(c)
        if s > 0.001 then
            hue = h
        end
        sat = s
        val = v
        if t ~= nil then
            trans = Clamp(t, 0, 1)
        end
        PlaceDraggers()
        Update(not silent)
    end

    Picker:Set(default, cfg.Transparency)

    Picker.Popup = Popup
    Picker.Preview = Preview

    if id then
        Library.Flags[id] = Picker
    end
    return Picker
end

function SubTabMt:AddButton(cfg)
    cfg = cfg or {}
    local Theme = Library.Theme
    local text = cfg.Text or "Button"
    local callback = cfg.Callback or function() end

    self._order = self._order + 1

    local Btn = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundColor3 = Theme.Element,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        LayoutOrder = self._order,
        Parent = self:_nextColumn(),
    })
    Stroke(Btn, "Border", 1)
    Stroke(Btn, "Outline")
    Sheen(Btn)

    local BtnTxt = Txt("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = Theme.Text,
        Parent = Btn,
    }, 0, true)

    Btn.MouseEnter:Connect(function()
        Tween(Btn, { BackgroundColor3 = Theme.ElementHover }, 0.1)
    end)
    Btn.MouseLeave:Connect(function()
        Tween(Btn, { BackgroundColor3 = Theme.Element }, 0.1)
    end)
    Btn.MouseButton1Click:Connect(function()
        Tween(Btn, { BackgroundColor3 = Theme.Accent }, 0.08)
        Tween(BtnTxt, { TextColor3 = Color3.fromRGB(16, 17, 20) }, 0.08)
        task.delay(0.12, function()
            Tween(Btn, { BackgroundColor3 = Theme.ElementHover }, 0.15)
            Tween(BtnTxt, { TextColor3 = Theme.Text }, 0.15)
        end)
        callback()
    end)

    local Button = { Type = "Button" }
    function Button:SetText(t)
        BtnTxt.Text = tostring(t)
    end
    return Button
end

function SubTabMt:AddLabel(text)
    local Theme = Library.Theme
    self._order = self._order + 1
    local Lbl = Txt("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        Text = tostring(text or ""),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.TextDark,
        LayoutOrder = self._order,
        Parent = self:_nextColumn(),
    }, 0, false)
    local Label = { Type = "Label" }
    function Label:Set(t)
        Lbl.Text = tostring(t)
    end
    return Label
end

--// ---------------- Dropdown ----------------

--// cfg = {
--//   Text = "Label",
--//   Items = { "a","b","c" } или { {Value=..., Text=...}, ... },
--//   Multi = false,                 -- true = мультивыбор
--//   Default = "a" / { "a","b" },   -- single: значение; multi: массив значений
--//   Max = 3,                       -- (multi) лимит выбранных, nil = без лимита
--//   Callback = function(value, isMulti) ... end,
--// }
function SubTabMt:AddDropdown(id, cfg)
    cfg = cfg or {}
    local Theme = Library.Theme
    local text = cfg.Text or id or "Dropdown"
    local multi = cfg.Multi == true
    local callback = cfg.Callback or function() end
    local maxSel = cfg.Max

    --// нормализация items -> { {Value=,Text=}, ... }
    local items = {}
    for _, it in ipairs(cfg.Items or {}) do
        if type(it) == "table" then
            local v = it.Value or it[1] or tostring(it)
            items[#items + 1] = { Value = v, Text = tostring(it.Text or it.Label or v) }
        else
            items[#items + 1] = { Value = it, Text = tostring(it) }
        end
    end

    local Dropdown = {
        Type = "Dropdown",
        Multi = multi,
        Items = items,
        Value = multi and {} or nil,
        IsOpen = false,
    }

    local function findItem(v)
        for _, it in ipairs(items) do
            if it.Value == v or it.Text == v then return it end
        end
        return nil
    end

    --// инициализация значения
    if multi then
        local d = cfg.Default
        if type(d) == "table" then
            for _, v in ipairs(d) do
                local it = findItem(v)
                if it then Dropdown.Value[it.Value] = true end
            end
        end
    else
        if cfg.Default ~= nil then
            local it = findItem(cfg.Default)
            Dropdown.Value = it and it.Value or (items[1] and items[1].Value or nil)
        elseif items[1] then
            Dropdown.Value = items[1].Value
        end
    end

    self._order = self._order + 1

    local Row = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = self._order,
        Parent = self:_nextColumn(),
    })
    Dropdown.Instance = Row

    local Box = New("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        Parent = Row,
    })
    Stroke(Box, "Border", 1)
    Stroke(Box, "Outline")

    local ValueLabel = Txt("TextLabel", {
        Size = UDim2.new(1, -26, 1, 0),
        Position = UDim2.fromOffset(6, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextColor3 = Theme.Text,
        Parent = Box,
    }, 0, false)

    --// стрелка (chevron) — тонкая наклонная полоска
    local Arrow = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(6, 1),
        Position = UDim2.new(1, -12, 0.5, 0),
        Rotation = 45,
        BackgroundColor3 = Theme.TextDark,
        BorderSizePixel = 0,
        Parent = Box,
    })
    local Arrow2 = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(6, 1),
        Position = UDim2.new(1, -8, 0.5, 0),
        Rotation = -45,
        BackgroundColor3 = Theme.TextDark,
        BorderSizePixel = 0,
        Parent = Box,
    })

    --// поп-ап со списком
    local POPUP_MAX_H = 160
    local Popup = New("TextButton", {
        Size = UDim2.fromOffset(180, 30),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Visible = false,
        ZIndex = 60,
        Parent = EnsureGui(),
    })
    Stroke(Popup, "Outline")
    Stroke(Popup, "Border", 1)
    New("Frame", { --// AccentLiner
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 61,
        Parent = Popup,
    })

    local List = New("ScrollingFrame", {
        Size = UDim2.new(1, -4, 1, -4),
        Position = UDim2.fromOffset(2, 2),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Outline,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ZIndex = 61,
        Parent = Popup,
    })
    local Layout = New("UIListLayout", {
        Padding = UDim.new(0, 1),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = List,
    })

    local optionRows = {}

    local function updateValueLabel()
        if multi then
            local names = {}
            for _, it in ipairs(items) do
                if Dropdown.Value[it.Value] then
                    names[#names + 1] = it.Text
                end
            end
            if #names == 0 then
                ValueLabel.Text = "None"
                ValueLabel.TextColor3 = Theme.TextDark
            else
                ValueLabel.Text = table.concat(names, ", ")
                ValueLabel.TextColor3 = Theme.Text
            end
        else
            local it = Dropdown.Value ~= nil and findItem(Dropdown.Value) or nil
            if it then
                ValueLabel.Text = it.Text
                ValueLabel.TextColor3 = Theme.Text
            else
                ValueLabel.Text = "None"
                ValueLabel.TextColor3 = Theme.TextDark
            end
        end
    end

    local function fire()
        if multi then
            --// возвращаем массив выбранных значений + map для удобства
            local arr = {}
            for _, it in ipairs(items) do
                if Dropdown.Value[it.Value] then
                    arr[#arr + 1] = it.Value
                end
            end
            callback(arr, true)
        else
            callback(Dropdown.Value, false)
        end
    end

    local function refreshRow(row, it)
        if multi then
            local on = Dropdown.Value[it.Value] == true
            row.Bg.BackgroundColor3 = on and Theme.ElementHover or Theme.Element
            row.Check.Visible = on
            row.Text.TextColor3 = on and Theme.Text or Theme.TextDark
        else
            local on = (Dropdown.Value == it.Value)
            row.Bg.BackgroundColor3 = on and Theme.ElementHover or Theme.Element
            row.Check.Visible = on
            row.Text.TextColor3 = on and Theme.Accent or Theme.TextDark
        end
    end

    local function refreshAll()
        for _, r in ipairs(optionRows) do
            refreshRow(r, r.Item)
        end
        updateValueLabel()
    end

    local function toggleItem(it)
        if multi then
            if Dropdown.Value[it.Value] then
                Dropdown.Value[it.Value] = nil
            else
                if maxSel then
                    local count = 0
                    for _ in pairs(Dropdown.Value) do count = count + 1 end
                    if count >= maxSel then
                        refreshAll()
                        return
                    end
                end
                Dropdown.Value[it.Value] = true
            end
            refreshAll()
            fire()
        else
            Dropdown.Value = it.Value
            refreshAll()
            fire()
            Dropdown:Close()
        end
    end

    for i, it in ipairs(items) do
        local OptBtn = New("TextButton", {
            Size = UDim2.new(1, 0, 0, 16),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = i,
            ZIndex = 62,
            Parent = List,
        })
        local Bg = New("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Theme.Element,
            BorderSizePixel = 0,
            ZIndex = 62,
            Parent = OptBtn,
        })
        local Check = New("Frame", { --// accent-полоска выбранного
            Size = UDim2.new(0, 2, 1, 0),
            Position = UDim2.fromOffset(0, 0),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 63,
            Parent = Bg,
        })
        local Label = Txt("TextLabel", {
            Size = UDim2.new(1, -8, 1, 0),
            Position = UDim2.fromOffset(7, 0),
            BackgroundTransparency = 1,
            Text = it.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextColor3 = Theme.TextDark,
            ZIndex = 63,
            Parent = Bg,
        }, 0, false)

        local row = { Item = it, Bg = Bg, Check = Check, Text = Label, Btn = OptBtn }
        optionRows[#optionRows + 1] = row

        OptBtn.MouseEnter:Connect(function()
            Bg.BackgroundColor3 = Theme.ElementHover
        end)
        OptBtn.MouseLeave:Connect(function()
            refreshRow(row, it)
        end)
        OptBtn.MouseButton1Click:Connect(function()
            toggleItem(it)
        end)
    end

    updateValueLabel()
    refreshAll()

    local function fitPopup()
        local w = math.max(Row.AbsoluteSize.X, 120)
        local h = Clamp(Layout.AbsoluteContentSize.Y + 6, 20, POPUP_MAX_H)
        Popup.Size = UDim2.fromOffset(math.floor(w), math.floor(h))
    end

    local repositionConn = nil

    function Dropdown:Open()
        if Library.ActivePicker then Library.ActivePicker:Close() end
        if Library.ActiveSettings then Library.ActiveSettings:SetOpen(false) end
        if Library.ActiveDropdown and Library.ActiveDropdown ~= self then
            Library.ActiveDropdown:Close()
        end
        Library.ActiveDropdown = self
        self.IsOpen = true
        fitPopup()
        Popup.Position = ResolvePopupPos(Row, Popup.Size.X.Offset, Popup.Size.Y.Offset)
        Popup.Visible = true
        Tween(Arrow, { Rotation = -45 }, 0.12)
        Tween(Arrow2, { Rotation = 45 }, 0.12)
        repositionConn = RunService.RenderStepped:Connect(function()
            if not IsActuallyVisible(Row) then
                self:Close()
                return
            end
            Popup.Position = ResolvePopupPos(Row, Popup.Size.X.Offset, Popup.Size.Y.Offset)
        end)
    end

    function Dropdown:Close()
        self.IsOpen = false
        Popup.Visible = false
        Tween(Arrow, { Rotation = 45 }, 0.12)
        Tween(Arrow2, { Rotation = -45 }, 0.12)
        if Library.ActiveDropdown == self then
            Library.ActiveDropdown = nil
        end
        if repositionConn then
            repositionConn:Disconnect()
            repositionConn = nil
        end
    end

    Row.MouseEnter:Connect(function()
        Tween(Box, { BackgroundColor3 = Theme.ElementHover }, 0.1)
    end)
    Row.MouseLeave:Connect(function()
        Tween(Box, { BackgroundColor3 = Theme.Element }, 0.1)
    end)
    Row.MouseButton1Click:Connect(function()
        if Dropdown.IsOpen then
            Dropdown:Close()
        else
            Dropdown:Open()
        end
    end)

    UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
        if not Dropdown.IsOpen then return end
        if InputInRect(input, Popup) or InputInRect(input, Row) then return end
        Dropdown:Close()
    end)

    function Dropdown:Set(v, silent)
        if multi then
            self.Value = {}
            if type(v) == "table" then
                for _, item in ipairs(v) do
                    local it = findItem(item)
                    if it then self.Value[it.Value] = true end
                end
            end
        else
            local it = v ~= nil and findItem(v) or nil
            self.Value = it and it.Value or nil
        end
        refreshAll()
        if not silent then fire() end
    end

    function Dropdown:GetSelected()
        if not self.Multi then return self.Value end
        local arr = {}
        for _, it in ipairs(items) do
            if self.Value[it.Value] then arr[#arr + 1] = it.Value end
        end
        return arr
    end

    function Dropdown:SetItems(list, keepValue)
        --// динамическая замена списка
        for _, r in ipairs(optionRows) do r.Btn:Destroy() end
        optionRows = {}
        items = {}
        for _, it in ipairs(list or {}) do
            if type(it) == "table" then
                local v = it.Value or it[1] or tostring(it)
                items[#items + 1] = { Value = v, Text = tostring(it.Text or it.Label or v) }
            else
                items[#items + 1] = { Value = it, Text = tostring(it) }
            end
        end
        Dropdown.Items = items
        if not keepValue then
            Dropdown.Value = multi and {} or (items[1] and items[1].Value or nil)
        end
        --// пересоздаём строки
        for i, it in ipairs(items) do
            local OptBtn = New("TextButton", {
                Size = UDim2.new(1, 0, 0, 16),
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = i,
                ZIndex = 62,
                Parent = List,
            })
            local Bg = New("Frame", {
                Size = UDim2.fromScale(1, 1),
                BackgroundColor3 = Theme.Element,
                BorderSizePixel = 0,
                ZIndex = 62,
                Parent = OptBtn,
            })
            local Check = New("Frame", {
                Size = UDim2.new(0, 2, 1, 0),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                Visible = false,
                ZIndex = 63,
                Parent = Bg,
            })
            local Label = Txt("TextLabel", {
                Size = UDim2.new(1, -8, 1, 0),
                Position = UDim2.fromOffset(7, 0),
                BackgroundTransparency = 1,
                Text = it.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextColor3 = Theme.TextDark,
                ZIndex = 63,
                Parent = Bg,
            }, 0, false)
            local row = { Item = it, Bg = Bg, Check = Check, Text = Label, Btn = OptBtn }
            optionRows[#optionRows + 1] = row
            OptBtn.MouseEnter:Connect(function() Bg.BackgroundColor3 = Theme.ElementHover end)
            OptBtn.MouseLeave:Connect(function() refreshRow(row, it) end)
            OptBtn.MouseButton1Click:Connect(function() toggleItem(it) end)
        end
        refreshAll()
    end

    Dropdown.Popup = Popup
    Dropdown.Row = Row

    if id then
        Library.Flags[id] = Dropdown
    end
    return Dropdown
end

--// ---------------- TextBox ----------------

--// cfg = {
--//   Text = "Label",
--//   Default = "",
--//   Placeholder = "type...",
--//   ClearOnFocus = true,
--//   Numeric = false,          -- только цифры/точка
--//   MaxLength = nil,
--//   Callback = function(text, enterPressed) ... end,
--// }
function SubTabMt:AddTextBox(id, cfg)
    cfg = cfg or {}
    local Theme = Library.Theme
    local text = cfg.Text or id or "Textbox"
    local callback = cfg.Callback or function() end

    local TextBox = { Type = "TextBox", Value = tostring(cfg.Default or "") }

    self._order = self._order + 1

    local Row = New("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundTransparency = 1,
        LayoutOrder = self._order,
        Parent = self:_nextColumn(),
    })

    Txt("TextLabel", {
        Size = UDim2.new(1, 0, 0, 14),
        Position = UDim2.fromOffset(2, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Text,
        Parent = Row,
    }, 0, false)

    local Field = New("Frame", {
        Size = UDim2.new(1, -4, 0, 16),
        Position = UDim2.new(0, 2, 0, 16),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        Parent = Row,
    })
    Stroke(Field, "Border", 1)
    Stroke(Field, "Outline")

    local Box = Txt("TextBox", {
        Size = UDim2.new(1, -12, 1, 0),
        Position = UDim2.fromOffset(6, 0),
        BackgroundTransparency = 1,
        Text = TextBox.Value,
        PlaceholderText = cfg.Placeholder or "",
        PlaceholderColor3 = Theme.TextDark,
        ClearTextOnFocus = cfg.ClearOnFocus ~= false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Text,
        Parent = Field,
    }, 0, false)

    if cfg.MaxLength then
        Box.MaxVisibleGraphemes = cfg.MaxLength
    end

    local FocusBar = New("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Visible = false,
        Parent = Field,
    })

    local function sanitize(s)
        if cfg.Numeric then
            s = s:gsub("[^%d%.%-]", "")
        end
        if cfg.MaxLength then
            s = s:sub(1, cfg.MaxLength)
        end
        return s
    end

    Box:GetPropertyChangedSignal("Text"):Connect(function()
        if cfg.Numeric then
            local s = sanitize(Box.Text)
            if s ~= Box.Text then
                Box.Text = s
                return
            end
        end
        TextBox.Value = Box.Text
    end)

    Box.Focused:Connect(function()
        FocusBar.Visible = true
        Tween(Field, { BackgroundColor3 = Theme.ElementHover }, 0.1)
    end)
    Box.FocusLost:Connect(function(enterPressed)
        FocusBar.Visible = false
        Tween(Field, { BackgroundColor3 = Theme.Element }, 0.1)
        TextBox.Value = Box.Text
        callback(Box.Text, enterPressed == true)
    end)

    function TextBox:Set(v, silent)
        v = tostring(v or "")
        Box.Text = v
        TextBox.Value = v
        if not silent then callback(v, false) end
    end

    function TextBox:Get()
        return TextBox.Value
    end

    TextBox.Instance = Row
    if id then
        Library.Flags[id] = TextBox
    end
    return TextBox
end

--// ---------------- KeyPicker ----------------

--// cfg = {
--//   Text = "Label",
--//   Default = Enum.KeyCode.F или "F" или nil,
--//   Callback = function(keyCode, isDown) ... end,
--// }
--// KeyPicker.Value = Enum.KeyCode | nil
--// KeyPicker.Mode = "toggle" | "hold" | "always" (информативно)
--// Привязка к реальному действию:
--//   KeyPicker:Bind(function(down) ... end)  -- down = true когда клавиша нажата
--//   KeyPicker:SetMode("hold")
function SubTabMt:AddKeyPicker(id, cfg)
    cfg = cfg or {}
    local Theme = Library.Theme
    local text = cfg.Text or id or "Keybind"
    local callback = cfg.Callback or function() end

    local default = cfg.Default
    if type(default) == "string" then
        default = StringToKeyCode(default)
    elseif cfg.Default == nil then
        default = Enum.KeyCode.F
    end

    local KeyPicker = {
        Type = "KeyPicker",
        Value = default,
        Mode = cfg.Mode or "toggle",
        IsListening = false,
        IsDown = false,
    }

    

    self._order = self._order + 1

    local Row = New("Frame", {
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        LayoutOrder = self._order,
        Parent = self:_nextColumn(),
    })

    Txt("TextLabel", {
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.fromOffset(2, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Text,
        Parent = Row,
    }, 0, false)

    --// кнопка-плашка с текущей клавишей
    local Btn = New("TextButton", {
        Size = UDim2.fromOffset(33, 14),
        Position = UDim2.new(1, -33, 0.5, -7),
        BackgroundColor3 = Theme.Element,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        Parent = Row,
    })
    Stroke(Btn, "Border", 1)
    Stroke(Btn, "Outline")
    Sheen(Btn)

    local KeyLabel = Txt("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "None",
        TextColor3 = Theme.Text,
        Parent = Btn,
    }, 0, true)

    local function refresh()
        if KeyPicker.IsListening then
            KeyLabel.Text = "..."
            KeyLabel.TextColor3 = Theme.Accent
            Btn.BackgroundColor3 = Theme.ElementHover
        else
            KeyLabel.Text = KeyCodeToString(KeyPicker.Value)
            KeyLabel.TextColor3 = KeyPicker.Value and Theme.Text or Theme.TextDark
            Btn.BackgroundColor3 = Theme.Element
        end
    end
    
    refresh()

    --// АВТО-ПРИВЯЗКА к KeybindList
    if Library.KeyList then
        local kb = Library.KeyList:Add("None", text, KeyPicker.Mode)
        KeyPicker._kb = kb
        KeyPicker._kbText = text
        function KeyPicker:BindToggle(toggleId)
            kb:Bind(toggleId)
            local toggle = Library.Flags[toggleId]
            if toggle and toggle.Type == "Toggle" then
                local function updateKey()
                    local isOn = toggle.Value == true
                    if isOn then
                        kb:Set(KeyCodeToString(self.Value), text, KeyPicker.Mode)
                        kb:SetVis(true)
                        kb:SetStatus(true)
                    else
                        if Library.KeyList and Library.KeyList.Mode == "all" then
                            kb:Set(KeyCodeToString(self.Value), text, KeyPicker.Mode)
                            kb:SetVis(true)
                            kb:SetStatus(false)
                        else
                            kb:SetVis(false)
                        end
                    end
                end
                -- initial sync
                pcall(updateKey)
                toggle:OnChanged(updateKey)
                function KeyPicker:Set(kc, silent)
                    if type(kc) == "string" then kc = StringToKeyCode(kc) end
                    self.Value = kc
                    self.IsDown = false
                    refresh()
                    updateKey()
                    if not silent then callback(self.Value, false) end
                end
            end
        end
        function KeyPicker:LinkToggle(toggleId) self:BindToggle(toggleId) end
        kb:Set(KeyCodeToString(KeyPicker.Value), text, KeyPicker.Mode)
    end

    Btn.MouseEnter:Connect(function()
        if not KeyPicker.IsListening then
            Tween(Btn, { BackgroundColor3 = Theme.ElementHover }, 0.1)
        end
    end)
    Btn.MouseLeave:Connect(function()
        if not KeyPicker.IsListening then
            Tween(Btn, { BackgroundColor3 = Theme.Element }, 0.1)
        end
    end)

    local inputConn = nil

    function KeyPicker:StartListening()
        if self.IsListening then return end
        self.IsListening = true
        refresh()
        inputConn = UserInputService.InputBegan:Connect(function(input, gpe)
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            if input.KeyCode == Enum.KeyCode.Escape then
                --// Esc — отмена
                self:StopListening()
                return
            end
            if IsModifierKey(input.KeyCode) then return end
            self:StopListening()
            self:Set(input.KeyCode)
        end)
    end

    function KeyPicker:StopListening()
        if not self.IsListening then return end
        self.IsListening = false
        if inputConn then
            inputConn:Disconnect()
            inputConn = nil
        end
        refresh()
    end

    function KeyPicker:Set(kc, silent)
        if type(kc) == "string" then
            kc = StringToKeyCode(kc)
        end
        self.Value = kc
        self.IsDown = false
        refresh()
        if not silent then
            callback(self.Value, false)
        end
    end

    function KeyPicker:SetMode(m)
        self.Mode = tostring(m or "toggle")
    end

    function KeyPicker:Bind(fn)
        self._bindFn = fn
        return self
    end

    Btn.MouseButton1Click:Connect(function()
        if KeyPicker.IsListening then
            KeyPicker:StopListening()
        else
            KeyPicker:StartListening()
        end
    end)

    --// [MODE SELECTOR] правый клик -> маленькое окно Toggle / Hold / Always
    do
        local ModePopup = nil
        local modeRefreshFn = nil
        local function createModePopup()
            if ModePopup and ModePopup.Parent then return ModePopup end
            local gui = EnsureGui()
            local Theme = Library.Theme
            ModePopup = New("Frame", {
                Size = UDim2.fromOffset(100, 58),
                BackgroundColor3 = Theme.Background,
                BorderSizePixel = 0,
                Visible = false,
                ZIndex = 75,
                Parent = gui,
            })
            Stroke(ModePopup, "Outline")
            Stroke(ModePopup, "Border", 1)
            AccentLiner(ModePopup, 76)
            local List = New("Frame", {
                Size = UDim2.new(1, 0, 1, -2),
                Position = UDim2.fromOffset(0, 1),
                BackgroundTransparency = 1,
                Parent = ModePopup,
            })
            New("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = List })
            New("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = List })
            local modes = {"Toggle","Hold","Always"}
            for _, m in ipairs(modes) do
                local opt = New("TextButton", {
                    Size = UDim2.new(1, 0, 0, 14),
                    BackgroundColor3 = Theme.Element,
                    BorderSizePixel = 0,
                    Text = "",
                    AutoButtonColor = false,
                    ZIndex = 76,
                    Parent = List,
                })
                Stroke(opt, "Border", 1)
                local lbl = Txt("TextLabel", {
                    Size = UDim2.fromScale(1,1),
                    BackgroundTransparency = 1,
                    Text = m:lower() == "always" and "Always On" or m,
                    TextColor3 = Theme.Text,
                    ZIndex = 77,
                    Parent = opt,
                }, 0, false)
                local function upd()
                    local cur = tostring(KeyPicker.Mode or "Toggle"):lower()
                    local sel = cur == m:lower() or (cur == "always" and m:lower()=="always")
                    -- normalize "Always On" vs "Always"
                    if (cur == "always" or cur == "always on") and m:lower()=="always" then sel = true end
                    opt.BackgroundColor3 = sel and Theme.ElementHover or Theme.Element
                    lbl.TextColor3 = sel and Theme.Accent or Theme.Text
                    if sel then
                        lbl.Text = "• " .. (m:lower()=="always" and "Always On" or m)
                    else
                        lbl.Text = m:lower()=="always" and "Always On" or m
                    end
                end
                upd()
                opt:SetAttribute("ModeUpd", true)
                -- store upd on opt for refresh
                opt:GetPropertyChangedSignal("Parent"):Connect(function() end)
                opt.MouseEnter:Connect(function()
                    local cur = tostring(KeyPicker.Mode or "Toggle"):lower()
                    if cur ~= m:lower() then
                        Tween(opt, {BackgroundColor3 = Theme.ElementHover}, 0.1)
                    end
                end)
                opt.MouseLeave:Connect(function() upd() end)
                opt.MouseButton1Click:Connect(function()
                    KeyPicker:SetMode(m)
                    -- обновить KeybindList отображение
                    if KeyPicker._kb and KeyPicker._kbText then
                        pcall(function()
                            KeyPicker._kb.Mode = m
                            -- форсим обновление строки в листе если привязан
                            if KeyPicker._boundToggle then
                                local tog = Library.Flags[KeyPicker._boundToggle]
                                if tog then
                                    local ks = KeyCodeToString(KeyPicker.Value)
                                    KeyPicker._kb:Set(ks, KeyPicker._kbText, m)
                                    -- триггерим updateKey через Set
                                    pcall(function() KeyPicker:Set(KeyPicker.Value, true) end)
                                else
                                    local ks = KeyCodeToString(KeyPicker.Value)
                                    KeyPicker._kb:Set(ks, KeyPicker._kbText, m)
                                end
                            else
                                local ks = KeyCodeToString(KeyPicker.Value)
                                KeyPicker._kb:Set(ks, KeyPicker._kbText, m)
                            end
                        end)
                    end
                    if ModePopup then ModePopup.Visible = false end
                    -- обновить все опты
                    task.defer(function()
                        for _, ch in ipairs(List:GetChildren()) do
                            if ch:IsA("TextButton") then
                                -- найдем lbl внутри
                                for _, sub in ipairs(ch:GetChildren()) do
                                    if sub:IsA("TextLabel") then
                                        local cur2 = tostring(KeyPicker.Mode or "Toggle"):lower()
                                        local isSel = cur2 == m:lower()
                                        -- но m разный для каждой кнопки, нужно перебрать modes
                                    end
                                end
                            end
                        end
                        -- проще пересоздать upd для всех
                        for _, btn in ipairs(List:GetChildren()) do
                            if btn:IsA("TextButton") then
                                local lbl2 = btn:FindFirstChildWhichIsA("TextLabel", true)
                                if lbl2 then
                                    -- извлечем mode из текста
                                    local btnMode = lbl2.Text:gsub("• ",""):gsub(" Always On","Always"):lower()
                                    local cur3 = tostring(KeyPicker.Mode or "Toggle"):lower()
                                    if cur3 == "always on" then cur3 = "always" end
                                    local sel2 = cur3 == btnMode:lower()
                                    btn.BackgroundColor3 = sel2 and Theme.ElementHover or Theme.Element
                                    lbl2.TextColor3 = sel2 and Theme.Accent or Theme.Text
                                    lbl2.Text = sel2 and ("• " .. (btnMode=="always" and "Always On" or btnMode)) or (btnMode=="always" and "Always On" or btnMode)
                                    -- капитализация
                                    if btnMode=="toggle" then lbl2.Text = sel2 and "• Toggle" or "Toggle" end
                                    if btnMode=="hold" then lbl2.Text = sel2 and "• Hold" or "Hold" end
                                end
                            end
                        end
                    end)
                end)
                -- хак: сохраним upd в атрибуте через closure table
                -- используем opt:SetAttribute невозможно функцию, поэтому храним в _G
            end
            -- метод обновления всех (локальная функция, не член Frame)
            local function refreshModePopupInner()
                for _, btn in ipairs(List:GetChildren()) do
                    if btn:IsA("TextButton") then
                        local lbl2 = btn:FindFirstChildWhichIsA("TextLabel", true)
                        if lbl2 then
                            local raw = lbl2.Text:gsub("• ","")
                            local btnMode = raw:lower()
                            if btnMode == "always on" then btnMode = "always" end
                            local cur = tostring(KeyPicker.Mode or "Toggle"):lower()
                            if cur == "always on" then cur = "always" end
                            local sel = cur == btnMode
                            btn.BackgroundColor3 = sel and Theme.ElementHover or Theme.Element
                            lbl2.TextColor3 = sel and Theme.Accent or Theme.Text
                            if sel then
                                if btnMode=="always" then lbl2.Text = "• Always On" else lbl2.Text = "• " .. (btnMode:sub(1,1):upper()..btnMode:sub(2)) end
                            else
                                if btnMode=="always" then lbl2.Text = "Always On" else lbl2.Text = btnMode:sub(1,1):upper()..btnMode:sub(2) end
                            end
                        end
                    end
                end
            end
            -- сохраняем refresh через closure (не на Frame)
            modeRefreshFn = refreshModePopupInner
            KeyPicker._modeRefresh = refreshModePopupInner
            return ModePopup
        end

        local function showModePopup()
            local mp = createModePopup()
            pcall(function()
                if modeRefreshFn then modeRefreshFn() end
            end)
            local p = Btn.AbsolutePosition
            local s = Btn.AbsoluteSize
            local cam = workspace.CurrentCamera
            local vp = cam and cam.ViewportSize or Vector2.new(1920,1080)
            local w = 100
            local h = 58
            local x = math.clamp(p.X - w + s.X, 0, math.max(vp.X - w, 0))
            local y = math.clamp(p.Y + s.Y + 5 + GuiInset, 0, math.max(vp.Y - h, 0))
            mp.Position = UDim2.fromOffset(x, y)
            mp.Visible = true
        end

        -- правый клик через InputBegan (надежнее чем MouseButton2Click)
        Btn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton2 then
                showModePopup()
            end
        end)
        -- также поддержка MouseButton2Click если есть
        pcall(function()
            Btn.MouseButton2Click:Connect(function()
                showModePopup()
            end)
        end)

        UserInputService.InputBegan:Connect(function(input, gpe)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
            if not ModePopup or not ModePopup.Visible then return end
            local pos = input.Position
            local function over(gui)
                if not gui or not gui.Parent then return false end
                local gp = gui.AbsolutePosition
                local gs = gui.AbsoluteSize
                return pos.X >= gp.X and pos.X <= gp.X+gs.X and pos.Y >= gp.Y and pos.Y <= gp.Y+gs.Y
            end
            if over(ModePopup) or over(Btn) then return end
            ModePopup.Visible = false
        end)

        -- патчим SetMode чтобы обновлять лист сразу
        do
            local origSM = KeyPicker.SetMode
            function KeyPicker:SetMode(m)
                local mm = tostring(m or "Toggle")
                -- нормализация Always On -> Always
                if mm:lower() == "always on" then mm = "Always" end
                -- капитализация
                if mm:lower() == "toggle" then mm = "Toggle" elseif mm:lower()=="hold" then mm="Hold" elseif mm:lower()=="always" then mm="Always" end
                self.Mode = mm
                -- обновить kb
                if self._kb and self._kbText then
                    pcall(function()
                        self._kb.Mode = mm
                        local ks = KeyCodeToString(self.Value)
                        self._kb:Set(ks, self._kbText, mm)
                    end)
                end
                if modeRefreshFn then
                    pcall(function() modeRefreshFn() end)
                elseif KeyPicker._modeRefresh then
                    pcall(function() KeyPicker._modeRefresh() end)
                end
            end
        end

        -- сохраняем привязку для обновления режима
        local origBindToggle = KeyPicker.BindToggle
        if origBindToggle then
            function KeyPicker:BindToggle(toggleId)
                self._boundToggle = toggleId
                return origBindToggle(self, toggleId)
            end
        else
            function KeyPicker:LinkToggle(toggleId)
                self._boundToggle = toggleId
                if self.BindToggle then return self:BindToggle(toggleId) end
            end
        end
    end

    --// глобальный слушатель: обновляет IsDown и дёргает callback/bind (gpe игнор для биндов)
    UserInputService.InputBegan:Connect(function(input, gpe)
        -- if gpe then return end -- [BIND_GPE_FIX] не игнорим gpe для биндов, иначе в игре не ворк
        if KeyPicker.IsListening then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if KeyPicker.Value and input.KeyCode == KeyPicker.Value then
            KeyPicker.IsDown = true
            pcall(callback, KeyPicker.Value, true)
            if KeyPicker._bindFn then
                local ok,err = pcall(KeyPicker._bindFn, true)
                if not ok then warn("[KeyPicker _bindFn] "..tostring(err)) end
            end
            --// подсветка
            pcall(function() Tween(Btn, { BackgroundColor3 = Theme.Accent }, 0.08) end)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if KeyPicker.Value and input.KeyCode == KeyPicker.Value then
            KeyPicker.IsDown = false
            pcall(callback, KeyPicker.Value, false)
            if KeyPicker._bindFn then
                local ok,err = pcall(KeyPicker._bindFn, false)
                if not ok then warn("[KeyPicker _bindFn end] "..tostring(err)) end
            end
            pcall(function() Tween(Btn, { BackgroundColor3 = KeyPicker.IsListening and Theme.ElementHover or Theme.Element }, 0.12) end)
        end
    end)

    KeyPicker.Instance = Row
    KeyPicker.Button = Btn
    KeyPicker.Label = KeyLabel

    if id then
        Library.Flags[id] = KeyPicker
    end
    return KeyPicker
end

--// ESP-preview: «манекен» / Viewport-модель в рамке, поверх — ESP-элементы (box/name/health/
--// distance/skeleton). Стилизован под тему: острые углы, Border+Outline,
--// accent-рамка, градиентный блик. Видимость/цвета читаются из Library.Flags:
--//   :AddESPreview({
--//       Height = 200,
--//       PlayerName = "Player", HealthValue = 100, Distance = 134,
--//       UsePlayerModel = true, -- // true = взять LocalPlayer.Character автоматом
--//       Model = localPlayerModel, -- // или передать Model напрямую
--//       Bind = {
--//           Enable = "esp_enable",
--//           Box = "esp_box", Name = "esp_name", Health = "esp_health",
--//           Distance = "esp_distance", Skeleton = "esp_skeleton",
--//           BoxColor = "esp_boxColor", Fill = "esp_fillColor",
--//           HealthColor = "esp_healthColor",
--//       },
--//   })
--// Bind-значение: id флага, true/false или nil (тогда дефолт).
--// UsePlayerModel = true -> Preview берет Players.LocalPlayer.Character и авто-обновляется при респавне.
--// Model = <Model> -> рендерит переданную модель через ViewportFrame.
function SubTabMt:AddESPreview(cfg)
    cfg = cfg or {}
    local Theme = Library.Theme
    local bind = cfg.Bind or {}
    local height = cfg.Height or 200

    self._order = self._order + 1

    local Panel = New("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        LayoutOrder = self._order,
        Parent = self:_nextColumn(),
    })
    Stroke(Panel, "Outline")
    Stroke(Panel, "Border", 1)

    --// фон-сцена с мягким градиентом
    local Stage = New("Frame", {
        Size = UDim2.new(1, -2, 1, -2),
        Position = UDim2.fromOffset(1, 1),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = Panel,
    })
    New("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.Section),
            ColorSequenceKeypoint.new(1, Theme.Background),
        }),
        Parent = Stage,
    })
    New("Frame", { --// accent-полоска сверху сцены
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = Stage,
    })

    --// сетка
    for _, gx in ipairs({ 0.25, 0.5, 0.75 }) do
        New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromScale(gx, 0),
            Size = UDim2.new(0, 1, 1, 0),
            BackgroundColor3 = Theme.Outline,
            BackgroundTransparency = 0.55,
            BorderSizePixel = 0,
            Parent = Stage,
        })
    end
    for _, gy in ipairs({ 0.33, 0.66 }) do
        New("Frame", {
            Position = UDim2.fromScale(0, gy),
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Theme.Outline,
            BackgroundTransparency = 0.55,
            BorderSizePixel = 0,
            Parent = Stage,
        })
    end

    --// подпись в углу сцены
    Txt("TextLabel", {
        Position = UDim2.fromOffset(6, 5),
        Size = UDim2.fromOffset(0, 10),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = string.upper(tostring(cfg.Tag or "esp preview")),
        TextColor3 = Theme.TextDark,
        Parent = Stage,
    }, 0, false)

    --// тень-эллипс под манекеном
    local Shadow = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -6),
        Size = UDim2.new(0.44, 0, 0.055, 0),
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Parent = Stage,
    })
    New("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = Shadow })

    --// геометрия «бокса»: манекен и ESP-элементы считаются от этого прямоугольника
    --// ESP бокс чуть поменьше модели (фикс по скриншоту) — можно переопределить через cfg.BoxWidth/BoxHeight/BoxX/BoxY
    local boxW = cfg.BoxWidth or cfg.BoxW or 0.450
    local boxH = cfg.BoxHeight or cfg.BoxH or 0.585
    local boxX = cfg.BoxX or 0.270
    local boxY = cfg.BoxY or 0.197
    local BoxRect = New("Frame", {
        Size = UDim2.fromScale(boxW, boxH),
        Position = UDim2.fromScale(boxX, boxY),
        BackgroundTransparency = 1,
        Parent = Stage,
    })

    local Character = New("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Parent = BoxRect,
    })

    local function BodyPart(name, px, py, sx, sy, tone)
        local part = New("Frame", {
            Name = name,
            Position = UDim2.fromScale(px, py),
            Size = UDim2.fromScale(sx, sy),
            BackgroundColor3 = tone or Theme.Element,
            BorderSizePixel = 0,
            ZIndex = 2,
            Parent = Character,
        })
        Stroke(part, "Outline")
        Sheen(part)
        return part
    end
    BodyPart("Head", 0.29, 0.00, 0.42, 0.17, Theme.ElementHover)
    BodyPart("Torso", 0.20, 0.18, 0.60, 0.38, Theme.ElementHover)
    BodyPart("ArmL", 0.00, 0.19, 0.17, 0.36)
    BodyPart("ArmR", 0.83, 0.19, 0.17, 0.36)
    BodyPart("LegL", 0.21, 0.57, 0.27, 0.43)
    BodyPart("LegR", 0.52, 0.57, 0.27, 0.43)

    --// ===== Viewport для реальной модели (LocalPlayer) =====
    local Viewport, VCam, CurrentClone
    local function GetTargetModel()
        if cfg.Model and typeof(cfg.Model) == "Instance" and cfg.Model:IsA("Model") then
            return cfg.Model
        end
        if cfg.PlayerModel and typeof(cfg.PlayerModel) == "Instance" and cfg.PlayerModel:IsA("Model") then
            return cfg.PlayerModel
        end
        if cfg.UsePlayerModel then
            if Players.LocalPlayer and Players.LocalPlayer.Character then
                return Players.LocalPlayer.Character
            end
            --// если персонаж еще не загрузился — ждем
            if Players.LocalPlayer then
                local ch = Players.LocalPlayer.Character
                if ch then return ch end
            end
        end
        return nil
    end
    local UseViewport = cfg.UsePlayerModel == true or (cfg.Model ~= nil) or (cfg.PlayerModel ~= nil)
    if UseViewport then
        Character.Visible = false
        Shadow.Visible = false
        Viewport = New("ViewportFrame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Ambient = Color3.fromRGB(170, 170, 170),
            LightDirection = Vector3.new(-1, -1, -1),
            LightColor = Color3.fromRGB(255, 255, 255),
            ZIndex = 2,
            ClipsDescendants = true,
            Parent = BoxRect,
        })
        VCam = Instance.new("Camera")
        VCam.FieldOfView = 55
        VCam.Parent = Viewport
        Viewport.CurrentCamera = VCam

        local function ClearClone()
            if CurrentClone then
                pcall(function() CurrentClone:Destroy() end)
                CurrentClone = nil
            end
        end

        local function PositionCamera(model)
            local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
            if ok and cf and size then
                local center = cf.Position
                local maxDim = math.max(size.X, size.Y, size.Z)
                --// чуть ближе чем раньше, чтобы модель заполняла бокс (было 1.55, стало 1.35)
                local dist = math.clamp(maxDim * 1.35, 4.5, 13)
                --// FIX: модель смотрела назад — камера должна быть СПЕРЕДИ, поэтому берем LookVector HRP
                local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                local look = Vector3.new(0,0,-1)
                local right = Vector3.new(1,0,0)
                if hrp and hrp:IsA("BasePart") then
                    local lv = hrp.CFrame.LookVector
                    local rv = hrp.CFrame.RightVector
                    --// берем только горизонтальную проекцию чтобы камера не улетала вверх при наклоне
                    look = Vector3.new(lv.X, 0, lv.Z)
                    right = Vector3.new(rv.X, 0, rv.Z)
                    if look.Magnitude < 0.05 then look = Vector3.new(0,0,-1) end
                    if right.Magnitude < 0.05 then right = Vector3.new(1,0,0) end
                    look = look.Unit
                    right = right.Unit
                end
                --// камера спереди, чуть сбоку (3/4 вид) и чуть сверху — как в инвентаре, но уже смотрит в лицо
                local camPos = center + look * dist * 0.92 + right * (dist * 0.12) + Vector3.new(0, maxDim * 0.14, 0)
                local target = center + Vector3.new(0, maxDim * 0.08, 0)
                --// если cfg.FrontOnly то строго спереди без бокового смещения
                if cfg.FrontOnly then
                    camPos = center + look * dist + Vector3.new(0, maxDim * 0.13, 0)
                end
                VCam.CFrame = CFrame.new(camPos, target)
            else
                VCam.CFrame = CFrame.new(Vector3.new(0, 1.2, 4.5), Vector3.new(0, 0.8, 0))
            end
        end

        local CaptureOnce = cfg.CaptureOnce or cfg.FreezeModel or cfg.Freeze or cfg.Once or false

        local function IsAliveModel(m)
            if not m or not m.Parent then return false end
            local hum = m:FindFirstChildOfClass("Humanoid")
            if hum then
                if hum.Health <= 0 then return false end
                if hum:GetState() == Enum.HumanoidStateType.Dead then return false end
            end
            --// должен быть HRP и Head чтобы точно "жив и играю"
            if not m:FindFirstChild("HumanoidRootPart") then return false end
            if not m:FindFirstChild("Head") then return false end
            return true
        end

        local function WaitForAliveModel(timeout)
            timeout = timeout or 20
            local start = tick()
            while tick() - start < timeout do
                local m = GetTargetModel()
                if m and IsAliveModel(m) then
                    return m
                end
                --// если персонаж мертв или не прогрузился — ждем
                task.wait(0.2)
                --// если модель вообще nil, подождем CharacterAdded
                if not m and cfg.UsePlayerModel and Players.LocalPlayer then
                    local ch = Players.LocalPlayer.Character
                    if not ch then
                        local ok, newCh = pcall(function() return Players.LocalPlayer.CharacterAdded:Wait() end)
                        if ok and newCh then
                            task.wait(0.3)
                        end
                    end
                end
            end
            return GetTargetModel()
        end

        local function SetupClone(srcOverride)
            ClearClone()
            local src = srcOverride or GetTargetModel()
            if not src then return end
            --// для CaptureOnce — берем только если жив
            if CaptureOnce and not IsAliveModel(src) then
                --// подождем пока оживет (но не вечно, 1 попытка)
                src = WaitForAliveModel(5) or src
                if not IsAliveModel(src) then
                    --// если все еще не жив — не клонируем, подождем следующего шанса только если не Freeze
                    if CaptureOnce then return end
                end
            end
            local ok, clone = pcall(function()
                src.Archivable = true
                return src:Clone()
            end)
            if not ok or not clone then return end
            --// чистим скрипты и якорим парты чтобы не сыпалось
            for _, d in ipairs(clone:GetDescendants()) do
                if d:IsA("Script") or d:IsA("LocalScript") then
                    pcall(function() d:Destroy() end)
                elseif d:IsA("BasePart") then
                    d.Anchored = true
                    d.CanCollide = false
                elseif d:IsA("Decal") or d:IsA("Texture") then
                    -- оставляем
                end
            end
            clone.Parent = Viewport
            --// убираем Humanoid AutoRotate и т.п. не нужно
            CurrentClone = clone
            PositionCamera(clone)
        end

        if CaptureOnce then
            --// захват 1 раз и навсегда, только когда жив и играю
            task.spawn(function()
                local src = WaitForAliveModel(25)
                if src and IsAliveModel(src) then
                    SetupClone(src)
                    print("[ESPreview] CaptureOnce: захвачена модель " .. src:GetFullName())
                else
                    --// fallback: пробуем хоть что-то
                    SetupClone()
                end
            end)
            --// НЕ подписываемся на CharacterAdded и НЕ делаем периодический рескан — freeze навсегда
        else
            SetupClone()

            --// авто-обновление при респавне LocalPlayer (только если не freeze)
            if cfg.UsePlayerModel and Players.LocalPlayer then
                Players.LocalPlayer.CharacterAdded:Connect(function()
                    task.wait(0.6)
                    --// проверяем что жив
                    local m = GetTargetModel()
                    if IsAliveModel(m) then
                        SetupClone(m)
                    else
                        --// подождем оживления
                        task.wait(1)
                        m = WaitForAliveModel(5)
                        if m then SetupClone(m) end
                    end
                end)
            end

            --// периодическая проверка что клон еще жив / модель сменилась
            task.spawn(function()
                local lastSrc = GetTargetModel()
                while Viewport and Viewport.Parent do
                    task.wait(0.8)
                    local src = GetTargetModel()
                    if src ~= lastSrc then
                        --// если новая модель, но она мертва — не обновляем, ждем живую
                        if IsAliveModel(src) then
                            lastSrc = src
                            SetupClone(src)
                        end
                    elseif not CurrentClone or not CurrentClone.Parent then
                        if IsAliveModel(src) then
                            SetupClone(src)
                        end
                    end
                    --// если камера потерялась
                    if Viewport and VCam and not Viewport.CurrentCamera then
                        Viewport.CurrentCamera = VCam
                    end
                end
            end)
        end
    end

    --// заливка бокса (снизу — мягкое свечение)
    local Fill = New("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.75,
        BorderSizePixel = 0,
        ZIndex = 1,
        Visible = false,
        Parent = BoxRect,
    })
    New("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.55, 0.85),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Parent = Fill,
    })

    --// скелет: кости рисуются по пиксельным координатам бокса
    local Skeleton = New("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 3,
        Parent = BoxRect,
    })
    local Bones = {}
    local function AddBone(x1, y1, x2, y2)
        local bone = New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = Skeleton,
        })
        table.insert(Bones, { Obj = bone, X1 = x1, Y1 = y1, X2 = x2, Y2 = y2 })
    end
    AddBone(0.5, 0.17, 0.5, 0.56)     -- позвоночник
    AddBone(0.085, 0.20, 0.915, 0.20) -- линия плеч
    AddBone(0.085, 0.20, 0.085, 0.55) -- левая рука
    AddBone(0.915, 0.20, 0.915, 0.55) -- правая рука
    AddBone(0.5, 0.56, 0.345, 0.99)   -- левая нога
    AddBone(0.5, 0.56, 0.655, 0.99)   -- правая нога

    local function LayoutBones()
        local s = BoxRect.AbsoluteSize
        if s.X < 2 or s.Y < 2 then return end
        for _, bone in ipairs(Bones) do
            local p1 = Vector2.new(bone.X1 * s.X, bone.Y1 * s.Y)
            local p2 = Vector2.new(bone.X2 * s.X, bone.Y2 * s.Y)
            local d = p2 - p1
            local mid = (p1 + p2) * 0.5
            bone.Obj.Size = UDim2.fromOffset(math.max(d.Magnitude, 1), 1)
            bone.Obj.Position = UDim2.fromOffset(mid.X, mid.Y)
            bone.Obj.Rotation = math.deg(math.atan2(d.Y, d.X))
        end
    end
    task.defer(LayoutBones)
    BoxRect:GetPropertyChangedSignal("AbsoluteSize"):Connect(LayoutBones)

    --// health bar слева от бокса
    local HealthOuter = New("Frame", {
        Position = UDim2.fromOffset(-8, 0),
        Size = UDim2.new(0, 4, 1, 0),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 4,
        Parent = BoxRect,
    })
    Stroke(HealthOuter, "Outline")
    Stroke(HealthOuter, "Border", 1)

    local HealthFill = New("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 1, 1, -1),
        Size = UDim2.new(1, -2, 1, -2),
        BackgroundColor3 = Theme.Safe,
        BorderSizePixel = 0,
        ZIndex = 5,
        Parent = HealthOuter,
    })
    Sheen(HealthFill)

    --// armor bar справа от бокса
    local ArmorOuter = New("Frame", {
        Position = UDim2.new(1, 2, 0, 0),
        Size = UDim2.new(0, 4, 1, 0),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 4,
        Parent = BoxRect,
    })
    Stroke(ArmorOuter, "Outline")
    Stroke(ArmorOuter, "Border", 1)

    local ArmorFill = New("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 1, 1, -1),
        Size = UDim2.new(1, -2, 1, -2),
        BackgroundColor3 = Color3.fromRGB(90, 170, 255),
        BorderSizePixel = 0,
        ZIndex = 5,
        Parent = ArmorOuter,
    })
    Sheen(ArmorFill)

    --// health number возле хп бара
    local HealthTextLabel = Txt("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.fromOffset(-10, 0),
        Size = UDim2.fromOffset(22, 12),
        BackgroundTransparency = 1,
        Text = "100",
        TextXAlignment = Enum.TextXAlignment.Right,
        TextColor3 = Theme.Text,
        TextStrokeColor3 = Theme.Border,
        TextStrokeTransparency = 0.3,
        Visible = false,
        ZIndex = 5,
        Parent = BoxRect,
    }, 0, false)

    --// weapon под боксом (ниже distance)
    local WeaponLabel = Txt("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 1, 18),
        Size = UDim2.fromOffset(0, 11),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = "AK-47",
        TextColor3 = Theme.Text,
        TextStrokeColor3 = Theme.Border,
        TextStrokeTransparency = 0.3,
        Visible = false,
        ZIndex = 5,
        Parent = BoxRect,
    }, 0, false)

    --// weapon icon — текст-иконка
    local WeaponIconLabel = Txt("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 1, 28),
        Size = UDim2.fromOffset(0, 10),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = "[AK]",
        TextColor3 = Theme.TextDark,
        TextStrokeColor3 = Theme.Border,
        TextStrokeTransparency = 0.3,
        Visible = false,
        ZIndex = 5,
        Parent = BoxRect,
    }, -1, false)

    --// flags справа от бокса (столбик)
    local FlagsLabel = Txt("TextLabel", {
        Position = UDim2.new(1, 8, 0, 0),
        Size = UDim2.fromOffset(50, 30),
        BackgroundTransparency = 1,
        Text = "HAS DEF\nFLASHED",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextColor3 = Color3.fromRGB(180, 225, 255),
        TextStrokeColor3 = Theme.Border,
        TextStrokeTransparency = 0.3,
        Visible = false,
        ZIndex = 5,
        Parent = BoxRect,
    }, -1, false)

    --// chams оверлей — полупрозрачная заливка поверх модели
    local ChamsOverlay = New("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(255, 70, 90),
        BackgroundTransparency = 0.6,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 2,
        Parent = BoxRect,
    })

    --// рамка бокса + уголки
    local Box = New("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 4,
        Parent = BoxRect,
    })
    local BoxStroke = New("UIStroke", {
        Color = Theme.Accent,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        LineJoinMode = Enum.LineJoinMode.Miter,
        Parent = Box,
    })

    local Corners = New("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 4,
        Parent = BoxRect,
    })
    local CornerLines = {}
    local CORNER = 7
    for _, c in ipairs({
        { X = 0, Y = 0, AX = 0, AY = 0, Right = false, Bottom = false },
        { X = 1, Y = 0, AX = 1, AY = 0, Right = true, Bottom = false },
        { X = 0, Y = 1, AX = 0, AY = 1, Right = false, Bottom = true },
        { X = 1, Y = 1, AX = 1, AY = 1, Right = true, Bottom = true },
    }) do
        local holder = New("Frame", {
            AnchorPoint = Vector2.new(c.AX, c.AY),
            Position = UDim2.fromScale(c.X, c.Y),
            Size = UDim2.fromOffset(CORNER, CORNER),
            BackgroundTransparency = 1,
            Parent = Corners,
        })
        table.insert(CornerLines, New("Frame", {
            Size = UDim2.new(1, 0, 0, 1),
            Position = UDim2.fromOffset(0, c.Bottom and (CORNER - 1) or 0),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Parent = holder,
        }))
        table.insert(CornerLines, New("Frame", {
            Size = UDim2.new(0, 1, 1, 0),
            Position = UDim2.fromOffset(c.Right and (CORNER - 1) or 0, 0),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Parent = holder,
        }))
    end

    --// имя над боксом и дистанция под ним
    local NameLabel = Txt("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 0, -5),
        Size = UDim2.fromOffset(0, 12),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = tostring(cfg.PlayerName or "Player"),
        TextColor3 = Theme.Accent,
        TextStrokeColor3 = Theme.Border,
        TextStrokeTransparency = 0.3,
        Visible = false,
        ZIndex = 5,
        Parent = BoxRect,
    }, 0, false)

    local DistLabel = Txt("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 1, 5),
        Size = UDim2.fromOffset(0, 11),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = Theme.TextDark,
        TextStrokeColor3 = Theme.Border,
        TextStrokeTransparency = 0.3,
        Visible = false,
        ZIndex = 5,
        Parent = BoxRect,
    }, 0, false)

    --// ---------------- привязка к флагам ----------------

    local State = {
        Health = Clamp(tonumber(cfg.HealthValue) or 100, 0, 100),
        Distance = tonumber(cfg.Distance) or 134,
        Armor = Clamp(tonumber(cfg.ArmorValue) or 100, 0, 100),
        Weapon = tostring(cfg.WeaponName or "AK-47"),
        FlagsText = tostring(cfg.FlagsText or "HAS DEF"),
    }

    local function ReadFlag(v, default)
        if v == nil then return default end
        if type(v) == "boolean" then return v end
        local f = Library.Flags[v]
        if not f then return default end
        if f.Type == "ColorPicker" then return true end
        if f.Type == "Toggle" then return f.Value == true end
        return f.Value ~= nil and f.Value ~= false
    end

    local function ReadColor(v, default)
        if type(v) == "string" then
            local f = Library.Flags[v]
            if f and f.Type == "ColorPicker" then
                return f.Value, f.Transparency
            end
        elseif typeof(v) == "Color3" then
            return v, nil
        end
        return default, nil
    end

    local function DrawHealth()
        local level = Clamp(State.Health, 0, 100) / 100
        HealthFill.Size = UDim2.new(1, -2, level, -2)
    end
    local function DrawArmor()
        local level = Clamp(State.Armor, 0, 100) / 100
        ArmorFill.Size = UDim2.new(1, -2, level, -2)
    end
    local function ReadDropdownValue(flagName, defaultVal)
        if not flagName then return defaultVal end
        local f = Library.Flags[flagName]
        if f and f.Value ~= nil then
            local v = f.Value
            if type(v) == "table" then
                -- multi dropdown returns table, take first
                for k, vv in pairs(v) do
                    if vv == true then return k end
                    if type(vv) == "string" then return vv end
                end
                if #v > 0 then return v[1] end
            end
            return v
        end
        return defaultVal
    end

    local function Update()
        local enabled = ReadFlag(bind.Enable, true)
        local showBox = ReadFlag(bind.Box, true)
        local showName = ReadFlag(bind.Name, true)
        local showHealth = ReadFlag(bind.Health, true)
        local showDist = ReadFlag(bind.Distance, true)
        local showSkel = ReadFlag(bind.Skeleton, false)
        local showFill = ReadFlag(bind.Fill, true)
        local showArmor = ReadFlag(bind.Armor or "espArmor", true)
        local showHealthText = ReadFlag(bind.HealthText or "espHealthText", true)
        local showWeapon = ReadFlag(bind.Weapon or "espWeapon", true)
        local showWeaponIcon = ReadFlag(bind.WeaponIcon or "espWeaponIcon", true)
        local showFlags = ReadFlag(bind.Flags or "espFlags", true)
        local showChams = ReadFlag(bind.Chams or "espChams", true)
        local boxStyle = ReadDropdownValue(bind.BoxStyle or "espBoxStyle", "Corner")

        local boxColor = ReadColor(bind.BoxColor, cfg.BoxColor or Theme.Accent)
        local fillColor, fillTrans = ReadColor(bind.Fill, cfg.FillColor or boxColor)
        local opacity = (1 - Clamp(fillTrans or 0.72, 0, 1)) * 0.55
        opacity = Clamp(opacity, 0.04, 0.45)

        -- box style: Corner только уголки, Full только рамка, иначе оба (как раньше)
        local styleIsCorner = tostring(boxStyle):lower():find("corner") ~= nil
        local styleIsFull = tostring(boxStyle):lower():find("full") ~= nil
        if styleIsCorner and not styleIsFull then
            Box.Visible = false
            Corners.Visible = enabled and showBox
        elseif styleIsFull and not styleIsCorner then
            Box.Visible = enabled and showBox
            Corners.Visible = false
        else
            Box.Visible = enabled and showBox
            Corners.Visible = enabled and showBox
        end
        BoxStroke.Color = boxColor
        for _, line in ipairs(CornerLines) do
            line.BackgroundColor3 = boxColor
        end

        Fill.Visible = enabled and showBox and showFill
        Fill.BackgroundColor3 = fillColor
        Fill.BackgroundTransparency = 1 - opacity

        NameLabel.Visible = enabled and showName
        NameLabel.TextColor3 = boxColor
        DistLabel.Visible = enabled and showDist
        DistLabel.Text = string.format("%dm", math.floor(State.Distance + 0.5))

        HealthOuter.Visible = enabled and showHealth
        local healthColor = ReadColor(bind.HealthColor, cfg.HealthColor or Theme.Safe)
        HealthFill.BackgroundColor3 = healthColor
        DrawHealth()

        -- новые элементы
        ArmorOuter.Visible = enabled and showArmor
        local armorColor = ReadColor(bind.ArmorColor or "espArmorColor", Color3.fromRGB(90, 170, 255))
        ArmorFill.BackgroundColor3 = armorColor
        DrawArmor()

        HealthTextLabel.Visible = enabled and showHealthText and showHealth
        HealthTextLabel.Text = tostring(math.floor(State.Health + 0.5))
        local htColor = ReadColor(bind.HealthTextColor or "espHealthTextColor", Theme.Text)
        HealthTextLabel.TextColor3 = htColor

        WeaponLabel.Visible = enabled and showWeapon
        WeaponLabel.Text = State.Weapon
        local wColor = ReadColor(bind.WeaponColor or "espWeaponColor", Theme.Text)
        WeaponLabel.TextColor3 = wColor

        WeaponIconLabel.Visible = enabled and showWeaponIcon and showWeapon
        -- иконка пока текст, цвет как Weapon

        FlagsLabel.Visible = enabled and showFlags
        FlagsLabel.Text = State.FlagsText
        local fColor = ReadColor(bind.FlagsColor or "espFlagsColor", Color3.fromRGB(180, 225, 255))
        FlagsLabel.TextColor3 = fColor

        ChamsOverlay.Visible = enabled and showChams
        local chamsColor = ReadColor(bind.ChamsColor or "espChamsColor", Color3.fromRGB(255, 70, 90))
        ChamsOverlay.BackgroundColor3 = chamsColor

        Skeleton.Visible = enabled and showSkel
        for _, bone in ipairs(Bones) do
            bone.Obj.BackgroundColor3 = cfg.SkeletonColor or boxColor
        end
    end

    --// флаги не имеют событий изменения — обновляем сцену 10 раз в секунду
    local Acc = 0
    RunService.RenderStepped:Connect(function(dt)
        Acc = Acc + dt
        if Acc < 0.1 then return end
        Acc = 0
        if not Panel.Visible then return end
        Update()
    end)

    local Preview = { Instance = Panel }
    function Preview:SetHealth(v)
        State.Health = Clamp(tonumber(v) or 0, 0, 100)
        DrawHealth()
        HealthTextLabel.Text = tostring(math.floor(State.Health + 0.5))
    end
    function Preview:SetArmor(v)
        State.Armor = Clamp(tonumber(v) or 0, 0, 100)
        DrawArmor()
    end
    function Preview:SetDistance(v)
        State.Distance = tonumber(v) or 0
        Update()
    end
    function Preview:SetPlayerName(t)
        NameLabel.Text = tostring(t)
    end
    function Preview:SetWeapon(t)
        State.Weapon = tostring(t or "AK-47")
        WeaponLabel.Text = State.Weapon
        WeaponIconLabel.Text = "["..State.Weapon:sub(1,2):upper().."]"
    end
    function Preview:SetFlagsText(t)
        State.FlagsText = tostring(t or "")
        FlagsLabel.Text = State.FlagsText
    end
    function Preview:SetChamsEnabled(b)
        ChamsOverlay.Visible = b == true
    end
    function Preview:SetVisible(b)
        Panel.Visible = b == true
    end
    function Preview:Bind(t)
        for k, v in pairs(t or {}) do
            bind[k] = v
        end
        Update()
    end
    --// для viewport-режима: сменить модель на лету
    function Preview:SetModel(newModel)
        cfg.Model = newModel
        cfg.UsePlayerModel = false
        --// если Viewport еще не был создан (был манекен) — предупредим
        if not Viewport then
            warn("[ESPreview] SetModel: preview был создан без Viewport (UsePlayerModel/Model не были указаны при создании). Пересоздай preview с UsePlayerModel=true")
            return
        end
        --// триггерит пересоздание через next tick проверки, но сделаем сразу
        if newModel and typeof(newModel) == "Instance" and newModel:IsA("Model") then
            pcall(function()
                if CurrentClone then CurrentClone:Destroy() end
                newModel.Archivable = true
                local clone = newModel:Clone()
                for _, d in ipairs(clone:GetDescendants()) do
                    if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy()
                    elseif d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end
                end
                clone.Parent = Viewport
                CurrentClone = clone
                local ok, cf, size = pcall(function() return clone:GetBoundingBox() end)
                if ok and cf and size then
                    local center = cf.Position
                    local maxDim = math.max(size.X, size.Y, size.Z)
                    local dist = math.clamp(maxDim * 1.35, 4.5, 13)
                    local hrp2 = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart
                    local look2 = Vector3.new(0,0,-1)
                    if hrp2 and hrp2:IsA("BasePart") then
                        local lv = hrp2.CFrame.LookVector
                        look2 = Vector3.new(lv.X,0,lv.Z)
                        if look2.Magnitude < 0.05 then look2 = Vector3.new(0,0,-1) end
                        look2 = look2.Unit
                    end
                    local right2 = Vector3.new(1,0,0)
                    if hrp2 then
                        local rv = hrp2.CFrame.RightVector
                        right2 = Vector3.new(rv.X,0,rv.Z)
                        if right2.Magnitude < 0.05 then right2 = Vector3.new(1,0,0) end
                        right2 = right2.Unit
                    end
                    local camPos2 = center + look2 * dist * 0.92 + right2 * (dist * 0.08) + Vector3.new(0, maxDim * 0.13, 0)
                    VCam.CFrame = CFrame.new(camPos2, center + Vector3.new(0, maxDim*0.08,0))
                end
            end)
        end
    end
    function Preview:UseLocalPlayer()
        cfg.UsePlayerModel = true
        cfg.Model = nil
        --// форс пересоздание
        if Viewport and Players.LocalPlayer and Players.LocalPlayer.Character then
            self:SetModel(Players.LocalPlayer.Character)
            cfg.UsePlayerModel = true
        end
    end
    function Preview:GetViewport() return Viewport end
    function Preview:GetModel() return CurrentClone end
    function Preview:GetBoxRect() return BoxRect end
    function Preview:SetBoxSize(w,h)
        boxW = w or boxW
        boxH = h or boxH
        BoxRect.Size = UDim2.fromScale(boxW, boxH)
        if LayoutBones then pcall(LayoutBones) end
        return BoxRect
    end
    function Preview:SetBoxPosition(x,y)
        boxX = x or boxX
        boxY = y or boxY
        BoxRect.Position = UDim2.fromScale(boxX, boxY)
        return BoxRect
    end
    function Preview:SetBox(w,h,x,y)
        if w then boxW = w end
        if h then boxH = h end
        if x then boxX = x end
        if y then boxY = y end
        BoxRect.Size = UDim2.fromScale(boxW, boxH)
        BoxRect.Position = UDim2.fromScale(boxX, boxY)
        if LayoutBones then pcall(LayoutBones) end
        return BoxRect
    end
    function Preview:GetBox() return boxW, boxH, boxX, boxY end

    Preview:SetPlayerName(cfg.PlayerName or (Players.LocalPlayer and Players.LocalPlayer.Name or "Player"))
    Update()

    return Preview
end

--// ---------------- tabs / sub-tabs ----------------

function TabMt:AddSubTab(name)
    local Theme = Library.Theme
    local Sub = setmetatable({ Tab = self, Name = name, _order = 0 }, SubTabMt)

    self._subOrder = self._subOrder + 1
    local isFirst = (self._subOrder == 1)

    local Btn = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = self._subOrder,
        Parent = self.SubHolder,
    })

    --// вертикальная полоска «уголка»: у первого суб-таба тянется от кнопки таба,
    --// у остальных стыкуется с предыдущей; до выбранного — accent, ниже — Outline
    local Vert = New("Frame", {
        Size = UDim2.new(0, 1, 1, 4),
        Position = UDim2.fromOffset(2, isFirst and -4 or -2),
        BackgroundColor3 = Theme.Outline,
        BorderSizePixel = 0,
        Parent = Btn,
    })

    --// горизонтальный отросток уголка — только у выбранного суб-таба
    local Horz = New("Frame", {
        Size = UDim2.fromOffset(6, 1),
        Position = UDim2.new(0, 2, 0.5, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Visible = false,
        Parent = Btn,
    })

    local Lbl = Txt("TextLabel", {
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.fromOffset(12, 0),
        BackgroundTransparency = 1,
        Text = tostring(name),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.TextDark,
        Parent = Btn,
    }, 0, false)

    local Page = New("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Outline,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = self.Window.Pages,
    })

    local ColL = New("Frame", {
        Size = UDim2.new(0.5, -3, 0, 0),
        Position = UDim2.fromOffset(0, 0),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = Page,
    })
    New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = ColL })
    New("UIPadding", { PaddingTop = UDim.new(0, 2), Parent = ColL })

    local ColR = New("Frame", {
        Size = UDim2.new(0.5, -3, 0, 0),
        Position = UDim2.new(0.5, 3, 0, 0),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = Page,
    })
    New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = ColR })
    New("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingRight = UDim.new(0, 6), Parent = ColR })

    Sub.Button = Btn
    Sub.Label = Lbl
    Sub.Vert = Vert
    Sub.Horz = Horz
    Sub.Page = Page
    Sub.ColL = ColL
    Sub.ColR = ColR

    Btn.MouseButton1Click:Connect(function()
        self:SelectSubTab(Sub)
    end)
    Btn.MouseEnter:Connect(function()
        if self.SelectedSub ~= Sub then
            Lbl.TextColor3 = Theme.Text
        end
    end)
    Btn.MouseLeave:Connect(function()
        if self.SelectedSub ~= Sub then
            Lbl.TextColor3 = Theme.TextDark
        end
    end)

    table.insert(self.SubTabs, Sub)

    if self.Active and not self.SelectedSub then
        self:SelectSubTab(Sub)
    end

    return Sub
end

function TabMt:SelectSubTab(sub)
    local Theme = Library.Theme
    self.SelectedSub = sub
    local selIdx = 0
    for i, st in ipairs(self.SubTabs) do
        if st == sub then
            selIdx = i
            break
        end
    end
    for i, st in ipairs(self.SubTabs) do
        local active = (st == sub)
        st.Page.Visible = active
        st.Label.TextColor3 = active and Theme.Accent or Theme.TextDark
        st.Horz.Visible = active
        st.Vert.BackgroundColor3 = (i <= selIdx) and Theme.Accent or Theme.Outline
    end
end

--// ---------------- window ----------------

function WindowMt:AddTab(name)
    local Theme = Library.Theme
    local Tab = setmetatable({
        Window = self,
        Name = name,
        SubTabs = {},
        SelectedSub = nil,
        Active = false,
        _subOrder = 0,
    }, TabMt)

    self._tabOrder = self._tabOrder + 1

    local Holder = New("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = self._tabOrder,
        Parent = self.SideList,
    })
    New("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = Holder })

    local Btn = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = Theme.Element,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        LayoutOrder = 0,
        Parent = Holder,
    })
    Sheen(Btn)
    local BtnStrokeOutline = Stroke(Btn, "Outline")
    BtnStrokeOutline.Transparency = 1
    local BtnStrokeBorder = Stroke(Btn, "Border", 1)
    BtnStrokeBorder.Transparency = 1

    local TabLabel = Txt("TextLabel", {
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1,
        Text = tostring(name),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.TextDark,
        Parent = Btn,
    }, 0, true)

    local SubHolder = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Visible = false,
        LayoutOrder = 1,
        Parent = Holder,
    })
    New("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = SubHolder })
    New("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
        PaddingTop = UDim.new(0, 2),
        PaddingBottom = UDim.new(0, 2),
        Parent = SubHolder,
    })

    Tab.Holder = Holder
    Tab.Button = Btn
    Tab.Label = TabLabel
    Tab.SubHolder = SubHolder
    Tab.Strokes = { BtnStrokeOutline, BtnStrokeBorder }

    Btn.MouseButton1Click:Connect(function()
        self:SelectTab(Tab)
    end)
    Btn.MouseEnter:Connect(function()
        if not Tab.Active then
            Tween(Btn, { BackgroundTransparency = 0.6 }, 0.1)
        end
    end)
    Btn.MouseLeave:Connect(function()
        if not Tab.Active then
            Tween(Btn, { BackgroundTransparency = 1 }, 0.1)
        end
    end)

    table.insert(self.Tabs, Tab)

    if #self.Tabs == 1 then
        self:SelectTab(Tab)
    end

    return Tab
end

function WindowMt:SelectTab(tab)
    local Theme = Library.Theme
    for _, t in ipairs(self.Tabs) do
        t.Active = false
        Tween(t.Button, { BackgroundTransparency = 1 }, 0.12)
        t.Label.TextColor3 = Theme.TextDark
        for _, s in ipairs(t.Strokes) do
            s.Transparency = 1
        end
        t.SubHolder.Visible = false
        for _, st in ipairs(t.SubTabs) do
            st.Page.Visible = false
        end
    end
    tab.Active = true
    Tween(tab.Button, { BackgroundTransparency = 0 }, 0.12)
    tab.Label.TextColor3 = Theme.Accent
    for _, s in ipairs(tab.Strokes) do
        s.Transparency = 0
    end
    tab.SubHolder.Visible = (#tab.SubTabs > 0)
    local target = tab.SelectedSub or tab.SubTabs[1]
    if target then
        tab:SelectSubTab(target)
    end
end

function WindowMt:Toggle()
    self.Open = not self.Open
    Library.UIVisible = self.Open
    if Library.ActivePicker then
        Library.ActivePicker:Close()
    end
    if Library.ActiveSettings then
        Library.ActiveSettings:SetOpen(false)
    end
    if Library.ActiveDropdown then
        Library.ActiveDropdown:Close()
    end
    if self.Open then
        Library._prevMouseIcon = UserInputService.MouseIconEnabled
        UserInputService.MouseIconEnabled = false --// системный курсор прячем, рисуем свой
        -- [CURSOR_UNLOCK] даже если игра зафиксировала курсор (LockCenter/LockCurrentPosition), разблокируем для UI
        pcall(function()
            Library._prevMouseBehavior = UserInputService.MouseBehavior
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
                UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            end
            -- синк кастомного курсора с реальным при открытии
            pcall(function()
                local m = UserInputService:GetMouseLocation()
                Library._cursorPos = Vector2.new(m.X, m.Y)
                if Library.Cursor then Library.Cursor.Position = UDim2.fromOffset(m.X - 18, m.Y - 18) end
            end)
        end)
        -- форсим через CameraController если есть
        pcall(function()
            local camCtrl = getgenv and getgenv()._FortunaCameraController
            if camCtrl and type(camCtrl.setForceLockOverride) == "function" then
                pcall(camCtrl.setForceLockOverride, "Fortuna.VIP", true)
            elseif camCtrl and type(camCtrl.SetForceLockOverride) == "function" then
                pcall(function() camCtrl:SetForceLockOverride("Fortuna.VIP", true) end)
            end
        end)
        self.Main.Visible = true
        self.Scale.Scale = 0.97
        Tween(self.Scale, { Scale = 1 }, 0.12)
    else
        UserInputService.MouseIconEnabled = Library._prevMouseIcon ~= false
        pcall(function()
            -- снимаем форc unlock у CameraController
            local camCtrl = getgenv and getgenv()._FortunaCameraController
            if camCtrl and type(camCtrl.setForceLockOverride) == "function" then
                pcall(camCtrl.setForceLockOverride, "Fortuna.VIP", false)
            elseif camCtrl and type(camCtrl.SetForceLockOverride) == "function" then
                pcall(function() camCtrl:SetForceLockOverride("Fortuna.VIP", false) end)
            end
        end)
        pcall(function()
            if Library._prevMouseBehavior ~= nil then
                UserInputService.MouseBehavior = Library._prevMouseBehavior
            else
                UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            end
        end)
        self.Main.Visible = false
    end
end

function WindowMt:SetTitle(t)
    self.TitleLabel.Text = tostring(t)
end

function WindowMt:SetStatus(text, color)
    if not self.StatusValue then return end
    self.StatusValue.Text = RichEscape(text)
    if color then
        self.StatusValue.TextColor3 = color
    end
end

function WindowMt:SetConfig(name)
    if not self.CfgValue then return end
    self.CfgValue.Text = RichEscape(name or "-")
end

--// ---------------- overlay widgets + cursor (outlaw-style) ----------------

Library.Cursor = nil
local CursorReady = false
Library._cursorPos = Vector2.new(0,0)

--// кастомный курсор как в outlaw: виден только пока меню открыто
local function EnsureCursor()
    if CursorReady then return end
    CursorReady = true
    local Cursor = New("ImageLabel", {
        Name = "Cursor",
        Visible = false,
        BackgroundTransparency = 1,
        Image = "http://www.roblox.com/asset/?id=5545698398",
        Size = UDim2.fromOffset(36, 36),
        ZIndex = 10000,
        BorderSizePixel = 0,
        Parent = ScreenGui,
    })
    Library.Cursor = Cursor
    --// окно стартует открытым — сразу прячем системный курсор
    Library._prevMouseIcon = UserInputService.MouseIconEnabled
    UserInputService.MouseIconEnabled = false
    pcall(function()
        Library._prevMouseBehavior = UserInputService.MouseBehavior
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end)
    -- init cursor pos
    pcall(function()
        local m = UserInputService:GetMouseLocation()
        Library._cursorPos = Vector2.new(m.X, m.Y)
    end)
    -- [CURSOR_UNLOCK] BindToRenderStep с приоритетом Camera+1 чтобы перебить игру которая лочит курсор
    pcall(function()
        RunService:BindToRenderStep("FortunaVIPCursorUnlock", Enum.RenderPriority.Camera.Value + 1, function()
            -- форсим Default пока UI открыто
            if Library.UIVisible then
                pcall(function()
                    if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
                        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
                    end
                end)
                -- также пробуем CameraController unlock если доступен
                pcall(function()
                    local camCtrl = nil
                    if getgenv and getgenv()._FortunaCameraController then
                        camCtrl = getgenv()._FortunaCameraController
                    else
                        local ok, mod = pcall(function() return require(game:GetService("ReplicatedStorage").Controllers.CameraController) end)
                        if ok and mod then camCtrl = mod; if getgenv then getgenv()._FortunaCameraController = mod end end
                    end
                    if camCtrl and type(camCtrl.setForceLockOverride) == "function" then
                        pcall(camCtrl.setForceLockOverride, "Fortuna.VIP", true)
                    elseif camCtrl and type(camCtrl.SetForceLockOverride) == "function" then
                        pcall(function() camCtrl:SetForceLockOverride("Fortuna.VIP", true) end)
                    end
                end)
            end
            Cursor.Visible = Library.UIVisible and true or false
            if not Library.UIVisible then return end
            local m = UserInputService:GetMouseLocation()
            local isLocked = (UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCurrentPosition)
            if isLocked then
                -- когда залочен GetMouseLocation возвращает центр, двигаем через GetMouseDelta
                local delta = UserInputService:GetMouseDelta()
                if delta.Magnitude > 0 then
                    Library._cursorPos = Library._cursorPos + Vector2.new(delta.X, delta.Y)
                end
                -- clamp в экран
                local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920,1080)
                Library._cursorPos = Vector2.new(math.clamp(Library._cursorPos.X, 0, vp.X), math.clamp(Library._cursorPos.Y, 0, vp.Y))
                Cursor.Position = UDim2.fromOffset(Library._cursorPos.X - 18, Library._cursorPos.Y - 18)
            else
                Library._cursorPos = Vector2.new(m.X, m.Y)
                Cursor.Position = UDim2.fromOffset(m.X - 18, m.Y - 18)
            end
        end)
    end)
    -- fallback если BindToRenderStep не доступен, оставим старый RenderStepped как бэкап
    pcall(function()
        if not RunService:FindFirstChild("FortunaVIPCursorUnlock") then
            RunService.RenderStepped:Connect(function()
                if not CursorReady then return end
                -- если BindToRenderStep не сработал, делаем тоже самое (проверку пропускаем)
                Cursor.Visible = Library.UIVisible
                if not Library.UIVisible then return end
                pcall(function()
                    if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
                        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
                    end
                end)
                local m = UserInputService:GetMouseLocation()
                Cursor.Position = UDim2.fromOffset(m.X - 18, m.Y - 18)
                Library._cursorPos = Vector2.new(m.X, m.Y)
            end)
        end
    end)
    -- также форсим через PropertyChangedSignal на случай если игра меняет после нашего шага
    pcall(function()
        UserInputService:GetPropertyChangedSignal("MouseBehavior"):Connect(function()
            if Library.UIVisible and UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
                pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
            end
        end)
    end)
    -- трекаем InputChanged для дельты когда залочен (на случай если GetMouseDelta лагает)
    pcall(function()
        UserInputService.InputChanged:Connect(function(input)
            if not Library.UIVisible then return end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
            local isLocked = (UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCurrentPosition)
            if not isLocked then return end
            if input.Delta.Magnitude > 0 then
                Library._cursorPos = Library._cursorPos + Vector2.new(input.Delta.X, input.Delta.Y)
                local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920,1080)
                Library._cursorPos = Vector2.new(math.clamp(Library._cursorPos.X, 0, vp.X), math.clamp(Library._cursorPos.Y, 0, vp.Y))
            end
        end)
    end)
end

--// watermark-виджет как в outlaw: draggable, accent-линия, шиммер, fps/дата
function Library:Watermark(cfg)
    cfg = cfg or {}
    local gui = EnsureGui()
    local Theme = Library.Theme

    local PrefixText = tostring(cfg.Name or cfg.Text or "watermark")
    local DynamicTextProvider = cfg.Dynamic
    local DynamicText = PrefixText
    local DynamicTick = 0
    local StatsText = ""
    local FpsFrames = 0
    local FpsShown = 0
    local FpsTick = tick()
    local ShimmerPhase = 0
    local ShimmerLast = tick()

    local Root = New("Frame", {
        Name = "Watermark",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 42),
        Size = UDim2.fromOffset(0, 25),
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Background,
        Parent = gui,
    })
    Stroke(Root, "Outline")
    Stroke(Root, "Border", 1)
    New("Frame", { --// DarkLiner
        Position = UDim2.new(0, -8, 0, 1),
        Size = UDim2.new(1, 16, 0, 1),
        BorderSizePixel = 0,
        BackgroundColor3 = Theme.LightBorder,
        Parent = Root,
    })
    local AccentLiner = New("Frame", {
        Position = UDim2.new(0, -8, 0, 0),
        Size = UDim2.new(1, 16, 0, 1),
        BorderSizePixel = 0,
        BackgroundColor3 = Theme.Accent,
        Parent = Root,
    })
    local AccentGradient = New("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.5, 1),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Parent = AccentLiner,
    })
    local TextLabel = Txt("TextLabel", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(0, 15),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.X,
        RichText = true,
        Text = PrefixText,
        TextColor3 = Theme.Text,
        Parent = Root,
    }, 0, false)
    New("UIPadding", {
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        Parent = Root,
    })
    MakeDraggable(Root, Root)

    local Watermark = { Instance = Root }

    function Watermark:SetVisibility(b)
        Root.Visible = b == true
    end

    function Watermark:Center()
        local pos = Root.AbsolutePosition
        Root.AnchorPoint = Vector2.new(0, 0)
        task.wait()
        Root.Position = UDim2.fromOffset(pos.X, pos.Y + GuiInset)
    end

    function Watermark:SetText(text)
        DynamicTextProvider = nil
        PrefixText = tostring(text or "")
        DynamicText = PrefixText
        StatsText = ""
        TextLabel.Text = PrefixText
    end

    function Watermark:SetName(text)
        self:SetText(text)
    end

    function Watermark:SetDynamicTextProvider(cb)
        DynamicTextProvider = type(cb) == "function" and cb or nil
        DynamicTick = 0
        DynamicText = PrefixText
    end

    function Watermark:GetBounds()
        return Root.AbsolutePosition, Root.AbsoluteSize
    end

    RunService.RenderStepped:Connect(function()
        if not Root.Visible then return end
        local now = tick()
        FpsFrames = FpsFrames + 1
        if now - ShimmerLast >= (1 / 30) then
            local dt = now - ShimmerLast
            ShimmerPhase = (ShimmerPhase + dt * (1 / 1.2)) % 1
            ShimmerLast = now
            if DynamicTextProvider and (now - DynamicTick) >= 0.25 then
                DynamicTick = now
                DynamicText = tostring(DynamicTextProvider(FpsShown) or "")
            end
            local plain = DynamicTextProvider and DynamicText or (PrefixText .. StatsText)
            local shineWidth = 6
            local shinePos = ShimmerPhase * (#plain + shineWidth)
            local rich = {}
            for i = 1, #plain do
                local dist = math.abs(i - shinePos)
                local a = Clamp(1 - (dist / shineWidth), 0, 1)
                local c = Theme.Text:Lerp(Theme.Accent, a)
                rich[#rich + 1] = string.format(
                    '<font color="rgb(%d,%d,%d)">%s</font>',
                    math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255),
                    plain:sub(i, i)
                )
            end
            AccentGradient.Offset = Vector2.new((ShimmerPhase * 2) - 1, 0)
            TextLabel.Text = table.concat(rich)
        end
        if now - FpsTick >= 1 then
            FpsTick = now
            FpsShown = FpsFrames
            if not DynamicTextProvider then
                StatsText = string.format(" / %s / %sfps", os.date("%a %b %d %X %Y"), FpsShown)
            end
            FpsFrames = 0
        end
    end)

    return Watermark
end

--// keybind-list как в outlaw: draggable-плашка со списком биндов.
--// Ширина плашки подстраивается под самый длинный бинд (не растягивается).
--//   local Kb = Library:KeybindList({ Name = "Keybinds", Mode = "all" })
--//   Kb:Add("F1", "Aimbot", "toggle"):Bind("aim_enable")  -- статус из флага
--//   row:SetStatus(true) / row:SetVis(false) / row:Set(key, name, mode)
--//   Kb:SetMode("active") — показывать только включённые
--//   Kb:SetVisibility(false) / Kb:SetTitle("Binds") / Kb:Center()
function Library:KeybindList(cfg)
    cfg = cfg or {}
    local gui = EnsureGui()
    local Theme = Library.Theme
    local mode = (cfg.Mode == "active") and "active" or "all"

    local Root = New("Frame", {
        Name = "KeybindList",
        AnchorPoint = cfg.AnchorPoint or Vector2.new(0, 0),
        Position = cfg.Position or UDim2.fromOffset(10, 60),
        Size = UDim2.fromOffset(64, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Visible = cfg.Visible ~= false,
        Parent = gui,
    })
    Stroke(Root, "Outline")
    Stroke(Root, "Border", 1)
    New("Frame", { --// AccentLiner
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        LayoutOrder = -1,
        Parent = Root,
    })
    New("UIPadding", {
        PaddingTop = UDim.new(0, 5),
        PaddingBottom = UDim.new(0, 5),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        Parent = Root,
    })
    New("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = Root,
    })

    local Title = Txt("TextLabel", {
        Size = UDim2.fromOffset(0, 12),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.X,
        Text = tostring(cfg.Name or "Keybinds"),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Accent,
        LayoutOrder = 0,
        Parent = Root,
    }, 0, true)

    local KeybindList = {
        Instance = Root,
        Rows = {},
        Mode = mode,
    }

    --// ширина плашки = самый длинный текст (заголовок или строка) + нормальные отступы.
    local PAD_X = 8
    local function UpdateWidth()
        local w = Title.Visible and Title.AbsoluteSize.X or 0
        for _, row in ipairs(KeybindList.Rows) do
            if row.Obj.Visible then
                w = math.max(w, row.Obj.AbsoluteSize.X)
            end
        end
        Root.Size = UDim2.fromOffset(math.max(math.ceil(w) + PAD_X * 2 + 2, 64), 0)
    end
    Title:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateWidth)

    local function Hex(color)
        return ColorToHex(color)
    end

    local function RefreshRow(row)
        local showAll = (KeybindList.Mode == "all")
        row.Obj.Visible = row.CanShow and (showAll or row.Status == true)

        local keyColor = row.Status and Theme.Accent or Theme.TextDark
        local nameColor = row.Status and Theme.Text or Theme.TextDark
        local modeColor = row.Status and Theme.Accent or Theme.TextDark

        local parts = {
            string.format('<font color="%s">%s</font>', Hex(keyColor), RichEscape(row.Key)),
        }
        if row.Name ~= "" then
            parts[#parts + 1] = string.format('<font color="%s">%s</font>', Hex(nameColor), RichEscape(row.Name))
        end
        if row.Mode ~= "" then
            parts[#parts + 1] = string.format('<font color="%s">[%s]</font>', Hex(modeColor), RichEscape(row.Mode))
        end
        if showAll then
            parts[#parts + 1] = string.format(
                '<font color="%s">%s</font>',
                Hex(row.Status and Theme.Accent or Theme.TextDark),
                row.Status and "on" or "off"
            )
        end
        row.Obj.Text = table.concat(parts, " ")
        UpdateWidth()
    end

    function KeybindList:Add(key, name, keyMode)
        local Row = {
            Key = tostring(key or ""),
            Name = tostring(name or ""),
            Mode = tostring(keyMode or ""),
            Status = false,
            CanShow = true,
            Flag = nil,
        }

        Row.Obj = New("TextLabel", {
            Size = UDim2.fromOffset(0, 12),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            RichText = true,
            Text = "",
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.Text,
            LayoutOrder = #KeybindList.Rows + 1,
            Parent = Root,
        })
        Row.Obj:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateWidth)

        function Row:SetStatus(b)
            self.Status = b == true
            RefreshRow(self)
        end

        function Row:SetVis(b)
            self.CanShow = b ~= false
            RefreshRow(self)
        end

        function Row:Set(k, n, m)
            self.Key = tostring(k or "")
            self.Name = tostring(n or "")
            self.Mode = tostring(m or "")
            RefreshRow(self)
        end

        --// привязать строку к флагу: статус читается из Library.Flags[id].Value
        function Row:Bind(id)
            self.Flag = id
            local f = id and Library.Flags[id]
            if f then
                self:SetStatus(f.Value == true)
            end
            return self
        end

        table.insert(KeybindList.Rows, Row)
        RefreshRow(Row)
        task.defer(UpdateWidth)
        return Row
    end

    function KeybindList:Remove(row)
        for i, r in ipairs(self.Rows) do
            if r == row then
                table.remove(self.Rows, i)
                row.Obj:Destroy()
                task.defer(UpdateWidth)
                return
            end
        end
    end

    function KeybindList:SetMode(m)
        self.Mode = (m == "active") and "active" or "all"
        for _, row in ipairs(self.Rows) do
            RefreshRow(row)
        end
        task.defer(UpdateWidth)
    end

    function KeybindList:SetVisibility(b)
        Root.Visible = b == true
        if Root.Visible then
            for _, row in ipairs(self.Rows) do
                RefreshRow(row)
            end
            task.defer(UpdateWidth)
        end
    end

    function KeybindList:SetTitle(t)
        Title.Text = tostring(t)
    end

    function KeybindList:Center()
        local pos = Root.AbsolutePosition
        Root.AnchorPoint = Vector2.new(0, 0)
        task.wait()
        Root.Position = UDim2.fromOffset(pos.X, pos.Y + GuiInset)
    end

    --// статусы привязанных строк тянем из флагов (у флагов нет событий)
    local Acc = 0
    RunService.RenderStepped:Connect(function(dt)
        if not Root.Visible then return end
        Acc = Acc + dt
        if Acc < 0.1 then return end
        Acc = 0
        for _, row in ipairs(KeybindList.Rows) do
            if row.Flag then
                local f = Library.Flags[row.Flag]
                if f then
                    local on = (f.Value == true)
                    if on ~= row.Status then
                        row:SetStatus(on)
                    end
                end
            end
        end
    end)

    MakeDraggable(Root, Root)

    Library.KeyList = KeybindList
    return KeybindList
end

--// ---------------- Notify (уведомления) ----------------

--// cfg = {
--//   Title = "Title",  -- ИГНОРИРУЕТСЯ
--//   Text = "Body",
--//   Duration = 4,
--//   Type = "info"|"success"|"warning"|"error",
--// }
function Library:Notify(cfg)
    cfg = cfg or {}
    local gui = EnsureGui()
    local Theme = Library.Theme

    local nType = tostring(cfg.Type or "info"):lower()
    local accentColor = Theme.Accent
    if nType == "success" then accentColor = Theme.Safe
    elseif nType == "warning" then accentColor = Color3.fromRGB(255, 190, 60)
    elseif nType == "error" then accentColor = Theme.Risky end

    local duration = tonumber(cfg.Duration) or 4
    local width = tonumber(cfg.Width) or 200

    if not Library._NotifyHolder or not Library._NotifyHolder.Parent then
        local Holder = New("Frame", {
            Name = "NotifyHolder",
            AnchorPoint = Vector2.new(0, 0),
            Position = UDim2.new(0, 12, 0, 12),
            Size = UDim2.fromOffset(width, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            ZIndex = 200,
            Parent = gui,
        })
        New("UIListLayout", {
            Padding = UDim.new(0, 5),
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Top,
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            Parent = Holder,
        })
        Library._NotifyHolder = Holder
    end

    local order = 0
    for _, c in ipairs(Library._NotifyHolder:GetChildren()) do
        if c:IsA("Frame") then
            order = math.max(order, c.LayoutOrder)
        end
    end

    local Card = New("Frame", {
        Name = "Notify",
        Size = UDim2.fromOffset(width, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ZIndex = 201,
        LayoutOrder = order + 1,
        Parent = Library._NotifyHolder,
    })
    Stroke(Card, "Outline")
    Stroke(Card, "Border", 1)

    --// ТОЛЬКО левая accent-полоса
    New("Frame", {
        Size = UDim2.new(0, 2, 1, 0),
        Position = UDim2.fromOffset(0, 0),
        BackgroundColor3 = accentColor,
        BorderSizePixel = 0,
        ZIndex = 202,
        Parent = Card,
    })

    local Pad = New("Frame", {
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.fromOffset(8, 0),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex = 202,
        Parent = Card,
    })
    -- // UIListLayout убран, чтобы текст мог центрироваться

    local bodyText = tostring(cfg.Text or "")
    if bodyText ~= "" then
        Txt("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Text = bodyText,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Center,  -- по центру
            TextYAlignment = Enum.TextYAlignment.Center,  -- по центру
            TextColor3 = accentColor,
            LayoutOrder = 1,
            ZIndex = 203,
            Parent = Pad,
        }, 0, false)
    end

    local Notify = { Instance = Card, Closed = false }
    local elapsed = 0
    local animConn = nil

    function Notify:Close()
        if self.Closed then return end
        self.Closed = true
        if animConn then animConn:Disconnect() end
        local tw = TweenService:Create(Card, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 1,
        })
        for _, d in ipairs(Card:GetDescendants()) do
            if d:IsA("GuiObject") and d.BackgroundTransparency < 1 then
                pcall(function() TweenService:Create(d, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play() end)
            elseif d:IsA("TextLabel") or d:IsA("TextBox") then
                pcall(function() TweenService:Create(d, TweenInfo.new(0.15), { TextTransparency = 1 }):Play() end)
            elseif d:IsA("UIStroke") then
                pcall(function() TweenService:Create(d, TweenInfo.new(0.15), { Transparency = 1 }):Play() end)
            end
        end
        tw:Play()
        task.delay(0.18, function()
            if Card and Card.Parent then Card:Destroy() end
        end)
    end

    local paused = false
    Card.MouseEnter:Connect(function() paused = true end)
    Card.MouseLeave:Connect(function() paused = false end)

    animConn = RunService.RenderStepped:Connect(function(dt)
        if Notify.Closed then return end
        if not paused then elapsed = elapsed + dt end
        if elapsed >= duration then Notify:Close() end
    end)

    Card.Position = UDim2.fromOffset(-20, 0)
    Tween(Card, { Position = UDim2.fromOffset(0, 0) }, 0.15)

    if cfg.Sound ~= false then
        pcall(function()
            local snd = New("Sound", { SoundId = "rbxassetid://6895079853", Volume = 0.25, Parent = gui })
            snd:Play()
            task.delay(1, function() snd:Destroy() end)
        end)
    end

    return Notify
end

--// плавающий виджет-окно: draggable, внутри можно класть элементы
--// (AddToggle/AddSlider/AddColorPicker/AddButton/AddLabel/AddDropdown/AddTextBox/AddKeyPicker)
function Library:CreateWidget(cfg)
    cfg = cfg or {}
    local gui = EnsureGui()
    local Theme = Library.Theme
    local width = cfg.Width or 200

    local Root = New("Frame", {
        Name = "Widget",
        Size = UDim2.fromOffset(width, 0),
        Position = cfg.Position or UDim2.new(0.5, -width / 2, 0, 90),
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Background,
        Parent = gui,
    })
    Stroke(Root, "Outline")
    Stroke(Root, "Border", 1)
    New("Frame", { --// AccentLiner
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = Root,
    })

    local TitleBar = New("Frame", {
        Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.fromOffset(0, 1),
        BackgroundColor3 = Theme.Section,
        BorderSizePixel = 0,
        Parent = Root,
    })
    New("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = Theme.Outline,
        BorderSizePixel = 0,
        Parent = TitleBar,
    })
    local TitleLabel = Txt("TextLabel", {
        Size = UDim2.new(1, -12, 1, 0),
        Position = UDim2.fromOffset(6, 0),
        BackgroundTransparency = 1,
        Text = tostring(cfg.Name or "Widget"),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Text,
        Parent = TitleBar,
    }, 0, true)
    MakeDraggable(TitleBar, Root)

    local Content = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.fromOffset(0, 21),
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = Root,
    })
    New("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = Content,
    })
    New("UIPadding", {
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        Parent = Content,
    })

    local Widget = setmetatable({ _order = 0 }, SectionMt)
    Widget.Content = Content
    Widget.Instance = Root

    function Widget:SetVisibility(b)
        Root.Visible = b == true
    end

    function Widget:SetTitle(t)
        TitleLabel.Text = tostring(t)
    end

    return Widget
end

--// Удобный хелпер: сразу отдельное окно-Widget с ESP preview внутри (берет LocalPlayer)
--// Usage:
--//   local ESPWidget = Library:CreateESPWidget({
--//       Name = "ESP Preview", Width = 240, Height = 260,
--//       Position = UDim2.fromOffset(900, 120),
--//       PlayerName = Players.LocalPlayer.Name, UsePlayerModel = true, Model = nil,
--//       Bind = { Enable="esp_enable", Box="esp_box", Name="esp_name", Health="esp_health", Distance="esp_distance", Skeleton="esp_skeleton", BoxColor="esp_boxColor", Fill="esp_fillColor" }
--//   })
--//   ESPWidget.Preview:SetHealth(50)
function Library:CreateESPWidget(cfg)
    cfg = cfg or {}
    local w = Library:CreateWidget({
        Name = cfg.Name or "ESP Preview",
        Width = cfg.Width or 240,
        Position = cfg.Position or UDim2.new(0.5, 260, 0, 90),
    })
    local preview = w:AddESPreview({
        Height = cfg.Height or 260,
        PlayerName = cfg.PlayerName or (Players.LocalPlayer and Players.LocalPlayer.Name or "Player"),
        HealthValue = cfg.HealthValue or 100,
        Distance = cfg.Distance or 134,
        Tag = cfg.Tag or "esp preview",
        UsePlayerModel = (cfg.UsePlayerModel ~= false), -- // по умолчанию true, как ты просил local player
        CaptureOnce = cfg.CaptureOnce or cfg.FreezeModel or cfg.Freeze or false, -- // true = захватить 1 раз когда жив и больше не обновлять
        FreezeModel = cfg.FreezeModel,
        Freeze = cfg.Freeze,
        Once = cfg.Once,
        FrontOnly = cfg.FrontOnly,
        BoxWidth = cfg.BoxWidth or cfg.BoxW,
        BoxHeight = cfg.BoxHeight or cfg.BoxH,
        BoxX = cfg.BoxX,
        BoxY = cfg.BoxY,
        Model = cfg.Model,
        PlayerModel = cfg.PlayerModel,
        BoxColor = cfg.BoxColor,
        FillColor = cfg.FillColor,
        HealthColor = cfg.HealthColor,
        SkeletonColor = cfg.SkeletonColor,
        Bind = cfg.Bind or {
            Enable = "esp_enable",
            Box = "esp_box",
            Name = "esp_name",
            Health = "esp_health",
            Distance = "esp_distance",
            Skeleton = "esp_skeleton",
            BoxColor = "esp_boxColor",
            Fill = "esp_fillColor",
            HealthColor = "esp_healthColor",
        },
    })
    w.Preview = preview
    --// прокси-методы для удобства
    function w:SetHealth(v) preview:SetHealth(v) end
    function w:SetDistance(v) preview:SetDistance(v) end
    function w:SetPlayerName(t) preview:SetPlayerName(t) end
    function w:SetModel(m) preview:SetModel(m) end
    function w:SetBox(wd,ht,x,y) return preview:SetBox(wd,ht,x,y) end
    function w:SetBoxSize(wd,ht) return preview:SetBoxSize(wd,ht) end
    function w:SetBoxPosition(x,y) return preview:SetBoxPosition(x,y) end
    function w:GetBox() return preview:GetBox() end
    function w:GetBoxRect() return preview:GetBoxRect() end
    return w
end

function Library:CreateWindow(cfg)
    cfg = cfg or {}
    EnsureGui()
    EnsureCursor()
    local Theme = Library.Theme
    local title = cfg.Title or "UI Library"
    local size = cfg.Size or UDim2.fromOffset(620, 460)
    local toggleKey = cfg.ToggleKey or Enum.KeyCode.RightShift

    local Window = setmetatable({ Tabs = {}, Open = true, _tabOrder = 0 }, WindowMt)

    local Main = New("Frame", {
        Size = size,
        Position = UDim2.new(0.5, -size.X.Offset / 2 + WindowOffset, 0.5, -size.Y.Offset / 2 + WindowOffset),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Parent = ScreenGui,
    })
    WindowOffset = WindowOffset + 24
    Stroke(Main, "Outline")
    Stroke(Main, "Border", 1)

    New("Frame", { --// AccentLiner
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = Main,
    })
    New("Frame", { --// DarkLiner
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.fromOffset(0, 1),
        BackgroundColor3 = Theme.LightBorder,
        BorderSizePixel = 0,
        Parent = Main,
    })

    local Scale = New("UIScale", { Scale = 1, Parent = Main })

    local Topbar = New("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        Position = UDim2.fromOffset(0, 2),
        BackgroundColor3 = Theme.Section,
        BorderSizePixel = 0,
        Parent = Main,
    })
    New("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = Theme.Outline,
        BorderSizePixel = 0,
        Parent = Topbar,
    })

    local TitleLabel = Txt("TextLabel", {
        Size = UDim2.new(1, -20, 1, 0),
        Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1,
        Text = title,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Text,
        Parent = Topbar,
    }, 0, true)

    MakeDraggable(Topbar, Main)

    local Body = New("Frame", {
        Size = UDim2.new(1, 0, 1, -32),
        Position = UDim2.fromOffset(0, 32),
        BackgroundTransparency = 1,
        Parent = Main,
    })

    local Sidebar = New("Frame", {
        Size = UDim2.new(0, 140, 1, 0),
        BackgroundColor3 = Theme.Section,
        BorderSizePixel = 0,
        Parent = Body,
    })
    New("Frame", {
        Size = UDim2.new(0, 1, 1, 0),
        Position = UDim2.new(1, -1, 0, 0),
        BackgroundColor3 = Theme.Outline,
        BorderSizePixel = 0,
        Parent = Sidebar,
    })

    --// статус-бокс над табами: status / cfg
    local StatusBox = New("Frame", {
        Size = UDim2.new(1, -12, 0, 34),
        Position = UDim2.fromOffset(6, 6),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        Parent = Sidebar,
    })
    Stroke(StatusBox, "Outline")
    Stroke(StatusBox, "Border", 1)

    local StatusKey = Txt("TextLabel", {
        Size = UDim2.new(0, 0, 0, 14),
        Position = UDim2.fromOffset(6, 3),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.X,
        Text = "status : ",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.TextDark,
        Parent = StatusBox,
    }, 0, false)

    local StatusValue = Txt("TextLabel", {
        Size = UDim2.new(0, 0, 0, 14),
        Position = UDim2.fromOffset(6, 0),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.X,
        Text = "undetect",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Safe,
        Parent = StatusBox,
    }, 0, false)

    local CfgKey = Txt("TextLabel", {
        Size = UDim2.new(0, 0, 0, 14),
        Position = UDim2.fromOffset(6, 17),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.X,
        Text = "cfg : ",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.TextDark,
        Parent = StatusBox,
    }, 0, false)

    local CfgValue = Txt("TextLabel", {
        Size = UDim2.new(0, 0, 0, 14),
        Position = UDim2.fromOffset(6, 17),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.X,
        Text = "-",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Text,
        Parent = StatusBox,
    }, 0, false)

    --// значения прижаты к ключам после рендера (ширина ключа зависит от шрифта)
    local function DockStatusLabels()
        local skw = StatusKey.TextBounds.X
        StatusValue.Position = UDim2.fromOffset(6 + skw, 3)
        local ckw = CfgKey.TextBounds.X
        CfgValue.Position = UDim2.fromOffset(6 + ckw, 17)
    end
    task.defer(DockStatusLabels)
    StatusKey:GetPropertyChangedSignal("TextBounds"):Connect(DockStatusLabels)
    CfgKey:GetPropertyChangedSignal("TextBounds"):Connect(DockStatusLabels)

    local SideList = New("ScrollingFrame", {
        Size = UDim2.new(1, -12, 1, -52),
        Position = UDim2.fromOffset(6, 46),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Outline,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = Sidebar,
    })
    New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = SideList })

    local Pages = New("Frame", {
        Size = UDim2.new(1, -152, 1, -12),
        Position = UDim2.fromOffset(146, 6),
        BackgroundTransparency = 1,
        Parent = Body,
    })

    Window.Main = Main
    Window.Scale = Scale
    Window.SideList = SideList
    Window.Pages = Pages
    Window.TitleLabel = TitleLabel
    Window.StatusValue = StatusValue
    Window.CfgValue = CfgValue

    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == toggleKey then
            Window:Toggle()
        end
    end)

    return Window
end

function Library:Destroy()
    if ScreenGui then
        ScreenGui:Destroy()
        ScreenGui = nil
    end
end

return Library

--[[ ===================== ПРИМЕР =====================
local Library = loadstring(readfile("library.lua"))()

local Window = Library:CreateWindow({
    Title = "FortunaVIP",
    Size = UDim2.fromOffset(620, 460),
    ToggleKey = Enum.KeyCode.RightShift,
})

Window:SetStatus("undetect")
Window:SetConfig("default")

local Wm = Library:Watermark({ Name = "FortunaVIP" })
Wm:SetDynamicTextProvider(function(fps) return "FortunaVIP / " .. fps .. "fps" end)

local Kb = Library:KeybindList({ Name = "Keybinds", Position = UDim2.fromOffset(10, 60) })
Kb:Add("F1", "Aimbot", "toggle"):Bind("aim_enable")
Kb:Add("F3", "ESP", "toggle"):Bind("esp_enable")

local Rage = Window:AddTab("Rage")
local Aimbot = Rage:AddSubTab("Aimbot")
local AimMain = Aimbot:AddSection("Main")

-- Toggle + Settings
local T = AimMain:AddToggle("aim_enable", { Text = "Enabled" })
local Wg = T:Settings()
Wg:AddSlider("aim_delay", { Text = "Delay", Min = 0, Max = 500, Default = 50 })

-- Dropdown single
AimMain:AddDropdown("aim_part", {
    Text = "Target part",
    Items = { "Head", "Torso", "Random" },
    Default = "Head",
    Callback = function(v) print("part:", v) end,
})

-- Dropdown multi
AimMain:AddDropdown("aim_multi", {
    Text = "Multi parts",
    Multi = true,
    Max = 2,
    Items = { "Head", "Torso", "LeftArm", "RightArm" },
    Default = { "Head" },
    Callback = function(arr) print("selected:", table.concat(arr, ", ")) end,
})

-- TextBox
AimMain:AddTextBox("aim_name", {
    Text = "Config name",
    Placeholder = "enter name...",
    Callback = function(text, enter) print("text:", text, "enter:", enter) end,
})

-- KeyPicker
AimMain:AddKeyPicker("aim_key", {
    Text = "Aim key",
    Default = Enum.KeyCode.E,
    Callback = function(kc, down) print("key:", kc and kc.Name, "down:", down) end,
}):Bind(function(down) print("aim key down:", down) end)

-- Button
AimMain:AddButton({ Text = "Apply", Callback = function()
    Library:Notify({ Title = "Applied", Text = "Config loaded", Type = "success", Duration = 3 })
end })

-- Notify
Library:Notify({ Title = "Loaded", Text = "Script ready", Type = "info", Duration = 5 })
Library:Notify({ Title = "Warning", Text = "Low fps detected", Type = "warning" })
Library:Notify({ Title = "Error", Text = "Something failed", Type = "error" })
--=================================================== ]]