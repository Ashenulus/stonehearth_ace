local LootTable = require 'stonehearth.lib.loot_table.loot_table'
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local util = require 'stonehearth_ace.lib.util'

--[[
   Used to determine what loot a mob drops when it dies.  This program is for
   dynamically spcifing loot drops on existing entities!  If you want to declare loot
   constantly, then use the stonehearth:destroyed_loot_table entity data.
]]

local AceLootDropsComponent = class()

function AceLootDropsComponent:set_filter_script(filter_script, filter_args)
   self._sv._filter_script = filter_script
   self._sv._filter_args = filter_args
end

-- changed the "auto_loot = " line, also changed to use output system instead of just raw spawning items
function AceLootDropsComponent:_on_kill_event(kill_data)
   local loot_table, filter_script, filter_args = self._sv.loot_table, self._sv._filter_script, self._sv._filter_args
   if not loot_table then
      loot_table = radiant.entities.get_json(self)
      if loot_table then
         filter_script = loot_table.filter_script
         filter_args = loot_table.filter_args
      end
   end

   if loot_table then
      local location = radiant.entities.get_world_grid_location(self._entity)
      if location then
         local auto_loot, force_auto_loot
         if self._sv.auto_loot_player_id then
            auto_loot = stonehearth.client_state:get_client_gameplay_setting(self._sv.auto_loot_player_id, 'stonehearth', 'auto_loot', false)
				force_auto_loot = loot_table.force_auto_loot or self._entity:get_player_id() == self._sv.auto_loot_player_id
         end
         local town = stonehearth.town:get_town(self._sv.auto_loot_player_id)

         local quality
         if loot_table.apply_entity_quality then
            quality = radiant.entities.get_item_quality(self._entity)
         end

         if filter_script and not filter_args then
            filter_args = util.get_current_conditions_loot_table_filter_args()
         end
         local items = LootTable(loot_table, quality, filter_script, filter_args)
                           :roll_loot()
         local spawned_entities = radiant.entities.output_items(items, location, 1, 3,
               { owner = force_auto_loot and (kill_data.source or self._sv.auto_loot_player_id) or self._entity }, self._entity, kill_data.source, true).spilled

         --Add a loot command to each of the spawned items, or claim them automatically
         for id, entity in pairs(spawned_entities) do
            local target = entity
            local entity_forms = entity:get_component('stonehearth:entity_forms')
            if entity_forms then
               target = entity_forms:get_iconic_entity()
            end
            if force_auto_loot then
               stonehearth.inventory:get_inventory(self._sv.auto_loot_player_id)
                                       :add_item_if_not_full(entity)
            else
               local command_component = target:add_component('stonehearth:commands')
               command_component:add_command('stonehearth:commands:loot_item')
               if auto_loot and town then
                  town:loot_item(target)
               end
            end
         end
      end
   end
end

return AceLootDropsComponent
