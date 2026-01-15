--@ module = true

local common = reqscript('internal/caravan/common')
local gui = require('gui')
local overlay = require('plugins.overlay')
local predicates = reqscript('internal/caravan/predicates')
local utils = require('utils')
local widgets = require('gui.widgets')

-- Load the item classifier
local item_classifier = reqscript('internal/caravan/item_classifier')

local trade = df.global.game.main_interface.trade

-- Constants
local STATUS_COL_WIDTH = 7
local COUNT_COL_WIDTH = 6
local VALUE_COL_WIDTH = 10 

-- -------------------
-- Trade Window
-- -------------------

Trade = defclass(Trade, widgets.Window)
Trade.ATTRS {
    frame_title='Hierarchical Pivot Trade',
    frame={w=100, h=47},
    resizable=true,
    resize_min={w=60, h=40},
}

function Trade:init()
    self.cur_page = 1 -- 1: Caravan, 2: Fort
    self.nav_stack = { {level='root', id=nil} } 
    
    self:addviews{
        widgets.TabBar{
            view_id='tabbar',
            frame={t=0, l=0},
            labels={'Caravan goods', 'Fort goods'},
            on_select=function(idx)
                self.cur_page = idx
                self.nav_stack = { {level='root', id=nil} }
                self:refresh_list()
            end,
            get_cur_page=function() return self.cur_page end,
        },
        widgets.HotkeyLabel{
            frame={t=0, r=0},
            label='Go Up',
            key='LEAVESCREEN',
            visible=function() return #self.nav_stack > 1 end,
            on_activate=self:callback('go_back'),
        },
        widgets.EditField{
            view_id='search',
            frame={t=2, l=0},
            label_text='Filter: ',
            on_change=function() self:refresh_list() end,
        },
        widgets.Panel{
            view_id='list_panel',
            frame={t=4, l=0, r=0, b=3},
            subviews={
                widgets.Label{
                    frame={t=0, l=0},
                    text={
                        {text='Status', width=STATUS_COL_WIDTH},
                        {text='Qty', width=COUNT_COL_WIDTH, gap=1},
                        {text='Value', width=VALUE_COL_WIDTH, gap=2},
                        {text='Hierarchy / Item Name'}
                    },
                    text_pen=COLOR_GREY,
                },
                widgets.FilteredList{
                    view_id='list',
                    frame={l=0, t=2, r=0, b=0},
                    on_submit=self:callback('on_submit'),
                },
            }
        },
        widgets.Label{
            view_id='footer',
            frame={b=0, l=0},
            text={
                {text="Total Selected Value: "},
                {text=function() return self:get_total_selected_value() end, color=COLOR_LIGHTGREEN},
                {text="\nShift+Enter: Select Group | Backspace: Up", color=COLOR_GREY}
            },
        }
    }

    self:reset_cache()
end

function Trade:reset_cache()
    self.item_cache = {[1]={}, [2]={}}
    
    for list_idx = 0, 1 do
        local page = list_idx + 1
        local goods = trade.good[list_idx]
        for i, item in ipairs(goods) do
            -- Corrected function name from original trade.lua
            local val = common.get_perceived_value(item, trade.mer)
            
            local class, sub = item_classifier.classify_item(item)
            
            table.insert(self.item_cache[page], {
                item = item,
                item_idx = i,
                list_idx = list_idx,
                class = class or "Other",
                sub = sub or "Misc",
                value = val or 0,
                desc = dfhack.items.getReadableDescription(item)
            })
        end
    end
    self:refresh_list()
end

function Trade:get_selection_marker(group_items)
    local selected_count = 0
    for _, entry in ipairs(group_items) do
        if trade.goodflag[entry.list_idx][entry.item_idx].selected then
            selected_count = selected_count + 1
        end
    end
    if selected_count == 0 then return " " end
    if selected_count == #group_items then return "*" end
    return "+"
end

function Trade:get_total_selected_value()
    local total = 0
    for page=1,2 do
        if self.item_cache[page] then
            for _, entry in ipairs(self.item_cache[page]) do
                if trade.goodflag[entry.list_idx][entry.item_idx].selected then
                    total = total + entry.value
                end
            end
        end
    end
    return total
