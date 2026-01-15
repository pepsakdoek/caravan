--@ module = true

-- TODO: the category checkbox that indicates whether all items in the category
-- are selected can be incorrect after the overlay adjusts the container
-- selection. the state is in trade.current_type_a_flag, but figuring out which
-- index to modify is non-trivial.

local common = reqscript('internal/caravan/common')
local gui = require('gui')
local overlay = require('plugins.overlay')
local predicates = reqscript('internal/caravan/predicates')
local classifier = reqscript('internal/caravan/item_classifier')
local sorting = reqscript('internal/caravan/sorting')
local ethics = reqscript('internal/caravan/ethics')
local tradeoverlay = reqscript('internal/caravan/tradeoverlay')
local utils = require('utils')
local widgets = require('gui.widgets')

local trade = df.global.game.main_interface.trade

-- -------------------
-- Trade
--

LuaTrade = defclass(LuaTrade, widgets.Window)
LuaTrade.ATTRS {
    frame_title='Select trade goods',
    frame={w=150, h=47},
    resizable=true,
    resize_min={w=48, h=40},
}


local STATUS_COL_WIDTH = 7
local COUNT_COL_WIDTH = 4
local VALUE_COL_WIDTH = 6
local FILTER_HEIGHT = 18
local CLASS_COL_WIDTH = 18
local SUBCLASS_COL_WIDTH = 15
local GROUPED_COL_WIDTH = 15


