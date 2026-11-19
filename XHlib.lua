--[[
    XHlib - the xanhub UI library (v4)
    https://github.com/PPainez/UILibs

    Drop-in replacement for xanhub 3.x: same API, flags and config files.

        local library = loadstring(game:HttpGet("https://raw.githubusercontent.com/PPainez/UILibs/main/XHlib.lua"))()
        local section = library:AddTab("Main"):AddColumn():AddSection("Combat")
        section:AddToggle({text = "Enabled", callback = function(on) end})
        library:Init()

    Layout of this file:
      environment + theme ........ services, palette, library table
      core ....................... Create, connections, branding, accent, unload
      configs .................... save/load/delete + per-place autoload
      helpers .................... tooltip, hover, popups, fields
      controls ................... label, divider, toggle, button, bind, slider, list, box, color
      structure .................. tabs, columns, sections, warnings
      window ..................... open/close, layout, Init
      settings tab + notifications
]]

---------------------------------------------------------------- environment
local env = (type(getgenv) == "function" and getgenv()) or _G
local runService = game:GetService("RunService")
local textService = game:GetService("TextService")
local inputService = game:GetService("UserInputService")
local tweenService = game:GetService("TweenService")
local playersService = game:GetService("Players")
local httpService = game:GetService("HttpService")

-- Older scripts read these globals.
env.runService = runService
env.textService = textService
env.inputService = inputService
env.tweenService = tweenService

local previousLibrary = env.xanhub
if type(previousLibrary) ~= "table" and type(env.library) == "table" and env.library.__xanhub then
	previousLibrary = env.library
end
if type(previousLibrary) == "table" and type(previousLibrary.Unload) == "function" then
	pcall(previousLibrary.Unload, previousLibrary)
end

local DEFAULT_ACCENT = Color3.fromRGB(0, 170, 255)
local PALETTE = {
	accent = DEFAULT_ACCENT,
	background = Color3.fromRGB(10, 12, 17),
	surface = Color3.fromRGB(15, 18, 25),
	surfaceRaised = Color3.fromRGB(21, 25, 34),
	section = Color3.fromRGB(18, 21, 28),
	popup = Color3.fromRGB(24, 28, 37),
	control = Color3.fromRGB(30, 35, 46),
	controlHover = Color3.fromRGB(43, 49, 64),
	stroke = Color3.fromRGB(44, 50, 65),
	text = Color3.fromRGB(245, 247, 255),
	textOn = Color3.fromRGB(215, 220, 230),
	textOff = Color3.fromRGB(160, 166, 180),
	textMuted = Color3.fromRGB(170, 180, 198),
	border = Color3.fromRGB(4, 6, 10),
}

local FONT = Enum.Font.Code
local TEXT_SIZE = 15

local library = {
	__xanhub = true,
	brand = "xanhub",
	version = "4.0.0",
	design = "xanhub",
	tabs = {},
	draggable = true,
	flags = {},
	title = "xanhub",
	open = false,
	mousestate = inputService.MouseIconEnabled,
	popup = nil,
	instances = {},
	connections = {},
	options = {},
	notifications = {},
	cleaners = {},
	tabSize = 0,
	theme = {},
	brandLabels = {},
	foldername = "xanhub_configs",
	fileext = ".xan",
	defaultAccent = DEFAULT_ACCENT,
	palette = PALETTE,
	font = FONT,
	windowHeight = 600,
	minimumWindowWidth = 494,
	minimumColumnWidth = 220,
	preferredColumnWidth = 285,
	columnGap = 8,
	userScale = 1,
	autoScale = 1,
	-- Some executors reject GUI tweens, so property sets are the default.
	-- Motion below uses library:Animate (RenderStepped), which always works.
	enableTweens = false,
	animations = true,
	soundsEnabled = true,
	soundVolume = 0.35,
	-- Ids from Morioh-Mini. One asset can serve two kinds at different pitch.
	sounds = {
		hover = "72987896926354",
		click = "6895079853",
		toggleOn = "118671160608385",
		toggleOff = "118671160608385",
		open = "115436572186380",
		close = "115436572186380",
		tab = "6895079853",
		notify = "110872490887215",
		speed = {toggleOff = 0.82, open = 1.15, close = 0.88},
		-- Measured peaks at volume 1: notify 263, toggle 217, open 151, hover 100, click 30.
		gain = {hover = 0.55, notify = 0.55},
		-- Seconds before a fade-out; notify's asset runs 4.6s.
		maxLength = {notify = 1.5},
	},
}

-- Seed theme flags before any control exists so nothing renders unstyled.
library.flags["Menu Accent Color"] = DEFAULT_ACCENT
library.flags["UI Background"] = "None"
library.flags["Menu Background Color"] = Color3.new(0, 0, 0)
library.flags["Menu Background Color Transparency"] = 1

env.xanhub = library
env.library = library
env.uwuware = nil

library.capabilities = {
	filesystem = type(isfolder) == "function" and type(makefolder) == "function" and type(listfiles) == "function" and type(readfile) == "function" and type(writefile) == "function",
	deletefile = type(isfile) == "function" and type(delfile) == "function",
	gethui = type(gethui) == "function" or type(get_hidden_gui) == "function" or type(gethiddengui) == "function",
}

local dragging, dragInput, dragStart, startPos, dragObject

local blacklistedKeys = {
	Enum.KeyCode.Unknown, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
	Enum.KeyCode.Slash, Enum.KeyCode.Tab, Enum.KeyCode.Escape,
}
local whitelistedMouseinputs = {
	Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2, Enum.UserInputType.MouseButton3,
}

local function isClick(input)
	local kind = input.UserInputType
	return kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
end

local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
end

local function isDrag(input)
	local kind = input.UserInputType
	return kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch
end

local function textWidth(text, size)
	return textService:GetTextSize(tostring(text), size or TEXT_SIZE, FONT, Vector2.new(9e9, 9e9)).X
end

---------------------------------------------------------------------- core
function library:SafeTween(object, tweenInfo, properties)
	if not object or type(properties) ~= "table" then
		return nil
	end
	if self.enableTweens and typeof(object) == "Instance" and object.Parent then
		local ok, tween = pcall(tweenService.Create, tweenService, object, tweenInfo or TweenInfo.new(0), properties)
		if ok and tween and pcall(tween.Play, tween) then
			return tween
		end
	end
	for property, value in next, properties do
		pcall(function()
			object[property] = value
		end)
	end
	return nil
end

function library.round(num, bracket)
	if typeof(num) == "Vector2" then
		return Vector2.new(library.round(num.X), library.round(num.Y))
	elseif typeof(num) == "Vector3" then
		return Vector3.new(library.round(num.X), library.round(num.Y), library.round(num.Z))
	elseif typeof(num) == "Color3" then
		return library.round(num.R * 255), library.round(num.G * 255), library.round(num.B * 255)
	end
	num = tonumber(num) or 0
	bracket = tonumber(bracket) or 1
	if bracket == 0 then
		return num
	end
	return math.floor((num / bracket) + 0.5) * bracket
end

local function escapeRichText(value)
	return (tostring(value or "")
		:gsub("&", "&amp;")
		:gsub("<", "&lt;")
		:gsub(">", "&gt;")
		:gsub('"', "&quot;")
		:gsub("'", "&apos;"))
end

function library:FormatBrand(value)
	local textValue = tostring(value or self.title or self.brand)
	local first, last = string.find(string.lower(textValue), "xanhub", 1, true)
	if not first then
		return escapeRichText(textValue)
	end
	local r, g, b = self.round(self:GetAccent())
	return escapeRichText(string.sub(textValue, 1, first - 1))
		.. string.format('<font color="rgb(%d,%d,%d)">xan</font>', r, g, b)
		.. '<font color="rgb(255,255,255)">hub</font>'
		.. escapeRichText(string.sub(textValue, last + 1))
end

function library:FormatTitle(value)
	local titleValue = tostring(value or self.title or self.brand)
	if titleValue == "" then
		titleValue = self.brand
	end
	if not string.find(string.lower(titleValue), "xanhub", 1, true) then
		titleValue = self.brand .. "  |  " .. titleValue
	end
	return self:FormatBrand(titleValue)
end

function library:RegisterBrandLabel(label, value, formatAsTitle)
	if typeof(label) ~= "Instance" then
		return label
	end
	table.insert(self.brandLabels, {label = label, value = tostring(value or self.brand), formatAsTitle = formatAsTitle == true})
	pcall(function()
		label.RichText = true
		label.Text = formatAsTitle and self:FormatTitle(value) or self:FormatBrand(value)
	end)
	return label
end

function library:RefreshBranding()
	for index = #self.brandLabels, 1, -1 do
		local entry = self.brandLabels[index]
		local label = entry and entry.label
		if typeof(label) ~= "Instance" or label.Parent == nil then
			table.remove(self.brandLabels, index)
		else
			pcall(function()
				label.Text = entry.formatAsTitle and self:FormatTitle(entry.value) or self:FormatBrand(entry.value)
			end)
		end
	end
end

function library:AddThemeObject(object)
	if typeof(object) == "Instance" then
		table.insert(self.theme, object)
	end
	return object
end

function library:GetAccent()
	return self.flags["Menu Accent Color"] or self.defaultAccent
end

function library:SetAccent(color)
	if typeof(color) ~= "Color3" then
		return false
	end
	self.flags["Menu Accent Color"] = color
	if self.currentTab and self.currentTab.button then
		pcall(function()
			self.currentTab.button.TextColor3 = color
		end)
	end
	for index = #self.theme, 1, -1 do
		local object = self.theme[index]
		if typeof(object) ~= "Instance" or object.Parent == nil then
			table.remove(self.theme, index)
		else
			pcall(function()
				if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
					object.TextColor3 = color
				elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
					object.ImageColor3 = color
				elseif object:IsA("UIStroke") then
					object.Color = color
				else
					object.BackgroundColor3 = color
				end
			end)
		end
	end
	for _, option in next, self.options do
		if option.type == "list" and option.refresh then
			pcall(option.refresh)
		end
	end
	self:RefreshBranding()
	return true
end

function library:SetTitle(value)
	self.title = tostring(value or self.brand)
	if self.titleLabel then
		for _, entry in ipairs(self.brandLabels) do
			if entry.label == self.titleLabel then
				entry.value = self.title
				break
			end
		end
		pcall(function()
			self.titleLabel.Text = self:FormatTitle(self.title)
		end)
	end
	return self.title
end

function library:Invoke(callback, ...)
	if type(callback) ~= "function" then
		return false, "callback is not a function"
	end
	local ok, result = pcall(callback, ...)
	if not ok then
		warn("[xanhub] Callback error: " .. tostring(result))
	end
	return ok, result
end

local DRAWING_CLASSES = {Square = true, Line = true, Text = true, Quad = true, Circle = true, Triangle = true}

function library:Create(class, properties)
	properties = properties or {}
	if not class or self.unloaded then
		return nil
	end

	local isDrawing = DRAWING_CLASSES[class] == true
	if isDrawing and (typeof(Drawing) ~= "table" or type(Drawing.new) ~= "function") then
		return nil
	end

	local ok, inst = pcall(function()
		return (isDrawing and Drawing or Instance).new(class)
	end)
	if not ok or not inst then
		warn("[xanhub] Unable to create " .. tostring(class) .. ": " .. tostring(inst))
		return nil
	end

	for property, value in next, properties do
		if property ~= "Parent" then
			local set, err = pcall(function()
				inst[property] = value
			end)
			if not set then
				warn("[xanhub] Skipped unsupported property " .. tostring(property) .. " on " .. tostring(class) .. ": " .. tostring(err))
			end
		end
	end
	if properties.Parent ~= nil then
		local set, err = pcall(function()
			inst.Parent = properties.Parent
		end)
		if not set then
			warn("[xanhub] Failed to parent " .. tostring(class) .. ": " .. tostring(err))
		end
	end

	table.insert(self.instances, {object = inst, method = isDrawing})
	return inst
end

function library:AddConnection(signal, name, callback)
	callback = type(name) == "function" and name or callback
	if not signal or type(callback) ~= "function" then
		return nil
	end
	local ok, connection = pcall(signal.Connect, signal, callback)
	if not ok then
		warn("[xanhub] Failed to connect signal: " .. tostring(connection))
		return nil
	end
	if type(name) == "string" then
		if self.connections[name] then
			pcall(function() self.connections[name]:Disconnect() end)
		end
		self.connections[name] = connection
	else
		table.insert(self.connections, connection)
	end
	return connection
end

function library:AddCleanup(callback)
	if type(callback) ~= "function" then
		return nil
	end
	table.insert(self.cleaners, callback)
	return callback
end

function library:RemoveCleanup(callback)
	local index = table.find(self.cleaners, callback)
	if index then
		table.remove(self.cleaners, index)
		return true
	end
	return false
end

function library:SetTweening(enabled)
	self.enableTweens = enabled == true
	return self.enableTweens
end

------------------------------------------------------------ motion + sound
-- Weak keys: an animation keyed on a destroyed instance must not pin it.
local animationTokens = setmetatable({}, {__mode = "k"})

