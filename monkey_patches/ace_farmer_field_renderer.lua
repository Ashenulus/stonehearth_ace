local ZoneRenderer = require 'stonehearth.renderers.zone_renderer'
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local Color4 = _radiant.csg.Color4

local constants = require 'stonehearth.constants'

local FarmerFieldRenderer = require 'stonehearth.renderers.farmer_field.farmer_field_renderer'
local AceFarmerFieldRenderer = class()

local log = radiant.log.create_logger('farmer_field.renderer')

AceFarmerFieldRenderer._ace_old_initialize = FarmerFieldRenderer.initialize
function AceFarmerFieldRenderer:initialize(render_entity, datastore)
   self._water_color = Color4(constants.hydrology.DEFAULT_WATER_COLOR)

   self._farmer_field_data = radiant.entities.get_component_data(render_entity:get_entity(), 'stonehearth:farmer_field')
   self._field_types = radiant.resources.load_json('stonehearth:farmer:all_crops').field_types or {}
   self._fertilized_dirt_model = self._farmer_field_data.fertilized_dirt

   self._fertilized_nodes = {}
   self._fertilized_zone_renderer = ZoneRenderer(render_entity)
   
   self:_ace_old_initialize(render_entity, datastore)

   self._ui_view_mode = stonehearth.renderer:get_ui_mode()
   self._ui_mode_listener = radiant.events.listen(radiant, 'stonehearth:ui_mode_changed', self, self._on_ui_mode_changed)
end

AceFarmerFieldRenderer._ace_old_destroy = FarmerFieldRenderer.destroy
function AceFarmerFieldRenderer:destroy()
   self:_ace_old_destroy()

   if self._ui_mode_listener then
      self._ui_mode_listener:destroy()
      self._ui_mode_listener = nil
   end

   if self._water_signal_region_node then
      self._water_signal_region_node:destroy()
      self._water_signal_region_node = nil
   end

   self._fertilized_zone_renderer:destroy()
end

-- override instead of patching so we're not re-calling certain things
function AceFarmerFieldRenderer:_update()
   local data = self._datastore:get_data()
   local size = data.size
   self._is_rotated = (data.rotation or 0) % 2 == 1

   local field_data = self._field_types[data.field_type or 'farm'] or {}
   local color = Color4(unpack(field_data.color or {55, 187, 56, 76}))
   self._zone_renderer:set_designation_colors(color, color)

   local items = {}

   self:_update_dirt_models(data.effective_humidity_level)

   local dirt_node_array = self:_update_and_get_dirt_node_array(data)
   self._zone_renderer:set_size(size)
   self._zone_renderer:set_current_items(items)
   self._zone_renderer:set_render_nodes(dirt_node_array)

   local fertilized_node_array = self:_update_and_get_fertilized_node_array(data)
   self._fertilized_zone_renderer:set_size(size)
   self._fertilized_zone_renderer:set_current_items(items)
   self._fertilized_zone_renderer:set_render_nodes(fertilized_node_array)

   self:_render_water_signal_region(data.water_signal_region)
end

function AceFarmerFieldRenderer:_on_ui_mode_changed()
   local mode = stonehearth.renderer:get_ui_mode()

   if self._ui_view_mode ~= mode then
      self._ui_view_mode = mode

      local data = self._datastore:get_data()
      self:_render_water_signal_region(data.water_signal_region)
   end
end

function AceFarmerFieldRenderer:_in_appropriate_mode()
   return self._ui_view_mode == 'hud'
end

function AceFarmerFieldRenderer:_update_dirt_models(effective_humidity_level)
   -- check the effective water level and set the appropriate dirt models
   local levels = stonehearth.constants.farming.water_levels
   local tilled_dirt_model = 'tilled_dirt'
   local furrow_dirt_model = 'furrow_dirt'
   local rotated = self._is_rotated and '_rotated' or ''
   
   if effective_humidity_level == levels.SOME then
      if self._farmer_field_data.tilled_dirt_water_partial then
         tilled_dirt_model = 'tilled_dirt_water_partial'
      end
      if self._farmer_field_data.furrow_dirt_water_partial then
         furrow_dirt_model = 'furrow_dirt_water_partial'
      end
   elseif effective_humidity_level == levels.PLENTY or effective_humidity_level == levels.EXTRA then
      if self._farmer_field_data.tilled_dirt_water_full then
         tilled_dirt_model = 'tilled_dirt_water_full'
      end
      if self._farmer_field_data.furrow_dirt_water_full then
         furrow_dirt_model = 'furrow_dirt_water_full'
      end
   end

   -- if our water level has changed, recreate the dirt nodes
   if self._prev_water_level ~= effective_humidity_level then
      self._prev_water_level = effective_humidity_level
      self._tilled_dirt_model = self._farmer_field_data[tilled_dirt_model .. rotated] or self._farmer_field_data[tilled_dirt_model]
      self._furrow_dirt_model = self._farmer_field_data[furrow_dirt_model .. rotated] or self._farmer_field_data[furrow_dirt_model]
      for _, row in pairs(self._dirt_nodes) do
         for _, node in pairs(row) do
            node:destroy()
         end
      end
      self._dirt_nodes = {}
   end