function LuaTrade:init()
    self.cur_page = 1
    self.filters = {'', ''}
    self.predicate_contexts = {{name='trade_caravan'}, {name='trade_fort'}}

    self.animal_ethics = common.is_animal_lover_caravan(trade.mer)
    self.wood_ethics = common.is_tree_lover_caravan(trade.mer)
    self.banned_items = common.get_banned_items()
    self.risky_items = common.get_risky_items(self.banned_items)

    self:addviews{
        widgets.CycleHotkeyLabel{
            view_id='sort',
            frame={t=0, l=0, w=21},
            label='Sort by:',
            key='CUSTOM_SHIFT_S',
            options={
                {label='status'..common.CH_DN, value=sorting.sort_by_status_desc},
                {label='status'..common.CH_UP, value=sorting.sort_by_status_asc},
                {label='value'..common.CH_DN, value=sorting.sort_by_value_desc},
                {label='value'..common.CH_UP, value=sorting.sort_by_value_asc},
                {label='cnt'..common.CH_DN, value=sorting.sort_by_count_desc},
                {label='cnt'..common.CH_UP, value=sorting.sort_by_count_asc},
                {label='class'..common.CH_DN, value=sorting.sort_by_class_desc},
                {label='class'..common.CH_UP, value=sorting.sort_by_class_asc},
                {label='subclass'..common.CH_DN, value=sorting.sort_by_subclass_desc},
                {label='subclass'..common.CH_UP, value=sorting.sort_by_subclass_asc},
                {label='grp'..common.CH_DN, value=sorting.sort_by_grouped_desc},
                {label='grp'..common.CH_UP, value=sorting.sort_by_grouped_asc},
                {label='name'..common.CH_DN, value=sorting.sort_by_name_desc},
                {label='name'..common.CH_UP, value=sorting.sort_by_name_asc},
            },
            initial_option=sorting.sort_by_status_desc,
            on_change=self:callback('refresh_list', 'sort'),
        },
        widgets.ToggleHotkeyLabel{
            view_id='trade_bins',
            frame={t=0, l=26, w=36},
            label='Bins:',
            key='CUSTOM_SHIFT_B',
            options={
                {label='Trade bin with contents', value=true, pen=COLOR_YELLOW},
                {label='Trade contents only', value=false, pen=COLOR_GREEN},
            },
            initial_option=false,
            on_change=function() self:refresh_list() end,
        },
        widgets.TabBar{
            frame={t=2, l=0},
            labels={
                'Caravan goods',
                'Fort goods',
            },
            on_select=function(idx)
                local list = self.subviews.list
                self.filters[self.cur_page] = list:getFilter()
                list:setFilter(self.filters[idx])
                self.cur_page = idx
                self:refresh_list()
            end,
            get_cur_page=function() return self.cur_page end,
        },
        widgets.ToggleHotkeyLabel{
            view_id='filters',
            frame={t=5, l=0, w=36},
            label='Show filters:',
            key='CUSTOM_SHIFT_F',
            options={
                {label='Yes', value=true, pen=COLOR_GREEN},
                {label='No', value=false}
            },
            initial_option=false,
            on_change=function() self:updateLayout() end,
        },
        widgets.EditField{
            view_id='search',
            frame={t=5, l=40},
            label_text='Search: ',
            on_char=function(ch) return ch:match('[%l -]') end,
        },
        widgets.Panel{
            frame={t=7, l=0, r=0, h=FILTER_HEIGHT},
            frame_style=gui.FRAME_INTERIOR,
            visible=function() return self.subviews.filters:getOptionValue() end,
            on_layout=function()
                local panel_frame = self.subviews.list_panel.frame
                if self.subviews.filters:getOptionValue() then
                    panel_frame.t = 7 + FILTER_HEIGHT + 1
                else
                    panel_frame.t = 7
                end
            end,
            subviews={
                widgets.Panel{
                    frame={t=0, l=0, w=38},
                    visible=function() return self.cur_page == 1 end,
                    subviews=common.get_slider_widgets(self, '1'),
                },
                widgets.Panel{
                    frame={t=0, l=0, w=38},
                    visible=function() return self.cur_page == 2 end,
                    subviews=common.get_slider_widgets(self, '2'),
                },
                widgets.Panel{
                    frame={b=0, l=40, r=0, h=2},
                    visible=function() return self.cur_page == 1 end,
                    subviews=common.get_advanced_filter_widgets(self, self.predicate_contexts[1]),
                },
                widgets.Panel{
                    frame={t=1, l=40, r=0},
                    visible=function() return self.cur_page == 2 end,
                    subviews=common.get_info_widgets(self, {trade.mer.buy_prices}, true, self.predicate_contexts[2]),
                },
            },
        },
        widgets.Panel{
            view_id='list_panel',
            frame={t=7, l=0, r=0, b=5},
            subviews={
                widgets.CycleHotkeyLabel{
                    view_id='sort_status',
                    frame={t=0, l=0, w=7},
                    options={
                        {label='status', value=sorting.sort_noop},
                        {label='status'..common.CH_DN, value=sorting.sort_by_status_desc},
                        {label='status'..common.CH_UP, value=sorting.sort_by_status_asc},
                    },
                    initial_option=sorting.sort_by_status_desc,
                    option_gap=0,
                    on_change=self:callback('refresh_list', 'sort_status'),
                },
                widgets.CycleHotkeyLabel{
                    view_id='sort_count',
                    frame={t=0, l=STATUS_COL_WIDTH+1, w=COUNT_COL_WIDTH},
                    options={
                        {label='Cnt', value=sorting.sort_noop},
                        {label='Cnt'..common.CH_DN, value=sorting.sort_by_count_desc},
                        {label='Cnt'..common.CH_UP, value=sorting.sort_by_count_asc},
                    },
                    on_change=self:callback('refresh_list', 'sort_count'),
                },
                widgets.CycleHotkeyLabel{
                    view_id='sort_value',
                    frame={t=0, l=STATUS_COL_WIDTH+1+COUNT_COL_WIDTH+1, w=VALUE_COL_WIDTH},
                    options={
                        {label='value', value=sorting.sort_noop},
                        {label='value'..common.CH_DN, value=sorting.sort_by_value_desc},
                        {label='value'..common.CH_UP, value=sorting.sort_by_value_asc},
                    },
                    option_gap=0,
                    on_change=self:callback('refresh_list', 'sort_value'),
                },
                widgets.CycleHotkeyLabel{
                    view_id='sort_class',
                    frame={t=0, l=STATUS_COL_WIDTH+1+COUNT_COL_WIDTH+1+VALUE_COL_WIDTH+2, w=CLASS_COL_WIDTH},
                    options={
                        {label='Class', value=sorting.sort_noop},
                        {label='Class'..common.CH_DN, value=sorting.sort_by_class_desc},
                        {label='Class'..common.CH_UP, value=sorting.sort_by_class_asc},
                    },
                    option_gap=0,
                    on_change=self:callback('refresh_list', 'sort_class'),
                },
                widgets.CycleHotkeyLabel{
                    view_id='sort_subclass',
                    frame={t=0, l=STATUS_COL_WIDTH+1+COUNT_COL_WIDTH+1+VALUE_COL_WIDTH+2+CLASS_COL_WIDTH+1, w=SUBCLASS_COL_WIDTH},
                    options={
                        {label='Subclass', value=sorting.sort_noop},
                        {label='Subclass'..common.CH_DN, value=sorting.sort_by_subclass_desc},
                        {label='Subclass'..common.CH_UP, value=sorting.sort_by_subclass_asc},
                    },
                    on_change=self:callback('refresh_list', 'sort_subclass'),
                },
                widgets.CycleHotkeyLabel{
                    view_id='sort_grouped',
                    frame={t=0, l=STATUS_COL_WIDTH+1+COUNT_COL_WIDTH+1+VALUE_COL_WIDTH+2+CLASS_COL_WIDTH+2+SUBCLASS_COL_WIDTH+2, w=GROUPED_COL_WIDTH},
                    options={
                        {label='Grouped', value=sorting.sort_noop},
                        {label='Grouped'..common.CH_DN, value=sorting.sort_by_grouped_desc},
                        {label='Grouped'..common.CH_UP, value=sorting.sort_by_grouped_asc},
                    },
                    on_change=self:callback('refresh_list', 'sort_grouped'),
                },
                widgets.CycleHotkeyLabel{
                    view_id='sort_name',
                    frame={t=0, l=STATUS_COL_WIDTH+1+COUNT_COL_WIDTH+1+VALUE_COL_WIDTH+2+CLASS_COL_WIDTH+2+SUBCLASS_COL_WIDTH+2+GROUPED_COL_WIDTH+2, w=5},
                    options={
                        {label='name', value=sorting.sort_noop},
                        {label='name'..common.CH_DN, value=sorting.sort_by_name_desc},
                        {label='name'..common.CH_UP, value=sorting.sort_by_name_asc},
                    },
                    option_gap=0,
                    on_change=self:callback('refresh_list', 'sort_name'),
                },
                widgets.FilteredList{
                    view_id='list',
                    frame={l=0, t=2, r=0, b=0},
                    icon_width=2,
                    on_submit=self:callback('toggle_item'),
                    on_submit2=self:callback('toggle_range'),
                    on_select=self:callback('select_item'),
                },
            }
        },
        widgets.Divider{
            frame={b=4, h=1},
            frame_style=gui.FRAME_INTERIOR,
            frame_style_l=false,
            frame_style_r=false,
        },
        widgets.Label{
            frame={b=2, l=0, r=0},
            text='Click to mark/unmark for trade. Shift click to mark/unmark a range of items.',
        },
        widgets.HotkeyLabel{
            frame={l=0, b=0},
            label='Select all/none',
            key='CUSTOM_CTRL_N',
            on_activate=self:callback('toggle_visible'),
            auto_width=true,
        },
    }

    self.subviews.list.list.frame.t = 0
    self.subviews.list.edit.visible = false
    self.subviews.list.edit = self.subviews.search
    self.subviews.search.on_change = self.subviews.list:callback('onFilterChange')

    self:reset_cache()