local function easeOut(alpha)
	local inverse = 1 - alpha
	return 1 - inverse * inverse * inverse
end

-- Runs apply(0..1, eased) over `duration`. A new call with the same key
-- supersedes the old one, whose onDone then never runs.
function library:Animate(key, duration, apply, onDone)
	local token = (animationTokens[key] or 0) + 1
	animationTokens[key] = token
	if not self.animations or self.unloaded or (tonumber(duration) or 0) <= 0 then
		pcall(apply, 1)
		if onDone then onDone() end
		return
	end
	local started = os.clock()
	local connection
	connection = runService.RenderStepped:Connect(function()
		if animationTokens[key] ~= token or self.unloaded then
			connection:Disconnect()
			return
		end
		local alpha = math.clamp((os.clock() - started) / duration, 0, 1)
		local ok, err = pcall(apply, easeOut(alpha))
		if not ok or alpha >= 1 then
			connection:Disconnect()
			if not ok then
				warn("[xanhub] Animation failed: " .. tostring(err))
			end
			if onDone then onDone() end
		end
	end)
end

function library:StopAnimation(key)
	animationTokens[key] = (animationTokens[key] or 0) + 1
end

local function fadeColor(object, property, target, duration)
	if not object then return end
	local from = object[property]
	library:Animate(object, duration or 0.12, function(t)
		object[property] = from:Lerp(target, t)
	end)
end

local soundCache = {}
local lastSoundAt = {}

function library:PlaySound(kind)
	if not self.soundsEnabled or self.unloaded then
		return
	end
	-- Quiet while the menu builds and autoloads, so it does not burst.
	if not self.readyAt or os.clock() - self.readyAt < 1 then
		return
	end
	local id = self.sounds[kind]
	if type(id) == "number" then
		id = tostring(id)
	end
	if type(id) ~= "string" or id == "" then
		return
	end
	if tonumber(id) then
		id = "rbxassetid://" .. id
	end
	-- One play per kind per 80ms; hover sweeps and toggle cascades collapse.
	local now = os.clock()
	if now - (lastSoundAt[kind] or 0) < 0.08 then
		return
	end
	lastSoundAt[kind] = now

	local sound = soundCache[kind]
	if not sound or not sound.Parent then
		sound = self:Create("Sound", {Name = "xanhub_" .. kind, Parent = game:GetService("SoundService")})
		soundCache[kind] = sound
	end
	if not sound then
		return
	end
	local gain = tonumber(self.sounds.gain and self.sounds.gain[kind]) or 1
	local volume = (tonumber(self.soundVolume) or 0.35) * gain
	pcall(function()
		sound.SoundId = id
		sound.Volume = volume
		sound.PlaybackSpeed = tonumber(self.sounds.speed and self.sounds.speed[kind]) or 1
		sound:Play()
	end)

	local limit = tonumber(self.sounds.maxLength and self.sounds.maxLength[kind])
	if limit then
		local playedAt = now
		task.delay(limit, function()
			-- A newer play of this kind owns the sound now.
			if lastSoundAt[kind] ~= playedAt or not sound.Parent then
				return
			end
			-- Volume fades whether or not animations are on: a hard cut clicks.
			local started = os.clock()
			while sound.Parent and lastSoundAt[kind] == playedAt do
				local alpha = (os.clock() - started) / 0.3
				if alpha >= 1 then
					pcall(sound.Stop, sound)
					break
				end
				sound.Volume = volume * (1 - alpha)
				runService.Heartbeat:Wait()
			end
		end)
	end
end

function library:Unload()
	if self.unloaded then
		return false
	end
	self.unloaded = true
	self.open = false
	dragging, dragInput, dragObject = false, nil, nil

	pcall(function()
		inputService.MouseIconEnabled = self.mousestate
	end)

	-- Let enabled features shut themselves off first.
	for _, option in next, self.options do
		if option.type == "toggle" and option.state and option.SetState then
			pcall(option.SetState, option, false)
		end
	end

	for index = #self.cleaners, 1, -1 do
		local cleaner = self.cleaners[index]
		self.cleaners[index] = nil
		if type(cleaner) == "function" then
			local ok, err = pcall(cleaner)
			if not ok then
				warn("[xanhub] Cleanup error: " .. tostring(err))
			end
		end
	end

	for key, connection in next, self.connections do
		pcall(function() connection:Disconnect() end)
		self.connections[key] = nil
	end

	for index = #self.instances, 1, -1 do
		local item = self.instances[index]
		if item and item.object then
			pcall(function()
				if item.method then
					item.object:Remove()
				else
					item.object:Destroy()
				end
			end)
		end
		self.instances[index] = nil
	end

	if self.base then
		pcall(function() self.base:Destroy() end)
	end

	self.notifications = {}
	self.brandLabels = {}
	self.popup, self.slider, self.warning = nil, nil, nil
	self.base, self.main, self.uiScale, self.top, self.currentTab = nil, nil, nil, nil, nil
	self.initialized, self.hasInit, self.ready = false, false, false

	if env.xanhub == self then env.xanhub = nil end
	if env.library == self then env.library = nil end
	if env.uwuware == self then env.uwuware = nil end
	return true
end

library.Destroy = library.Unload