end

function Trade:refresh_list()
    local current = self.nav_stack[#self.nav_stack]
    local items = self.item_cache[self.cur_page]
    local filter = self.subviews.search.text:lower()
    local choices = {}

    if current.level == 'root' then
        local groups = {}
        for _, entry in ipairs(items) do
            if filter == "" or entry.class:lower():find(filter) then
                if not groups[entry.class] then groups[entry.class] = {} end
                table.insert(groups[entry.class], entry)
            end
        end
        for name, g_items in pairs(groups) do
            local val = 0; for _, e in ipairs(g_items) do val = val + e.value end
            table.insert(choices, self:make_choice(name, #g_items, val, self:get_selection_marker(g_items), {level='class', id=name, items=g_items}))
        end
    elseif current.level == 'class' then
        local groups = {}
        for _, entry in ipairs(items) do
            if entry.class == current.id then
                if filter == "" or entry.sub:lower():find(filter) then
                    if not groups[entry.sub] then groups[entry.sub] = {} end
                    table.insert(groups[entry.sub], entry)
                end
            end
        end
        for name, g_items in pairs(groups) do
            local val = 0; for _, e in ipairs(g_items) do val = val + e.value end
            table.insert(choices, self:make_choice(name, #g_items, val, self:get_selection_marker(g_items), {level='subclass', id=name, items=g_items}))
        end
    elseif current.level == 'subclass' then
        for _, entry in ipairs(items) do
            if entry.sub == current.id then
                if filter == "" or entry.desc:lower():find(filter) then
                    local marker = trade.goodflag[entry.list_idx][entry.item_idx].selected and "√" or " "
                    table.insert(choices, self:make_choice(entry.desc, 1, entry.value, marker, {level='item', entry=entry}))
                end
            end
        end
    end

    self.subviews.list:setChoices(choices)
end

function Trade:make_choice(name, count, value, marker, data)
    return {
        text = {
            {text=string.format("   %s", marker), width=STATUS_COL_WIDTH},
            {text=tostring(count), width=COUNT_COL_WIDTH, rjustify=true, gap=1},
            {text=tostring(value), width=VALUE_COL_WIDTH, rjustify=true, gap=2, color=COLOR_LIGHTGREEN},
            {text=name}
        },
        data = data,
        search_key = name:lower()
    }
end

function Trade:on_submit(idx, choice)
    local data = choice.data
    local shift = dfhack.internal.getModifiers().shift

    if data.level == 'item' then
        local gf = trade.goodflag[data.entry.list_idx][data.entry.item_idx]
        gf.selected = not gf.selected
    elseif shift then
        -- Bulk select group (Shift+Enter)
        local marker = self:get_selection_marker(data.items)
        local target = (marker ~= "*") 
        for _, entry in ipairs(data.items) do
            trade.goodflag[entry.list_idx][entry.item_idx].selected = target
        end
    else
        -- Drill down
        table.insert(self.nav_stack, data)
    end
    self:refresh_list()
end

function Trade:go_back()
    if #self.nav_stack > 1 then
        table.remove(self.nav_stack)
        self:refresh_list()
    end
end

-- -------------------
-- Screen Wrapper
-- -------------------

TradeScreen = defclass(TradeScreen, gui.ZScreen)
TradeScreen.ATTRS { focus_path='pivot_trade' }
function TradeScreen:init() self:addviews{Trade{}} end

-- -------------------
-- Overlay Button
-- -------------------

TradeBannerOverlay = defclass(TradeBannerOverlay, overlay.OverlayWidget)
TradeBannerOverlay.ATTRS{
    desc='Launch Pivot Trade UI',
    default_pos={x=-31,y=-7},
    default_enabled=true,
    viewscreens='dwarfmode/Trade/Default',
    frame={w=25, h=1},
}
function TradeBannerOverlay:init()
    self:addviews{
        widgets.TextButton{
            label='DFHack Pivot Trade',
            key='CUSTOM_CTRL_T',
            on_activate=function() 
                TradeScreen{}:show() 
            end,
        },
    }
end

overlay.register_handler('pivot_trade_button', TradeBannerOverlay)

return _ENV