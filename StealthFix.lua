if RequiredScript == "lib/managers/group_ai_states/groupaistatebase" then
	-- scram bug fix
	local propagate_alert_original = GroupAIStateBase.propagate_alert
	function GroupAIStateBase:propagate_alert(alert_data, ...)
		if Network:is_server() and managers.groupai:state():whisper_mode() then
			if (alert_data[1] and alert_data[1] == "vo_distress") and (alert_data[3] and alert_data[3] > 200) then
				alert_data[3] = 25
			end
		end
		return propagate_alert_original(self, alert_data, ...)
	end

elseif RequiredScript == "lib/units/enemies/cop/actions/lower_body/copactionidle" then
	-- civ exclamation pos fix
	Hooks:PostHook(CopActionIdle, "update", "update_head_pos", function(self, t)
		if self._ext_anim.base_need_upd and managers.groupai:state():whisper_mode() then
		--if self._ext_anim.crouch and managers.groupai:state():whisper_mode() then
			self._ext_movement:upd_m_head_pos()
		end
	end)

elseif RequiredScript == "lib/units/weapons/raycastweaponbase" then
	-- shot through fix
	function RaycastWeaponBase.collect_hits(from, to, setup_data)
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