------------------------------------------------------------------- configs
function library:GetConfigs()
	if not self.capabilities.filesystem then
		return {}
	end
	local ok, result = pcall(function()
		if not isfolder(self.foldername) then
			makefolder(self.foldername)
		end
		local files = {}
		for _, path in next, listfiles(self.foldername) do
			if path:sub(-#self.fileext) == self.fileext then
				local name = path:gsub("\\", "/"):match("([^/]+)$") or path
				name = name:sub(1, #name - #self.fileext)
				if name ~= "" and name ~= "autoload" then
					table.insert(files, name)
				end
			end
		end
		table.sort(files)
		return files
	end)
	return ok and result or {}
end

function library:NormalizeConfigName(name)
	return (tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("[^%w%-%_ ]", ""):sub(1, 64))
end

function library:ResolveConfigName(name)
	name = self:NormalizeConfigName(name)
	if name ~= "" then
		return name
	end
	local listOption = self.options["Config List"]
	if listOption and type(listOption.value) == "string" and listOption.value ~= "" then
		return self:NormalizeConfigName(listOption.value)
	end
	for _, flag in ipairs({"Config List", "Config Name"}) do
		local value = self.flags[flag]
		if type(value) == "string" and value ~= "" then
			return self:NormalizeConfigName(value)
		end
	end
	return self:GetConfigs()[1] or ""
end

function library:RefreshConfigList(selectName)
	local configOption = self.options["Config List"]
	local configs = self:GetConfigs()
	if not configOption or not configOption.hasInit then
		return configs
	end

	for _, config in ipairs(configs) do
		if not table.find(configOption.values, config) then
			configOption:AddValue(config)
		end
	end
	for index = #configOption.values, 1, -1 do
		local existing = configOption.values[index]
		if not table.find(configs, existing) then
			configOption:RemoveValue(existing)
		end
	end

	selectName = self:NormalizeConfigName(selectName)
	if selectName ~= "" and table.find(configs, selectName) then
		configOption:SetValue(selectName, true)
	elseif type(configOption.value) == "string" and table.find(configs, configOption.value) then
		configOption:SetValue(configOption.value, true)
	elseif configs[1] then
		configOption:SetValue(configs[1], true)
	end
	return configs
end

-- Autoload is per PlaceId: the file name carries the place, so other games never load it.
function library:GetAutoloadPath(placeId)
	return self.foldername .. "/autoload_" .. tostring(tonumber(placeId) or game.PlaceId) .. ".txt"
end

function library:GetAutoloadConfig(placeId)
	if not self.capabilities.filesystem then
		return nil
	end
	local path = self:GetAutoloadPath(placeId)
	local ok, name = pcall(function()
		if not isfile(path) then
			return nil
		end
		local trimmed = self:NormalizeConfigName(readfile(path))
		return trimmed ~= "" and trimmed or nil
	end)
	return ok and name or nil
end

function library:SetAutoloadConfig(config, placeId)
	if not self.capabilities.filesystem then
		return false, "filesystem unavailable"
	end
	config = self:NormalizeConfigName(config)
	if config == "" then
		return false, "invalid config name"
	end
	if not table.find(self:GetConfigs(), config) then
		return false, "config does not exist"
	end
	local ok, err = pcall(function()
		if not isfolder(self.foldername) then
			makefolder(self.foldername)
		end
		writefile(self:GetAutoloadPath(placeId), config)
	end)
	if ok then
		self:UpdateAutoloadLabel()
	end
	return ok, err
end

function library:ClearAutoloadConfig(placeId)
	if not self.capabilities.filesystem then
		return false
	end
	local path = self:GetAutoloadPath(placeId)
	local ok = pcall(function()
		if isfile(path) then
			if self.capabilities.deletefile then
				delfile(path)
			else
				writefile(path, "")
			end
		end
	end)
	if ok then
		self:UpdateAutoloadLabel()
	end
	return ok
end

function library:UpdateAutoloadLabel()
	if not self.autoloadStatus then
		return
	end
	local name = self:GetAutoloadConfig()
	if name then
		self.autoloadStatus.Text = "Auto load (place " .. tostring(game.PlaceId) .. "): " .. name
	else
		self.autoloadStatus.Text = "Auto load: none for this place"
	end
end

function library:TryAutoloadConfig()
	if not self.capabilities.filesystem then
		return false, "filesystem unavailable"
	end
	local name = self:GetAutoloadConfig()
	if not name then
		return false, "no autoload for this place"
	end
	local ok, result = self:LoadConfig(name)
	if ok then
		self:SendNotification(2, "Autoloaded '" .. name .. "' for place " .. tostring(game.PlaceId))
	end
	return ok, result
end

local function configToggleEnabled(saved)
	if saved == true or saved == 1 or saved == "1" then
		return true
	elseif saved == false or saved == 0 or saved == "0" then
		return false
	end
	return nil
end

function library:ApplyConfigData(configData)
	if type(configData) ~= "table" then
		return false, "invalid config data"
	end
	local applied = 0
	for _, option in pairs(self.options) do
		if option.hasInit and option.type ~= "button" and option.flag and not option.skipflag then
			local saved = configData[option.flag]
			local ok = pcall(function()
				if option.type == "toggle" then
					local enabled = configToggleEnabled(saved)
					if enabled ~= nil then
						option:SetState(enabled)
						applied += 1
					end
				elseif saved == nil then
					return
				elseif option.type == "color" then
					option:SetColor(saved)
					local transparency = configData[option.flag .. " Transparency"]
					if option.trans and transparency ~= nil then
						option:SetTrans(transparency)
					end
					applied += 1
				elseif option.type == "bind" then
					option:SetKey(saved)
					applied += 1
				elseif option.SetValue then
					option:SetValue(saved)
					applied += 1
				else
					self.flags[option.flag] = saved
					applied += 1
				end
			end)
			if not ok then
				self.flags[option.flag] = saved
			end
		end
	end
	return applied > 0, applied
end

function library:CreateConfig(config)
	if not self.capabilities.filesystem then return false, "filesystem unavailable" end
	config = self:NormalizeConfigName(config)
	if config == "" then return false, "invalid config name" end
	local ok, err = pcall(function()
		if not isfolder(self.foldername) then makefolder(self.foldername) end
		local path = self.foldername .. "/" .. config .. self.fileext
		-- Never clobber an existing config with an empty one.
		if not (type(isfile) == "function" and isfile(path)) then
			writefile(path, "{}")
		end
	end)
	if ok then
		self:RefreshConfigList(config)
	end
	return ok, err
end

function library:DeleteConfig(config)
	if not self.capabilities.deletefile then return false, "deletefile unavailable" end
	config = self:NormalizeConfigName(config)
	if config == "" then return false, "invalid config name" end
	local ok, err = pcall(function()
		local path = self.foldername .. "/" .. config .. self.fileext
		if isfile(path) then delfile(path) end
	end)
	if ok then
		if self:GetAutoloadConfig() == config then
			self:ClearAutoloadConfig()
		end
		self:RefreshConfigList()
	end
	return ok, err
end

function library:LoadConfig(config)
	if not self.capabilities.filesystem then
		return false, "filesystem unavailable"
	end
	config = self:ResolveConfigName(config)
	if config == "" then
		return false, "no config selected"
	end
	if not table.find(self:GetConfigs(), config) then
		return false, "config not found"
	end
	local ok, configData = pcall(function()
		return httpService:JSONDecode(readfile(self.foldername .. "/" .. config .. self.fileext))
	end)
	if not ok or type(configData) ~= "table" then
		return false, "config file is invalid"
	end
	local applied, count = self:ApplyConfigData(configData)
	if not applied then
		return false, "config is empty or incompatible"
	end
	self:RefreshConfigList(config)
	return true, count
end

function library:SaveConfig(config)
	if not self.capabilities.filesystem then return false, "filesystem unavailable" end
	config = self:ResolveConfigName(config)
	if config == "" then return false, "no config selected" end

	local data = {}
	for _, option in pairs(self.options) do
		if option.type ~= "button" and option.flag and not option.skipflag then
			if option.type == "toggle" then
				data[option.flag] = option.state and 1 or 0
			elseif option.type == "color" then
				data[option.flag] = {option.color.R, option.color.G, option.color.B}
				if option.trans then data[option.flag .. " Transparency"] = option.trans end
			elseif option.type == "bind" then
				if option.key ~= "none" then data[option.flag] = option.key end
			else
				data[option.flag] = option.value
			end
		end
	end

	local ok, err = pcall(function()
		if not isfolder(self.foldername) then makefolder(self.foldername) end
		writefile(self.foldername .. "/" .. config .. self.fileext, httpService:JSONEncode(data))
	end)
	if ok then
		self:RefreshConfigList(config)
	end
	return ok, err
end

------------------------------------------------------------------- helpers
local function corner(parent, radius)
	return library:Create("UICorner", {CornerRadius = UDim.new(0, radius or 3), Parent = parent})
end

local function stroke(parent, color)
	return library:Create("UIStroke", {
		Color = color or PALETTE.stroke,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- A rounded, outlined control surface. Returns the object and its outline.
local function field(class, properties)
	properties.BackgroundColor3 = properties.BackgroundColor3 or PALETTE.control
	properties.BorderSizePixel = 0
	local object = library:Create(class, properties)
	corner(object, 3)
	return object, stroke(object)
end

local function label(properties)
	properties.BackgroundTransparency = 1
	properties.Font = properties.Font or FONT
	properties.TextSize = properties.TextSize or TEXT_SIZE
	properties.TextColor3 = properties.TextColor3 or PALETTE.textOn
	properties.TextXAlignment = properties.TextXAlignment or Enum.TextXAlignment.Left
	return library:Create("TextLabel", properties)
end

-- Converts an input position into the ScreenGui's own offset space.
function library:ToGuiSpace(position)
	local origin = self.base and self.base.AbsolutePosition or Vector2.zero
	return Vector2.new(position.X, position.Y) - origin
end

function library:ShowTooltip(text, position)
	local tip = self.tooltip
	if not tip or not text or text == "" then
		return
	end
	tip.Text = tostring(text)
	local width = textWidth(tip.Text) + 14
	tip.Size = UDim2.fromOffset(width, 22)
	local point = self:ToGuiSpace(position)
	local screen = self.base.AbsoluteSize
	tip.Position = UDim2.fromOffset(
		math.clamp(point.X + 16, 4, math.max(4, screen.X - width - 4)),
		math.clamp(point.Y + 20, 4, math.max(4, screen.Y - 26))
	)
end

function library:HideTooltip()
	if self.tooltip then
		self.tooltip.Position = UDim2.new(2, 0, 2, 0)
	end
end

-- Reads option.tip on every event so scripts can change tips after creation.
local function bindTooltip(option, object)
	object.InputBegan:Connect(function(input)
		if isMove(input) and option.tip then
			library:ShowTooltip(option.tip, input.Position)
		end
	end)
	object.InputChanged:Connect(function(input)
		if isMove(input) and option.tip then
			library:ShowTooltip(option.tip, input.Position)
		end
	end)
	object.InputEnded:Connect(function(input)
		if isMove(input) then
			library:HideTooltip()
		end
	end)
end

local function bindHover(object, outline, keepLit)
	object.InputBegan:Connect(function(input)
		if isMove(input) and not library.warning and not library.slider then
			fadeColor(outline, "Color", library:GetAccent(), 0.1)
		end
	end)
	object.InputEnded:Connect(function(input)
		if isMove(input) and not (keepLit and keepLit()) then
			fadeColor(outline, "Color", PALETTE.stroke, 0.15)
		end
	end)
end

-- Grows a popup open from zero height; it clips its content while growing.
local popupTargets = setmetatable({}, {__mode = "k"})

local function growOpen(holder, targetSize)
	-- Placement uses the final size so the popup does not flip mid-grow.
	popupTargets[holder] = Vector2.new(targetSize.X.Offset, targetSize.Y.Offset)
	holder.ClipsDescendants = true
	library:Animate(holder, 0.16, function(t)
		holder.Size = UDim2.fromOffset(targetSize.X.Offset, math.floor(targetSize.Y.Offset * t + 0.5))
	end)
end

-- Popups live on the ScreenGui root and track their anchor every frame, so
-- they stay attached while the window is dragged or a column scrolls.
function library:PlacePopup(holder, anchor, alignRight)
	if not self.base or not anchor or not anchor.Parent then
		return
	end
	local origin = self.base.AbsolutePosition
	local position = anchor.AbsolutePosition - origin
	local size = anchor.AbsoluteSize
	local holderSize = popupTargets[holder] or holder.AbsoluteSize
	local screen = self.base.AbsoluteSize
	local x = alignRight and (position.X + size.X - holderSize.X) or position.X
	local y = position.Y + size.Y + 4
	if y + holderSize.Y > screen.Y - 4 then
		y = position.Y - holderSize.Y - 4
	end
	holder.Position = UDim2.fromOffset(
		math.clamp(x, 4, math.max(4, screen.X - holderSize.X - 4)),
		math.max(4, y)
	)
end

function library:OpenPopup(option, holder, anchor, alignRight)
	if self.popup and self.popup ~= option then
		self.popup:Close()
	end
	self.popup = option
	option.open = true
	option.reposition = function()
		self:PlacePopup(holder, anchor, alignRight)
	end
	holder.Visible = true
	option.reposition()
	if self.popupCatcher then
		self.popupCatcher.Visible = true
	end
end

function library:ClosePopup(option)
	if self.popup == option then
		self.popup = nil
	end
	option.open = false
	if self.popupCatcher and not self.popup then
		self.popupCatcher.Visible = false
	end
end

local function decimalsOf(step)
	local text = string.format("%.10f", step):gsub("0+$", "")
	local dot = text:find(".", 1, true)
	return dot and (#text - dot) or 0
end

local function formatNumber(value, step)
	local decimals = decimalsOf(step)
	if decimals == 0 then
		return tostring(math.floor(value + 0.5))
	end
	return string.format("%." .. decimals .. "f", value)
end

local function displayKey(key)
	if key == "none" then
		return "NONE"
	end
	local text = key
	if text:match("Mouse") then
		text = text:gsub("Button", ""):gsub("Mouse", "M")
	else
		text = text:gsub("Left", "L"):gsub("Right", "R"):gsub("Control", "CTRL")
	end
	return text:upper()
end

------------------------------------------------------------------ controls
library.createLabel = function(option, parent)
	option.main = label({
		LayoutOrder = option.position,
		Size = UDim2.new(1, -12, 0, 20),
		TextColor3 = PALETTE.text,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Parent = parent,
	})

	local lastKey
	local function reflow()
		local main = option.main
		if not main or not main.Parent then return end
		local width = math.max(80, main.AbsoluteSize.X)
		local key = width .. "|" .. main.Text
		if key == lastKey then return end
		lastKey = key
		local bounds = textService:GetTextSize(main.Text, TEXT_SIZE, FONT, Vector2.new(width, 9e9))
		main.Size = UDim2.new(1, -12, 0, math.max(20, bounds.Y + 4))
	end

	setmetatable(option, {__newindex = function(t, i, v)
		if i == "Text" then
			option.main.Text = tostring(v)
			task.defer(reflow)
		else
			rawset(t, i, v)
		end
	end})

	library:AddConnection(option.main:GetPropertyChangedSignal("AbsoluteSize"), function()
		task.defer(reflow)
	end)
	option.Text = option.text
end

library.createDivider = function(option, parent)
	option.main = library:Create("Frame", {
		LayoutOrder = option.position,
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	library:Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 0, 1),
		BackgroundColor3 = PALETTE.stroke,
		BorderSizePixel = 0,
		Parent = option.main,
	})
	option.title = label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 0,
		BackgroundColor3 = PALETTE.section,
		BorderSizePixel = 0,
		TextColor3 = PALETTE.textMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = option.main,
	})
	-- label() forces transparency; dividers need a solid gap behind the text.
	option.title.BackgroundTransparency = 0

	setmetatable(option, {__newindex = function(t, i, v)
		if i == "Text" then
			if v then
				option.title.Text = tostring(v)
				option.title.Size = UDim2.fromOffset(textWidth(option.title.Text) + 12, 18)
				option.main.Size = UDim2.new(1, 0, 0, 18)
			else
				option.title.Text = ""
				option.title.Size = UDim2.new()
				option.main.Size = UDim2.new(1, 0, 0, 6)
			end
		else
			rawset(t, i, v)
		end
	end})
	option.Text = option.text
end

library.createToggle = function(option, parent)
	option.hasInit = true

	option.main = library:Create("Frame", {
		LayoutOrder = option.position,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Parent = parent,
	})

	local round = option.style and 6 or 2
	local box = library:Create("Frame", {
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = PALETTE.control,
		BorderSizePixel = 0,
		Parent = option.main,
	})
	corner(box, round)
	local boxStroke = stroke(box)

	local fill = library:Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundColor3 = library:GetAccent(),
		BorderSizePixel = 0,
		Visible = option.state == true,
		Parent = box,
	})
	corner(fill, math.max(1, round - 1))
	library:AddThemeObject(fill)

	option.interest = library:Create("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Parent = option.main,
	})

	option.title = label({
		Position = UDim2.fromOffset(24, 0),
		Size = UDim2.new(1, -24, 1, 0),
		Text = option.text,
		TextColor3 = option.state and PALETTE.textOn or PALETTE.textOff,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = option.interest,
	})

	option.interest.InputBegan:Connect(function(input)
		if isClick(input) then
			option:SetState(not option.state)
		end
	end)
	bindHover(option.interest, boxStroke)
	bindTooltip(option, option.interest)

	function option:SetState(state, nocallback)
		state = state == true
		local changed = state ~= (self.state == true)
		library.flags[self.flag] = state
		rawset(self, "state", state)
		fadeColor(self.title, "TextColor3", state and PALETTE.textOn or PALETTE.textOff, 0.15)
		if changed and library.readyAt then
			fill.Visible = true
			library:Animate(fill, 0.14, function(t)
				local scale = state and t or (1 - t)
				fill.Size = UDim2.new(scale, -4 * scale, scale, -4 * scale)
			end, function()
				fill.Visible = state
				fill.Size = UDim2.new(1, -4, 1, -4)
			end)
			library:PlaySound(state and "toggleOn" or "toggleOff")
		else
			fill.Visible = state
		end
		if not nocallback then
			library:Invoke(self.callback, state)
		end
	end

	if option.state ~= nil then
		task.defer(function()
			if not library.unloaded then
				library:Invoke(option.callback, option.state)
			end
		end)
	end

	setmetatable(option, {__newindex = function(t, i, v)
		if i == "Text" then
			option.title.Text = tostring(v)
		else
			rawset(t, i, v)
		end
	end})
end

library.createButton = function(option, parent)
	option.hasInit = true

	option.main = library:Create("Frame", {
		LayoutOrder = option.position,
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Parent = parent,
	})

	local outline
	option.title, outline = field("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -12, 0, 20),
		AutoButtonColor = false,
		Text = option.text,
		TextColor3 = PALETTE.text,
		TextSize = TEXT_SIZE,
		Font = FONT,
		Parent = option.main,
	})

	option.title.InputBegan:Connect(function(input)
		if isClick(input) then
			library:PlaySound("click")
			-- Accent flash that settles back to the hover shade.
			option.title.BackgroundColor3 = library:GetAccent():Lerp(PALETTE.control, 0.55)
			fadeColor(option.title, "BackgroundColor3", PALETTE.controlHover, 0.25)
			library:Invoke(option.callback)
			if not library.unloaded then
				library.flags[option.flag] = true
			end
		elseif isMove(input) and not library.warning and not library.slider then
			fadeColor(option.title, "BackgroundColor3", PALETTE.controlHover, 0.1)
		end
	end)
	option.title.InputEnded:Connect(function(input)
		if isMove(input) then
			fadeColor(option.title, "BackgroundColor3", PALETTE.control, 0.15)
		end
	end)
	bindHover(option.title, outline)
	bindTooltip(option, option.title)
end

