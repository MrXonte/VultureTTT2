if SERVER then
	AddCSLuaFile()	
end

SWEP.HoldType               = "knife"

if CLIENT then
	SWEP.PrintName           = "Vulture Talon"
	SWEP.Slot                = 8
	SWEP.ViewModelFlip       = false
	SWEP.ViewModelFOV        = 90
	SWEP.DrawCrosshair       = false
	
	SWEP.EquipMenuData = {
		type = "item_weapon",
		desc = "Eat bodies to destroy evidence and restore health. Also functions as a weaker version of the Traitor knife."
	};

	SWEP.Icon                = "vgui/ttt/icon_vult_knife"
	SWEP.IconLetter          = "j"
end

SWEP.Base                   = "weapon_tttbase"

SWEP.UseHands               = true
SWEP.ViewModel              = "models/weapons/cstrike/c_knife_t.mdl"
SWEP.WorldModel             = "models/weapons/w_knife_t.mdl"

SWEP.Primary.Damage         = GetConVar("ttt2_vult_talon_damage"):GetInt()
SWEP.Primary.ClipSize       = -1
SWEP.Primary.DefaultClip    = -1
SWEP.Primary.Automatic      = true
SWEP.Primary.Delay          = 1
SWEP.Primary.Ammo           = "none"

SWEP.Kind                   = WEAPON_CLASS
SWEP.AllowDrop              = false -- Is the player able to drop the swep

SWEP.IsSilent               = true

-- Pull out faster than standard guns
SWEP.DeploySpeed            = 2

--Removes the Talon on death or drop
function SWEP:OnDrop()
	self:Remove()
end

-- Override original primary attack
function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire( CurTime() + self.Primary.Delay )

	if not IsValid(self:GetOwner()) then return end

	self:GetOwner():LagCompensation(true)

	local spos = self:GetOwner():GetShootPos()
	local sdest = spos + (self:GetOwner():GetAimVector() * 70)

	local kmins = Vector(1,1,1) * -10
	local kmaxs = Vector(1,1,1) * 10

	local tr = util.TraceHull({start=spos, endpos=sdest, filter=self:GetOwner(), mask=MASK_SHOT_HULL, mins=kmins, maxs=kmaxs})

	-- Hull might hit environment stuff that line does not hit
	if not IsValid(tr.Entity) then
		tr = util.TraceLine({start=spos, endpos=sdest, filter=self:GetOwner(), mask=MASK_SHOT_HULL})
	end

	local hitEnt = tr.Entity

	-- effects
	if IsValid(hitEnt) then
		self:SendWeaponAnim( ACT_VM_MISSCENTER )

		local edata = EffectData()
		edata:SetStart(spos)
		edata:SetOrigin(tr.HitPos)
		edata:SetNormal(tr.Normal)
		edata:SetEntity(hitEnt)

		--if the entity he hit was a ragdoll
		if hitEnt:GetClass() == "prop_ragdoll" then
			-- if he hits a body spawn blood
			util.Effect("BloodImpact", edata)

			-- if he hits a body it plays a sound to alert those nearby
			EmitSound( "npc/fast_zombie/claw_strike1.wav", self:GetOwner():GetPos() )
		end
		--if the entity he hit was a player
		if hitEnt:IsPlayer() then
			-- if he hits a body spawn blood
			util.Effect("BloodImpact", edata)

			-- deal some damage to the target RAHHHH
			local dmg = DamageInfo()
			dmg:SetDamage(GetConVar("ttt2_vult_talon_damage"):GetInt())
			dmg:SetAttacker(self:GetOwner())
			dmg:SetInflictor(self)
			dmg:SetDamageForce(self:GetOwner():GetAimVector() * 5)
			dmg:SetDamagePosition(self:GetOwner():GetPos())
			dmg:SetDamageType(DMG_SLASH)

			hitEnt:DispatchTraceAttack(dmg, spos + (self:GetOwner():GetAimVector() * 3), sdest)
			
			-- make a special sound
			EmitSound( "npc/fast_zombie/claw_strike2.wav", self:GetOwner():GetPos() )
		end
	else
		self:SendWeaponAnim( ACT_VM_MISSCENTER )
	end

	if SERVER then
		self:GetOwner():SetAnimation( PLAYER_ATTACK1 )
	end
	if SERVER and tr.Hit and tr.HitNonWorld and IsValid(hitEnt) then
		if hitEnt:GetClass() == "prop_ragdoll" and not timer.Exists("ttt2_vult_talon_cooldown") then
			-- make sure the body is that of a player not a map ragdoll or whatever
			local corpsePlayer = CORPSE.GetPlayer(hitEnt)
			if (not hitEnt.player_ragdoll) or (hitEnt.player_ragdoll and hitEnt:GetNWBool("IsFakeBody") and not GetConVar("ttt2_vult_eat_fake"):GetBool()) then					
				LANG.Msg(owner, "label_vult_not_corpse", nil, MSG_MSTACK_WARN)
				return
			end

			-- if he hits a body he heals
			-- make sure health does not go above max
			local healing = GetConVar("ttt2_vult_talon_healing"):GetInt()
			if self:GetOwner():Health() + healing < self:GetOwner():GetMaxHealth() then
				self:GetOwner():SetHealth(self:GetOwner():Health() + healing)
			else
				self:GetOwner():SetHealth(self:GetOwner():GetMaxHealth())
			end

			-- if he hits a body it spawns some bones
			local myGib1 = ents.Create("prop_physics") -- make a skull prop
			myGib1:SetPos( hitEnt:GetPos() )
			myGib1:SetModel( "models/Gibs/HGIBS.mdl" )
			myGib1:Spawn()
			local myGib2 = ents.Create("prop_physics") -- make a spine prop
			myGib2:SetPos( hitEnt:GetPos() )
			myGib2:SetModel( "models/Gibs/HGIBS_spine.mdl" )
			myGib2:Spawn()
			local myGib3 = ents.Create("prop_physics") -- make a rib prop
			myGib3:SetPos( hitEnt:GetPos() )
			myGib3:SetModel( "models/Gibs/HGIBS_rib.mdl" )
			myGib3:Spawn()

			-- if he hits a body, leave a blood pool
			util.PaintDown(hitEnt:LocalToWorld(hitEnt:OBBCenter()), "Blood", hitEnt)
		 
			events.Trigger(EVENT_VULTURE_EAT, CORPSE.GetPlayerSID64(hitEnt), CORPSE.GetPlayerNick(hitEnt), self:GetOwner())
			VULTURE_DATA:AddEaten()
			-- then delete body cus he eats it  
			hitEnt:Remove()
			
			--Start the digestion timer
			STATUS:AddTimedStatus(self:GetOwner(), "ttt2_vult_cooldown_stat", GetConVar("ttt2_vult_digestion_time"):GetInt(), true)
			timer.Create("ttt2_vult_talon_cooldown", GetConVar("ttt2_vult_digestion_time"):GetInt(), 1, function()
			end)
		end
	end
	self:GetOwner():LagCompensation(false)
end