end

function LuaTrade:refresh_list(sort_widget, sort_fn)
    if self._refreshing then return end
    self._refreshing = true
    sort_widget = sort_widget or 'sort'
    sort_fn = sort_fn or self.subviews[sort_widget]:getOptionValue()

    if sort_fn == sorting.sort_noop then
        self.subviews[sort_widget]:cycle()
        self._refreshing = false
        return
    end

    -- Update ALL sort-related widgets to match the current active sort function
    local sort_widgets = {
        'sort', 'sort_status', 'sort_value', 'sort_count', 
        'sort_name', 'sort_class', 'sort_subclass', 'sort_grouped'
    }

    for _, widget_name in ipairs(sort_widgets) do
        if self.subviews[widget_name] then
            self.subviews[widget_name]:setOption(sort_fn)
        end
    end

    local list = self.subviews.list
    local saved_filter = list:getFilter()
    local saved_top = list.list.page_top
    list:setFilter('')
    list:setChoices(self:get_choices(), list:getSelected())
    list:setFilter(saved_filter)
    list.list:on_scrollbar(math.max(0, saved_top - list.list.page_top))
    self._refreshing = false
end

local function make_choice_text(value, desc, class, subclass, grouped)
    return {
        {width=STATUS_COL_WIDTH-2, text=''},
        {gap=1, width=COUNT_COL_WIDTH, rjustify=true, text='1'},
        {gap=1, width=VALUE_COL_WIDTH, rjustify=true, text=common.obfuscate_value(value)},
        {gap=2, width=CLASS_COL_WIDTH, text=class, pen=COLOR_CYAN},     -- Added width
        {gap=2, width=SUBCLASS_COL_WIDTH, text=subclass, pen=COLOR_GREY}, -- Added width
        {gap=2, width=GROUPED_COL_WIDTH, text=grouped},
        {gap=2, text=desc},
    } 
end