end

function AceFarmerFieldRenderer:_render_water_signal_region(region)
   if self._water_signal_region_node then
      self._water_signal_region_node:destroy()
      self._water_signal_region_node = nil
   end

   if not self:_in_appropriate_mode() then
      return
   end

   if region then
      local material = '/stonehearth/data/horde/materials/transparent_box_nodepth.material.json'

      -- extruded apparently doesn't work with non-integer values, so we have to recreate the region
      -- but we assume it's a single box, so we can just do that from the bounds
      local bounds = region:get_bounds()
      --bounds.max.y = bounds.max.y - 0.9
      local r = Region3(Cube3(bounds)):inflated(Point3(-0.05, -0.05, -0.05))
      self._water_signal_region_node = _radiant.client.create_region_outline_node(self._entity_node,
            r, self._water_color, Color4(0, 0, 0, 0), material, 1)
         :set_casts_shadows(false)
         :set_can_query(false)
   end
end

function AceFarmerFieldRenderer:_get_fertilized_node(x, y)
   local row = self._fertilized_nodes[x]
   if not row then
      return nil
   end
   return row[y]
end

function AceFarmerFieldRenderer:_set_fertilized_node(x, y, node)
   local row = self._fertilized_nodes[x]
   if not row then
      row = {}
      self._fertilized_nodes[x] = row
   end
   row[y] = node
end

function AceFarmerFieldRenderer:_destroy_fertilized_node(x, y)
   local row = self._fertilized_nodes[x]
   if not row then
      return nil
   end
   local node = row[y]
   if node then
      node:destroy()
      row[y] = nil
   end
end

-- it makes sense at this point (with the puddles) to just override this whole function
function AceFarmerFieldRenderer:_update_and_get_dirt_node_array(data)
   local size_x = data.size.x
   local size_y = data.size.y
   local contents = data.contents
   local dirt_node_array = {}
   for x=1, size_x do
      for y=1, size_y do
         local dirt_plot = contents[x][y]
         if dirt_plot and dirt_plot.x ~= nil then -- need to check for nil for backward compatibility reasons
            local node = self:_get_dirt_node(x, y)
            if not node then
               local model = dirt_plot.overwatered_model or
                     dirt_plot.is_furrow and self._furrow_dirt_model or self._tilled_dirt_model
               node = self:_create_node(Point3(dirt_plot.x - 1.5, 0, dirt_plot.y - 1.5), model)
               self:_set_dirt_node(x, y, node)
            end
            table.insert(dirt_node_array, node)
         end
      end
   end
   return dirt_node_array
end

function AceFarmerFieldRenderer:_update_and_get_fertilized_node_array(data)
   local size_x = data.size.x
   local size_y = data.size.y
   local contents = data.contents
   local dirt_node_array = {}

   for x=1, size_x do
      for y=1, size_y do
         local dirt_plot = contents[x][y]
         if dirt_plot and dirt_plot.x ~= nil then -- need to check for nil for backward compatibility reasons
            local node = self:_get_fertilized_node(x, y)
            if not node and not dirt_plot.is_furrow and dirt_plot.is_fertilized then
               local model = self._fertilized_dirt_model
               node = self:_create_node(Point3(dirt_plot.x - 1.46, 0.05, dirt_plot.y - 1.46), model)
               self:_set_fertilized_node(x, y, node)
            end
            if node then
               if dirt_plot.is_fertilized then
                  table.insert(dirt_node_array, node)
               else
                  self:_destroy_fertilized_node(x, y)
               end
            end
         end
      end
   end

   return dirt_node_array
end

return AceFarmerFieldRenderer