library.createBind = function(option, parent)
	option.hasInit = true

	local binding = false
	local loop

	if option.sub then
		option.main = option:getMain()
	else
		option.main = library:Create("Frame", {
			LayoutOrder = option.position,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Parent = parent,
		})
		option.title = label({
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.new(1, -12, 1, 0),
			Text = option.text,
			Parent = option.main,
		})
	end

	local bindinput = library:Create(option.sub and "TextButton" or "TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6 - (option.subpos or 0), 0, 2),
		Size = UDim2.fromOffset(40, 16),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 14,
		Font = FONT,
		TextColor3 = PALETTE.textOff,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = option.main,
	})
	if option.sub then
		bindinput.AutoButtonColor = false
	end
	option.bindinput = bindinput

	local interest = option.sub and bindinput or option.main
	interest.InputEnded:Connect(function(input)
		if isClick(input) and not binding then
			library:PlaySound("click")
			binding = true
			bindinput.Text = "[...]"
			bindinput.Size = UDim2.fromOffset(textWidth(bindinput.Text, 14) + 2, 16)
			bindinput.TextColor3 = library:GetAccent()
		end
	end)
	bindTooltip(option, interest)

	local function release()
		if loop then
			loop:Disconnect()
			loop = nil
			library.flags[option.flag] = false
			library:Invoke(option.callback, false, 0)
		end
	end

	library:AddConnection(inputService.InputBegan, function(input)
		if binding then
			local kind = input.UserInputType
			if table.find(whitelistedMouseinputs, kind) and not option.nomouse then
				option:SetKey(kind)
			elseif kind == Enum.UserInputType.Keyboard and not table.find(blacklistedKeys, input.KeyCode) then
				option:SetKey(input.KeyCode)
			else
				option:SetKey(false) -- cancel, keep the old key
			end
			return
		end
		if option.key == "none" or library.capturingKey or inputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode.Name ~= option.key and input.UserInputType.Name ~= option.key then
			return
		end
		if option.mode == "toggle" then
			library.flags[option.flag] = not library.flags[option.flag]
			library:Invoke(option.callback, library.flags[option.flag], 0)
		else
			release()
			library.flags[option.flag] = true
			library:Invoke(option.callback, true, 0)
			loop = library:AddConnection(runService.RenderStepped, function(step)
				if not inputService:GetFocusedTextBox() then
					library:Invoke(option.callback, nil, step)
				end
			end)
		end
	end)

	library:AddConnection(inputService.InputEnded, function(input)
		if option.key ~= "none" and (input.KeyCode.Name == option.key or input.UserInputType.Name == option.key) then
			release()
		end
	end)

	function option:SetKey(key)
		binding = false
		bindinput.TextColor3 = PALETTE.textOff
		release()
		if typeof(key) == "EnumItem" then
			key = key.Name
		end
		if type(key) == "string" and key ~= "" then
			self.key = key
		end
		if self.key == "Backspace" then
			self.key = "none"
		end
		bindinput.Text = "[" .. displayKey(self.key) .. "]"
		bindinput.Size = UDim2.fromOffset(textWidth(bindinput.Text, 14) + 2, 16)
	end
	option:SetKey()
end

local function setSliderFill(option, value)
	local minimum, maximum = option.min, option.max
	local range = maximum - minimum
	local valueAlpha = math.clamp((value - minimum) / range, 0, 1)
	-- Ranges that cross zero fill outward from zero.
	local zeroAlpha = minimum >= 0 and 0 or (maximum <= 0 and 1 or math.clamp(-minimum / range, 0, 1))
	library:SafeTween(option.fill, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(math.min(valueAlpha, zeroAlpha), 0),
		Size = UDim2.fromScale(math.abs(valueAlpha - zeroAlpha), 1),
	})
end

library.createSlider = function(option, parent)
	option.hasInit = true
	local inline = option.sub or option.textpos

	if option.sub then
		option.main = option:getMain()
		option.main.Size = UDim2.new(1, 0, 0, 42)
	else
		option.main = library:Create("Frame", {
			LayoutOrder = option.position,
			Size = UDim2.new(1, 0, 0, option.textpos and 24 or 40),
			BackgroundTransparency = 1,
			Parent = parent,
		})
	end

	local outline
	option.slider, outline = field("Frame", {
		Position = UDim2.fromOffset(6, option.sub and 22 or (option.textpos and 4 or 20)),
		Size = UDim2.new(1, -12, 0, 16),
		ClipsDescendants = true,
		Parent = option.main,
	})

	option.fill = library:Create("Frame", {
		BackgroundColor3 = library:GetAccent(),
		BorderSizePixel = 0,
		Parent = option.slider,
	})
	corner(option.fill, 3)
	library:AddThemeObject(option.fill)
	library:Create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(150, 150, 150), Color3.new(1, 1, 1)),
		Rotation = -90,
		Parent = option.fill,
	})

	local function valueText()
		return (option.text == "nil" and "" or option.text .. ": ") .. formatNumber(option.value, option.float) .. option.suffix
	end

	option.title = library:Create("TextBox", {
		Position = UDim2.fromOffset(inline and 0 or 6, 0),
		Size = UDim2.new(1, inline and 0 or -12, inline and 1 or 0, inline and 0 or 18),
		BackgroundTransparency = 1,
		Text = valueText(),
		TextSize = inline and 14 or TEXT_SIZE,
		Font = FONT,
		TextColor3 = PALETTE.textOn,
		TextXAlignment = inline and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		ZIndex = 2,
		Parent = inline and option.slider or option.main,
	})

	-- Ctrl+click types an exact value; any other focus is bounced.
	local manualInput = false
	option.title.Focused:Connect(function()
		if manualInput then
			option.title.Text = formatNumber(option.value, option.float)
			option.title.CursorPosition = #option.title.Text + 1
		else
			option.title:ReleaseFocus()
		end
	end)
	option.title.FocusLost:Connect(function()
		fadeColor(outline, "Color", PALETTE.stroke, 0.15)
		if manualInput and tonumber(option.title.Text) then
			option:SetValue(tonumber(option.title.Text))
		else
			option.title.Text = valueText()
		end
		manualInput = false
	end)

	local function setFromInput(position)
		local width = option.slider.AbsoluteSize.X
		if width > 0 then
			option:SetValue(option.min + ((position.X - option.slider.AbsolutePosition.X) / width) * (option.max - option.min))
		end
	end
	option.setFromInput = setFromInput
	option.outline = outline

	local interest = inline and option.slider or option.main
	interest.InputBegan:Connect(function(input)
		if isClick(input) then
			if inputService:IsKeyDown(Enum.KeyCode.LeftControl) or inputService:IsKeyDown(Enum.KeyCode.RightControl) then
				manualInput = true
				option.title:CaptureFocus()
			else
				library.slider = option
				fadeColor(outline, "Color", library:GetAccent(), 0.1)
				setFromInput(input.Position)
			end
		end
	end)
	bindHover(interest, outline, function()
		return library.slider == option or option.title:IsFocused()
	end)
	bindTooltip(option, interest)

	function option:SetValue(value, nocallback)
		if typeof(value) ~= "number" then
			value = tonumber(value) or self.value or self.min
		end
		value = math.clamp(library.round(value, self.float), self.min, self.max)
		setSliderFill(self, value)
		library.flags[self.flag] = value
		self.value = value
		if not self.title:IsFocused() then
			self.title.Text = valueText()
		end
		if not nocallback then
			library:Invoke(self.callback, value)
		end
	end

	setSliderFill(option, option.value)
	task.defer(function()
		if not library.unloaded then
			option:SetValue(option.value)
		end
	end)
end

library.createList = function(option, parent)
	option.hasInit = true

	if option.sub then
		option.main = option:getMain()
		option.main.Size = UDim2.new(1, 0, 0, 48)
	else
		option.main = library:Create("Frame", {
			LayoutOrder = option.position,
			Size = UDim2.new(1, 0, 0, option.text == "nil" and 30 or 48),
			BackgroundTransparency = 1,
			Parent = parent,
		})
		if option.text ~= "nil" then
			option.title = label({
				Position = UDim2.fromOffset(6, 0),
				Size = UDim2.new(1, -12, 0, 18),
				Text = option.text,
				Parent = option.main,
			})
		end
	end

	local function multiText()
		local picked = {}
		for _, value in ipairs(option.values) do
			if option.value[value] then
				table.insert(picked, tostring(value))
			end
		end
		return #picked > 0 and table.concat(picked, ", ") or "-"
	end

	local outline
	option.listvalue, outline = field("TextLabel", {
		Position = UDim2.fromOffset(6, (option.text == "nil" and not option.sub) and 4 or 22),
		Size = UDim2.new(1, -12, 0, 22),
		Text = "",
		TextSize = TEXT_SIZE,
		Font = FONT,
		TextColor3 = PALETTE.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = option.main,
	})
	library:Create("UIPadding", {PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 20), Parent = option.listvalue})

	option.arrow = library:Create("ImageLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 6, 0.5, 0),
		Size = UDim2.fromOffset(8, 8),
		Rotation = 90,
		BackgroundTransparency = 1,
		Image = "rbxassetid://4918373417",
		ImageColor3 = PALETTE.text,
		ImageTransparency = 0.4,
		ScaleType = Enum.ScaleType.Fit,
		Parent = option.listvalue,
	})

	option.holder = field("TextButton", {
		ZIndex = 20,
		BackgroundColor3 = PALETTE.popup,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		Parent = library.base,
	})

	option.content = library:Create("ScrollingFrame", {
		ZIndex = 21,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollBarImageColor3 = PALETTE.stroke,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		Parent = option.holder,
	})
	local layout = library:Create("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = option.content,
	})
	library:Create("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		Parent = option.content,
	})

	local function resize()
		local count = 0
		for _ in next, option.labels do
			count += 1
		end
		local visible = math.max(1, math.min(count, option.max))
		option.holder.Size = UDim2.fromOffset(option.listvalue.AbsoluteSize.X, 8 + visible * 22 - 2)
		option.content.CanvasSize = UDim2.fromOffset(0, 8 + layout.AbsoluteContentSize.Y)
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resize)

	local function isSelected(value)
		if option.multiselect then
			return option.value[value] == true
		end
		return option.value == value
	end

	local function paint()
		local accent = library:GetAccent()
		for value, item in next, option.labels do
			local on = isSelected(value)
			item.TextColor3 = on and accent or PALETTE.textOn
			item.BackgroundTransparency = on and 0.85 or 1
		end
		option.listvalue.Text = option.multiselect and multiText() or tostring(option.value)
	end
	option.refresh = paint

	option.listvalue.InputBegan:Connect(function(input)
		if isClick(input) then
			if option.open then
				option:Close()
				return
			end
			library:PlaySound("click")
			option.arrow.Rotation = -90
			fadeColor(outline, "Color", library:GetAccent(), 0.1)
			resize()
			local target = option.holder.Size
			library:OpenPopup(option, option.holder, option.listvalue)
			growOpen(option.holder, target)
		end
	end)
	bindHover(option.listvalue, outline, function()
		return option.open
	end)
	bindTooltip(option, option.sub and option.listvalue or option.main)

	function option:AddValue(value, state)
		value = tostring(value)
		if self.labels[value] then return end
		if not table.find(self.values, value) then
			table.insert(self.values, value)
		end
		if self.multiselect and self.value[value] == nil then
			self.value[value] = state == true
		end

		local item = library:Create("TextButton", {
			ZIndex = 22,
			LayoutOrder = table.find(self.values, value) or 0,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundColor3 = library:GetAccent(),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = " " .. value,
			TextSize = TEXT_SIZE,
			Font = FONT,
			TextColor3 = PALETTE.textOn,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = self.content,
		})
		corner(item, 2)
		self.labels[value] = item

		item.InputBegan:Connect(function(input)
			if isClick(input) then
				library:PlaySound("click")
				if self.multiselect then
					self.value[value] = not self.value[value]
					self:SetValue(self.value)
				else
					self:SetValue(value)
					self:Close()
				end
			elseif isMove(input) and not isSelected(value) then
				item.BackgroundTransparency = 0.93
			end
		end)
		item.InputEnded:Connect(function(input)
			if isMove(input) and not isSelected(value) then
				item.BackgroundTransparency = 1
			end
		end)
		paint()
	end

	function option:RemoveValue(value)
		value = tostring(value)
		local item = self.labels[value]
		if not item then return end
		item:Destroy()
		self.labels[value] = nil
		local index = table.find(self.values, value)
		if index then
			table.remove(self.values, index)
		end
		if self.multiselect then
			self.value[value] = nil
			self:SetValue(self.value)
		elseif self.value == value then
			self:SetValue(self.values[1] or "")
		end
		resize()
	end

	function option:SetValue(value, nocallback)
		if self.multiselect then
			if typeof(value) ~= "table" then
				value = {}
			end
			local clean = {}
			for _, known in ipairs(self.values) do
				clean[known] = value[known] == true
			end
			self.value = clean
		else
			value = tostring(value or "")
			self.value = table.find(self.values, value) and value or self.values[1] or ""
		end
		library.flags[self.flag] = self.value
		paint()
		if not nocallback then
			library:Invoke(self.callback, self.value)
		end
	end

	function option:Close()
		library:ClosePopup(self)
		self.arrow.Rotation = 90
		self.holder.Visible = false
		fadeColor(outline, "Color", PALETTE.stroke, 0.15)
	end

	for i, value in next, option.values do
		option:AddValue(tostring(typeof(i) == "number" and value or i))
	end
	paint()
	task.defer(function()
		if not library.unloaded then
			option:SetValue(option.value)
		end
	end)
	return option
end