function LuaTrade:cache_choices(list_idx, trade_bins)
    if self.choices[list_idx][trade_bins] then return self.choices[list_idx][trade_bins] end

    local goodflags = trade.goodflag[list_idx]
    local trade_bins_choices, notrade_bins_choices = {}, {}
    local parent_data
    for item_idx, item in ipairs(trade.good[list_idx]) do
        local goodflag = goodflags[item_idx]
        if not goodflag.contained then
            parent_data = nil
        end
        local is_banned, is_risky = common.scan_banned(item, self.risky_items)
        local is_requested = dfhack.items.isRequestedTradeGood(item, trade.mer)
        local wear_level = item:getWear()
        local desc = dfhack.items.getReadableDescription(item)
        local is_ethical = ethics.is_ethical_product(item, self.animal_ethics, self.wood_ethics)
        local class, subclass = classifier.classify_item(item)
        local data = {
            desc=desc,
            value=common.get_perceived_value(item, trade.mer),
            list_idx=list_idx,
            item=item,
            item_idx=item_idx,
            class=class or 'Other',
            subclass=subclass or 'Other',
            grouped='',
            quality=item.flags.artifact and 6 or item:getQuality(),
            wear=wear_level,
            has_foreign=item.flags.foreign,
            has_banned=is_banned,
            has_risky=is_risky,
            has_requested=is_requested,
            has_ethical=is_ethical,
            ethical_mixed=false,
        }
        if parent_data then
            data.update_container_fn = function(from, to)
                -- TODO
            end
            parent_data.has_banned = parent_data.has_banned or is_banned
            parent_data.has_risky = parent_data.has_risky or is_risky
            parent_data.has_requested = parent_data.has_requested or is_requested
            parent_data.ethical_mixed = parent_data.ethical_mixed or (parent_data.has_ethical ~= is_ethical)
            parent_data.has_ethical = parent_data.has_ethical or is_ethical
        end
        local is_container = df.item_binst:is_instance(item)
        local search_key
        local search_str = ('%s %s %s %s'):format(desc, data.class, data.subclass, data.grouped)
        if (trade_bins and is_container) or item:isFoodStorage() then
            search_key = common.make_container_search_key(item, search_str)
        else
            search_key = common.make_search_key(search_str)
        end
        local choice = {
            search_key=search_key,
            icon=curry(sorting.get_entry_icon, data),
            data=data,
            text=make_choice_text(data.value, desc, data.class, data.subclass, data.grouped),
        }
        if not data.update_container_fn then
            table.insert(trade_bins_choices, choice)
        end
        if data.update_container_fn or not is_container then
            table.insert(notrade_bins_choices, choice)
        end
        if is_container then parent_data = data end
    end

    self.choices[list_idx][true] = trade_bins_choices
    self.choices[list_idx][false] = notrade_bins_choices
    return self:cache_choices(list_idx, trade_bins)
end


function LuaTrade:get_choices()
    local raw_choices = self:cache_choices(self.cur_page-1, self.subviews.trade_bins:getOptionValue())
    local provenance = self.subviews.provenance:getOptionValue()
    local banned = self.cur_page == 1 and 'ignore' or self.subviews.banned:getOptionValue()
    local only_agreement = self.cur_page == 2 and self.subviews.only_agreement:getOptionValue() or false
    local ethical = self.cur_page == 1 and 'show' or self.subviews.ethical:getOptionValue()
    local strict_ethical_bins = self.subviews.strict_ethical_bins:getOptionValue()
    local min_condition = self.subviews['min_condition'..self.cur_page]:getOptionValue()
    local max_condition = self.subviews['max_condition'..self.cur_page]:getOptionValue()
    local min_quality = self.subviews['min_quality'..self.cur_page]:getOptionValue()
    local max_quality = self.subviews['max_quality'..self.cur_page]:getOptionValue()
    local min_value = self.subviews['min_value'..self.cur_page]:getOptionValue().value
    local max_value = self.subviews['max_value'..self.cur_page]:getOptionValue().value
    local choices = {}
    for _,choice in ipairs(raw_choices) do
        local data = choice.data
        if ethical ~= 'show' then
            if strict_ethical_bins and data.ethical_mixed then goto continue end
            if ethical == 'hide' and data.has_ethical then goto continue end
            if ethical == 'only' and not data.has_ethical then goto continue end
        end
        if provenance ~= 'all' then
            if (provenance == 'local' and data.has_foreign) or
                (provenance == 'foreign' and not data.has_foreign)
            then
                goto continue
            end
        end
        if min_condition < data.wear then goto continue end
        if max_condition > data.wear then goto continue end
        if min_quality > data.quality then goto continue end
        if max_quality < data.quality then goto continue end
        if min_value > data.value then goto continue end
        if max_value < data.value then goto continue end
        if only_agreement and not data.has_requested then goto continue end
        if banned ~= 'ignore' then
            if data.has_banned or (banned ~= 'banned_only' and data.has_risky) then
                goto continue
            end
        end
        if not predicates.pass_predicates(self.predicate_contexts[self.cur_page], data.item) then
            goto continue
        end
        table.insert(choices, choice)
        ::continue::
    end
    table.sort(choices, self.subviews.sort:getOptionValue())
    return choices
