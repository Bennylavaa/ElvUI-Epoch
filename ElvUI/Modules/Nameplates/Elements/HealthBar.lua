local E, L, V, P, G = unpack(select(2, ...)); --Import: Engine, Locales, PrivateDB, ProfileDB, GlobalDB
local NP = E:GetModule("NamePlates")
local LSM = E.Libs.LSM

--Lua functions
--WoW API / Variables

function NP:Update_HealthOnValueChanged()
	local frame = self:GetParent().UnitFrame
	if not frame.UnitType then return end -- Bugs

	NP:Update_Health(frame)
	NP:Update_HealthColor(frame)
	NP:Update_Glow(frame)
	NP:StyleFilterUpdate(frame, "UNIT_HEALTH")
end

function NP:Update_HealthColor(frame)
	if not frame.Health:IsShown() then return end

	local r, g, b
	local scale = 1

	local class = frame.UnitClass
	local classColor = CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class] or RAID_CLASS_COLORS[class]
	local useClassColor = NP.db.units[frame.UnitType].health.useClassColor
	if classColor and ((frame.UnitType == "FRIENDLY_PLAYER" and useClassColor) or (frame.UnitType == "ENEMY_PLAYER" and useClassColor)) then
		r, g, b = classColor.r, classColor.g, classColor.b
	else
		local db = self.db.colors
		local status = frame.ThreatStatus
		local inCombat = status ~= nil -- If we have threat status, we're in combat
		
		-- Check if manual tank assignment or stance-based tank detection
		local isTank = E.Role == "Tank" or (E.GetAssignedTankRole and E:GetAssignedTankRole("player"))
		
		-- Check if another tank has this mob (for off-tank coloring)
		-- Only relevant when in a group and mob is alive
		local otherTankHasAggro = false
		local inGroup = GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0
		local mobHealth = frame.oldHealthBar and frame.oldHealthBar:GetValue() or 0
		local mobIsAlive = mobHealth > 0 and (not UnitIsDead(frame.unit or ""))
		
		if inGroup and mobIsAlive and isTank and status and status < 3 then -- We're a tank but don't have aggro
			-- Check if the mob's target is another assigned tank (not ourselves)
			if frame.unit and UnitExists(frame.unit.."target") then
				local targetName = UnitName(frame.unit.."target")
				-- Only color purple if target is another tank (not self) and is a player
				if targetName and targetName ~= E.myname and UnitIsPlayer(frame.unit.."target") then
					if E.db.general.tankAssignments and E.db.general.tankAssignments[targetName] then
						-- The mob is targeting another assigned tank
						otherTankHasAggro = true
					end
				end
			end
		end
		
		-- Use threat colors when in combat and setting is enabled
		if status and NP.db.threat.useThreatColor and inCombat then
			if otherTankHasAggro then
				-- Another tank has aggro - use purple/blue color to indicate off-tank threat
				r, g, b = 0.5, 0.2, 1 -- Purple/Blue for "other tank has it"
				scale = 1
			elseif status == 3 then -- Tanking, highest threat
				if isTank then
					r, g, b = db.threat.goodColor.r, db.threat.goodColor.g, db.threat.goodColor.b -- Green for tanks
					scale = NP.db.threat.goodScale
				else
					r, g, b = db.threat.badColor.r, db.threat.badColor.g, db.threat.badColor.b -- Red for DPS
					scale = NP.db.threat.badScale
				end
			elseif status == 2 then -- High threat, not tanking
				if isTank then
					r, g, b = db.threat.badTransition.r, db.threat.badTransition.g, db.threat.badTransition.b -- Yellow/Orange for tanks losing threat
				else
					r, g, b = db.threat.goodTransition.r, db.threat.goodTransition.g, db.threat.goodTransition.b -- Yellow for DPS
				end
				scale = 1
			elseif status == 1 then -- Low threat
				if isTank then
					r, g, b = db.threat.goodTransition.r, db.threat.goodTransition.g, db.threat.goodTransition.b -- Yellow for tanks building threat
				else
					r, g, b = db.threat.badTransition.r, db.threat.badTransition.g, db.threat.badTransition.b -- Orange for DPS
				end
				scale = 1
			else -- Very low threat or no threat
				if isTank then
					r, g, b = db.threat.badColor.r, db.threat.badColor.g, db.threat.badColor.b -- Red for tanks with no threat
					scale = self.db.threat.badScale
				else
					r, g, b = db.threat.goodColor.r, db.threat.goodColor.g, db.threat.goodColor.b -- Green for DPS with no threat
					scale = self.db.threat.goodScale
				end
			end
		else
			-- Not in combat or threat coloring disabled - use reaction colors
			local reactionType = frame.UnitReaction
			if reactionType == 4 then
				r, g, b = db.reactions.neutral.r, db.reactions.neutral.g, db.reactions.neutral.b
			elseif reactionType and reactionType > 4 then
				if frame.UnitType == "FRIENDLY_PLAYER" then
					r, g, b = db.reactions.friendlyPlayer.r, db.reactions.friendlyPlayer.g, db.reactions.friendlyPlayer.b
				else
					r, g, b = db.reactions.good.r, db.reactions.good.g, db.reactions.good.b
				end
			else
				r, g, b = db.reactions.bad.r, db.reactions.bad.g, db.reactions.bad.b
			end
		end
	end

	if r ~= frame.Health.r or g ~= frame.Health.g or b ~= frame.Health.b then
		if not frame.HealthColorChanged then
			frame.Health:SetStatusBarColor(r, g, b)

			if frame.HealthColorChangeCallbacks then
				for _, cb in ipairs(frame.HealthColorChangeCallbacks) do
					cb(self, frame, r, g, b)
				end
			end
		end
		frame.Health.r, frame.Health.g, frame.Health.b = r, g, b
	end

	if frame.ThreatScale ~= scale then
		frame.ThreatScale = scale
		if frame.isTarget and self.db.useTargetScale then
			scale = scale * self.db.targetScale
		end
		self:SetFrameScale(frame, scale * (frame.ActionScale or 1))
	end