library.createBox = function(option, parent)
	option.hasInit = true

	option.main = library:Create("Frame", {
		LayoutOrder = option.position,
		Size = UDim2.new(1, 0, 0, option.text == "nil" and 28 or 44),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	if option.text ~= "nil" then
		option.title = label({
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.new(1, -12, 0, 18),
			Text = option.text,
			Parent = option.main,
		})
	end

	local outline
	option.holder, outline = field("Frame", {
		Position = UDim2.fromOffset(6, option.text == "nil" and 4 or 20),
		Size = UDim2.new(1, -12, 0, 20),
		Parent = option.main,
	})

	local inputvalue = library:Create("TextBox", {
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -12, 1, 0),
		BackgroundTransparency = 1,
		Text = option.value,
		PlaceholderText = option.placeholder or "",
		PlaceholderColor3 = PALETTE.textOff,
		TextSize = TEXT_SIZE,
		Font = FONT,
		TextColor3 = PALETTE.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ClearTextOnFocus = false,
		Parent = option.holder,
	})
	option.input = inputvalue

	inputvalue.Focused:Connect(function()
		fadeColor(outline, "Color", library:GetAccent(), 0.1)
		inputvalue.SelectionStart = 1
		inputvalue.CursorPosition = #inputvalue.Text + 1
	end)
	inputvalue.FocusLost:Connect(function(enter)
		fadeColor(outline, "Color", PALETTE.stroke, 0.15)
		option:SetValue(inputvalue.Text, enter)
	end)
	bindHover(inputvalue, outline, function()
		return inputvalue:IsFocused()
	end)
	bindTooltip(option, inputvalue)

	function option:SetValue(value, enter)
		if tostring(value) == "" then
			inputvalue.Text = self.value
			return
		end
		self.value = tostring(value)
		library.flags[self.flag] = self.value
		inputvalue.Text = self.value
		library:Invoke(self.callback, value, enter)
	end
	task.defer(function()
		if not library.unloaded then
			option:SetValue(option.value)
		end
	end)
end

library.createColorPickerWindow = function(option)
	local hasTrans = option.trans ~= nil
	option.mainHolder = field("TextButton", {
		ZIndex = 20,
		Size = UDim2.fromOffset(hasTrans and 200 or 184, 264),
		BackgroundColor3 = PALETTE.popup,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		Parent = library.base,
	})
	local holder = option.mainHolder

	local hue, sat, val = option.color:ToHSV()
	local editing -- "satval" | "hue" | "trans"
	local fromPicker = false

	local satval = library:Create("ImageLabel", {
		ZIndex = 21,
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, hasTrans and -28 or -12, 1, -74),
		BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
		BorderSizePixel = 0,
		Image = "rbxassetid://4155801252",
		Parent = holder,
	})
	stroke(satval)
	local satvalCursor = library:Create("Frame", {
		ZIndex = 22,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(sat, 1 - val),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = satval,
	})
	corner(satvalCursor, 3)
	stroke(satvalCursor, Color3.new(0, 0, 0))

	local hueBar = library:Create("Frame", {
		ZIndex = 21,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 6, 1, -54),
		Size = UDim2.new(1, hasTrans and -28 or -12, 0, 10),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = holder,
	})
	stroke(hueBar)
	library:Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 0, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
		}),
		Parent = hueBar,
	})
	local hueCursor = library:Create("Frame", {
		ZIndex = 22,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(1 - hue, 0),
		Size = UDim2.new(0, 2, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = hueBar,
	})
	stroke(hueCursor, Color3.new(0, 0, 0))

	local transBar, transShade, transCursor
	if hasTrans then
		transBar = library:Create("ImageLabel", {
			ZIndex = 21,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 6),
			Size = UDim2.new(0, 10, 1, -60),
			BorderSizePixel = 0,
			Image = "rbxassetid://4632082392",
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(5, 5),
			Parent = holder,
		})
		stroke(transBar)
		transShade = library:Create("ImageLabel", {
			ZIndex = 22,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = "rbxassetid://2454009026",
			ImageColor3 = Color3.fromHSV(hue, 1, 1),
			Rotation = 180,
			Parent = transBar,
		})
		transCursor = library:Create("Frame", {
			ZIndex = 23,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 1 - option.trans),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = transBar,
		})
		stroke(transCursor, Color3.new(0, 0, 0))
	end

	local function inputRow(y)
		local row = field("Frame", {
			ZIndex = 21,
			Position = UDim2.fromOffset(6, y),
			Size = UDim2.new(1, -12, 0, 20),
			Parent = holder,
		})
		return library:Create("TextBox", {
			ZIndex = 22,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			TextSize = 14,
			Font = FONT,
			TextColor3 = PALETTE.text,
			ClearTextOnFocus = false,
			Parent = row,
		})
	end
	option.rgbInput = inputRow(214)
	option.hexInput = inputRow(238)

	local function relative(object, position)
		local size = object.AbsoluteSize
		local offset = position - object.AbsolutePosition
		return math.clamp(offset.X / math.max(size.X, 1), 0, 1), math.clamp(offset.Y / math.max(size.Y, 1), 0, 1)
	end

	local function pick(position)
		local p = Vector2.new(position.X, position.Y)
		if editing == "satval" then
			local x, y = relative(satval, p)
			sat, val = x, 1 - y
		elseif editing == "hue" then
			local x = relative(hueBar, p)
			hue = 1 - math.min(x, 0.999)
		elseif editing == "trans" then
			local _, y = relative(transBar, p)
			option:SetTrans(1 - y)
			return
		else
			return
		end
		fromPicker = true
		option:SetColor(Color3.fromHSV(hue, sat, val))
		fromPicker = false
	end

	local function beginEdit(object, kind)
		object.InputBegan:Connect(function(input)
			if isClick(input) then
				editing = kind
				pick(input.Position)
			end
		end)
	end
	beginEdit(satval, "satval")
	beginEdit(hueBar, "hue")
	if transBar then
		beginEdit(transBar, "trans")
	end

	library:AddConnection(inputService.InputChanged, function(input)
		if editing and isDrag(input) then
			pick(input.Position)
		end
	end)
	-- Releasing anywhere ends the drag, not just over the bar.
	library:AddConnection(inputService.InputEnded, function(input)
		if isClick(input) then
			editing = nil
		end
	end)

	option.rgbInput.FocusLost:Connect(function()
		local r, g, b = option.rgbInput.Text:gsub("%s+", ""):match("^(%d+),(%d+),(%d+)$")
		if r then
			option:SetColor(Color3.fromRGB(math.clamp(tonumber(r), 0, 255), math.clamp(tonumber(g), 0, 255), math.clamp(tonumber(b), 0, 255)))
		else
			option:updateVisuals(option.color)
		end
	end)
	option.hexInput.FocusLost:Connect(function()
		local ok, color = pcall(Color3.fromHex, (option.hexInput.Text:gsub("[^%x]", "")))
		if ok and color then
			option:SetColor(color)
		else
			option:updateVisuals(option.color)
		end
	end)

	function option:updateVisuals(color)
		if not fromPicker then
			local h, s, v = color:ToHSV()
			-- Greys and black carry no hue; keep the last one so the bar does not jump.
			if s > 0 and v > 0 then
				hue = h
			end
			sat, val = s, v
		end
		satval.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
		if transShade then
			transShade.ImageColor3 = Color3.fromHSV(hue, 1, 1)
		end
		hueCursor.Position = UDim2.fromScale(1 - hue, 0)
		satvalCursor.Position = UDim2.fromScale(sat, 1 - val)
		local r, g, b = library.round(color)
		self.hexInput.Text = string.format("#%02x%02x%02x", r, g, b)
		self.rgbInput.Text = r .. ", " .. g .. ", " .. b
	end

	function option:updateTrans(value)
		if transCursor then
			transCursor.Position = UDim2.fromScale(0, 1 - value)
		end
	end

	option:updateVisuals(option.color)
	return option
end

library.createColor = function(option, parent)
	option.hasInit = true

	if option.sub then
		option.main = option:getMain()
	else
		option.main = library:Create("Frame", {
			LayoutOrder = option.position,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Parent = parent,
		})
		option.title = label({
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.new(1, -36, 1, 0),
			Text = option.text,
			Parent = option.main,
		})
	end

	local outline
	option.visualize, outline = field(option.sub and "TextButton" or "Frame", {
		Position = UDim2.new(1, -(option.subpos or 0) - 24, 0, 4),
		Size = UDim2.fromOffset(18, 12),
		BackgroundColor3 = option.color,
		Parent = option.main,
	})
	if option.sub then
		option.visualize.Text = ""
		option.visualize.AutoButtonColor = false
	end

	local interest = option.sub and option.visualize or option.main
	interest.InputBegan:Connect(function(input)
		if isClick(input) then
			if option.open then
				option:Close()
				return
			end
			if not option.mainHolder then
				library.createColorPickerWindow(option)
			end
			library:PlaySound("click")
			fadeColor(outline, "Color", library:GetAccent(), 0.1)
			library:OpenPopup(option, option.mainHolder, option.visualize, true)
			growOpen(option.mainHolder, UDim2.fromOffset(option.trans and 200 or 184, 264))
		end
	end)
	bindHover(interest, outline, function()
		return option.open
	end)
	bindTooltip(option, interest)

	function option:SetColor(newColor, nocallback)
		if typeof(newColor) == "table" then
			newColor = Color3.new(
				math.clamp(tonumber(newColor[1]) or 1, 0, 1),
				math.clamp(tonumber(newColor[2]) or 1, 0, 1),
				math.clamp(tonumber(newColor[3]) or 1, 0, 1)
			)
		end
		if typeof(newColor) ~= "Color3" then
			newColor = Color3.new(1, 1, 1)
		end
		self.color = newColor
		library.flags[self.flag] = newColor
		self.visualize.BackgroundColor3 = newColor
		if self.mainHolder then
			self:updateVisuals(newColor)
		end
		if not nocallback then
			library:Invoke(self.callback, newColor)
		end
	end

	if option.trans then
		function option:SetTrans(value)
			value = math.clamp(tonumber(value) or 0, 0, 1)
			self.trans = value
			library.flags[self.flag .. " Transparency"] = 1 - value
			if self.updateTrans then
				self:updateTrans(value)
			end
			library:Invoke(self.calltrans, value)
		end
		option:SetTrans(option.trans)
	end

	function option:Close()
		library:ClosePopup(self)
		if self.mainHolder then
			self.mainHolder.Visible = false
		end
		fadeColor(outline, "Color", PALETTE.stroke, 0.15)
	end

	task.defer(function()
		if not library.unloaded then
			option:SetColor(option.color)
		end
	end)
end

----------------------------------------------------------------- structure
local function flagFor(option)
	return (library.flagprefix and library.flagprefix .. " " or "") .. (option.flag or option.text)
end

-- Sub-controls share their parent's row and sit right-to-left in 24px slots.
local function addSubs(option, section, kinds, growRow)
	for _, kind in ipairs(kinds) do
		option["Add" .. kind] = function(self, sub)
			sub = typeof(sub) == "table" and sub or {}
			sub.sub = true
			if kind == "Color" or kind == "Bind" then
				sub.subpos = self.subcount * 24
			end
			function sub.getMain()
				if growRow then
					self.main.Size = UDim2.new(1, 0, 0, 40)
				end
				return self.main
			end
			self.subcount += 1
			return section["Add" .. kind](section, sub)
		end
	end
end

-- Shared registration: records the option and builds it now or at Init.
local function register(section, option, kind, creator, flagged)
	option.section = section
	option.type = kind
	option.position = #section.options
	option.canInit = option.canInit ~= false
	option.tip = option.tip and tostring(option.tip)
	if flagged then
		option.flag = flagFor(option)
		library.options[option.flag] = option
	end
	table.insert(section.options, option)

	local function build(target, parent)
		creator(target, parent)
		-- Sub-controls share their parent's row, which already has a hover sound.
		local row = target.main
		if not target.sub and kind ~= "label" and kind ~= "divider" and typeof(row) == "Instance" then
			row.MouseEnter:Connect(function()
				library:PlaySound("hover")
			end)
		end
	end

	if library.hasInit and section.hasInit then
		build(option, section.content)
	else
		option.Init = build
		-- A section that was empty at Init is built on its first option.
		if library.hasInit and section.column.hasInit and not section.hasInit then
			section:Init()
		end
	end
	return option
end

local function prepare(option)
	option = typeof(option) == "table" and option or {}
	option.text = tostring(option.text)
	option.callback = typeof(option.callback) == "function" and option.callback or function() end
	option.subcount = option.subcount or 0
	return option
end