end

local function toggle_item_base(choice, target_value)
    local goodflag = trade.goodflag[choice.data.list_idx][choice.data.item_idx]
    if target_value == nil then
        target_value = not goodflag.selected
    end
    local prev_value = goodflag.selected
    goodflag.selected = target_value
    if choice.data.update_container_fn then
        choice.data.update_container_fn(prev_value, target_value)
    end
    return target_value
end

function LuaTrade:select_item(idx, choice)
    if not dfhack.internal.getModifiers().shift then
        self.prev_list_idx = self.subviews.list.list:getSelected()
    end
end

function LuaTrade:toggle_item(idx, choice)
    toggle_item_base(choice)
end

function LuaTrade:toggle_range(idx, choice)
    if not self.prev_list_idx then
        self:toggle_item(idx, choice)
        return
    end
    local choices = self.subviews.list:getVisibleChoices()
    local list_idx = self.subviews.list.list:getSelected()
    local target_value
    for i = list_idx, self.prev_list_idx, list_idx < self.prev_list_idx and 1 or -1 do
        target_value = toggle_item_base(choices[i], target_value)
    end
    self.prev_list_idx = list_idx
end

function LuaTrade:toggle_visible()
    local target_value
    for _, choice in ipairs(self.subviews.list:getVisibleChoices()) do
        target_value = toggle_item_base(choice, target_value)
    end
end

function LuaTrade:reset_cache()
    self.choices = {[0]={}, [1]={}}
    self:refresh_list()
end

-- -------------------
-- TradeScreen
--

trade_view = trade_view or nil

TradeScreen = defclass(TradeScreen, gui.ZScreen)
TradeScreen.ATTRS {
    focus_path='caravan/trade',
}

function TradeScreen:init()
    self.trade_window = LuaTrade{}
    self:addviews{self.trade_window}
end

function TradeScreen:onInput(keys)
    if self.reset_pending then return false end
    local handled = TradeScreen.super.onInput(self, keys)
    if keys._MOUSE_L and not self.trade_window:getMouseFramePos() then
        -- "trade" or "offer" buttons may have been clicked and we need to reset the cache
        self.reset_pending = true
    end
    return handled
end

function TradeScreen:onRenderFrame()
    if not df.global.game.main_interface.trade.open then
        if trade_view then trade_view:dismiss() end
    elseif self.reset_pending and
        (dfhack.gui.matchFocusString('dfhack/lua/caravan/trade') or
         dfhack.gui.matchFocusString('dwarfmode/Trade/Default'))
    then
        self.reset_pending = nil
        self.trade_window:reset_cache()
    end
end

function TradeScreen:onDismiss()
    trade_view = nil
end

EthicsScreen = ethics.EthicsScreen
TradeEthicsWarningOverlay = ethics.TradeEthicsWarningOverlay

TradeOverlay = tradeoverlay.TradeOverlay

-- -------------------
-- TradeBannerOverlay
--

TradeBannerOverlay = defclass(TradeBannerOverlay, overlay.OverlayWidget)
TradeBannerOverlay.ATTRS{
    desc='Adds link to the trade screen to launch the DFHack trade UI.',
    default_pos={x=-31,y=-7},
    default_enabled=true,
    viewscreens='dwarfmode/Trade/Default',
    frame={w=25, h=1},
    frame_background=gui.CLEAR_PEN,
}

function TradeBannerOverlay:init()
    self:addviews{
        widgets.TextButton{
            frame={t=0, l=0},
            label='DFHack trade UI',
            key='CUSTOM_CTRL_T',
            enabled=function() return trade.stillunloading == 0 and trade.havetalker == 1 end,
            on_activate=function() trade_view = trade_view and trade_view:raise() or TradeScreen{}:show() end,
        },
    }
end

function TradeBannerOverlay:onInput(keys)
    if TradeBannerOverlay.super.onInput(self, keys) then return true end

    if keys._MOUSE_R or keys.LEAVESCREEN then
        if trade_view then
            trade_view:dismiss()
        end
    end
end