end

function NP:Update_Health(frame)
	if not frame.Health:IsShown() then return end

	local health = frame.oldHealthBar:GetValue()
	local _, maxHealth = frame.oldHealthBar:GetMinMaxValues()
	frame.Health:SetMinMaxValues(0, maxHealth)

	if frame.HealthValueChangeCallbacks then
		for _, cb in ipairs(frame.HealthValueChangeCallbacks) do
			cb(self, frame, health, maxHealth)
		end
	end

	frame.Health:SetValue(health)
	frame.FlashTexture:Point("TOPRIGHT", frame.Health:GetStatusBarTexture(), "TOPRIGHT") --idk why this fixes this

	if self.db.units[frame.UnitType].health.text.enable then
		frame.Health.Text:SetText(E:GetFormattedText(self.db.units[frame.UnitType].health.text.format, health, maxHealth))
	end
end

function NP:RegisterHealthBarCallbacks(frame, valueChangeCB, colorChangeCB)
	if valueChangeCB then
		frame.HealthValueChangeCallbacks = frame.HealthValueChangeCallbacks or {}
		tinsert(frame.HealthValueChangeCallbacks, valueChangeCB)
	end

	if colorChangeCB then
		frame.HealthColorChangeCallbacks = frame.HealthColorChangeCallbacks or {}
		tinsert(frame.HealthColorChangeCallbacks, colorChangeCB)
	end
end

function NP:Update_HealthBar(frame)
	if self.db.units[frame.UnitType].health.enable or (frame.isTarget and self.db.alwaysShowTargetHealth) then
		frame.Health:Show()
	else
		frame.Health:Hide()
	end
end

function NP:Configure_HealthBarScale(frame, scale, noPlayAnimation)
	if noPlayAnimation then
		frame.Health:SetWidth(self.db.units[frame.UnitType].health.width * scale)
		frame.Health:SetHeight(self.db.units[frame.UnitType].health.height * scale)
	else
		if frame.Health.scale:IsPlaying() then
			frame.Health.scale:Stop()
		end

		frame.Health.scale.width:SetChange(self.db.units[frame.UnitType].health.width * scale)
		frame.Health.scale.height:SetChange(self.db.units[frame.UnitType].health.height * scale)
		frame.Health.scale:Play()
	end
end

function NP:Configure_HealthBar(frame, configuring)
	local db = self.db.units[frame.UnitType].health
	local healthBar = frame.Health

	healthBar:SetPoint("TOP", frame, "TOP", 0, 0)

	if configuring then
		healthBar:SetStatusBarTexture(LSM:Fetch("statusbar", self.db.statusbar), "BORDER")

		self:Configure_HealthBarScale(frame, frame.currentScale or 1, configuring)

		E:SetSmoothing(healthBar, self.db.smoothbars)

		if db.text.enable then
			healthBar.Text:ClearAllPoints()
			healthBar.Text:Point(E.InversePoints[db.text.position], db.text.parent == "Nameplate" and frame or frame[db.text.parent], db.text.position, db.text.xOffset, db.text.yOffset)
			healthBar.Text:FontTemplate(LSM:Fetch("font", db.text.font), db.text.fontSize, db.text.fontOutline)
			healthBar.Text:Show()
		else
			healthBar.Text:Hide()
		end
	end
end

local function HealthBar_OnSizeChanged(self, width)
	local health = self:GetValue()
	local _, maxHealth = self:GetMinMaxValues()
	self:GetStatusBarTexture():SetPoint("TOPRIGHT", -(width * ((maxHealth - health) / maxHealth)), 0)
end

function NP:Construct_HealthBar(parent)
	local frame = CreateFrame("StatusBar", "$parentHealthBar", parent)
	frame:SetStatusBarTexture(LSM:Fetch("statusbar", self.db.statusbar), "BORDER")
	self:StyleFrame(frame)

	frame:SetScript("OnSizeChanged", HealthBar_OnSizeChanged)

	parent.FlashTexture = frame:CreateTexture(nil, "OVERLAY")
	parent.FlashTexture:SetTexture(LSM:Fetch("background", "ElvUI Blank"))
	parent.FlashTexture:Point("BOTTOMLEFT", frame:GetStatusBarTexture(), "BOTTOMLEFT")
	parent.FlashTexture:Point("TOPRIGHT", frame:GetStatusBarTexture(), "TOPRIGHT")
	parent.FlashTexture:Hide()

	frame.Text = frame:CreateFontString(nil, "OVERLAY")
	frame.Text:SetAllPoints(frame)
	frame.Text:SetWordWrap(false)

	frame.scale = CreateAnimationGroup(frame)
	frame.scale.width = frame.scale:CreateAnimation("Width")
	frame.scale.width:SetDuration(0.2)
	frame.scale.height = frame.scale:CreateAnimation("Height")
	frame.scale.height:SetDuration(0.2)

	frame:Hide()

	return frame
end