function library:AddTab(title, pos)
	local order = tonumber(pos) or (#self.tabs + 1)
	local tab = {canInit = true, tabs = {}, columns = {}, title = tostring(title), order = order}
	local insertIndex = #self.tabs + 1
	for index, existing in ipairs(self.tabs) do
		if order < (tonumber(existing.order) or index) then
			insertIndex = index
			break
		end
	end
	table.insert(self.tabs, insertIndex, tab)

	function tab:AddColumn()
		local column = {sections = {}, position = #self.columns, canInit = true, tab = self}
		table.insert(self.columns, column)

		function column:AddSection(sectionTitle)
			local section = {title = tostring(sectionTitle), options = {}, canInit = true, column = self}
			table.insert(self.sections, section)

			function section:AddLabel(text)
				return register(self, {text = text}, "label", library.createLabel, false)
			end

			function section:AddDivider(text)
				return register(self, {text = text}, "divider", library.createDivider, false)
			end

			function section:AddToggle(option)
				option = prepare(option)
				if option.state ~= nil then
					option.state = option.state == true
				end
				option.style = option.style == 2
				addSubs(option, self, {"Color", "Bind", "List", "Slider"}, false)
				register(self, option, "toggle", library.createToggle, true)
				library.flags[option.flag] = option.state
				return option
			end

			function section:AddButton(option)
				option = prepare(option)
				addSubs(option, self, {"Bind", "Color"}, true)
				return register(self, option, "button", library.createButton, true)
			end

			function section:AddBind(option)
				option = prepare(option)
				local key = option.key
				if typeof(key) == "EnumItem" then
					key = key.Name
				end
				option.key = type(key) == "string" and key or "none"
				option.nomouse = option.nomouse == true
				option.mode = option.mode == "hold" and "hold" or "toggle"
				register(self, option, "bind", library.createBind, true)
				library.flags[option.flag] = false
				return option
			end

			function section:AddSlider(option)
				option = prepare(option)
				option.min = typeof(option.min) == "number" and option.min or 0
				option.max = typeof(option.max) == "number" and option.max or (option.min + 100)
				if option.max <= option.min then
					option.max = option.min + 1
				end
				option.value = math.clamp(typeof(option.value) == "number" and option.value or option.min, option.min, option.max)
				option.float = typeof(option.float) == "number" and math.abs(option.float) or 1
				if option.float == 0 then
					option.float = 1
				end
				option.suffix = option.suffix and tostring(option.suffix) or ""
				option.textpos = option.textpos == 2
				addSubs(option, self, {"Color", "Bind"}, false)
				register(self, option, "slider", library.createSlider, true)
				library.flags[option.flag] = option.value
				return option
			end

			function section:AddList(option)
				option = prepare(option)
				option.values = typeof(option.values) == "table" and option.values or {}
				option.multiselect = option.multiselect == true
				if option.multiselect then
					option.value = typeof(option.value) == "table" and option.value or {}
					for _, value in next, option.values do
						local key = tostring(value)
						option.value[key] = option.value[key] == true
					end
				else
					option.value = tostring(option.value or option.values[1] or "")
				end
				option.max = math.max(1, math.floor(tonumber(option.max) or 4))
				option.open = false
				option.labels = {}

				-- Pre-Init AddValue; createList replaces it with the live version.
				function option:AddValue(value, state)
					value = tostring(value)
					if not table.find(self.values, value) then
						table.insert(self.values, value)
					end
					if self.multiselect and self.value[value] == nil then
						self.value[value] = state == true
					end
				end

				addSubs(option, self, {"Color", "Bind"}, false)
				register(self, option, "list", library.createList, true)
				library.flags[option.flag] = option.value
				return option
			end

			function section:AddBox(option)
				option = prepare(option)
				option.value = tostring(option.value or "")
				register(self, option, "box", library.createBox, true)
				library.flags[option.flag] = option.value
				return option
			end

			function section:AddColor(option)
				option = prepare(option)
				if typeof(option.color) == "table" then
					option.color = Color3.new(
						math.clamp(tonumber(option.color[1]) or 1, 0, 1),
						math.clamp(tonumber(option.color[2]) or 1, 0, 1),
						math.clamp(tonumber(option.color[3]) or 1, 0, 1)
					)
				elseif typeof(option.color) ~= "Color3" then
					option.color = Color3.new(1, 1, 1)
				end
				option.calltrans = typeof(option.calltrans) == "function" and option.calltrans
					or (option.calltrans == 1 and option.callback)
					or function() end
				option.open = false
				option.trans = option.trans ~= nil and math.clamp(tonumber(option.trans) or 0, 0, 1) or nil
				option.subcount = 1
				addSubs(option, self, {"Color"}, false)
				register(self, option, "color", library.createColor, true)
				library.flags[option.flag] = option.color
				if option.trans then
					library.flags[option.flag .. " Transparency"] = option.trans
				end
				return option
			end

			function section:SetTitle(newTitle)
				self.title = tostring(newTitle)
				if self.titleText then
					self.titleText.Text = self.title
					self.titleText.Size = UDim2.fromOffset(textWidth(self.title) + 10, 3)
				end
			end

			function section:Init()
				if self.hasInit then return end
				self.hasInit = true

				self.main = library:Create("Frame", {
					BackgroundColor3 = PALETTE.section,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 20),
					Parent = column.main,
				})
				corner(self.main, 4)
				stroke(self.main)

				self.content = library:Create("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Parent = self.main,
				})

				library:AddThemeObject(library:Create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromScale(0.5, 0),
					Size = UDim2.new(1, -8, 0, 1),
					BackgroundColor3 = library:GetAccent(),
					BorderSizePixel = 0,
					Parent = self.main,
				}))

				local layout = library:Create("UIListLayout", {
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 2),
					Parent = self.content,
				})
				library:Create("UIPadding", {PaddingTop = UDim.new(0, 12), Parent = self.content})

				self.titleText = label({
					ZIndex = 2,
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromOffset(12, 0),
					Size = UDim2.fromOffset(textWidth(self.title) + 10, 3),
					Text = self.title,
					TextColor3 = PALETTE.text,
					TextXAlignment = Enum.TextXAlignment.Center,
					Parent = self.main,
				})
				self.titleText.BackgroundTransparency = 0
				self.titleText.BackgroundColor3 = PALETTE.section
				self.titleText.BorderSizePixel = 0

				library:AddConnection(layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
					if self.main then
						self.main.Size = UDim2.new(1, 0, 0, layout.AbsoluteContentSize.Y + 18)
						library:RequestLayout(column.tab)
					end
				end)

				for _, option in ipairs(self.options) do
					if option.canInit and type(option.Init) == "function" then
						local ok, err = pcall(option.Init, option, self.content)
						if not ok then
							warn("[xanhub] Failed to initialize " .. tostring(option.type) .. " '" .. tostring(option.text or option.flag) .. "': " .. tostring(err))
						end
					end
				end
			end

			if library.hasInit and self.hasInit then
				section:Init()
			end
			return section
		end

		function column:Init()
			if self.hasInit then return end
			self.hasInit = true

			self.main = library:Create("ScrollingFrame", {
				ZIndex = 2,
				Position = UDim2.fromOffset(0, 2),
				Size = UDim2.new(0, 233, 1, -4),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(),
				ScrollBarImageColor3 = PALETTE.stroke,
				ScrollBarThickness = 4,
				VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				Visible = false,
				Parent = library.columnHolder,
			})

			local layout = library:Create("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 12),
				Parent = self.main,
			})
			self.layout = layout
			library:Create("UIPadding", {
				PaddingTop = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, 2),
				PaddingRight = UDim.new(0, 2),
				Parent = self.main,
			})

			local function updateMetrics()
				if not self.main or not layout then return end
				self.contentHeight = math.max(0, layout.AbsoluteContentSize.Y + 14)
				self.main.CanvasSize = UDim2.fromOffset(0, self.contentHeight)
				if library.currentTab == self.tab then
					library:RequestLayout(self.tab)
				end
			end
			library:AddConnection(layout:GetPropertyChangedSignal("AbsoluteContentSize"), updateMetrics)

			-- A scrolled-away anchor would leave its popup floating.
			library:AddConnection(self.main:GetPropertyChangedSignal("CanvasPosition"), function()
				local popup = library.popup
				if popup and popup.section and popup.section.column == self then
					popup:Close()
				end
			end)

			for _, section in ipairs(self.sections) do
				if section.canInit and #section.options > 0 then
					local ok, err = pcall(section.Init, section)
					if not ok then
						warn("[xanhub] Failed to initialize section '" .. tostring(section.title) .. "': " .. tostring(err))
					end
				end
			end
			task.defer(updateMetrics)
		end

		if library.hasInit and self.hasInit then
			column:Init()
		end
		return column
	end

	function tab:Init()
		if self.hasInit then return end
		self.hasInit = true
		local width = textWidth(self.title) + 16

		self.button = label({
			Position = UDim2.fromOffset(library.tabSize, 22),
			Size = UDim2.fromOffset(width, 30),
			Text = self.title,
			TextColor3 = Color3.fromRGB(235, 235, 235),
			TextXAlignment = Enum.TextXAlignment.Center,
			ClipsDescendants = true,
			Visible = self.hidden ~= true,
			Parent = library.main,
		})
		if self.hidden ~= true then
			library.tabSize += width
		end

		self.button.InputBegan:Connect(function(input)
			if isClick(input) then
				library:selectTab(self)
			end
		end)

		for _, column in ipairs(self.columns) do
			if column.canInit then
				local ok, err = pcall(column.Init, column)
				if not ok then
					warn("[xanhub] Failed to initialize a column in tab '" .. tostring(self.title) .. "': " .. tostring(err))
				end
			end
		end
	end

	if self.hasInit then
		tab:Init()
	end
	return tab
end

function library:AddWarning(warning)
	warning = typeof(warning) == "table" and warning or {}
	warning.text = tostring(warning.text)
	warning.type = warning.type == "confirm" and "confirm" or ""

	local answer
	local function dialogButton(parent, text, position, value)
		local button, outline = field("TextButton", {
			ZIndex = 12,
			Position = position,
			Size = UDim2.fromOffset(100, 24),
			BackgroundColor3 = PALETTE.popup,
			Text = text,
			TextSize = 16,
			Font = FONT,
			TextColor3 = PALETTE.text,
			AutoButtonColor = false,
			Parent = parent,
		})
		bindHover(button, outline)
		button.Activated:Connect(function()
			if answer == nil then
				answer = value
			end
		end)
		return button
	end

	function warning:Show()
		answer = nil
		library.warning = warning
		if library.popup then
			library.popup:Close()
		end

		if not warning.main then
			warning.main = library:Create("TextButton", {
				ZIndex = 10,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 0.45,
				BackgroundColor3 = Color3.new(0, 0, 0),
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = false,
				Parent = library.main,
			})
			corner(warning.main, 5)
			warning.message = label({
				ZIndex = 11,
				Position = UDim2.new(0, 20, 0.5, -60),
				Size = UDim2.new(1, -40, 0, 40),
				TextSize = 16,
				TextColor3 = PALETTE.text,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = true,
				RichText = true,
				Parent = warning.main,
			})
			warning.main.Activated:Connect(function()
				if answer == nil then
					answer = false
				end
			end)
			if warning.type == "confirm" then
				dialogButton(warning.main, "Yes", UDim2.new(0.5, -105, 0.5, -10), true)
				dialogButton(warning.main, "No", UDim2.new(0.5, 5, 0.5, -10), false)
			else
				dialogButton(warning.main, "OK", UDim2.new(0.5, -50, 0.5, -10), true)
			end
		end

		warning.main.Visible = true
		warning.message.Text = warning.text

		repeat
			task.wait()
		until answer ~= nil or library.unloaded

		local result = answer == true
		warning:Close()
		library.warning = nil
		return result
	end

	function warning:Close()
		answer = nil
		if warning.main then
			warning.main.Visible = false
		end
	end

	return warning
end

-------------------------------------------------------------------- window
function library:selectTab(tab)
	if not tab or not tab.button or tab.hidden == true or tab.button.Visible == false then
		return false
	end
	if self.currentTab == tab then
		return false
	end
	if self.popup then
		self.popup:Close()
	end
	local previous = self.currentTab
	if previous then
		pcall(function()
			-- Set directly: wrappers like menu-polish recolour tabs right after this returns.
			previous.button.TextColor3 = Color3.fromRGB(235, 235, 235)
		end)
		for _, column in ipairs(self.currentTab.columns) do
			if column.main then
				column.main.Visible = false
			end
		end
	end
	self.currentTab = tab
	self:UpdateWindowLayout(tab)
	tab.button.TextColor3 = self:GetAccent()
	self:MoveTabHighlight(tab, previous ~= nil)
	for _, column in ipairs(tab.columns) do
		if column.main then
			column.main.Visible = true
		end
	end

	if previous and self.columnHolder then
		-- Content slides in from the side of the tab you moved toward.
		local direction = (table.find(self.tabs, tab) or 0) >= (table.find(self.tabs, previous) or 0) and 1 or -1
		local holder = self.columnHolder
		self:Animate(holder, 0.16, function(t)
			holder.Position = UDim2.fromOffset(5 + 14 * direction * (1 - t), 57)
		end)
		self:PlaySound("tab")
	end
	return true
end

function library:MoveTabHighlight(tab, animate)
	local highlight = self.tabHighlight
	if not highlight or not tab or not tab.button then
		return
	end
	local fromX, fromW = highlight.Position.X.Offset, highlight.Size.X.Offset
	local toX, toW = tab.button.Position.X.Offset, tab.button.Size.X.Offset
	self:Animate(highlight, animate and 0.18 or 0, function(t)
		highlight.Position = UDim2.fromOffset(fromX + (toX - fromX) * t, 50)
		highlight.Size = UDim2.fromOffset(fromW + (toW - fromW) * t, 2)
	end)
end

function library:RefreshTabBar()
	local offset = 0
	for _, tab in ipairs(self.tabs) do
		if tab.button then
			tab.button.Visible = tab.hidden ~= true
			if tab.hidden ~= true then
				tab.button.Position = UDim2.fromOffset(offset, 22)
				offset += tab.button.Size.X.Offset
			end
		end
	end
	self.tabSize = offset
	local current = self.currentTab
	if current and current.button and current.button.Visible then
		self:MoveTabHighlight(current, true)
	end
