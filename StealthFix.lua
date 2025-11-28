if RequiredScript == "lib/managers/group_ai_states/groupaistatebase" then
	-- groupaistatebase
	local propagate_alert_original = GroupAIStateBase.propagate_alert
	function GroupAIStateBase:propagate_alert(alert_data, ...)
		if Network:is_server() and managers and managers.groupai and managers.groupai:state() and managers.groupai:state():whisper_mode() then
			if (alert_data[1] and alert_data[1] == "vo_distress") and (alert_data[3] and alert_data[3] > 200) then
				alert_data[3] = 25
			end
		end
		return propagate_alert_original(self, alert_data, ...)
	end

elseif RequiredScript == "lib/units/enemies/cop/actions/lower_body/copactionidle" then
	-- copactionidle
	Hooks:PostHook(CopActionIdle, "update", "update_head_pos", function(self, t)
		if self._ext_anim.base_need_upd and managers.groupai:state():whisper_mode() then
			self._ext_movement:upd_m_head_pos()
		end
	end)

elseif RequiredScript == "lib/units/enemies/cop/copbase" then
	-- copbase

	Hooks:PostHook(CopBase, "post_init", "add_init", function(self, ...)
		if managers.groupai:state():whisper_mode() then
			self._allow_invisible = true
		end
	end)

	function CopBase:set_allow_invisible(allow)
		if managers.groupai:state():whisper_mode() then
			self._allow_invisible = allow
		end
	end

	local CopBase_set_visibility_state_original = CopBase.set_visibility_state
	function CopBase:set_visibility_state(stage)
		if not managers.groupai:state():whisper_mode() then
			return CopBase_set_visibility_state_original(self, stage, ...)
		end

		local state = stage and true

		if not state and not self._allow_invisible then
			state = true
			stage = 1
		elseif not state and self._prevent_invisible then
			stage = math.max(stage or 1, 3)
			state = true
		end

		if self._force_invisible then
			self._lod_stage = stage

			return
		end

		if self._lod_stage == stage then
			return
		end

		if self._visibility_state ~= state then
			self:_update_visibility_state(state)
		end

		if state then
			if self._unit:movement() and self._unit:movement().enable_update then
				self._unit:movement():enable_update(true)
			end
			
			if stage == 1 then
				self._unit:set_animatable_enabled(Idstring("lod1"), true)
			elseif self._lod_stage == 1 then
				self._unit:set_animatable_enabled(Idstring("lod1"), false)
			end
		end

		self:set_anim_lod(stage)

		self._lod_stage = stage

		self:chk_freeze_anims()
	end

elseif RequiredScript == "lib/units/enemies/cop/logics/coplogicidle" then
	-- coplogicidle
	Hooks:PostHook(CopLogicIdle, "_chk_relocate", "fix_follow_unit", function(data)
		if data.objective and data.objective.type == "follow" then
			local relocate = nil
			local follow_unit = data.objective.follow_unit
			local advance_pos = follow_unit:brain() and follow_unit:brain():is_advancing()
			local follow_unit_pos = advance_pos or (follow_unit:movement() and follow_unit:movement().m_newest_pos and follow_unit:movement():m_newest_pos())

			if data.objective.relocated_to and mvector3.equal(data.objective.relocated_to, follow_unit_pos) then
				return
			end

			if data.objective.distance and data.objective.distance < mvector3.distance(data.m_pos, follow_unit_pos) then
				relocate = true
			end

			if relocate then
				data.objective.in_place = nil
				data.objective.nav_seg = follow_unit:movement():nav_tracker():nav_segment()
				data.objective.relocated_to = mvector3.copy(follow_unit_pos)

				data.logic._exit(data.unit, "travel")

				return true
			end
		end
	end)

elseif RequiredScript == "lib/units/weapons/raycastweaponbase" then
	-- raycastweaponbase
	--local RaycastWeaponBase_collect_hits_original = RaycastWeaponBase.collect_hits
	function RaycastWeaponBase.collect_hits(from, to, setup_data)
		--[[if managers.groupai:state():whisper_mode() then
			return RaycastWeaponBase_collect_hits_original(from, to, setup_data)
		end--]]

		setup_data = setup_data or {}
		local ray_hits = nil
		local hit_enemy = false
		local ignore_unit = setup_data.ignore_units or {}
		local enemy_mask = setup_data.enemy_mask
		local bullet_slotmask = setup_data.bullet_slotmask or managers.slot:get_mask("bullet_impact_targets")

		if setup_data.stop_on_impact then
			ray_hits = {}
			local hit = World:raycast("ray", from, to, "slot_mask", bullet_slotmask, "ignore_unit", ignore_unit)

			if hit then
				table.insert(ray_hits, hit)

				hit_enemy = hit.unit:in_slot(enemy_mask)
			end

			return ray_hits, hit_enemy, hit_enemy and {
				[hit.unit:key()] = hit.unit
			} or nil
		end

		local can_shoot_through_wall = setup_data.can_shoot_through_wall
		local can_shoot_through_shield = setup_data.can_shoot_through_shield
		local can_shoot_through_enemy = setup_data.can_shoot_through_enemy
		local wall_mask = setup_data.wall_mask
		local shield_mask = setup_data.shield_mask
		local ai_vision_ids = Idstring("ai_vision")
		local bulletproof_ids = Idstring("bulletproof")

		if can_shoot_through_wall then
			ray_hits = World:raycast_wall("ray", from, to, "slot_mask", bullet_slotmask, "ignore_unit", ignore_unit, "thickness", 40, "thickness_mask", wall_mask)
		else
			ray_hits = World:raycast_all("ray", from, to, "slot_mask", bullet_slotmask, "ignore_unit", ignore_unit)
		end

		local unique_hits = {}
		local enemies_hit = {}
		local unit, u_key, is_enemy = nil
		local units_hit = {}
		local in_slot_func = Unit.in_slot
		local has_ray_type_func = Body.has_ray_type

		local function is_surrendered(unit) -- add dominated cop function
			local anim = unit:anim_data()
			if not anim then
				return false
			end
			
			if anim.hands_up or anim.hands_back or anim.surrender or anim.tied then
				return true
			end

			return false
		end

		for i, hit in ipairs(ray_hits) do
			unit = hit.unit
			u_key = unit:key()

			if not units_hit[u_key] then
				units_hit[u_key] = true
				unique_hits[#unique_hits + 1] = hit
				hit.hit_position = hit.position
				is_enemy = in_slot_func(unit, enemy_mask)

				if is_enemy then
					enemies_hit[u_key] = unit
					hit_enemy = true
				end

				local tweak = hit.unit:base() and hit.unit:base()._tweak_table
				if not can_shoot_through_enemy and (is_enemy or CopDamage.is_civilian(tweak) or is_surrendered(hit.unit)) then
					-- add civilian through block
					break
				elseif not can_shoot_through_shield and in_slot_func(unit, shield_mask) then
					break
				elseif not can_shoot_through_wall and in_slot_func(unit, wall_mask) and (has_ray_type_func(hit.body, ai_vision_ids) or has_ray_type_func(hit.body, bulletproof_ids)) then
					break
				end

			end
		end

		return unique_hits, hit_enemy, hit_enemy and enemies_hit or nil
	end

end