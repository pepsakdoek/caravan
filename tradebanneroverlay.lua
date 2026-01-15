--@ module = true

local gui = require('gui')
local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')

local trade = df.global.game.main_interface.trade

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