end

function library:SetTabVisible(tab, visible)
	if not tab or not tab.button then
		return false
	end
	visible = visible == true
	tab.hidden = not visible
	if not visible and self.currentTab == tab then
		for _, candidate in ipairs(self.tabs) do
			if candidate ~= tab and candidate.hidden ~= true and candidate.button then
				self:selectTab(candidate)
				break
			end
		end
		for _, column in ipairs(tab.columns) do
			if column.main then
				column.main.Visible = false
			end
		end
	elseif visible and self.currentTab == tab then
		for _, column in ipairs(tab.columns) do
			if column.main then
				column.main.Visible = true
			end
		end
	end
	self:RefreshTabBar()
	return true
end

function library:SetOpen(state)
	if self.unloaded then return false end
	state = state == true
	self.open = state

	if not state then
		dragging, dragInput, dragObject = false, nil, nil
		self.slider = nil
		if self.popup then
			pcall(function() self.popup:Close() end)
		end
		self:HideTooltip()
	end
	if self.main then
		self:AnimateWindow(state)
	end
	-- The ScreenGui stays enabled so binds and notifications keep working.
	if self.base then
		self.base.Enabled = true
	end
	pcall(function()
		inputService.MouseIconEnabled = self.mousestate
	end)
	return self.open
end

-- Open slides up into place; close slides up and hides. The resting position
-- is remembered so an interrupted animation never leaves the window offset.
function library:AnimateWindow(state)
	local main = self.main
	local rest = self.windowRest or main.Position
	self.windowRest = rest
	local function at(offset)
		main.Position = UDim2.new(rest.X.Scale, rest.X.Offset, rest.Y.Scale, rest.Y.Offset + offset)
	end
	if state then
		main.Visible = true
		self:Animate("window", 0.2, function(t)
			at(12 * (1 - t))
		end, function()
			at(0)
			self.windowRest = nil
		end)
		self:PlaySound("open")
	else
		self:Animate("window", 0.12, function(t)
			at(-8 * t)
		end, function()
			main.Visible = false
			at(0)
			self.windowRest = nil
		end)
		self:PlaySound("close")
	end
end

function library:Close()
	return self:SetOpen(not self.open)
end

function library:Toggle()
	return self:Close()
end

function library:IsInitialized()
	if self.initialized ~= true or not self.base or not self.main then
		return false
	end
	local ok, parent = pcall(function() return self.base.Parent end)
	return ok and parent ~= nil
end

function library:GetStatus()
	return {
		brand = self.brand,
		version = self.version,
		initialized = self:IsInitialized(),
		open = self.open == true,
		unloaded = self.unloaded == true,
		parent = self.uiParent,
		lastInitError = self.lastInitError,
	}
end

function library:GetViewportSize()
	local camera = workspace.CurrentCamera
	if camera then
		local ok, viewport = pcall(function() return camera.ViewportSize end)
		if ok and typeof(viewport) == "Vector2" and viewport.X > 0 and viewport.Y > 0 then
			return viewport
		end
	end
	return Vector2.new(1920, 1080)
end

function library:GetTabContentHeight(tab)
	local tallest = 0
	for _, column in ipairs(tab and tab.columns or {}) do
		local height = tonumber(column.contentHeight) or 0
		if height <= 0 and column.layout then
			height = column.layout.AbsoluteContentSize.Y + 14
		end
		tallest = math.max(tallest, height)
	end
	return tallest
end

function library:GetRequiredWindowSize(tab)
	local columnCount = math.max(1, tab and #tab.columns or 1)
	local gap = tonumber(self.columnGap) or 8
	local preferred = tonumber(self.preferredColumnWidth) or 285
	local contentWidth = 12 + columnCount * preferred + math.max(0, columnCount - 1) * gap
	local desiredWidth = math.max(contentWidth, self.minimumWindowWidth or 494, (self.tabSize or 0) + 14)

	-- Fits the screen in both directions; columns scroll instead of squashing.
	local viewport = self:GetViewportSize()
	local width = math.min(desiredWidth, math.max(320, viewport.X - 56))
	local height = math.min(tonumber(self.windowHeight) or 600, math.max(300, viewport.Y - 40))
	return Vector2.new(math.floor(width + 0.5), math.floor(height + 0.5))
end

function library:RequestLayout(tab)
	self.pendingLayoutTab = tab or self.currentTab
	if self.layoutQueued then return end
	self.layoutQueued = true
	task.defer(function()
		self.layoutQueued = false
		if not self.unloaded and self.main then
			self:UpdateWindowLayout(self.pendingLayoutTab or self.currentTab)
		end
	end)
end

function library:UpdateWindowLayout(tab)
	if not self.main then
		return false
	end
	tab = tab or self.currentTab
	local required = self:GetRequiredWindowSize(tab)
	self.main.Size = UDim2.fromOffset(required.X, required.Y)

	local columns = tab and tab.columns or {}
	local columnCount = math.max(1, #columns)
	local gap = tonumber(self.columnGap) or 8
	local holderWidth = math.max(1, required.X - 10)
	local columnWidth = math.floor((holderWidth - gap * (columnCount + 1)) / columnCount)
	columnWidth = math.max(tonumber(self.minimumColumnWidth) or 220, columnWidth)

	for index, column in ipairs(columns) do
		if column.main then
			column.main.Position = UDim2.fromOffset(gap + (index - 1) * (columnWidth + gap), 2)
			column.main.Size = UDim2.new(0, columnWidth, 1, -4)
			local contentHeight = tonumber(column.contentHeight) or 0
			column.main.CanvasSize = UDim2.fromOffset(0, contentHeight)
			column.main.ScrollBarThickness = contentHeight > math.max(0, required.Y - 64) and 4 or 0
		end
	end

	self.userScale, self.autoScale = 1, 1
	if self.uiScale then
		self.uiScale.Scale = 1
	end
	return true
end

-- Compatibility: the window resizes per axis and never scales uniformly.
function library:SetMenuScale(_)
	self:UpdateWindowLayout(self.currentTab)
	return 1
end

function library:GetMenuScale()
	return 1
end

local function findGuiParents()
	local parents = {}
	local function add(parent)
		if typeof(parent) == "Instance" and not table.find(parents, parent) then
			table.insert(parents, parent)
		end
	end
	-- pairs, not ipairs: missing getters leave holes in this table.
	for _, getter in pairs({gethui, get_hidden_gui, gethiddengui}) do
		if type(getter) == "function" then
			local ok, parent = pcall(getter)
			if ok then add(parent) end
		end
	end
	local ok, coreGui = pcall(game.GetService, game, "CoreGui")
	if ok then
		if type(cloneref) == "function" then
			local cloned, ref = pcall(cloneref, coreGui)
			if cloned and ref then coreGui = ref end
		end
		add(coreGui)
	end
	pcall(function()
		local player = playersService.LocalPlayer
		if player then
			add(player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5))
		end
	end)
	return parents
end

function library:Init()
	if self.unloaded then
		return nil, "xanhub has already been unloaded"
	end
	if self:IsInitialized() or self.initializing then
		return self
	end
	self.initializing = true
	self.lastInitError = nil

	local function traceback(message)
		return (type(debug) == "table" and type(debug.traceback) == "function") and debug.traceback(tostring(message), 2) or tostring(message)
	end

	local success, initError = xpcall(function()
		self.base = self:Create("ScreenGui", {
			Name = "xanhub_ui",
			Enabled = true,
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			DisplayOrder = 999999,
			ZIndexBehavior = Enum.ZIndexBehavior.Global,
		})
		assert(self.base, "failed to create ScreenGui")

		local parents = findGuiParents()
		for _, parent in ipairs(parents) do
			pcall(function()
				for _, child in ipairs(parent:GetChildren()) do
					if child:IsA("ScreenGui") and (child.Name == "xanhub_ui" or child.Name == "uwuware_ui") then
						child:Destroy()
					end
				end
			end)
		end

		if type(syn) == "table" and type(syn.protect_gui) == "function" then
			pcall(syn.protect_gui, self.base)
		elseif type(protectgui) == "function" then
			pcall(protectgui, self.base)
		end

		local parented, lastError = false, "no valid GUI parent was found"
		for _, parent in ipairs(parents) do
			local ok, err = pcall(function()
				self.base.Parent = parent
			end)
			if ok and self.base.Parent ~= nil then
				parented = true
				break
			end
			lastError = tostring(err)
		end
		assert(parented, "failed to parent ScreenGui: " .. lastError)

		self.main = self:Create("ImageButton", {
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(494, 600),
			BackgroundColor3 = PALETTE.background,
			BorderSizePixel = 0,
			Image = "",
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(90, 90),
			Modal = true,
			Visible = true,
			Parent = self.base,
		})
		assert(self.main, "failed to create main window")
		corner(self.main, 5)
		stroke(self.main, PALETTE.stroke)

		self.uiScale = self:Create("UIScale", {Scale = 1, Parent = self.main})

		self.top = self:Create("Frame", {
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundColor3 = PALETTE.surfaceRaised,
			BorderSizePixel = 0,
			Parent = self.main,
		})
		corner(self.top, 5)
		-- Squares off the bottom corners of the rounded header.
		self:Create("Frame", {
			Position = UDim2.new(0, 0, 1, -6),
			Size = UDim2.new(1, 0, 0, 6),
			BackgroundColor3 = PALETTE.surfaceRaised,
			BorderSizePixel = 0,
			Parent = self.top,
		})

		self.titleLabel = self:Create("TextLabel", {
			ZIndex = 3,
			Position = UDim2.fromOffset(9, 1),
			Size = UDim2.new(1, -18, 0, 21),
			BackgroundTransparency = 1,
			Text = self:FormatTitle(self.title),
			RichText = true,
			Font = Enum.Font.GothamSemibold,
			TextSize = 16,
			TextColor3 = PALETTE.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = self.main,
		})
		self:RegisterBrandLabel(self.titleLabel, self.title, true)

		self:AddThemeObject(self:Create("Frame", {
			ZIndex = 3,
			Position = UDim2.fromOffset(0, 24),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = self:GetAccent(),
			BorderSizePixel = 0,
			Parent = self.main,
		}))

		self.tabHighlight = self:Create("Frame", {
			ZIndex = 3,
			BackgroundColor3 = self:GetAccent(),
			BorderSizePixel = 0,
			Parent = self.main,
		})
		self:AddThemeObject(self.tabHighlight)

		self.columnHolder = self:Create("Frame", {
			Position = UDim2.fromOffset(5, 57),
			Size = UDim2.new(1, -10, 1, -62),
			BackgroundTransparency = 1,
			Parent = self.main,
		})

		-- Click-anywhere-to-close layer, shown only while a popup is open.
		self.popupCatcher = self:Create("TextButton", {
			ZIndex = 15,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Visible = false,
			Parent = self.base,
		})
		self.popupCatcher.Activated:Connect(function()
			if self.popup then
				self.popup:Close()
			end
			self.popupCatcher.Visible = false
		end)

		self.tooltip = self:Create("TextLabel", {
			ZIndex = 40,
			Position = UDim2.new(2, 0, 2, 0),
			BackgroundColor3 = PALETTE.popup,
			BorderSizePixel = 0,
			TextSize = TEXT_SIZE,
			Font = FONT,
			TextColor3 = PALETTE.text,
			Parent = self.base,
		})
		corner(self.tooltip, 3)
		stroke(self.tooltip)

		self:AddConnection(self.top.InputBegan, function(input)
			if isClick(input) then
				-- Settle an in-flight open/close slide before measuring the drag.
				if self.windowRest then
					self:StopAnimation("window")
					self.main.Position = self.windowRest
					self.windowRest = nil
				end
				dragObject = self.main
				dragging = true
				dragStart = input.Position
				startPos = dragObject.Position
				if self.popup then
					self.popup:Close()
				end
			end
		end)
		self:AddConnection(self.top.InputChanged, function(input)
			if dragging and isDrag(input) then
				dragInput = input
			end
		end)
		self:AddConnection(inputService.InputEnded, function(input)
			if isClick(input) then
				dragging = false
				if self.slider then
					fadeColor(self.slider.outline, "Color", PALETTE.stroke, 0.15)
					self.slider = nil
				end
			end
		end)

		local firstTab
		for _, tab in ipairs(self.tabs) do
			if tab.canInit then
				local ok, err = pcall(tab.Init, tab)
				if ok and tab.button then
					if tab.hidden == true then
						tab.button.Visible = false
					else
						firstTab = firstTab or tab
					end
				else
					warn("[xanhub] Failed to initialize tab '" .. tostring(tab.title) .. "': " .. tostring(err))
				end
			end
		end
		if firstTab then
			self:selectTab(firstTab)
		else
			self:UpdateWindowLayout(nil)
		end

		local function watchViewport()
			local camera = workspace.CurrentCamera
			if camera then
				self:AddConnection(camera:GetPropertyChangedSignal("ViewportSize"), "ViewportScale", function()
					self:UpdateWindowLayout(self.currentTab)
				end)
			end
		end
		watchViewport()
		self:AddConnection(workspace:GetPropertyChangedSignal("CurrentCamera"), "CameraScaleWatcher", function()
			task.defer(function()
				watchViewport()
				self:UpdateWindowLayout(self.currentTab)
			end)
		end)

		self:AddConnection(inputService.InputChanged, function(input)
			if not self.open or self.unloaded or not isDrag(input) then
				return
			end
			if self.slider then
				self.slider.setFromInput(input.Position)
			end
			if dragging and dragObject and self.draggable and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
				local delta = input.Position - dragStart
				self:SafeTween(dragObject, TweenInfo.new(0.08, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
					Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, math.max(-36, startPos.Y.Offset + delta.Y)),
				})
			end
		end)

		self:AddConnection(runService.RenderStepped, "PopupFollow", function()
			local popup = self.popup
			if popup and popup.reposition then
				popup.reposition()
			end
		end)

		if self.capabilities.filesystem and self.options["Config List"] then
			task.spawn(function()
				while not self.unloaded and self.base and self.base.Parent do
					task.wait(5)
					if self.unloaded then break end
					if not (self.popup == self.options["Config List"]) then
						pcall(self.RefreshConfigList, self)
					end
				end
			end)
		end

		self.open = true
		self.base.Enabled = true
		self.main.Visible = true
		self.uiParent = self.base.Parent
		pcall(function()
			inputService.MouseIconEnabled = self.mousestate
		end)
	end, traceback)

	self.initializing = false
	if not success then
		self.lastInitError = initError
		warn("[xanhub] Initialization warning: " .. tostring(initError))
		-- A late, noncritical failure still leaves a usable window.
		if self.base and self.main and self.base.Parent then
			self.hasInit, self.initialized, self.ready = true, true, true
			self:SetOpen(true)
			return self
		end
		self.hasInit, self.initialized, self.ready = false, false, false
		pcall(function()
			if self.base then self.base:Destroy() end
		end)
		self.base, self.main = nil, nil
		return nil, initError
	end

	self.hasInit, self.initialized, self.ready = true, true, true
	self:SetAccent(self:GetAccent())
	self:UpdateWindowLayout(self.currentTab)
	-- Autoload runs after every feature module has registered its options.
	pcall(function()
		self:RefreshConfigList()
		self:UpdateAutoloadLabel()
		self:TryAutoloadConfig()
	end)
	self.readyAt = os.clock()
	self:AnimateWindow(true)
	print("[xanhub " .. tostring(self.version) .. "] UI initialized | parent: " .. (self.uiParent and self.uiParent:GetFullName() or "unknown"))
	return self
end

library.Initialize = library.Init
library.Start = library.Init
library.Ready = function(self)
	return self:IsInitialized()
end

-------------------------------------------------------------- settings tab
library.SettingsTab = library:AddTab("Settings", 100)
library.SettingsColumn = library.SettingsTab:AddColumn()
library.SettingsColumn1 = library.SettingsTab:AddColumn()

library.SettingsMain = library.SettingsColumn:AddSection("Main")
library.SettingsMain:AddButton({text = "Unload xanhub", nomouse = true, callback = function()
	library:Unload()
	env.xanhub = nil
end})
library.SettingsMain:AddBind({text = "Panic Key", callback = library.options["Unload xanhub"].callback})

library.SettingsMenu = library.SettingsColumn:AddSection("Menu")
library.SettingsMenu:AddBind({text = "Open / Close", flag = "UI Toggle", nomouse = true, key = "Insert", callback = function()
	library:Close()
end})
library.SettingsMenu:AddColor({text = "Accent Color", flag = "Menu Accent Color", color = DEFAULT_ACCENT, callback = function(color)
	library:SetAccent(color)
end})
library.SettingsMenu:AddToggle({text = "Animations", flag = "UI Animations", state = true, tip = "Slide, fade and grow effects", callback = function(state)
	library.animations = state
end})
library.SettingsMenu:AddToggle({text = "UI Sounds", flag = "UI Sounds", state = true, tip = "Hover, click, toggle and open/close sounds", callback = function(state)
	library.soundsEnabled = state
end})
library.SettingsMenu:AddSlider({text = "Sound Volume", flag = "UI Sound Volume", value = 35, min = 0, max = 100, suffix = "%", callback = function(value)
	library.soundVolume = value / 100
end})

local BACKGROUNDS = {
	{"None", nil},
	{"Floral", 5553946656},
	{"Flowers", 6071575925},
	{"Circles", 6071579801},
	{"Hearts", 6073763717},
	{"Polka dots", 6214418014},
	{"Mountains", 6214412460},
	{"Zigzag", 6214416834},
	{"Zigzag 2", 6214375242},
	{"Tartan", 6214404863},
	{"Roses", 6214374619},
	{"Hexagons", 6214320051},
	{"Leopard print", 6214318622},
}
local backgroundNames, backgroundIds = {}, {}
for _, entry in ipairs(BACKGROUNDS) do
	table.insert(backgroundNames, entry[1])
	backgroundIds[entry[1]] = entry[2]
end

library.SettingsMenu:AddList({text = "Background", flag = "UI Background", max = 6, value = "None", values = backgroundNames, callback = function(value)
	if library.main then
		local id = backgroundIds[value]
		library.main.Image = id and ("rbxassetid://" .. id) or ""
	end
end}):AddColor({flag = "Menu Background Color", color = Color3.new(), trans = 1, callback = function(color)
	if library.main then
		library.main.ImageColor3 = color
	end
end, calltrans = function(value)
	if library.main then
		library.main.ImageTransparency = 1 - value
	end
end})
library.SettingsMenu:AddSlider({text = "Tile Size", value = 90, min = 50, max = 500, callback = function(value)
	if library.main then
		library.main.TileSize = UDim2.fromOffset(value, value)
	end
end})

library.ConfigSection = library.SettingsColumn1:AddSection("Configs")
if library.capabilities.filesystem then
	local function accentName(name)
		local r, g, b = library.round(library:GetAccent())
		return string.format("<font color='rgb(%d,%d,%d)'>%s</font>", r, g, b, escapeRichText(name))
	end

	library.ConfigSection:AddBox({text = "Config Name", skipflag = true})
	library.ConfigSection:AddButton({text = "Create", callback = function()
		local ok, err = library:CreateConfig(library.flags["Config Name"])
		library:SendNotification(2, ok and ("Created config " .. library:NormalizeConfigName(library.flags["Config Name"])) or ("Create failed: " .. tostring(err)))
	end})
	library.ConfigWarning = library:AddWarning({type = "confirm"})
	library.ConfigSection:AddList({text = "Configs", skipflag = true, value = "", flag = "Config List", values = library:GetConfigs()})
	library.ConfigSection:AddButton({text = "Save", callback = function()
		local name = library:ResolveConfigName(library.flags["Config List"])
		if name == "" then
			library:SendNotification(2, "Select or create a config first")
			return
		end
		library.ConfigWarning.text = "Save the current settings to config " .. accentName(name) .. "?"
		if library.ConfigWarning:Show() then
			local ok, err = library:SaveConfig(name)
			library:SendNotification(2, ok and ("Saved " .. name) or ("Save failed: " .. tostring(err)))
		end
	end})
	library.ConfigSection:AddButton({text = "Load", callback = function()
		local name = library:ResolveConfigName(library.flags["Config List"])
		if name == "" then
			library:SendNotification(2, "No config selected")
			return
		end
		library.ConfigWarning.text = "Load config " .. accentName(name) .. "?"
		if library.ConfigWarning:Show() then
			local ok, result = library:LoadConfig(name)
			library:SendNotification(2, ok and ("Loaded " .. name) or ("Load failed: " .. tostring(result)))
		end
	end})
	library.ConfigSection:AddButton({text = "Delete", callback = function()
		local name = library:ResolveConfigName(library.flags["Config List"])
		if name == "" or not table.find(library:GetConfigs(), name) then
			return
		end
		library.ConfigWarning.text = "Delete config " .. accentName(name) .. "? This cannot be undone."
		if library.ConfigWarning:Show() then
			library:DeleteConfig(name)
		end
	end})
	library.ConfigSection:AddDivider("Place Autoload")
	library.ConfigSection:AddLabel("Binds to this PlaceId only; other games ignore it")
	library.autoloadStatus = library.ConfigSection:AddLabel("Auto load: -")
	library.ConfigSection:AddButton({text = "Save + Set Autoload (this place)", callback = function()
		local name = library:ResolveConfigName(library.flags["Config List"])
		if name == "" then
			library:SendNotification(2, "Select or create a config first")
			return
		end
		if not library:SaveConfig(name) then
			library:SendNotification(3, "Save failed")
			return
		end
		local ok, err = library:SetAutoloadConfig(name)
		library:SendNotification(ok and 2 or 3, ok and ("Autoload set for place " .. tostring(game.PlaceId) .. ": " .. name) or ("Autoload failed: " .. tostring(err)))
	end})
	library.ConfigSection:AddButton({text = "Set Selected as Autoload", callback = function()
		local name = library:ResolveConfigName(library.flags["Config List"])
		local ok, err = library:SetAutoloadConfig(name)
		library:SendNotification(ok and 2 or 3, ok and ("Autoload -> " .. name .. " @ " .. tostring(game.PlaceId)) or tostring(err or "failed"))
	end})
	library.ConfigSection:AddButton({text = "Clear Autoload (this place)", callback = function()
		library:ClearAutoloadConfig()
		library:SendNotification(2, "Autoload cleared for this place")
	end})
else
	library.ConfigSection:AddLabel("Config saving is unavailable in this executor")
end

------------------------------------------------------------- notifications
local NOTIFY_WIDTH = 260

local function restackNotifications()
	local y = -10
	for index = #library.notifications, 1, -1 do
		local notification = library.notifications[index]
		local from = notification.Position
		local toY = y
		library:Animate(notification, 0.22, function(t)
			notification.Position = UDim2.new(1, from.X.Offset + (-10 - from.X.Offset) * t, 1, from.Y.Offset + (toY - from.Y.Offset) * t)
		end)
		y -= notification.Size.Y.Offset + 6
	end
end

function library:SendNotification(duration, message)
	if self.unloaded or not self.base then
		return nil
	end
	if message == nil and type(duration) == "string" then
		message, duration = duration, 2
	end
	duration = math.max(tonumber(duration) or 2, 1)
	message = tostring(message or "")

	local textHeight = textService:GetTextSize(message, 14, FONT, Vector2.new(NOTIFY_WIDTH - 16, 9e9)).Y
	local height = 30 + math.max(16, textHeight)

	local notification = self:Create("Frame", {
		ZIndex = 30,
		AnchorPoint = Vector2.new(1, 1),
		-- Starts off-screen to the right; restack slides it in.
		Position = UDim2.new(1, NOTIFY_WIDTH + 20, 1, -10),
		Size = UDim2.fromOffset(NOTIFY_WIDTH, height),
		BackgroundColor3 = PALETTE.surfaceRaised,
		BorderSizePixel = 0,
		Parent = self.base,
	})
	if not notification then
		return nil
	end
	corner(notification, 4)
	stroke(notification)

	local brand = self:Create("TextLabel", {
		ZIndex = 31,
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamSemibold,
		TextSize = 14,
		TextColor3 = PALETTE.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = notification,
	})
	self:RegisterBrandLabel(brand, self.brand)

	label({
		ZIndex = 31,
		Position = UDim2.fromOffset(8, 22),
		Size = UDim2.new(1, -16, 0, textHeight),
		Text = message,
		TextSize = 14,
		TextColor3 = PALETTE.textOn,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = notification,
	})

	local progress = self:Create("Frame", {
		ZIndex = 31,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 4, 1, -3),
		Size = UDim2.new(1, -8, 0, 2),
		BackgroundColor3 = self:GetAccent(),
		BorderSizePixel = 0,
		Parent = notification,
	})
	self:AddThemeObject(progress)

	table.insert(self.notifications, notification)
	restackNotifications()
	self:PlaySound("notify")

	-- Driven by Heartbeat rather than a tween so it animates on every executor.
	task.spawn(function()
		local started = os.clock()
		while not self.unloaded and notification.Parent do
			local alpha = (os.clock() - started) / duration
			if alpha >= 1 then
				break
			end
			progress.Size = UDim2.new(1 - alpha, -8 * (1 - alpha), 0, 2)
			runService.Heartbeat:Wait()
		end
		local index = table.find(self.notifications, notification)
		if index then
			table.remove(self.notifications, index)
		end
		if self.unloaded then
			pcall(notification.Destroy, notification)
			return
		end
		restackNotifications()
		-- Slide out to the right, then remove.
		local from = notification.Position
		self:Animate(notification, 0.2, function(t)
			notification.Position = UDim2.new(1, from.X.Offset + (NOTIFY_WIDTH + 30) * t, 1, from.Y.Offset)
		end, function()
			pcall(notification.Destroy, notification)
		end)
	end)
	return notification
end

print("[xanhub " .. tostring(library.version) .. "] library loaded")
return library
